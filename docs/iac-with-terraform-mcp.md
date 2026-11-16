# Developing Terraform code with an AI agent and the Terraform MCP Server

A step-by-step process, from a machine with nothing installed to a validated,
tested, policy-scanned Terraform configuration.

## How to read the claims in this document

| Mark | Meaning |
|---|---|
| **[verified]** | Executed on macOS (darwin_arm64) while writing this guide; the stated output is real |
| **[docs]** | Quoted or taken from official HashiCorp documentation, linked in [References](#references) |
| **[not executed]** | Correct as far as the documentation goes, but not run here. Verify before relying on it |

Versions current as of **2026-11-16**. Version numbers age; re-check them with
the commands given rather than trusting this table later.

---

## Part 0 — Which scenario are you in?

Find your row and start at the stage named.

| Your situation | Start at | Notes |
|---|---|---|
| Nothing installed | [Part 1](#part-1--prerequisites) | Full path, ~15 minutes |
| Terraform installed, no MCP server | [Part 2](#part-2--connect-the-terraform-mcp-server) | |
| Docker unavailable or not allowed | [Part 1, Option B](#option-b-native-binary-no-docker) | A native binary exists |
| MCP server connected already | [Part 3](#part-3--discovery-retrieve-documentation-before-writing-code) | Verify the toolset first |
| **No cloud account, no credentials** | All parts | Everything here works except a real `plan`/`apply`. Use mocked tests and a local-provider root |
| Have a cloud account | All parts | Add the credential step in [Part 8](#part-8--plan-review-and-approval) |
| Have HCP Terraform | All parts | The `terraform` toolset adds workspace/run tools; see [Part 2](#choosing-toolsets) |
| Air-gapped or unreliable venue network | [Part 9](#part-9--offline-and-workshop-preparation) | Pre-cache everything |
| Just want the commands | [Quick reference](#quick-reference) | |

A note on expectations before you start: an AI agent plus an MCP server
improves the *inputs* to your Terraform — current argument names, real version
numbers, actual defaults. It does not replace the validation ladder in
[Part 5](#part-5--the-validation-ladder). Treat generated configuration as a
competent first draft from someone who has read the documentation and never run
the code.

---

## Part 1 — Prerequisites

### 1.1 Terraform

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform version
```

**[verified]** Output: `Terraform v1.17.2 on darwin_arm64`. Check the current
release independently of any tool's claim:

```bash
curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version
```

Version floors that matter later **[docs]**:

| Feature | Minimum Terraform |
|---|---|
| `terraform test` framework (`.tftest.hcl`) | **v1.6.0** |
| Provider mocking (`mock_provider`) | **v1.7.0** |

If you are below 1.7.0, mocked testing is unavailable and most of
[Part 6](#part-6--testing-with-mocked-providers) does not apply.

### 1.2 The MCP server — pick one option

#### Option A: Docker (what this project uses)

```bash
docker --version
docker info >/dev/null && echo "daemon running"
docker pull hashicorp/terraform-mcp-server:1.4.1
docker run --rm hashicorp/terraform-mcp-server:1.4.1 --version
```

**[verified]** Output: `Terraform MCP Server / Version: 1.4.1`.
Docker Engine tested: 29.9.3 (Docker Desktop).

Pin the tag. `:latest` means your toolchain changes without you choosing it,
which is a poor foundation for a reproducible demo or a team repository. Confirm
a tag exists before pinning to it:

```bash
docker manifest inspect hashicorp/terraform-mcp-server:1.4.1 >/dev/null && echo "tag exists"
```

**[verified]** `1.4.1` exists; `v1.4.1` does not. Tag naming is not guessable.

#### Option B: Native binary (no Docker)

```bash
brew install terraform-mcp-server
terraform-mcp-server --version
```

**[verified]** The Homebrew formula `terraform-mcp-server` exists at version
**1.4.1**, described as "MCP server for Terraform", homepage
`github.com/hashicorp/terraform-mcp-server`. **[not executed]** I did not
install it, so the exact invocation is unconfirmed — but the flags are the
same binary's, so substitute `terraform-mcp-server` for the
`docker run … hashicorp/terraform-mcp-server:1.4.1` prefix throughout.

Use this option when Docker is unavailable, disallowed by policy, or when you
want the demo not to depend on a container runtime starting up on stage.

### 1.3 Supporting tools

```bash
brew install jq git            # jq is needed for the MCP helper scripts
jq --version && git --version
```

### 1.4 Quality and security tooling

These are the parts most often skipped, and the reason AI-generated Terraform
reaches production over-permissive. Install them **before** generating code, so
the guardrails exist before there is anything to guard.

```bash
brew install trivy             # IaC + vulnerability scanning
brew install checkov           # IaC policy scanning
brew tap terraform-linters/tap # tflint is not in homebrew-core
brew install terraform-linters/tap/tflint
brew install pre-commit
```

**[verified]** Trivy present locally at **0.69.3**. Checkov available in
Homebrew at **3.4.5**. `tflint` is **not** in homebrew-core — it requires the
`terraform-linters/tap` tap first (confirmed by Homebrew's own error message).
**[not executed]** I did not install checkov, tflint or pre-commit.

You do not need all three scanners. Pick one of Trivy or Checkov; adding
`tflint` is worthwhile because it catches provider-specific mistakes that
`terraform validate` accepts, such as an invalid instance type.

### 1.5 Verify the whole toolchain

```bash
for t in terraform docker jq git trivy checkov tflint; do
  printf '%-12s ' "$t"
  command -v "$t" >/dev/null 2>&1 && "$t" --version 2>&1 | head -1 || echo "MISSING"
done
```

---

## Part 2 — Connect the Terraform MCP Server

### 2.1 Interrogate before trusting

Ask the binary what it accepts rather than assuming. This step caught two of my
own wrong assumptions while building this project.

```bash
docker run --rm hashicorp/terraform-mcp-server:1.4.1 --help
```

**[verified]** Subcommands: `stdio`, `streamable-http`, `completion`, `help`.
Relevant flags: `--toolsets`, `--tools`, `--log-level`, `--log-format`,
`--log-file`.

### 2.2 Choosing toolsets

**This is the most important security decision in the process.**

**[verified]** Available toolsets: `registry`, `registry-private`, `terraform`.
Special keywords: `all`, `default`. **The flag defaults to `all`.**

| Toolset | Contains | Needs credentials | Can change infrastructure |
|---|---|---|---|
| `registry` | Public provider/module/policy documentation | No | **No** |
| `registry-private` | Private registry lookups | Yes (HCP token) | No |
| `terraform` | Workspaces, runs, variables, apply/discard | Yes (HCP token) | **Yes** |

For development, learning, and any workshop without cloud accounts, use
`registry` alone:

```bash
--toolsets=registry
```

This is **not** the default. A default invocation gets `all`. With `registry`
alone the tools that could reach a cloud account, a workspace or a run **do not
exist in the process** — a far stronger guarantee than instructing an agent to
behave. Narrow further with `--tools` if you want an explicit allowlist:

```bash
--tools=search_provider_docs,get_provider_details,get_latest_provider_version
```

`--tools` and `--toolsets` are mutually exclusive **[verified from `--help`]**.

### 2.3 Register with your agent

Scope matters:

| Scope | Flag | Stored in | Use when |
|---|---|---|---|
| Local | `--scope local` | Personal config, this project only | Experimenting |
| **Project** | `--scope project` | **`.mcp.json`, committed** | Team or workshop repos |
| User | `--scope user` | Personal config, all projects | A tool you always want |

```bash
cd /path/to/your/repo
claude mcp add terraform --scope project -- \
  docker run -i --rm hashicorp/terraform-mcp-server:1.4.1 stdio --toolsets=registry
```

**[verified]** Writes `.mcp.json`:

```json
{
  "mcpServers": {
    "terraform": {
      "type": "stdio",
      "command": "docker",
      "args": ["run","-i","--rm","hashicorp/terraform-mcp-server:1.4.1",
               "stdio","--toolsets=registry"],
      "env": {}
    }
  }
}
```

Project scope is the right default for shared work: the configuration is
reviewable in a pull request and reproducible by anyone who clones the repo.

### 2.4 Approve it

```bash
claude mcp list
```

**[verified]** A project-scoped server first appears as:

```
terraform: docker run -i --rm … - ⏸ Pending approval (run `claude` to approve)
```

Because `.mcp.json` is committed, it travels with the repository and could come
from anyone. The client therefore refuses to connect until a human approves it,
**once per project**. Approval is an interactive prompt at session startup — not
a CLI flag:

1. Exit your agent session
2. `cd` into the repository
3. Run `claude`
4. Approve the `terraform` server at the prompt

```bash
claude mcp get terraform
```

**[verified]** Expected:

```
Scope: Project config (shared via .mcp.json)
Status: ✔ Connected
```

Useful related commands **[verified]**:

```bash
claude mcp list                     # all servers + health
claude mcp get terraform            # one server's detail
claude mcp remove terraform -s project
claude mcp reset-project-choices    # replay the approval prompt
```

`reset-project-choices` is how you rehearse the approval prompt for a live
audience.

You now have **two independent guardrails**: a human gate (per-project approval
of committed configuration) and a capability gate (`--toolsets=registry` omits
the dangerous tools entirely). Neither relies on the agent's good behaviour.

### 2.5 Fallback: drive the server by hand

If approval is pending, the client is unavailable, or you want to show the
audience what an MCP server actually is, talk to it directly. An MCP server is
just a process speaking JSON-RPC on stdin/stdout:

```bash
printf '%s\n' \
 '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}' \
 '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
 '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
 | docker run -i --rm hashicorp/terraform-mcp-server:1.4.1 stdio --toolsets=registry 2>/dev/null \
 | jq -c 'select(.id==2) | .result.tools[].name'
```

**[verified]** Returns nine tool names. `scripts/mcp-query.sh` in this
repository wraps this pattern; `scripts/fetch-aws-docs.sh` uses it to cache
documentation.

---

## Part 3 — Discovery: retrieve documentation before writing code

**The rule: never write a provider argument from memory.** This is the whole
point of connecting the MCP server. Language models produce plausible argument
names that do not exist, and plausible defaults that are wrong.

### 3.1 The nine registry tools

**[verified]** With `--toolsets=registry`:

| Tool | Required arguments |
|---|---|
| `get_latest_provider_version` | `namespace`, `name` |
| `get_provider_capabilities` | `namespace`, `name` (+ optional `version`) |
| `search_provider_docs` | `provider_name`, `provider_namespace`, `service_slug`, `provider_document_type` |
| `get_provider_details` | `provider_doc_id` |
| `get_latest_module_version` | module coordinates |
| `search_modules` | query |
| `get_module_details` | `module_id` (from `search_modules`) |
| `search_policies` | query |
| `get_policy_details` | `terraform_policy_id` (from `search_policies`) |

Argument names are not guessable: it is `provider_document_type`, not
`provider_data_type`. Read the schema instead of assuming.

### 3.2 The documented discovery order

The server's own guidance is: **version → capabilities → details.**

```
get_latest_provider_version  →  get_provider_capabilities  →  search_provider_docs  →  get_provider_details
```

`get_provider_capabilities` is the step most often skipped. It tells you whether
a provider offers a resource type at all, which is cheaper than discovering it
through a failed `validate`.

### 3.3 Worked example

Pin the version first, so every later lookup is against a known version:

```bash
scripts/mcp-query.sh call get_latest_provider_version \
  '{"namespace":"hashicorp","name":"aws"}'
```

**[verified]** `6.73.0` (and `hashicorp/local` → `2.9.1`).

Resolve a resource to a document id:

```bash
scripts/mcp-query.sh call search_provider_docs '{
  "provider_namespace":"hashicorp","provider_name":"aws",
  "service_slug":"dynamodb_table","provider_document_type":"resources"}'
```

**[verified]** Returns `providerDocID: 14784520` for `dynamodb_table`, alongside
near-miss neighbours (`dynamodb_table_item`, `_replica`, `_export`). Match the
title exactly or you will document the wrong resource.

Fetch the argument reference:

```bash
scripts/mcp-query.sh call get_provider_details '{"provider_doc_id":"14784520"}'
```

**[verified]** 543 lines. The first fact it yielded:
`aws_dynamodb_table.billing_mode` accepts `PROVISIONED` or `PAY_PER_REQUEST`
and **defaults to `PROVISIONED`**. On-demand must be set explicitly. That is a
real cost decision buried in a silent default — exactly what retrieval is for,
and exactly what a test should assert.

### 3.4 Cache the results as evidence

Write retrieved documentation to a directory in the repository
(`docs/mcp-evidence/` here). This gives you:

- an audit trail that each argument came from documentation, not recollection;
- a reviewer's answer to "where did this come from?";
- offline capability for a venue with poor network.

### 3.5 Expect rate limiting

**[verified]** The public registry throttles bursts. Ten rapid consecutive
calls produced failures, and a throttled reply surfaced as a **misleading**
`provider not found: hashicorp/aws` — not a rate-limit message. Pace calls and
retry with backoff; see `scripts/fetch-aws-docs.sh`.

A caution learned the hard way: when writing that retry logic, do not treat any
reply containing "not found" as an error. A genuine document may contain the
phrase while describing a 404 response. Apply error patterns only to short
payloads.

---

## Part 4 — Write the configuration

### 4.1 Pin versions using what you retrieved

```hcl
terraform {
  required_version = ">= 1.7.0"   # floor for mock_provider [docs]

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"          # from get_latest_provider_version
    }
  }
}
```

Pinning strategy:

| Constraint | Behaviour | Use for |
|---|---|---|
| `>= 1.7.0` | Any newer version | Terraform core, when you need a feature floor |
| `~> 6.73` | 6.73.x and later 6.x minors | Providers, usual choice |
| `= 6.73.0` | Exactly this | Maximum reproducibility, more maintenance |

Commit `.terraform.lock.hcl`. The constraint states intent; the lock file
records what was actually used. Without it, a colleague or CI run may resolve a
different provider version than you tested.

```bash
terraform providers lock -platform=darwin_arm64 -platform=linux_amd64
```

**[not executed]** Add every platform your CI and colleagues use, or they will
fail on a lock file that lacks their hashes.

### 4.2 Keep secrets out

- No credentials in `.tf`, `.tfvars` or anywhere in Git
- `.gitignore` must include `*.tfstate*`, `*.tfvars`, `.terraform/`, `*.tfplan`
- State contains secrets in plain text, even when the configuration does not
- Prefer short-lived credentials over long-lived keys

---

## Part 5 — The validation ladder

Run these in order. Each catches a different class of problem, and **none of
them catches what the next one does**.

| # | Command | Catches | Does **not** catch | Network |
|---|---|---|---|---|
| 1 | `terraform fmt -check -recursive` | Formatting drift | Anything semantic | No |
| 2 | `terraform init -backend=false` | Missing/unresolvable providers | Configuration errors | **Yes** |
| 3 | `terraform validate` | Syntax, schema, bad argument names, type errors | Whether the design is safe or sane | No |
| 4 | `tflint` | Provider-specific invalid values, deprecations | Policy and security posture | Varies |
| 5 | `terraform test` | Behaviour your assertions describe | Anything you did not think to assert | No, with mocks |
| 6 | `trivy config .` / `checkov -d .` | Known insecure patterns, over-permissive IAM | Logic specific to your design |  No |
| 7 | `terraform plan` | What would actually change | Whether you *want* that change | **Yes + credentials** |

```bash
cd infra/your-root

terraform fmt -check -recursive        # add -diff to see changes
terraform init -backend=false          # skip backend when you only want validation
terraform validate
tflint
terraform test
trivy config .
```

Two things worth internalising:

**`terraform validate` is not a safety check.** It will happily validate a
security group open to the world and an IAM policy with `Resource: "*"`. Steps
4 and 6 exist because 3 cannot do their job.

**`-backend=false` is legitimate; faking credentials is not.** Skipping backend
initialisation to validate locally is normal practice. Setting dummy
credentials or skip-validation flags so a command appears to succeed produces a
result that means nothing — and it is dishonest to present it as a successful
plan.

---

## Part 6 — Testing with mocked providers

This is how you test cloud configuration **without a cloud account**.

### 6.1 Read this warning first

**[docs]** The `terraform test` documentation states the command "creates
_real_ infrastructure", and that after each test file Terraform "attempts to
destroy any remaining infrastructure." If it cannot, it reports what it could
not destroy.

Two independent protections, and you want both:

- `mock_provider` — no real provider calls for mocked resources
- `command = plan` in `run` blocks — **[docs]** "instructs Terraform to _not_
  create new infrastructure for this `run` block"

**[docs]** Default is `command = apply`. You must opt into `plan`.

### 6.2 Layout

**[docs]** Test files are discovered by extension — `.tftest.hcl` or
`.tftest.json`. The default directory is **`tests`**, overridable with
`-test-directory`, though the documentation says "We do not recommend changing
the default test directory." Files in the root configuration directory are
always loaded regardless.

```
infra/aws-reference/
├── main.tf
├── versions.tf
└── tests/
    └── mocked.tftest.hcl
```

### 6.3 Syntax

All syntax below is **[docs]** from the mocking and tests pages:

```hcl
mock_provider "aws" {}

# Supply values for computed attributes:
mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::name" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

run "log_retention_is_explicit" {
  command = plan

  variables {
    environment = "test"
  }

  assert {
    condition     = aws_cloudwatch_log_group.app.retention_in_days != null
    error_message = "Log group must set an explicit retention period"
  }
}
```

Other documented blocks:

| Block | Purpose |
|---|---|
| `mock_provider "x" { alias = "fake" }` | Mock an aliased provider |
| `mock_provider "x" { source = "./testing/aws" }` | Load mock data from `.tfmock.hcl`/`.tfmock.json` |
| `override_during = plan` \| `apply` | When overrides apply; default generates data at apply |
| `override_resource { target = … values = {…} }` | Override a resource; provider not called |
| `override_data { target = … values = {…} }` | Override a data source; provider not called |
| `override_module { target = … outputs = {…} }` | Override module outputs; no resources created |
| `variables { … }` | File-level; a `run` block's values override it |
| `expect_failures` | Assert a failure is expected |
| `state_key`, `parallel` | State isolation, parallel execution |

A `run`-level override takes precedence over a file-level one.

### 6.4 Running tests

**[docs]** `terraform test [options]`, with exactly these options:

| Flag | Meaning |
|---|---|
| `-filter=testfile` | Limit to specific test files |
| `-verbose` | Print plan or state for each `run` block |
| `-json` | Machine-readable output |
| `-junit-xml=<path>` | JUnit XML report (incompatible with `-cloud-run`) |
| `-test-directory=<dir>` | Override the `tests` directory |
| `-parallelism=<n>` | Parallel plan/apply operations, default 10 |
| `-run-parallelism=<n>` | Parallel `run` blocks per file, default 10 |
| `-cloud-run=<module source>` | Execute remotely on HCP Terraform (needs `terraform login`) |

```bash
terraform test
terraform test -verbose
terraform test -filter=tests/mocked.tftest.hcl
terraform test -junit-xml=test-results.xml      # for CI
```

**[docs]** Exit codes are **not** documented on that page. `-var` and
`-var-file` are **not** listed — pass values via `variables` blocks instead.
Whether `terraform init` is required beforehand is not stated; in practice
providers must be resolvable, so run `init` first.

### 6.5 What mocked tests do *not* verify

Be precise about this, especially in front of an audience. **[docs]**, quoted:

- "This allows you to test parts of your module without creating infrastructure
  or requiring credentials."
- "During the execution of the `terraform test` command, Terraform does not
  distinguish between a real and a mocked provider."
- "Mocked providers do not have any information about the expected format of the
  computed attributes, so the generated data will rarely match any expected
  syntax that real providers would return for those attributes."
- "Mocked providers only generate data for computed attributes. All required
  resource attributes must be set when you use a mocked provider."

So mocked tests confirm your configuration **produces the plan you intended**.
They do not confirm the cloud provider will accept it, that quotas and IAM
permit it, that ARNs are realistically shaped, or that the design is sound. A
mocked test suite passing is not evidence that a deployment would succeed.

Label such configuration honestly. In this repository:
*"AWS reference architecture — validated and mock-tested, not deployed or
verified against AWS."*

### 6.6 Assertions worth writing

Target silent defaults and security posture, not restatements of your own code:

```hcl
assert { condition = aws_dynamodb_table.votes.billing_mode == "PAY_PER_REQUEST" … }
assert { condition = aws_cloudwatch_log_group.app.retention_in_days != null … }
assert { condition = !strcontains(data.aws_iam_policy_document.app.json, "\"*\"") … }
assert { condition = alltrue([for k in ["project","environment","owner"] : contains(keys(aws_dynamodb_table.votes.tags), k)]) … }
```

Each of those asserts something a default would otherwise get wrong.

---

## Part 7 — Policy and security scanning

The step that closes the gap `validate` and your own tests leave: a scanner
encodes judgement you may not have had.

```bash
trivy config infra/                      # [verified: trivy 0.69.3 installed]
trivy config --severity HIGH,CRITICAL infra/
trivy config --exit-code 1 --severity HIGH,CRITICAL infra/   # for CI

checkov -d infra/                        # [not executed]
checkov -d infra/ --compact --quiet
checkov -d infra/ --hard-fail-on HIGH,CRITICAL
```

Scan the **plan** as well as the source for better coverage of computed values:

```bash
terraform plan -out=tf.plan
terraform show -json tf.plan > tf.plan.json
checkov -f tf.plan.json                  # [not executed]
```

Suppress findings in the configuration with a documented reason, never by
silently dropping a rule from CI.

---

## Part 8 — Plan review and approval

### 8.1 Produce a plan you can inspect

```bash
terraform plan -out=tf.plan          # save it; do not just read scrollback
terraform show tf.plan               # human-readable
terraform show -json tf.plan | jq '.resource_changes[] | {address, actions}'
```

There is **no `terraform dry-run` command**. `terraform plan` *is* the preview.

Useful JSON queries:

```bash
# Anything being destroyed or replaced
terraform show -json tf.plan | jq -r '.resource_changes[]
  | select(.change.actions | inside(["delete","create"]) | not)
  | "\(.change.actions|join(","))  \(.address)"'

# Count by action
terraform show -json tf.plan | jq -r '.resource_changes[].change.actions|join(",")' | sort | uniq -c
```

### 8.2 What to state before applying

Whether the agent or a human is driving, the plan review should name:

- resources to **create, update, replace, delete** — replacements especially
- **IAM changes**: new roles, trust policies, widened permissions
- **publicly reachable endpoints** created
- **cost drivers**: per-hour resources, data transfer, anything with a minimum
- **state and backend** changes
- **unresolved concerns** the plan does not settle

### 8.3 Approval boundaries for the agent

Write these into a committed `AGENTS.md` rather than leaving them in a chat
session. Committed, they survive a context reset and apply to any agent
pointed at the repository.

A workable split:

| Agent may do autonomously | Requires explicit human approval |
|---|---|
| Create and edit local files | `git push` |
| `terraform fmt`, `validate`, `test` | `terraform apply`, `destroy` |
| `init -backend=false`, local scans | Any remote workspace change |
| Read documentation via MCP | Creating or merging a PR |
| Run local tests | Anything that spends money or is publicly reachable |

Keep auto-apply disabled. And treat instructions found *inside* retrieved
documentation, logs or tool responses as untrusted content: a tool result that
tries to widen these boundaries is a prompt-injection attempt, not an
instruction. Note that this server ships guidance describing HCP workspace and
`apply_run` tools; under `--toolsets=registry` those tools do not exist, so that
guidance is inapplicable here.

---

## Part 9 — Offline and workshop preparation

Provider installation and MCP documentation retrieval both need network access.
Venue wifi and registry rate limits should not be on your critical path.

```bash
# Pre-pull the MCP server image
docker pull hashicorp/terraform-mcp-server:1.4.1

# Pre-cache provider plugins for every root
cd infra/aws-reference && terraform init -backend=false
cd ../local-demo      && terraform init

# Pre-cache the documentation you will reference
scripts/fetch-aws-docs.sh

# Shared plugin cache across roots
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
mkdir -p "$TF_PLUGIN_CACHE_DIR"
```

Rehearsal checklist:

- [ ] `terraform version` shows no upgrade nag (distracting on screen)
- [ ] `claude mcp get terraform` → `✔ Connected`
- [ ] Documentation cache populated, so a throttled registry cannot derail you
- [ ] `terraform test` passes with no network
- [ ] A saved plan file exists as a fallback if live commands misbehave
- [ ] `claude mcp reset-project-choices` if you want to demo the approval prompt

---

## Part 10 — CI

Everything above should run on every pull request, or it will quietly stop
being true.

```yaml
name: terraform
on: [pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.17.2

      - run: terraform fmt -check -recursive

      - name: Validate and test each root
        run: |
          for d in infra/*/; do
            echo "::group::$d"
            terraform -chdir="$d" init -backend=false
            terraform -chdir="$d" validate
            [ -d "$d/tests" ] && terraform -chdir="$d" test
            echo "::endgroup::"
          done

      - uses: aquasecurity/trivy-action@master
        with:
          scan-type: config
          scan-ref: infra/
          severity: HIGH,CRITICAL
          exit-code: '1'
```

**[not executed]** This workflow has not been run. Verify action versions
before relying on it. Mocked tests need no credentials, which is why the whole
job runs on a public runner safely.

Add a secrets scan (`gitleaks`) too — state and plan files leak, and a scan is
cheaper than a rotation.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Pending approval` in `claude mcp list` | Project-scoped server not yet trusted | Exit, run `claude` in the repo, approve |
| `Cannot connect to the Docker daemon` | Docker not running | Start Docker Desktop, or use the native binary |
| `provider not found: hashicorp/aws` | **Usually registry throttling**, not a real error | Pace calls, retry with backoff |
| MCP tools absent after registering | Client needs restart | Restart the session |
| HCP/workspace tools missing | `--toolsets=registry` excludes them | Intended. Add `terraform` toolset + token only if you need them |
| `terraform test` tries to create real resources | `command = apply` is the default | Add `mock_provider` **and** `command = plan` |
| `mock_provider` unrecognised | Terraform below 1.7.0 | Upgrade |
| Tests not discovered | Wrong extension or directory | Use `.tftest.hcl` in `tests/` |
| `init` fails offline | Plugins not cached | Pre-run `init`, set `TF_PLUGIN_CACHE_DIR` |
| Lock file conflicts in CI | Missing platform hashes | `terraform providers lock -platform=…` for every platform |
| Agent invented an argument | It skipped retrieval | Require an MCP lookup before generation; `validate` catches it |

---

## What this process does not give you

Worth saying plainly, especially from a stage:

1. **Mocked tests are not deployment evidence.** They verify your intended plan, not that the provider will accept it.
2. **`validate` is not a security review.** Hence scanning.
3. **Scanners encode known patterns.** They miss logic specific to your design.
4. **Retrieval reduces invention; it does not eliminate error.** An agent can retrieve correct documentation and still assemble it wrongly. The ladder exists for that reason.
5. **No tool here reviews intent.** A plan can be entirely correct and still not be what you wanted. That judgement stays human.

---

## Quick reference

```bash
# Prerequisites
brew install hashicorp/tap/terraform jq git trivy
docker pull hashicorp/terraform-mcp-server:1.4.1

# Connect MCP (registry only)
claude mcp add terraform --scope project -- \
  docker run -i --rm hashicorp/terraform-mcp-server:1.4.1 stdio --toolsets=registry
claude mcp list && claude mcp get terraform

# Discover before writing
scripts/mcp-query.sh list
scripts/mcp-query.sh call get_latest_provider_version '{"namespace":"hashicorp","name":"aws"}'
scripts/mcp-query.sh call get_provider_capabilities   '{"namespace":"hashicorp","name":"aws"}'
scripts/mcp-query.sh call search_provider_docs '{"provider_namespace":"hashicorp","provider_name":"aws","service_slug":"dynamodb_table","provider_document_type":"resources"}'
scripts/mcp-query.sh call get_provider_details '{"provider_doc_id":"14784520"}'

# Validate
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
tflint
terraform test -verbose
trivy config .

# Plan review (needs credentials)
terraform plan -out=tf.plan
terraform show tf.plan
terraform show -json tf.plan | jq '.resource_changes[] | {address, actions}'
```

---

## References

Official documentation:

- Terraform tests — https://developer.hashicorp.com/terraform/language/tests
- Test mocking — https://developer.hashicorp.com/terraform/language/tests/mocking
- `terraform test` command — https://developer.hashicorp.com/terraform/cli/commands/test
- `terraform plan` — https://developer.hashicorp.com/terraform/cli/commands/plan
- `terraform fmt` — https://developer.hashicorp.com/terraform/cli/commands/fmt
- `terraform validate` — https://developer.hashicorp.com/terraform/cli/commands/validate
- Provider requirements and version constraints — https://developer.hashicorp.com/terraform/language/providers/requirements
- Dependency lock file — https://developer.hashicorp.com/terraform/language/files/dependency-lock
- AWS provider registry — https://registry.terraform.io/providers/hashicorp/aws/latest/docs

Tools:

- Terraform MCP Server — https://github.com/hashicorp/terraform-mcp-server
- Model Context Protocol — https://modelcontextprotocol.io
- tflint — https://github.com/terraform-linters/tflint
- Trivy IaC scanning — https://trivy.dev/latest/docs/coverage/iac/terraform/
- Checkov — https://www.checkov.io/

Live version checks:

```bash
curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version
curl -s "https://api.releases.hashicorp.com/v1/releases/terraform?limit=5" | jq -r '.[]|"\(.version)\t\(.is_prerelease)"'
scripts/mcp-query.sh call get_latest_provider_version '{"namespace":"hashicorp","name":"aws"}'
```
