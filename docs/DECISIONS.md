# Decision record

Every decision taken on this project, with its reasoning and status. One row
per decision; the detail follows below.

This file is the authority on *what was decided and why*. It is not a progress
log — `PROGRESS.md` records what has been built and verified. It is not a
per-architecture ADR — those live in `adr/` and go deeper on single technical
choices.

Convention: **Active** decisions hold. **Superseded** ones are kept, not
deleted, because a reversed decision is more informative than a silent edit.
**Open** items are unresolved and block nothing until they do.

| # | Date | Decision | Status |
|---|---|---|---|
| 1 | 2026-11-16 | Run entirely locally — no AWS account, no credentials, no HCP Terraform | Active |
| 2 | 2026-11-16 | Two independent Terraform roots: one illustrative, one really applied | Active |
| 3 | 2026-11-16 | Shared core with a DynamoDB adapter as real code | **Superseded by 13** |
| 4 | 2026-11-16 | Workshop label is configuration, never hardcoded | Active |
| 5 | 2026-11-16 | Terraform upgraded 1.10.4 → 1.17.2 | Active |
| 6 | 2026-11-16 | MCP server pinned to `1.4.1`, `--toolsets=registry`, project scope | Active |
| 7 | 2026-11-16 | Three best-practice gaps deferred by choice | Deferred |
| 8 | 2026-11-17 | Documentation covers Phase 0 now, extends as phases land | Active |
| 9 | 2026-11-17 | Talk is 45+ minutes, workshop length | Active |
| 10 | 2026-11-17 | Room watches; the walkthrough is a take-home document | Active |
| 11 | 2026-11-17 | Three documents with distinct jobs: README, walkthrough, presentation | Active |
| 12 | 2026-11-17 | Stay dependency-free; report no coverage number | Active |
| 13 | 2026-11-17 | SQLite only for now; DynamoDB adapter deferred | Active |
| 14 | 2026-11-17 | One pull request, five commits — split rule overridden | Active |
| 15 | 2026-11-17 | No sub-agent orchestration; follow CLAUDE.md rules directly | Active |
| 16 | 2026-11-17 | Application targets Python >= 3.11, not the installed version | Active |
| — | — | `infra/` layout deviates from the CLAUDE.md structure | **Open** |
| — | — | Error message wording is unreviewed by the project owner | **Open** |

---

## 1 — Run entirely locally

**Decision.** No AWS account, no AWS credentials, no HCP Terraform account. The
application runs locally on Python and SQLite.

**Why.** The revised brief superseded the original cloud-deployed design. A
talk that depends on a live cloud account depends on a working venue network, a
billing relationship and a region that is having a good day.

**Consequence.** Nothing in this repository may request a credential. Fake
credentials and validation-skipping flags are also out, because they would let
a failed operation look like a successful one.

## 2 — Two independent Terraform roots

**Decision.** `infra/aws-reference/` is illustrative: validated and
mock-tested, explicitly never deployed. `infra/local-demo/` uses the `local`
provider, is really planned and really applied, with approval required before
apply.

**Why.** It separates the two things an audience conflates. The AWS root shows
*realistic architecture*; the local root shows *a real Terraform lifecycle*.
Trying to do both in one root would require either a cloud account or a
pretence.

## 3 — Shared core with a DynamoDB adapter — SUPERSEDED

**Decision as taken.** Build the DynamoDB adapter and Lambda handler as real,
unit-tested code against an injected fake client, so the AWS reference
architecture was backed by code rather than illustration.

**Superseded by 13** on 2026-11-17 when the scope narrowed to a bare-minimum
local application. The reasoning still stands and this may be revived; it is
recorded here so reviving it does not start from scratch.

## 4 — Workshop label is configuration

**Decision.** The event or city label comes from a `SESSION_PULSE_*`
environment variable. Precedence is Terraform-generated JSON, then environment
variables, then built-in defaults.

**Why.** The repository is public and reusable. A hardcoded city makes it a
souvenir of one event instead of something an attendee can run at theirs.

## 5 — Terraform 1.17.2

**Decision.** Upgraded from 1.10.4 to 1.17.2.

**Why.** Confirmed as latest stable from HashiCorp's release API rather than
from recollection.

**Worth keeping separate from the floor.** The *requirement* is lower than the
installed version: the `terraform test` framework needs 1.6.0+ and
`mock_provider` needs 1.7.0+, both read from HashiCorp's documentation.
Being current is a choice; those floors are constraints.

## 6 — MCP server configuration

**Decision.** `hashicorp/terraform-mcp-server:1.4.1`, invoked with
`--toolsets=registry`, registered at project scope in a committed `.mcp.json`.

**Why, in three parts.**

*Pinned, not `latest`* — an attendee cloning this repo in three months gets the
server that was demoed. Note the tag is `1.4.1`; `v1.4.1` does not exist.

*`--toolsets=registry`* — the server's default is `all`, which includes the HCP
Terraform workspace and run tools and the private registry. Narrowing to
`registry` removes every tool that could reach a cloud account, a workspace or
a run. This was established by running `--help` against the image, which also
corrected a wrong assumption that toolsets were set by environment variable.

*Project scope* — the configuration is committed, so it is reviewable in a pull
request and reproducible by anyone who clones. The cost is that it requires one
human approval per project, which is the point rather than a drawback.

**Two independent guardrails result:** one human (per-project approval of
committed configuration) and one capability-level (the toolset flag). Neither
depends on the other.

## 7 — Three best-practice gaps, deferred by choice

**Decision.** Deferred, not overlooked: no IaC security scanning, no CI, no
linting or pre-commit hooks. `AGENTS.md` is also unwritten.

**Why it matters that these are named.** Gap one contradicts the mandatory
Checkov gate in CLAUDE.md. `terraform validate` checks schema, not safety — it
will validate a wide-open security group without complaint. Mocked tests only
assert what the author thought to assert. So neither catches an over-permissive
IAM policy, and a policy scanner is the thing that encodes judgement the author
may not have had.

**Sequencing note.** These guardrails tell a stronger story existing *before*
the AI writes the Terraform than retrofitted after.

## 8 — Documentation covers Phase 0 now

**Decision.** Write documentation for what has actually been run, and extend it
as later phases are built and verified.

**Why.** Phases 2–5 do not exist. A walkthrough covering them would contain
invented expected output — which is both dishonest and fragile, since the real
command would print something else on stage.

**Rejected alternatives.** Building everything first and documenting once
(longer wait, nothing followable meanwhile). A full skeleton with placeholders
(risks placeholders being mistaken for verified steps).

## 9 — 45+ minute workshop-length talk

**Decision.** The session is 45 minutes or longer.

**Consequence.** Around 30 slides, and the offline-preparation material needs
to be solid rather than nominal.

## 10 — The room watches

**Decision.** Attendees do not type along. The deck carries the narrative and
the presenter drives the terminal.

**Consequence, and it is a significant one.** The walkthrough is written for
someone alone, weeks later, with nobody present to unblock them. Every step
must therefore state its own failure modes and fixes — it cannot rely on a
presenter filling gaps.

## 11 — Three documents, distinct jobs

**Decision.**

| Document | Job | Organised by |
|---|---|---|
| `README.md` | Front door: what this is, what is built | Orientation |
| `walkthrough.md` | Hands-on steps you type | Time |
| `presentation.md` | The talk | Narrative |
| `iac-with-terraform-mcp.md` | Reference appendix | Topic |
| `PROGRESS.md` | Internal build log | Chronology |

**Why.** The reference document already written is organised by topic — "here
is everything about mocked testing". A guided document must be organised by
time — "run this, expect this, here is why". Same material, different axis, and
one cannot substitute for the other.

## 12 — Dependency-free; no coverage number

**Decision.** Standard library only, including in tests. No coverage tool is
installed and **no coverage percentage will be reported**.

**Why.** Zero dependencies is a deliberate, demonstrable property of the
project. Measuring coverage requires `coverage.py`, a third-party package, and
installing it to satisfy a gate would falsify the claim the gate exists to
protect.

**The conflict, stated plainly.** CLAUDE.md makes ≥80% unit coverage a blocking
gate. That gate will **not** be verified. Any pull request must say so
explicitly rather than implying it passed. Tests are written thoroughly against
an agreed list; thoroughness is asserted, not measured.

**Rejected.** `coverage.py` as a dev dependency (breaks the property). The
stdlib `trace` module (keeps the property, but clumsy and inaccurate enough
that the number would mislead).

## 13 — SQLite only; DynamoDB adapter deferred

**Decision.** One storage adapter. `app/storage/base.py` defines the interface
so the seam stays clean, but nothing is built behind it yet.

**Why.** "Bare minimum" means one adapter. Adding the second later without
touching core or validation code is itself the evidence that the abstraction
earned its place — a better demonstration than asserting it up front.

**Supersedes 3.**

## 14 — One pull request, five commits

**Decision.** Five conventional commits in dependency order — `feat(core)`,
`feat(storage)`, `feat(api)`, `feat(ui)`, `docs` — in a single pull request.

**Rule overridden.** The CLAUDE.md >10-file rule defaults to one PR per commit
group, which would have meant five stacked PRs. Overridden by explicit
instruction; the override applies to this session only and must be stated in
the PR description.

**Why.** Five stacked PRs is disproportionate review ceremony for a demo
repository.

## 15 — No sub-agent orchestration

**Decision.** Do the work directly and follow the *rules* in CLAUDE.md —
commit convention, error standards, ADR, CHANGELOG, sdlc-log — rather than
route through the agent ecosystem it describes.

**Why.** `.claude/agents/` does not exist in this repository. None of the
fourteen agent definitions CLAUDE.md mandates, including
`sdlc-orchestrator` and `senior-fullstack-developer`, are present. Agents that
are not defined cannot be invoked, and simulating the orchestration would be
theatre.

**This is a live conflict with CLAUDE.md**, recorded rather than resolved. It
disappears if the agent definitions are added.

## 16 — Target Python >= 3.11

**Decision.** The application declares `>= 3.11`, not the installed version.

**Why.** The installed interpreter moved from 3.14.8 to 3.15.2 between two
consecutive working days. Pinning to whatever happened to be installed on a
given day would make the project fail for attendees for no reason.

---

## Open — not yet decided

### `infra/` layout deviates from the CLAUDE.md repository structure

CLAUDE.md specifies
`infrastructure/terraform/modules|environments/{dev,staging,prod}`. This project
uses `infra/aws-reference/` and `infra/local-demo/` — a split by *demo purpose*
rather than by environment, because one root is deliberately never deployed and
therefore has no environment.

The project layout appears right for a talk, but the convention is the owner's
and the deviation is theirs to accept or reject. This becomes real at Phase 4
and nothing before then depends on it.

### Error message wording is unreviewed

The user-facing error strings for the application were drafted to satisfy the
CLAUDE.md standard — name the cause, say what to do next, never show raw
validator text or a bare status code. They have not been reviewed by the
project owner, who is the one presenting them. Worth a read-through before they
are set in tests, since each is asserted verbatim.

---

## Appendix — the approved implementation prompt

Kept here because it is the contract the application is built against, and
because a decision record that omits the operative instruction is incomplete.
Decisions 12, 13, 14 and 16 are folded into it.

See the prompt agreed on 2026-11-17 covering: stdlib-only Python >= 3.11;
I/O-free `app/core/`; SQLite as the sole adapter behind an interface;
parameterised SQL and one transaction per vote; the six routes; the three
required questions; the privacy rules (submission UUID, three choice keys, a
timestamp, nothing else, no request-body logging); the verbatim error
catalogue; a vanilla-JS frontend responsive to 360px with idempotent retry and
visibility-aware polling; `unittest` tests including one per error path
asserting exact message text; no coverage tool and an explicit statement that
the ≥80% gate was unverified; five commits in one PR; CHANGELOG, ADR 0001 and
`sdlc-log.md` entries; and nothing committed or pushed until asked.
