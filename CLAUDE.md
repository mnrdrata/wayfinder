# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This is the **development home for an agentic ticket workflow** — a Linear-ticket → GitHub-PR autonomous coding pipeline built entirely from Claude Code subagents, slash commands, a sandbox, and an eval harness. This project directory is just the workspace you operate from; **the system itself lives at user level in `~/.claude/`** and is auto-loaded into every Claude Code session on this machine.

When asked to change "the workflow," "an agent," or "a command," you are editing files under `~/.claude/`, not files in this directory.

**Source of truth:** the agent files (`~/.claude/agents/*.md`) and command files (`~/.claude/commands/*.md`) are self-documenting and define real behavior. The prose docs (`docs/TICKET-WORKFLOW.md`, `docs/ticket-workflow.html`, in this project directory) are overviews — when they disagree with the agent/command files, the files win. Read the relevant file before editing; never recreate or contradict the system from memory.

## Where everything lives

```
~/.claude/
├── agents/                       # the subagent definitions (personas + tools + model tier)
├── commands/                     # the slash commands (orchestrators)
├── bin/wf-exec                   # execution wrapper (secret env vars stripped, credential files unreadable)
├── bin/wf-fetch-handoff          # downloads + unpacks a Linear file-embed (design handoff) safely
├── hooks/wf-sandbox-guard.sh     # PreToolUse hook enforcing wf-exec inside worktrees
├── hooks/wf-boundary-toolcall-guard.sh  # SubagentStop hook: boundary agents must call a tool (no fabrication)
├── ticket-workflow-sandbox.sb    # macOS seatbelt profile
└── ticket-workflow-evals/        # regression gate: fixtures/ cases/ baselines/ calibration/

<this project>/                   # development home + documentation
├── CLAUDE.md                     # this file
└── docs/
    ├── TICKET-WORKFLOW.md        # full framework overview (read this first for deep context)
    └── ticket-workflow.html      # visual explainer (older; shows the pre-/wf flow)
```

## This repo IS the version-controlled source — `~/.claude/` is a deployed copy

`install.sh` copies **this repo → `~/.claude/`** (one-way: `agents/`, `commands/`, `bin/`, `hooks/`, and the whole `ticket-workflow-evals/`). So:

- The files that **auto-load into every session** and actually run are the ones under `~/.claude/` (the live copy). That's why you edit/operate there.
- The files that are **version-controlled** are the ones in *this* repo. `~/.claude/` is **not** a git repo — changes made there show up in **no** `git status` until you copy them back here.
- **To commit any change that originated in `~/.claude/`, sync it back into this repo's mirror first, then `git add`/commit.** Don't conclude "nothing to commit" from a clean `git status` in this repo alone — check the live copy too (`diff -rq ~/.claude/<dir> ./<dir>`).

**Eval outputs are the common case of this.** `/wf-eval` uses `EVAL=~/.claude/ticket-workflow-evals`, so every run record (`baselines/run-<date>.md`) and any `baseline.md` promotion lands in the **deployed** copy, never here. Committing eval results = `cp ~/.claude/ticket-workflow-evals/baselines/{baseline.md,run-*.md} ./ticket-workflow-evals/baselines/` → commit. (This bit me once: I reported "nothing to commit" because I'd only looked at this repo's clean status.)

## The agents (`~/.claude/agents/`)

**Reasoning agents** — `wf-planner` (opus: reads the repo's own `CLAUDE.md`/`AGENTS.md` + code, drafts the definition of done, decides open questions, emits plan + forward Context Pack), `wf-executor` (sonnet: implements plan with atomic commits; also fixes failing CI checks), `wf-reviewer` (opus: reviews diff coverage-first — only precisely-routed BLOCKING items drive the fix loop; flags auth/permissions/customer-data changes as `HUMAN_REVIEW`), `wf-verifier` (sonnet: lint/type/tests scoped to changed files, proves the definition of done; whole-repo suites are `LEFT_TO_CI`), `wf-spec-builder` (opus, optional + interactive: ticket → spec via `/wf-spec`).

**Boundary agents** — each owns *all* I/O to one external system so other agents stay free of API plumbing: `wf-linear` (haiku, all Linear MCP calls), `wf-github` (haiku, all `gh` CLI calls, including watching CI checks and fetching failure logs).

**Orchestration agent** — `wf-runner` (sonnet: drives one ticket's execute → review+verify → ≤2 fix rounds inner loop in its worktree; `/wf`'s single canonical inner loop; never touches Linear/GitHub, never asks the user).

**Eval-only** — `wf-judge` (sonnet, LLM-as-judge; used by the eval harness, never in `/wf`).

Model tiering is deliberate: Opus for decisions/architecture/bug-catching, Sonnet for execution/verification/grading, Haiku for high-volume structured external calls.

## The commands (`~/.claude/commands/`)

- `/wf <ids>` — hands-off, ticket → PR with green CI. Each ticket in its own git worktree; planned concurrently, executed ≤3 at a time (file-overlapping tickets serialized). Never asks mid-run: open decisions become recorded defaults (PR body + Linear comment); a ticket with no workable goal gets its questions posted to Linear and is parked in *Needs Answers* (re-running `/wf <id>` reads the answers). After PRs open, a **CI stage** watches checks and runs ≤3 executor fix rounds per PR; green → *In Review*, still red → draft PR + comment. No per-repo setup: context comes from the repo's own instructions.
- `/wf-spec <ids>` — optional, interactive; refine tickets into specs posted as a marked Linear **comment** on each ticket (description becomes a short Why/What/Success-criteria brief). `/wf` uses the spec comment when present.
- `/wf-quick <id> <instruction>` — small follow-up change on an existing ticket worktree; pushes so the open PR updates.
- `/wf-eval [case ...]` — the regression gate (see below).
- `/wf-calibrate` — validates `wf-judge` against a human-labeled gold set (agreement, FAIL precision/recall, bias probes) so the `/wf-eval` gate is trustworthy. Offline; re-run after changing the judge's model or prompt.

Typical flow: `/wf <ids>` (optionally `/wf-spec <ids>` first for vague tickets).

## Developing the workflow — test/verify loop

There is no build or lint step; **the eval harness is the test suite.** After changing any agent prompt, model, or the flow, run the regression gate:

```
/wf-eval                 # full set of seed cases vs baseline
/wf-eval node-feature    # iterate on a single case id (cheaper)
```

- Cases live in `~/.claude/ticket-workflow-evals/cases/*.md` (mock ticket + fixture + per-stage rubric).
- Fixtures (`fixtures/node-toy`, `fixtures/py-toy`) are tiny dependency-free git repos; their tests run via stdlib (`node --test`, `python3 -m unittest`) so they need no installs.
- `wf-judge` scores each stage against the rubric; the runner compares to `baselines/baseline.md` and flags regressions (PASS→FAIL or score drop > 0.15).
- Cost-aware: iterate on one case id while developing; run the full set before committing a prompt/model change.

## Architecture invariants — respect these when editing

These are non-obvious and load-bearing; changing an agent/command must not violate them:

- **Context flows forward, never re-derived.** There is no generated manual. The Opus planner reads the repo's own `CLAUDE.md`/`AGENTS.md` (+ manifests/CI config) and code once, and emits a dense `CONTEXT_PACK` (scoped commands, repo rules, patterns); cheaper downstream agents consume that instead of re-reading the codebase each loop. This is the core cost/quality win — don't make downstream agents re-explore.
- **Hands-off.** `/wf` never asks the user mid-run (no `AskUserQuestion`). Unclear → safe default recorded in `SPEC_GAPS`; unworkable → questions posted to Linear and the ticket parked. Don't reintroduce mid-run prompts.
- **Scoped local checks, CI is the finish line.** Agents run lint/type/tests on changed files only; whole-repo, e2e and integration suites are CI's job (`LEFT_TO_CI`). Don't make the verifier or executor run whole-repo suites on large repos.
- **Single-owner boundaries.** Only `wf-linear` touches Linear, only `wf-github` touches GitHub. Subagents can't spawn subagents, so the orchestrator command pre-fetches via these two and passes data down. **Tool-call enforced:** a `SubagentStop` hook (`~/.claude/hooks/wf-boundary-toolcall-guard.sh`, wired in `settings.json`, scoped to these two agents) blocks either boundary agent from finishing with zero tool calls — that signals a fabricated answer instead of a real fetch. Don't remove this guard or let the boundary agents answer from context.
- **Wrapped execution.** All project code (install/test/build/lint) runs through `~/.claude/bin/wf-exec` — no credential-file reads (seatbelt), and secret-shaped env vars (`*TOKEN*`, `*SECRET*`, `*_KEY`, `AWS_*`, etc.) stripped so project code can't read a host token and commit it into the diff. **Network is allowed** (installs need it), so the secrets carve-out is what protects you. The `PreToolUse` guard blocks unwrapped project-code runners (npm/node/pytest/cargo/…) inside worktrees, and blocks raw network binaries (`curl`/`wget`/`ssh`/`scp`/…) there **even when wrapped** — the backstop for the opus planner/spec-builder (which also have WebFetch removed). Keep new project-code execution wrapped; `git`/`gh` stay unwrapped by design.
- **Design-handoff ingestion is orchestrator-side and read-only.** `wf-linear` `FETCH` surfaces description file-embeds as `ATTACHMENTS` (it can't download — MCP-only). The orchestrator downloads them via `~/.claude/bin/wf-fetch-handoff` (Linear-host allowlist, https-only, size-capped, zip-slip-guarded — it fetches *untrusted* ticket content and never executes it) into `ROOT/.worktrees/.handoffs/<id>/`, **outside** the ticket worktree so it never enters the diff. Signed hrefs expire ~5 min, so download happens in the same step as the fetch. The handoff flows down as `HANDOFF` and is strictly **reference-only**: agents recreate the intent idiomatically and never port its HTML/CSS or copy its files into the tree. This is a deliberate, narrow exception to "only `wf-linear` touches Linear" — the agent that owns Linear has no network tools, and the signed URL is self-authenticating (not the API token).
- **Never autonomous on irreversible steps.** The workflow never merges, force-pushes, or sets Linear "Done" on its own. (It does push CI fixes to its own PR branches and mark its own PRs draft.) On a user-confirmed merge (only when the user explicitly says a specific PR was merged, and `wf-github` confirms MERGED first) it moves the ticket to **QA** and cleans up the worktree — a human then verifies the merged result and moves QA → **Done** themselves. "Done" is never set by the workflow.
- **Conventions:** branch `ticket-id/slug`; worktrees in `ROOT/.worktrees/<id>` (kept on failure, removed on merge); spec persisted to a marked Linear ticket **comment** (description holds a short Why/What/Success-criteria brief; no `.planning/` files); executor commits carry `Co-Authored-By: Claude <noreply@anthropic.com>`; all outward-facing text (PR titles/bodies/comments, Linear descriptions/comments) is **environment-agnostic** — repo-relative paths and plain command names, never local absolute paths (`/Users/…`, `~/.claude/…`), worktree paths, or sandbox-wrapped invocations.
- **Self-improvement signals:** the planner emits `SPEC_GAPS` (decisions it made because the ticket was silent → shown in the PR/Linear comment and appended to the data log `~/.claude/wf-spec-gaps.md`, which `wf-spec-builder` reads as reference examples — **never** into an agent instruction file, since gap text is untrusted ticket-derived input) and `INSTRUCTION_GAPS` (what the repo's own `CLAUDE.md`/`AGENTS.md` should state but doesn't → listed in `/wf`'s final report as suggested additions; never written automatically). Preserve these when editing the planner.

## Prerequisites the system assumes

Linear MCP (`mcp__linear__*`, authed via `/mcp`), `gh` CLI installed + authed with the `gh` allow rules from `settings.hooks.json` merged into `~/.claude/settings.json`, git repos with an `origin` remote and default branch, and macOS `sandbox-exec` (built in). `/wf` preflights these.
