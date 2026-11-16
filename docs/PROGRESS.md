# Implementation progress — Meeting Session Pulse

Running record of what has been done, verified and still outstanding.
Each entry states how a fact was established, so nothing rests on recollection.

Last updated: 2026-11-16 (MCP server approved and connected)

---

## Status at a glance

| Phase | Description | Status |
|---|---|---|
| 0 | Prerequisites and Terraform MCP connection | **Done** |
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
| AWS provider (registry latest) | **6.73.0** | MCP `get_latest_provider_version` (scripted, then confirmed natively) |
| `local` provider (registry latest) | **2.9.1** | MCP `get_latest_provider_version` (native) |

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

### Approval — done

Project-scoped MCP servers are not trusted automatically: `.mcp.json` is
committed and travels with the repository, so Claude Code refuses to connect
until a human approves it once per project. The server sat at
`Pending approval` until approved interactively at session startup.

Now confirmed via `claude mcp get terraform`:

```
Scope: Project config (shared via .mcp.json)
Status: Connected
Args:  run -i --rm hashicorp/terraform-mcp-server:1.4.1 stdio --toolsets=registry
```

Nine native MCP tools are available as `mcp__terraform__*`. Verified by calling
`get_latest_provider_version` natively for `hashicorp/aws`, which returned
**6.73.0** — the same answer the scripted client gave, so the two paths agree.

Worth noting for the talk: this is **two independent guardrails**. One human
(per-project approval of committed configuration) and one capability-level
(`--toolsets=registry`, which omits every tool that could reach a cloud
account, workspace or run). `claude mcp reset-project-choices` clears the
approval if you want to rehearse that prompt on stage.

`scripts/mcp-query.sh` remains the reproducible path and still works; native
tool calls are now used in preference.

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
| Terraform constraints | `>= 1.7.0` in `aws-reference` (the `mock_provider` floor, confirmed against official docs), `>= 1.0` in `local-demo` |
| MCP scope | `registry` toolset only; no credentials, no HCP, no workspaces |

---

## Next actions when we resume

1. Phase 2 — application: `app/core/` (questions, validation, aggregation),
   storage adapters, stdlib server, frontend.
2. Phase 3 — tests against the full acceptance list.
3. Phase 4 — write `infra/aws-reference/` from the cached documentation, then
   `fmt`, `init -backend=false`, `validate` and mocked `terraform test`.
4. Phase 5 — `infra/local-demo/`: real plan, **pause for your approval**, apply,
   then a settings change and a second plan.
5. Phases 6–7 — documentation set, verification pass, grouped commits.

## Nothing has been claimed that was not run

No AWS account was contacted. No cloud credentials exist in this repository.
No Terraform `init`, `validate`, `test`, `plan` or `apply` has been run yet.
The only commits are documentation, scripts, MCP configuration and
MCP-retrieved provider documentation. No application or Terraform code exists
yet.

---

## Best-practice gaps identified (2026-11-16) — agreed to address later

Reviewed whether this project follows good practice for AI-assisted Terraform
development. Three real gaps, deferred by decision, not oversight:

1. **No IaC security scanning.** This contradicts the mandatory CI gate in
   CLAUDE.md (Checkov, fail on CRITICAL/HIGH). `terraform validate` checks
   schema correctness, not safety — it will validate a wide-open security
   group without complaint. Trivy 0.69.3 is already installed locally and
   scans IaC, so `trivy config infra/` could cover this at no cost.
2. **No CI.** None of the six mandatory security gates run anywhere. For a
   publicly published workshop repository, a workflow running
   fmt/validate/test/scan is part of the demo's credibility.
3. **No linting or pre-commit hooks.** `terraform fmt` and `tflint` as hooks
   are standard. `tflint` also catches provider-specific errors that
   `validate` misses, such as invalid instance types or malformed ARNs.
   Neither `tflint` nor `pre-commit` is installed.

Two weaker spots:

- `get_provider_capabilities` was skipped; the server's own recommended flow is
  capabilities → details. Use it in Phase 4.
- The validation discipline is **unproven**: no Terraform has been written yet,
  so everything about fmt/validate/test remains plan rather than practice.

**The limit worth stating on stage:** documentation retrieval, `validate` and
mocked tests catch *schema* errors well. They do **not** catch semantic
wrongness — an IAM policy can validate, pass mocked tests, and still be
over-permissive. Mocked tests only assert what the author thought to assert.
That is precisely why a policy scanner belongs in the loop: it encodes
judgement the author may not have had.

**Sequencing note:** these guardrails are a stronger story if they exist
*before* the AI writes the Terraform, rather than being retrofitted after.

`AGENTS.md` is also still unwritten. The approval boundaries currently live
only in a chat session. Committed, they survive a context reset and apply to
any agent an attendee points at this repository. Write it before Phase 4.

---

## Resume point

**Repository:** https://github.com/chefgs/event-session-pulse (public)
**Open PR:** #1 `feature/mcp-foundation` → `main` (not merged)
**Current branch:** `feature/mcp-foundation`
**Working tree:** clean — this record, and the process guide in
`docs/iac-with-terraform-mcp.md`, are both committed and pushed

Phase 0 is complete. The Terraform MCP server is approved, connected at project
scope and verified by a native tool call. Nine `mcp__terraform__*` registry
tools are available.

`docs/iac-with-terraform-mcp.md` writes Phase 0 up as a reusable, from-zero
process guide: prerequisites, MCP connection, the validation ladder, mocked
testing, scanning and approval boundaries. Every claim in it is tagged
`[verified]`, `[docs]` or `[not executed]`.

Pick up with any of:

- **Phase 2** — application: `app/core/` (questions, validation, aggregation),
  storage adapters, stdlib server, frontend.
- **Harden first** — close gaps 1–3 above and write `AGENTS.md` before any
  Terraform is generated.
- **Phase 4 prep** — the `mock_provider` floor is settled: `terraform test`
  needs **1.6.0+**, mocking needs **1.7.0+**, both read from
  `developer.hashicorp.com`. Worth remembering why the registry MCP toolset
  could not answer it: that is Terraform *core* documentation, and the toolset
  serves provider and module documentation only.

Still true: no AWS account contacted, no credentials in the repository, no
`terraform init`, `validate`, `test`, `plan` or `apply` ever run, nothing
merged, and `main` holds only its empty root commit.
