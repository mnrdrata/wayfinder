#!/bin/bash
# install.sh — install the agentic ticket workflow into ~/.claude.
#
# Copies the wf-* agents, commands, bin scripts, and hooks into your Claude Code
# config dir, generates the sandbox profile for your machine, and sets up the eval
# fixtures. It does NOT touch your settings.json — hook wiring stays a manual step
# (so it can never clobber your existing config), but the installer now DETECTS
# whether the two guard hooks are wired and warns loudly until they are.
#
# Re-runnable: it overwrites only wf-* files it owns and leaves everything else alone.
# Usage: ./install.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE="${CLAUDE_HOME:-$HOME/.claude}"

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m! %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31m!! %s\033[0m\n' "$*"; }

say "Installing Wayfinder into $CLAUDE"

# --- platform + dependency checks (warn, don't block) --------------------------
if [ "$(uname)" != "Darwin" ]; then
  warn "Not macOS: the execution sandbox uses macOS 'sandbox-exec' (seatbelt) and"
  warn "will not work here. The agents/commands still install, but /wf's"
  warn "sandboxed test/build execution is macOS-only. See README > Platform support."
fi
for dep in git jq gh; do
  command -v "$dep" >/dev/null 2>&1 || warn "missing dependency: $dep (see README > Prerequisites)"
done
command -v node    >/dev/null 2>&1 || warn "node not found — the node eval fixture won't run"
command -v python3 >/dev/null 2>&1 || warn "python3 not found — the py eval fixture won't run"

# --- copy the pieces -----------------------------------------------------------
mkdir -p "$CLAUDE"/{agents,commands,bin,hooks}

cp "$REPO"/agents/wf-*.md      "$CLAUDE/agents/"
cp "$REPO"/commands/wf*.md     "$CLAUDE/commands/"   # wf.md + wf-*.md
cp "$REPO"/bin/wf-exec "$REPO"/bin/wf-fetch-handoff "$REPO"/bin/wf-ci-checks "$CLAUDE/bin/"
cp "$REPO"/hooks/wf-*.sh       "$CLAUDE/hooks/"
chmod +x "$CLAUDE"/bin/wf-exec "$CLAUDE"/bin/wf-fetch-handoff "$CLAUDE"/bin/wf-ci-checks "$CLAUDE"/hooks/wf-*.sh

# --- retire files from earlier versions (they would otherwise linger in ~/.claude) ---
# /wf-run became /wf; /wf-prime and its cartographer agent are gone (/wf reads the repo's
# own CLAUDE.md/AGENTS.md instead of a generated CONTEXT.md).
rm -f "$CLAUDE/commands/wf-run.md" "$CLAUDE/commands/wf-prime.md" "$CLAUDE/agents/wf-cartographer.md"

# --- generate the sandbox profile for this machine -----------------------------
# The seatbelt profile needs literal absolute paths; fill in this machine's dirs —
# __HOME__ = your home, __CLAUDE__ = the Claude config dir (CLAUDE_HOME may relocate it).
sed -e "s#__CLAUDE__#$CLAUDE#g" -e "s#__HOME__#$HOME#g" "$REPO/ticket-workflow-sandbox.sb.template" \
  > "$CLAUDE/ticket-workflow-sandbox.sb"

# --- learned-gaps data log (append-only; never clobber an existing one) ---------
# wf-spec-builder reads this as reference examples; /wf appends to it when a planner
# reports SPEC_GAPS. It holds ticket-derived text, so it is DATA, never an agent prompt —
# seed it empty, once, and leave any existing log (a user's accumulated history) untouched.
[ -f "$CLAUDE/wf-spec-gaps.md" ] || cp "$REPO/wf-spec-gaps.md" "$CLAUDE/wf-spec-gaps.md"

# --- eval harness --------------------------------------------------------------
mkdir -p "$CLAUDE/ticket-workflow-evals"
cp -R "$REPO"/ticket-workflow-evals/. "$CLAUDE/ticket-workflow-evals/"
bash "$CLAUDE/ticket-workflow-evals/setup-fixtures.sh"

say "Files installed."
echo

# --- hook wiring check (detect-and-warn; never touches settings.json) ----------
# The guards are the workflow's enforcement layer: the PreToolUse hook blocks
# unsandboxed project commands in worktrees, the SubagentStop hook blocks
# boundary agents that answer without making a tool call. The workflow RUNS
# without them (agents follow their prompts voluntarily), so a skipped wiring
# step fails silently — this check makes that state loud on every install run.
SETTINGS="$CLAUDE/settings.json"
hooks_wired=false
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ] && jq -e . "$SETTINGS" >/dev/null 2>&1; then
  if jq -e '.hooks.PreToolUse[]?.hooks[]?.command | select(contains("wf-sandbox-guard.sh"))' "$SETTINGS" >/dev/null 2>&1 \
  && jq -e '.hooks.SubagentStop[]?.hooks[]?.command | select(contains("wf-boundary-toolcall-guard.sh"))' "$SETTINGS" >/dev/null 2>&1; then
    hooks_wired=true
  fi
fi

if [ "$hooks_wired" = true ]; then
  say "Guard hooks: wired in $SETTINGS — sandbox + boundary enforcement active."
else
  err "GUARD HOOKS NOT WIRED — the workflow's security model is NOT enforced."
  err "Nothing currently blocks unsandboxed project commands in worktrees, or a"
  err "boundary agent fabricating an answer without a real API call. Fix it now:"
  cat <<EOF
  Merge the two entries in:
      $REPO/settings.hooks.json
  into the "hooks" object of:
      $SETTINGS
  (If you have no "hooks" key yet, you can paste the whole "hooks": { ... } block.)
  Then re-run ./install.sh — this warning repeats until both hooks are detected.
EOF
fi

# --- gh permission check (detect-and-warn) --------------------------------------
# Without allow rules, wf-github's gh calls prompt (or are denied in auto mode) and a
# hands-off /wf run stalls with partial PR history or no PR at all.
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ] \
   && jq -e '.permissions.allow[]? | select(startswith("Bash(gh pr create"))' "$SETTINGS" >/dev/null 2>&1 \
   && jq -e '.permissions.allow[]? | select(startswith("Bash(~/.claude/bin/wf-ci-checks"))' "$SETTINGS" >/dev/null 2>&1; then
  say "gh permissions: allow rules present."
else
  warn "gh allow rules not found — /wf will stop on gh permission prompts."
  warn "Add the \"permissions.allow\" rules from $REPO/settings.hooks.json to $SETTINGS."
fi
echo
say "Then, in Claude Code:"
echo "  - Connect the Linear MCP:  /mcp"
echo "  - Verify gh is authed:     gh auth status"
echo "  - Try it, from a repo:     /wf <TICKET-ID> [<TICKET-ID>...]"
echo "  - Optional, vague tickets: /wf-spec <TICKET-ID> first"
