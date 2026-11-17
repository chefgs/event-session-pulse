# Walkthrough — Phase 0: from an empty machine to verified Terraform documentation

A worksheet. You run every command; nothing here has been run for you.

This covers **Phase 0 only**: getting the Terraform MCP Server connected and
proving it returns real provider documentation. Writing Terraform, testing it
and planning it are Phases 2–5 and are not in this document yet — they will be
added once they exist and have been run, not before.

For the topic-organised reference (every flag, every toolset, the full
validation ladder), see `iac-with-terraform-mcp.md`. This document is the
sequence; that one is the encyclopedia.

---

## How to use this document

Work top to bottom. Each step has the same shape:

| Field | Meaning |
|---|---|
| **Goal** | Why this step exists at all |
| **Run** | Type exactly this |
| **Look for** | How to tell it worked, without needing to match output character for character |
| **Proves** | What you now know that you did not know before |
| **Does not prove** | The limit — stated so you do not over-claim it on stage |
| **If it fails** | The specific failure I hit, and its fix |
| **Observed** | Empty. Paste your real output here |

Do not skip the **Does not prove** rows. They are the part of this process that
survives a sceptical question from the audience.

### Who performs each action

Three different actors appear in this walkthrough and the talk depends on not
blurring them:

| Marker | Actor | Example |
|---|---|---|
| `[you]` | You, in a terminal | `terraform version` |
| `[mcp]` | A documentation call to the MCP server | `get_latest_provider_version` |
| `[agent]` | Claude Code editing a file | writing `.mcp.json` |

No step in Phase 0 contacts AWS. No step needs cloud credentials. If any
command here asks you for a credential, stop — something is wrong.

### My reference run

Where I state a version, it is what **I** saw on 2026-11-16 on macOS (Darwin
27.2.0, Apple Silicon). Registry versions move. If yours differ, yours are
right and this document is stale — tell me and I will correct it.

---

## Step 0 — Pre-flight

**Goal.** Find out now what is missing, rather than halfway through.

**Run** `[you]`

```bash
# Each line prints a version or fails. Failure here is information, not a problem.
terraform version
docker --version
git --version
jq --version
python3 --version
claude --version
```

**Look for.** Six version strings. Anything that says `command not found` is a
gap to close in Step 1.

**Proves.** Which of the prerequisites you already have.

**Does not prove.** That the versions are *current*, or that Docker is actually
**running** — `docker --version` answers from the CLI binary and succeeds even
when the engine is stopped. Step 2 is what tests the engine.

**If it fails.** Nothing to fix yet. Record what is missing and continue.

**Observed**

```text
(paste your output here)
```

---

## Step 1 — Install what is missing

**Goal.** Reach a known-good toolchain.

**Run** `[you]` — only the lines for things Step 0 reported missing:

```bash
# macOS, Homebrew
brew install terraform    # or: brew tap hashicorp/tap && brew install hashicorp/tap/terraform
brew install jq git
brew install --cask docker          # Docker Desktop
```

Then confirm you are on current Terraform rather than assuming it:

```bash
# Ask HashiCorp what the latest stable release is — do not trust memory
curl -s https://api.releases.hashicorp.com/v1/releases/terraform/latest | jq -r .version
terraform version
```

**Look for.** The two versions matching, or a deliberate decision to stay
behind.

**Proves.** Your Terraform is current as of today, established from
HashiCorp's own release API.

**Does not prove.** That current is *required*. Note the real floors, because
they matter in Phase 4: the `terraform test` framework needs **1.6.0+**, and
`mock_provider` needs **1.7.0+**. Both read from HashiCorp's documentation.

**If it fails.** `brew install terraform` installs a community formula that has
historically lagged. The `hashicorp/tap` form is the vendor's own.

**My run.** Latest stable `1.17.2`; I upgraded from `1.10.4`. Python `3.14.8`.

**Observed**

```text
(paste your output here)
```

---

## Step 2 — Confirm the Docker engine is actually running

**Goal.** Separate "the CLI exists" from "the engine will run a container".
This is the failure you are most likely to hit, because the engine does not
survive a reboot unless you told it to.

**Run** `[you]`

```bash
docker info --format '{{.ServerVersion}}'
```

**Look for.** A single version number. An error mentioning
`Cannot connect to the Docker daemon` means the CLI is fine and the engine is
down.

**Proves.** A container can start, so the MCP server can run.

**Does not prove.** Anything about the MCP image yet.

**If it fails.** Start Docker Desktop and re-run. On macOS:
`open -a Docker`, then wait for the whale icon to stop animating. This exact
failure is why the MCP server showed `CONNECTION_CLOSED` at the start of this
session — the server is a container, so no engine means no server.

**My run.** `29.9.3` (Docker Desktop).

**Observed**

```text
(paste your output here)
```

---

## Step 3 — Pull the MCP server at a pinned version

**Goal.** Get the server image, pinned — not `latest`.

**Run** `[you]`

```bash
docker pull hashicorp/terraform-mcp-server:1.4.1
docker run --rm hashicorp/terraform-mcp-server:1.4.1 --version
```

**Look for.** The reported version matching the tag you asked for.

**Proves.** The image runs on your machine and self-reports its version.

**Does not prove.** That `1.4.1` is the newest release. Pinning is a
reproducibility choice, not a currency claim — an attendee cloning this repo in
three months gets the same server you demoed.

**If it fails.** The tag is `1.4.1`, **not** `v1.4.1` — the `v`-prefixed tag
does not exist and fails with a manifest error. If you would rather not use
Docker at all, there is a native binary: `brew install terraform-mcp-server`
(Homebrew carried `1.4.1` when I checked). Same server, no container; you would
then change `.mcp.json` to invoke the binary instead of `docker run`.

**Observed**

```text
(paste your output here)
```

---

## Step 4 — Interrogate the server before trusting it

**Goal.** Find out what the server exposes **by default**, rather than
assuming. This step is the single most useful one in the whole walkthrough and
it is the one everybody skips.

**Run** `[you]`

```bash
docker run --rm hashicorp/terraform-mcp-server:1.4.1 --help
```

**Look for.** How toolsets are selected, and what the default is.

**Proves.** Two things worth saying out loud on stage, both of which contradict
the obvious guess:

1. Toolsets are chosen with a **`--toolsets` command-line flag**, not an
   environment variable.
2. The default is **`all`** — which includes the HCP Terraform toolsets
   (workspaces, runs, applies) and the private registry. Not just public docs.

**Does not prove.** That `all` is dangerous *on its own*. Those tools still
need a token to do anything. But a default that reaches further than you
intended is worth narrowing deliberately.

**Why this matters more than it looks.** I had written both of those facts the
other way round in my own plan before running this command. Reading `--help`
cost five seconds and corrected two wrong assumptions that would have shipped
into a conference talk.

**If it fails.** Nothing commonly fails here.

**Observed**

```text
(paste your output here)
```

---

## Step 5 — Register the server, scoped to the repository

**Goal.** Make the configuration reviewable, committed and reproducible for
anyone who clones the repo.

This file already exists in the repo — read it rather than recreating it:

**Run** `[you]`

```bash
cat .mcp.json
```

The registration it holds:

```json
{
  "mcpServers": {
    "terraform": {
      "type": "stdio",
      "command": "docker",
      "args": ["run","-i","--rm","hashicorp/terraform-mcp-server:1.4.1","stdio","--toolsets=registry"],
      "env": {}
    }
  }
}
```

**Look for.** Three deliberate choices: the pinned tag, `--toolsets=registry`,
and an empty `env` — no credentials anywhere.

**Proves.** The capability boundary is **in version control**. A reviewer can
object to it in a pull request. An attendee gets the same boundary by cloning.

**Does not prove.** That the server is connected. Registration and connection
are separate; Step 6 is the connection.

**Scope choice, if you are doing this on a different project.** `claude mcp add`
takes `--scope local` (just you, this machine), `--scope project` (committed to
`.mcp.json`, what this repo uses) or `--scope user` (you, everywhere). Project
scope is right for a workshop precisely *because* it is shared — which is also
why it requires the human approval in Step 6.

**Observed**

```text
(paste your output here)
```

---

## Step 6 — Approve the server, then confirm it connected

**Goal.** Pass the human gate, and verify rather than assume.

**Run** `[you]`

```bash
claude mcp list
claude mcp get terraform
```

**Look for.** `Connected`. If it says `Pending approval`, start `claude` in
this directory and approve the `terraform` server when prompted.

**Proves.** The approval gate is real and it is **per project**. Claude Code
will not connect to a server defined in a committed file until a human says so
once — because `.mcp.json` arrives with the repository, from whoever wrote it.

**Does not prove.** That the server is safe. Approval records *consent*, not
*scrutiny*. The thing that actually constrains the server is
`--toolsets=registry` from Step 5. Two independent guardrails: one human, one
capability-level.

**If it fails.** `CONNECTION_CLOSED` almost always means the Docker engine is
down — go back to Step 2. To rehearse the approval prompt itself (useful before
a talk), clear the stored decision with
`claude mcp reset-project-choices` and restart.

**My run.** `Scope: Project config (shared via .mcp.json)`, `Status: Connected`,
nine tools exposed as `mcp__terraform__*`.

**Observed**

```text
(paste your output here)
```

---

## Step 7 — Make a real documentation call

**Goal.** Prove the connection does useful work, and that the answer is live
rather than recalled.

**Run** `[you]` — the scripted path, which works regardless of client state:

```bash
./scripts/mcp-query.sh list
./scripts/mcp-query.sh call get_latest_provider_version '{"name":"aws","namespace":"hashicorp"}'
```

`[mcp]` Then ask Claude Code the same question through the native tool, and
compare the two answers.

**Look for.** Nine tools in the listing, and the same provider version from
both paths.

**Proves.** The agent is reading the registry at call time. Two independent
clients agreeing rules out a cached or confabulated answer.

**Does not prove.** That the documentation is *correct* for your use, or that
the agent will use it properly once it has it. Retrieval removes one failure
mode — inventing a schema — and leaves every other one intact.

**If it fails.** A reply of `provider not found: hashicorp/aws` is usually
**registry rate limiting wearing a misleading error message**, not a missing
provider. Wait and retry; `scripts/fetch-aws-docs.sh` already paces itself with
backoff for this reason. Also note the parameter is
`provider_document_type` — `provider_data_type` is wrong and will be rejected.

**My run.** AWS provider `6.73.0`, `local` provider `2.9.1`, both via the
native tool; `6.73.0` also via the script, so the paths agreed.

**Observed**

```text
(paste your output here)
```

---

## Step 8 — Cache the documentation as evidence

**Goal.** Put the retrieved documentation on disk so the claim "this code was
written against real schemas" is auditable, and so the demo survives bad venue
wifi.

**Run** `[you]`

```bash
./scripts/fetch-aws-docs.sh
ls -la docs/mcp-evidence/
wc -l docs/mcp-evidence/*.md
```

**Look for.** Ten resource documents. The script skips files it already has, so
a second run should be nearly instant.

**Proves.** The inputs to Phase 4 are reviewable. When the Terraform gets
written, the schema it was written against is in the repository next to it.

**Does not prove.** That the cache is current. It is a point-in-time snapshot
against AWS provider `6.73.0`. Cached documentation going stale is a real
failure mode, and the fix is to record the provider version alongside it —
which the filenames and this note do.

**If it fails.** See the rate-limiting note in Step 7.

**Observed**

```text
(paste your output here)
```

---

## What Phase 0 establishes, honestly

Worth being precise, because the temptation is to claim more:

**You can now show** that an agent writing Terraform is reading current
provider schemas from the registry at the moment it writes, through a server
whose reach you deliberately narrowed and a human approved, with the retrieved
documentation committed as evidence.

**You cannot yet show** anything about Terraform correctness. No `.tf` file
exists in this repository. Nothing has been formatted, validated, tested,
planned or applied. The validation ladder is documented and unexercised.

That honest boundary is itself the strongest part of the talk: it is the
difference between demonstrating a workflow and asserting one.

---

## What to send back

For each step, the command you actually ran and its real output — including
anything that failed, which is more useful than the successes. If a step's
wording was unclear or assumed knowledge it did not give you, say so; that is a
defect in this document, not in your reading of it.

Once your output is in, I will:

1. Replace every `Observed` block with your real output.
2. Correct any version or behaviour where your run disagrees with mine.
3. Fix any step that turned out not to be followable as written.
4. Then write `README.md` and `docs/presentation.md` — both of which should
   quote only output that actually happened on your machine.
