# 🧭 Wayfinder

**An agent crew that turns Linear tickets into GitHub PRs — built on Claude Code.**

Wayfinder is a **Linear-ticket → GitHub-PR autonomous coding pipeline** built entirely from
[Claude Code](https://claude.com/claude-code) subagents, slash commands, a macOS
sandbox, and an eval harness. Each agent is modeled on a senior engineering role
and assigned a model tier matched to its cognitive load. Every ticket runs in its
own git worktree and ends as a PR with green CI that you review and merge yourself.
A run never stops to ask you questions, and it **never merges or marks a ticket Done.**

```
/wf ENG-12 ENG-13 ENG-14  # hands-off: each ticket → PR with green CI (In Review)
                          # …you review & merge the PRs yourself…
"ENG-12 is merged"        # only now does the workflow clean up (Linear marks it Merged)
```

There is no per-repo setup. `/wf` reads the repo's own `CLAUDE.md`/`AGENTS.md`.
`/wf-spec <ids>` is optional, for tickets you want to agree a spec on before building.

See [`docs/TICKET-WORKFLOW.md`](docs/TICKET-WORKFLOW.md) for the full framework
overview and [`docs/ticket-workflow.html`](docs/ticket-workflow.html) for a visual
explainer. **The agent and command files are the source of truth** — the docs are
an overview; when they disagree, the files win.

## What's in the box

| Path | What |
|---|---|
| `agents/wf-*.md` | 9 subagents: planner, executor, reviewer, verifier, runner, spec-builder, the Linear/GitHub boundary agents, and an eval judge |
| `commands/wf*.md` | 5 slash commands: `/wf`, `/wf-spec`, `/wf-quick`, `/wf-eval`, `/wf-calibrate` |
| `bin/wf-exec` | Runs a repo's install/tests/lint inside a no-network, no-secrets sandbox |
| `bin/wf-fetch-handoff` | Safely downloads a Linear design-handoff embed (allowlisted, size-capped, zip-slip-guarded) |
| `hooks/` | Two guard hooks: sandbox enforcement + boundary-agent tool-call enforcement |
| `ticket-workflow-sandbox.sb.template` | macOS seatbelt profile (installer fills in your `$HOME`) |
| `ticket-workflow-evals/` | The regression gate — fixtures, cases, rubrics, baselines, judge calibration |

## Design principles

- **Hands-off.** Open decisions get a safe default, recorded in the PR and on the
  ticket for a human to overrule. Only a ticket with no workable goal is parked,
  with its questions posted to Linear.
- **Context comes from the repo.** The Opus planner reads the repo's own
  instructions and code once and emits a dense Context Pack. Cheaper downstream
  agents work from it instead of re-reading the codebase. Gaps in the repo's
  instructions come back as suggested `CLAUDE.md` additions.
- **Scoped local checks, CI as the finish line.** Agents check only what the change
  touches. Whole-repo suites run in CI, and `/wf` fixes CI failures until green.
- **Single-owner boundaries.** Only `wf-linear` touches Linear; only `wf-github`
  touches GitHub. A `SubagentStop` hook blocks either from finishing without a real
  tool call (no fabricated answers).
- **Sandboxed execution.** All project code runs through `wf-exec`: no network
  egress, no credential-file reads, and secret-shaped env vars (`*TOKEN*`, `*_KEY`,
  `AWS_*`, …) stripped. Dependencies install offline from your local cache. A
  `PreToolUse` hook blocks unwrapped project code and raw network tools
  (`curl`/`wget`/`ssh`/…) inside worktrees. This breaks the "lethal trifecta"
  (untrusted ticket text + repo secrets + exfiltration path).
- **Never autonomous on irreversible steps.** No merging, no setting Done. A human
  always closes the loop.
- **Model tiering is deliberate.** Opus for decisions/architecture/bug-catching,
  Sonnet for execution/verification, Haiku for high-volume structured API calls.

## Prerequisites

- **macOS** — the execution sandbox uses `sandbox-exec` (seatbelt). See
  [Platform support](#platform-support).
- **Claude Code** with a Claude subscription or API key.
- **[Linear MCP](https://linear.app/docs/mcp)** connected in Claude Code (`/mcp`).
- **`gh` CLI**, installed and authenticated (`gh auth status`).
- **`jq`** (used by the guard hooks).
- **`node`** and **`python3`** to run the eval fixtures (stdlib only; no deps).
- Git repos with an `origin` remote and a default branch.

## Install

```bash
git clone https://github.com/kyuss/wayfinder
cd wayfinder
./install.sh
```

The installer copies the `wf-*` files into `~/.claude/`, generates the sandbox
profile for your machine, and sets up the eval fixtures.

Then it checks `~/.claude/settings.json` for the hook entries and `gh` permission
rules in [`settings.hooks.json`](settings.hooks.json). The hooks enforce the sandbox
and the boundary guard. The permission rules let `wf-github` run `gh` without prompts,
so a hands-off run doesn't stall.

If anything is missing, the installer lists it and asks before adding it. It only
adds entries: your existing settings stay as they are, and it saves a timestamped
backup first.

To edit the file yourself, answer no or run `./install.sh --no-settings`. The
installer then prints the manual steps, and repeats the check on every run until
nothing is missing.

Then, in Claude Code: connect Linear (`/mcp`) and run `/wf <TICKET-ID>` from a repo.

## Linear workflow states

`wf-linear` lists each team's real states and matches by exact name, then a synonym
table, then a per-stage fallback. At Drata the stages resolve like this:

| Workflow step | Drata state |
|---|---|
| Work starts (after planning) | In Progress |
| PR open, CI green | In Review (Code Review on Infrastructure) |
| Ticket parked with questions | Blocked; teams without it keep their state |
| Spec agreed (`/wf-spec`) | Ready for Development where it exists, else Todo |
| PR merged | Merged, set by Linear's GitHub integration. The workflow leaves it there. |

**Done is never automatic.** The workflow refuses to set any completed-type state
(Done, Merged, Deployed, Closed). It never moves a completed, canceled or duplicate
ticket backwards. It detects parked tickets by their `🤖 Spec questions` comment,
not by their state.

## Developing / testing changes

There's no build step — **the eval harness is the test suite.** After changing any
agent prompt, model tier, or the flow:

```
/wf-eval                 # full seed set vs the saved baseline
/wf-eval node-feature    # iterate on one case (cheaper)
```

`wf-judge` scores each stage against a rubric and the runner flags regressions.
Run `/wf-calibrate` after changing the judge's model or prompt to keep the gate
trustworthy.

## Platform support

The sandbox is **macOS-only** (`sandbox-exec` / seatbelt). On other platforms the
agents and commands still install and most of the flow works, but `/wf` will
run project tests/build **without the sandbox** — meaning untrusted ticket/PR
content and dependency code run unconfined. Don't run it against untrusted tickets
on non-macOS until a Linux sandbox backend (e.g. bubblewrap) is wired in.
Contributions welcome.

## Security

This runs autonomous agents against your repos. The threat model and mitigations
(sandbox, boundary guards, read-only handoff ingestion, never-merge policy) are
described in [`docs/TICKET-WORKFLOW.md`](docs/TICKET-WORKFLOW.md). The sandbox is
defense-in-depth, not a guarantee — review PRs before merging.

**Audit the sandbox deny-list against your own secrets.** The seatbelt profile is
`(allow default)` with carve-outs, so it blocks reads of the *standard* credential
stores (`~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.config/gh`, `~/.config/git`, `~/.netrc`).
If you keep secrets elsewhere (`.env` files in repos, a custom
`$CLOUDSDK_CONFIG` or other cloud-CLI cache, tokens outside `$HOME`), add matching
`deny file-read*` entries to `ticket-workflow-sandbox.sb.template` before installing.

## License

[MIT](LICENSE)
