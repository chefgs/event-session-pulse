#!/usr/bin/env bash
# Cache AWS provider documentation for every resource used by
# infra/aws-reference/, retrieved through the Terraform MCP Server.
#
# Two MCP calls per resource:
#   1. search_provider_docs  -- resolve a service slug to a providerDocID
#   2. get_provider_details  -- fetch that document's argument reference
#
# Output lands in docs/mcp-evidence/, which is the audit trail proving each
# argument in the Terraform config came from current documentation rather
# than from a model's memory.
#
# The public registry rate-limits bursts of requests, and a throttled reply can
# surface as a misleading "provider not found" message. Calls are therefore
# paced and retried with backoff. Re-running is cheap: cached files are kept.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="docs/mcp-evidence"
MCP="./scripts/mcp-query.sh"
PACE_SECONDS=3          # gap between resources, to stay under registry throttling
MAX_ATTEMPTS=4
mkdir -p "$OUT"

# Run an MCP call, retrying with exponential backoff. A throttled registry
# reply is not distinguishable from a real failure, so treat both as retryable.
# Error replies are short; a real document is long and may itself contain the
# words "not found" (for example, describing a 404 response), so the error
# pattern is only applied to short payloads.
mcp_retry() {
  local tool="$1" args="$2" attempt=1 out
  while (( attempt <= MAX_ATTEMPTS )); do
    if out=$($MCP call "$tool" "$args" 2>/dev/null) && [[ -n "$out" ]]; then
      if (( ${#out} > 400 )) \
         || ! grep -qi 'not found\|rate limit\|too many requests' <<<"$out"; then
        printf '%s' "$out"; return 0
      fi
    fi
    sleep $(( attempt * PACE_SECONDS ))
    (( attempt++ ))
  done
  return 1
}

RESOURCES=(
  dynamodb_table
  lambda_function
  lambda_permission
  apigatewayv2_api
  apigatewayv2_integration
  apigatewayv2_route
  apigatewayv2_stage
  cloudwatch_log_group
  iam_role
  iam_role_policy
)

for slug in "${RESOURCES[@]}"; do
  dest="$OUT/aws_${slug}.md"
  if [[ -s "$dest" ]]; then
    printf '  cached  %s\n' "$slug"; continue
  fi

  # Resolve the doc id, requiring an exact title match so we do not
  # accidentally document a neighbouring resource.
  doc_id=$(mcp_retry search_provider_docs "$(jq -cn --arg s "$slug" \
      '{provider_namespace:"hashicorp",provider_name:"aws",service_slug:$s,provider_document_type:"resources"}')" \
    | awk -v want="$slug" '
        /^- providerDocID:/ { id=$3 }
        /^- Title:/        { if ($3 == want && id != "") { print id; exit } }')

  if [[ -z "${doc_id:-}" ]]; then
    printf '  FAILED  %s (no exact title match)\n' "$slug" >&2; continue
  fi

  if ! mcp_retry get_provider_details "$(jq -cn --arg d "$doc_id" '{provider_doc_id:$d}')" > "$dest"; then
    rm -f "$dest"
    printf '  FAILED  %s (details fetch failed after %s attempts)\n' "$slug" "$MAX_ATTEMPTS" >&2
    continue
  fi
  printf '  fetched %s (docID %s, %s lines)\n' "$slug" "$doc_id" "$(wc -l < "$dest" | tr -d ' ')"
  sleep "$PACE_SECONDS"
done

printf '\nProvider version at time of retrieval: '
mcp_retry get_latest_provider_version '{"namespace":"hashicorp","name":"aws"}' \
  || echo "unavailable (registry throttled; re-run to confirm)"
