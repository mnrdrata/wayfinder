---
description: Apply a small, described follow-up change to an EXISTING ticket worktree and push it so the open PR updates — no re-planning, no new PR, no Linear/merge changes. For tweaks after /wf (update/remove a test, address a review note). Use /wf for substantial or new-scope work.
argument-hint: [ticket-id] <instruction> [--review]
allowed-tools: Task, Bash, Read, AskUserQuestion
---

# /wf-quick

A lightweight follow-up: make **one small, described change** on an **existing** ticket worktree and push it so the open PR updates. It skips the planner and (by default) the reviewer — it's for tweaks, not fresh tickets. For anything substantial or new-scope, use `/wf`.

**Hard boundaries (same spirit as `/wf`):**
- Operates ONLY on an **existing** worktree — never creates a worktree or a new PR.
- Never merges, never sets Linear **Done**, and does **not** change Linear status (the ticket is already In Review).
- All project code runs sandboxed via `~/.claude/bin/wf-exec` (no egress, no credential reads); `git`/`gh` run unwrapped.
- Be surgical, simple, and goal-driven. **If the instruction implies broad / multi-area / new-scope work, STOP** and tell the user to run `/wf` instead — keep "quick" honest.

## Parse arguments
`$ARGUMENTS` = an optional leading **ticket id**, then the **instruction** (free text), then an optional `--review` flag.
- If the first token matches an identifier pattern (`[A-Z][A-Z0-9]+-[0-9]+`), treat it as the ticket id; the remainder (minus `--review`) is the instruction.
- Otherwise the whole thing (minus `--review`) is the instruction, and you resolve the worktree from the current directory (below).

## Resolve ROOT + the target worktree
Works whether invoked from the main checkout or from inside a worktree (any subdir):
1. Confirm a git repo: `git rev-parse --is-inside-work-tree` (else stop).
2. **ROOT** — the main checkout, shared by all worktrees:
   ```
   GITDIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || git rev-parse --git-common-dir)"
   ROOT="$(cd "$(dirname "$GITDIR")" && pwd)"
   ```
   `--git-common-dir` resolves to the shared `.git` from the main checkout *and* any linked worktree, so its parent is always ROOT.
3. **Pick the worktree** (`WT`):
   - **Ticket id given** → `WT="$ROOT/.worktrees/<id>"`.
   - **No id, but cwd is inside a worktree** → `TOP="$(git rev-parse --show-toplevel)"`; if `TOP` is under `$ROOT/.worktrees/`, use `WT="$TOP"` and read `<id>` from `basename "$TOP"`.
   - **No id, in the main checkout** → list `git worktree list` and ask the user which ticket (AskUserQuestion); if there are none, stop and point them at `/wf`.
4. **Validate** `WT` is a registered worktree: it must appear in `git worktree list --porcelain` (`worktree $WT`). If not → STOP: "No worktree for `<id>` under `$ROOT/.worktrees/`. `/wf-quick` only works on an existing ticket worktree — run `/wf <id>` first." Capture its branch (`<id>/<slug>`).
5. **BASE** — default branch: `git -C "$ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's@^origin/@@'` (fallback `main`/`master`). Then `git -C "$ROOT" fetch origin` so the diff base is current.
**Worktree-path discipline — pass to every agent:** all file ops target the absolute `WT` (`cd "$WT"` for Bash; absolute paths under it for Read/Edit/Grep/Glob).

## Preflight (cheap, fail fast)
- Sandbox present: `~/.claude/bin/wf-exec` executable and `~/.claude/ticket-workflow-sandbox.sb` exists.
- `gh auth status` succeeds (needed to push).
- PR context: spawn `wf-github` `PR_STATUS <branch>` to find the open PR for this branch → capture `PR_URL`. If there's no open PR, note it and continue (pushing still updates the branch).

## Flow
1. **Execute.** Spawn `wf-executor` with: the **instruction** (as a fix-style task — "make exactly this change, nothing more"), the diff base `origin/<BASE>`, and the worktree path. **There is no CONTEXT_PACK** — tell it so: the change is small, so it should read the repo's `CLAUDE.md`/`AGENTS.md` for conventions and commands, locate the relevant file(s) itself with Grep/Read, and make the minimal surgical **atomic commit** (attribution trailer), running any project code through `wf-exec`. If it returns `BLOCKED`, surface and stop. If it reports the change is actually large/cross-cutting, relay that and recommend `/wf` instead of forcing it.
2. **(Only if `--review`)** Spawn `wf-reviewer` once with the diff (`origin/<BASE>..HEAD`) and worktree path. If `CHANGES_REQUIRED`, run one `wf-executor` fix round.
3. **Verify (light, ≤2 rounds).** Spawn `wf-verifier` with the worktree path, the diff base `origin/<BASE>`, and the change description as what to confirm. It runs the checks scoped to the changed files (whole-repo and e2e suites are reported as `LEFT_TO_CI`, never blocking). If `FAIL`, run one `wf-executor` fix round and re-verify; if still failing after 2 rounds, surface to the user (AskUserQuestion: Fix manually / Continue anyway / Stop).
4. **Push.** Spawn `wf-github` to push the branch (`git push`; **do not** create a PR). The open PR updates automatically.
5. **Leave Linear alone.** No status change, no Done, no merge.

## Report
```
<id> — quick change
COMMITS: <subjects>
CHANGED: <files>
VERIFY:  <key checks + result>
CI:      <LEFT_TO_CI lines, or none>
PR:      <PR_URL updated, or "no open PR — branch pushed">
```
Remind: review and merge stay with the user; for anything beyond a small tweak, use `/wf`.
