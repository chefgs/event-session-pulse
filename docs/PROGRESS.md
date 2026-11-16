# Implementation progress — Meeting Session Pulse

Running record of what has been done, verified and still outstanding.
Each entry states how a fact was established, so nothing rests on recollection.

Last updated: 2026-11-16

---

## Status at a glance

| Phase | Description | Status |
|---|---|---|
| 0 | Prerequisites and Terraform MCP connection | **Done** (one item needs your action) |
| 1 | Repository scaffold | Partial — directories and scripts only |
| 2 | Application (core, storage, server, frontend) | Not started |
| 3 | Tests | Not started |
| 4 | `infra/aws-reference/` | Not started (documentation already gathered) |
| 5 | `infra/local-demo/` | Not started |
| 6 | Documentation set | Not started |
| 7 | Verification pass and commits | Not started |

---

## Phase 0 — completed, with verified findings

### Toolchain

| Component | Version | How established |
|---|---|---|
| Terraform | **1.17.2** (darwin_arm64) | `terraform version` after upgrade |
| Python | 3.14.8 | `python3 --version` |
| Docker Engine | 29.9.3 (Docker Desktop) | `docker info` |
| Terraform MCP Server | **1.4.1** | `docker run --rm <image> --version` |
| AWS provider (registry latest) | **6.73.0** | MCP `get_latest_provider_version` |

Terraform was upgraded from 1.10.4 during this session. Latest stable was
confirmed as 1.17.2 from HashiCorp's release API, not from memory.

### Terraform MCP Server

Registered at **project scope**, so the configuration is committed and
attendees can reproduce it. File: `.mcp.json`.

```
docker run -i --rm hashicorp/terraform-mcp-server:1.4.1 stdio --toolsets=registry
```

Findings worth knowing, all established by interrogating the image rather
than assuming:

- The toolset selector is the **`--toolsets` CLI flag**. An earlier assumption
  that it was a `TERRAFORM_MCP_TOOLSETS` environment variable was wrong.
- The default is **`--toolsets=all`**, which includes `registry-private` and
  `terraform` (the HCP/operations toolset). Registry-only is **not** the
  default and must be requested explicitly.
- Available toolsets: `registry`, `registry-private`, `terraform`.
- The image is pinned to tag `1.4.1` (verified to exist via
  `docker manifest inspect`) rather than floating on `:latest`.
- With `--toolsets=registry` the server exposes **9 tools** and none of them
  can reach a cloud account, a workspace or a run. The capability boundary is
  enforced by the flag, not by agent discretion — a good point to make on stage.

Tools available in the `registry` toolset:

| Tool | Used here |
|---|---|
| `search_provider_docs` | Resolve a service slug to a `providerDocID` |
| `get_provider_details` | Fetch a resource's argument reference |
| `get_provider_capabilities` | Confirm a provider offers a resource type |
| `get_latest_provider_version` | Pin the provider constraint honestly |
| `search_modules`, `get_module_details`, `get_latest_module_version` | Not needed |
| `search_policies`, `get_policy_details` | Not needed |

### ACTION REQUIRED FROM YOU

The server shows **`Pending approval`** in `claude mcp list`. Project-scoped
MCP servers require explicit approval before the client will connect.

> Exit this session, run `claude` in this directory, and approve the
> `terraform` server when prompted.

Until that is done, documentation retrieval goes through
`scripts/mcp-query.sh` instead of native MCP tool calls. Both talk to the
same server with the same toolset; only the client differs.

### Documentation retrieved through MCP

Cached in `docs/mcp-evidence/` — the audit trail showing every argument in the
forthcoming Terraform config came from current documentation. All ten fetched
against AWS provider **6.73.0**:

`dynamodb_table`, `lambda_function`, `lambda_permission`, `apigatewayv2_api`,
`apigatewayv2_integration`, `apigatewayv2_route`, `apigatewayv2_stage`,
`cloudwatch_log_group`, `iam_role`, `iam_role_policy`.

First verified fact already drawn from it:

- `aws_dynamodb_table.billing_mode` accepts `PROVISIONED` or `PAY_PER_REQUEST`
  and **defaults to `PROVISIONED`**. On-demand billing must therefore be set
  explicitly — exactly the kind of silent default the mocked Terraform test
  should assert against.

### Two real problems hit and fixed

Both are worth demonstrating live, because they are the sort of thing that
derails an unrehearsed demo:

1. **Registry rate limiting.** Ten rapid consecutive MCP calls caused failures,
   and a throttled reply surfaced as a misleading
   `provider not found: hashicorp/aws`. Fixed by pacing calls and retrying
   with exponential backoff in `scripts/fetch-aws-docs.sh`.
2. **A false positive in my own retry logic.** The guard treated any reply
   containing "not found" as an error, but the API Gateway stage document
   legitimately contains that phrase while describing a 404 response. The
   check now applies the error pattern only to short payloads.

**Pre-workshop preparation:** pre-pull the image and pre-populate
`docs/mcp-evidence/` so venue wifi and registry throttling are off the
critical path. The fetch script skips anything already cached.

---

## Phase 1 — partial

Created: `app/{core,storage}`, `static/`, `tests/`,
`infra/{aws-reference/tests,local-demo}`, `generated/`, `docs/adr/`,
`scripts/`. Git repository initialised; **no commits yet**.

Written so far: `.gitignore`, `.mcp.json`, and the two scripts below.

---

## Scripts

### `scripts/mcp-query.sh`

Drives the Terraform MCP Server over stdio by hand. Makes every lookup
reproducible and auditable, and demonstrates that an MCP server is just a
process speaking JSON-RPC on stdin/stdout.

```bash
scripts/mcp-query.sh list
scripts/mcp-query.sh call get_latest_provider_version '{"namespace":"hashicorp","name":"aws"}'
scripts/mcp-query.sh call search_provider_docs \
  '{"provider_namespace":"hashicorp","provider_name":"aws","service_slug":"dynamodb_table","provider_document_type":"resources"}'
scripts/mcp-query.sh call get_provider_details '{"provider_doc_id":"14784520"}'
```

### `scripts/fetch-aws-docs.sh`

Caches the argument reference for all ten resources into
`docs/mcp-evidence/`. Two MCP calls per resource: `search_provider_docs` to
resolve the `providerDocID` by exact title match, then `get_provider_details`.
Paced and retried; re-running is cheap because cached files are skipped.

```bash
scripts/fetch-aws-docs.sh
```

---

## Decisions settled so far

| Decision | Choice |
|---|---|
| AWS code scope | Shared storage-agnostic core; SQLite adapter runs locally; DynamoDB adapter and Lambda handler are committed and unit-tested against an injected fake client, never deployed |
| Workshop label | No city hardcoded. Precedence: Terraform-generated `generated/app-config.json` > `SESSION_PULSE_*` env vars > built-in defaults. Terraform deliberately outranks the env var, which is the point of the `local-demo` root |
| Dependencies | Python standard library only; `unittest`, not pytest; `boto3` not installed locally |
| Terraform constraints | `>= 1.7.0` in `aws-reference` (the `mock_provider` floor — still to be confirmed against official docs), `>= 1.0` in `local-demo` |
| MCP scope | `registry` toolset only; no credentials, no HCP, no workspaces |

---

## Next actions when we resume

1. **You:** approve the project-scoped `terraform` MCP server (see above).
2. Confirm the `mock_provider` minimum Terraform version from official docs.
3. Phase 2 — application: `app/core/` (questions, validation, aggregation),
   storage adapters, stdlib server, frontend.
4. Phase 3 — tests against the full acceptance list.
5. Phase 4 — write `infra/aws-reference/` from the cached documentation, then
   `fmt`, `init -backend=false`, `validate` and mocked `terraform test`.
6. Phase 5 — `infra/local-demo/`: real plan, **pause for your approval**, apply,
   then a settings change and a second plan.
7. Phases 6–7 — documentation set, verification pass, grouped commits.

## Nothing has been claimed that was not run

No AWS account was contacted. No cloud credentials exist in this repository.
No Terraform `init`, `validate`, `test`, `plan` or `apply` has been run yet.
No commits have been made and nothing has been pushed.
