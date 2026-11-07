---
description: Run the ticket-workflow eval harness — stage evals (spec-builder, planner, executor) over seed cases, judged by wf-judge, with regression comparison against the saved baseline. Run after changing any agent prompt, model, or the flow.
argument-hint: [case-id ...] [--stage spec|decision|plan|execute|review]
allowed-tools: Task, Bash, Read, Write
---

# /wf-eval

Catch silent quality regressions in the agent pipeline. This runs **stage evals**: it invokes a single agent on a fixture and has `wf-judge` score its output against the case rubric. Cheap and frequent — run it whenever you edit an agent file or switch a model.

It is fully offline: it touches only the local fixtures in `~/.claude/ticket-workflow-evals/`. It never calls Linear or GitHub and never opens a PR. All project code runs through `wf-exec` (the sandbox).

## Scope
- `EVAL = ~/.claude/ticket-workflow-evals`. Cases in `EVAL/cases/*.md`; fixtures in `EVAL/fixtures/`.
- `$ARGUMENTS` may name specific case ids and/or `--stage spec|decision|plan|execute|review`. Default: all cases, all stages (run a stage only for cases whose `stages:` lists it).

## Preconditions
- `EVAL/cases` and `EVAL/fixtures` exist; `~/.claude/bin/wf-exec` is executable. If missing, tell the user to set up the harness.

## Per case
Parse the case file: `id`, `fixture` (relative to `EVAL`), `stages`, the `## TICKET` block, the `## RUBRIC:spec` / `## RUBRIC:decision` / `## RUBRIC:plan` / `## RUBRIC:execute` / `## RUBRIC:review` blocks, and (review cases only) the `## MUTATION` block.

**Reset the fixture to a clean baseline first** (and again after each stage that mutates it):
`git -C "<fixture>" checkout -- . ; git -C "<fixture>" clean -fd ; git -C "<fixture>" checkout main 2>/dev/null` (delete any throwaway eval branch).

### Stage: spec (read-only — does not mutate the fixture)
1. Spawn `wf-spec-builder` with: the case TICKET as the raw/thin ticket, the fixture path as the codebase to explore, `PR_HISTORY=none`, `RELATED_TICKETS=none`, `RELATED_DECISIONS=none`, `HANDOFF=none`, and this flag: **"EVAL MODE — non-interactive: do NOT return `STATUS: NEEDS_INPUT`; resolve every decision conservatively from the code, record each as a fact, and produce your best `STATUS: SPEC`."** Capture its full output as `ARTIFACT`.
2. Spawn `wf-judge` with `STAGE=spec`, the case (TICKET + `RUBRIC:spec`), and `ARTIFACT`. Record its verdict. (No branch or reset needed — the spec stage only reads the fixture.)

### Stage: decision (read-only — does not mutate the fixture)
For research/spike cases, where the deliverable is a recorded decision, not code.
1. Spawn `wf-spec-builder` with: the case TICKET as the raw/thin ticket, the fixture path as the codebase to explore, `PR_HISTORY=none`, `RELATED_TICKETS=none`, `RELATED_DECISIONS=none`, `HANDOFF=none`, and this flag: **"EVAL MODE — non-interactive: this is a research/spike ticket. Do NOT return `STATUS: NEEDS_INPUT`; resolve the decision conservatively from the code, commit to one option, and produce your best `STATUS: DECISION` (original description preserved + an appended `## Decision` section)."** Capture its full output as `ARTIFACT`.
2. Spawn `wf-judge` with `STAGE=decision`, the case (TICKET + `RUBRIC:decision`), and `ARTIFACT`. Record its verdict. (No branch or reset needed — the decision stage only reads the fixture.)

### Stage: plan
1. Spawn `wf-planner` with: the case TICKET as the enriched ticket, the fixture path as the worktree, `PR_HISTORY=none`, and this flag: **"EVAL MODE — do NOT return `STATUS: UNCLEAR`; resolve each open decision conservatively, record it in `SPEC_GAPS`, and produce your best `STATUS: PLAN`."** Capture its full output as `ARTIFACT`.
2. Spawn `wf-judge` with `STAGE=plan`, the case (TICKET + `RUBRIC:plan`), and `ARTIFACT`. Record its verdict.

**Chain cases.** When the case has a `chain:` line (ordered ticket ids), the TICKET block holds one `### <id>` section per ticket. Spawn `wf-planner` once with `CHAIN` = those tickets in that order. Use the same EVAL MODE flag, but ask for `STATUS: CHAIN_PLAN` instead of `STATUS: PLAN`. Chain cases run only the plan stage.

### Stage: execute
1. On a throwaway branch in the fixture: `git -C "<fixture>" checkout -b eval/<id>`.
2. Spawn `wf-executor` with: the plan from the plan stage (or, if plan stage didn't run, a minimal plan derived from the TICKET's acceptance criteria), the fixture path as the worktree, and the standard sandbox rule (run project code via `wf-exec`). Let it edit + commit on the branch.
3. Capture `ARTIFACT` = `git -C "<fixture>" diff main...HEAD` **plus** the test result from running the fixture's tests sandboxed (e.g. `wf-exec bash -c "cd <fixture> && <test cmd>"`).
4. Spawn `wf-judge` with `STAGE=execute`, the case (TICKET + `RUBRIC:execute`), and `ARTIFACT`. Record the verdict.
5. Reset: `git -C "<fixture>" checkout main && git -C "<fixture>" branch -D eval/<id> && git -C "<fixture>" clean -fd`.

### Stage: review (mutates the fixture on a throwaway branch)
Exercises `wf-reviewer` against a planted-flaw diff — the case ships a `## MUTATION` (full post-change contents per `### file:` entry, simulating a flawed executor's work) and a `RUBRIC:review`.
1. Throwaway branch: `git -C "<fixture>" checkout -b eval/<id>`.
2. Apply the mutation: overwrite each file named by a `### file:` heading with its fenced contents, then `git -C "<fixture>" add -A && git -C "<fixture>" commit -m "eval: planted diff for review stage"`.
3. Spawn `wf-reviewer` with: the TICKET's goal + acceptance criteria, `PLAN=none` (tell it: judge the diff directly against the criteria), `CONTEXT_PACK=none`, `HANDOFF=none`, the fixture path as the worktree, and diff base `main` — tell it explicitly there is no `origin` here, so the diff is `git diff main...HEAD`. Do NOT tell it the flaws are planted. Capture its full output as `ARTIFACT`.
4. Spawn `wf-judge` with `STAGE=review`, the case (TICKET + `## MUTATION` + `RUBRIC:review`), and `ARTIFACT`.
5. Reset: `git -C "<fixture>" checkout main && git -C "<fixture>" branch -D eval/<id> && git -C "<fixture>" clean -fd`.

## Report + regression gate
- Print a table: `case | stage | PASS/FAIL | score | biggest weakness`.
- Compute the mean score and pass-rate.
- **Compare to baseline:** if `EVAL/baselines/baseline.md` exists, diff each case/stage verdict against it and flag any **regression** (was PASS now FAIL, or score dropped > 0.15). If there are regressions, say so loudly — that's the signal a recent agent/model/flow change degraded the pipeline.
- Save this run to `EVAL/baselines/run-<today>.md` — but **never overwrite an existing run record**: if that file already exists (a same-day rerun), save to `run-<today>-<HHMMSS>.md` instead (e.g. `date +%Y-%m-%d-%H%M%S`) so each run is preserved as immutable history. Then offer to promote it to `baseline.md` (only do so on explicit user confirmation — never overwrite the baseline silently). `baseline.md` is the moving gold pointer the gate diffs against; the dated `run-*.md` files are the permanent per-run archive and are never pruned.

## Notes
- Stage evals isolate *which* agent regressed. The spec stage is independent (it consumes only the raw TICKET); the execute stage currently consumes the planner's plan (so a plan regression can cascade) — acceptable for a quick gate; pin a reference plan per case later if you want full isolation.
- Keep token cost in mind: each case spawns 1–2 agents + a judge. Run a single case id during iteration; run all before committing a prompt/model change.
