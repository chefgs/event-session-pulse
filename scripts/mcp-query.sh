#!/usr/bin/env bash
# Query the Terraform MCP Server (registry toolset only) over stdio.
#
# Why this exists: it makes every documentation lookup in this project
# reproducible and auditable. The same server, the same toolset and the same
# JSON-RPC calls that an AI agent makes -- driven by hand so you can read them.
#
# Usage:
#   scripts/mcp-query.sh list
#   scripts/mcp-query.sh call <tool_name> '<json-arguments>'
#
# Examples:
#   scripts/mcp-query.sh call get_latest_provider_version \
#       '{"name":"aws","namespace":"hashicorp"}'
#   scripts/mcp-query.sh call search_provider_docs \
#       '{"provider_name":"aws","provider_namespace":"hashicorp","service_slug":"dynamodb_table","provider_data_type":"resources"}'
set -euo pipefail

IMAGE="hashicorp/terraform-mcp-server:1.4.1"
TOOLSETS="registry"          # public registry docs only: no HCP, no credentials
PROTOCOL="2024-11-05"

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

# Build the JSON-RPC conversation: initialize -> initialized -> one request.
rpc() {
  printf '%s\n' \
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"$PROTOCOL\",\"capabilities\":{},\"clientInfo\":{\"name\":\"mcp-query.sh\",\"version\":\"1.0.0\"}}}" \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    "$1" \
  | docker run -i --rm "$IMAGE" stdio --toolsets="$TOOLSETS" 2>/dev/null
}

case "${1:-}" in
  list)
    rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
      | jq -r 'select(.id==2) | .result.tools[] | "\(.name)\n    \(.description|split("\n")[0])"'
    ;;
  call)
    tool="${2:?tool name required}"
    args="${3:-\{\}}"
    echo "$args" | jq empty || { echo "arguments are not valid JSON" >&2; exit 1; }
    req=$(jq -cn --arg t "$tool" --argjson a "$args" \
      '{jsonrpc:"2.0",id:2,method:"tools/call",params:{name:$t,arguments:$a}}')
    out=$(rpc "$req")
    # Surface protocol-level errors instead of silently printing nothing.
    if echo "$out" | jq -e 'select(.id==2) | .error' >/dev/null 2>&1; then
      echo "MCP error:" >&2
      echo "$out" | jq 'select(.id==2) | .error' >&2
      exit 1
    fi
    echo "$out" | jq -r 'select(.id==2) | .result.content[]? | .text // empty'
    ;;
  *) usage ;;
esac
