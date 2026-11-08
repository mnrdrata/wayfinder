#!/bin/bash
# install.sh — install the agentic ticket workflow into ~/.claude.
#
# Copies the wf-* agents, commands, bin scripts, and hooks into your Claude Code
# config dir, generates the sandbox profile for your machine, and sets up the eval
# fixtures. Then it checks your settings.json for the guard hooks and gh allow rules
# from settings.hooks.json. If any are missing, it lists them and asks before adding
# them: it only appends, and backs up settings.json first. Answer no, pass
# --no-settings, or run without a terminal, and it prints the manual steps instead.
#
# Re-runnable: it overwrites only wf-* files it owns and leaves everything else alone.
# Usage: ./install.sh [--no-settings]
set -euo pipefail

NO_SETTINGS=false
for arg in "$@"; do
  case "$arg" in
    --no-settings) NO_SETTINGS=true ;;
    *) echo "unknown option: $arg (usage: ./install.sh [--no-settings])" >&2; exit 2 ;;
  esac
done

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
cp "$REPO"/bin/wf-exec "$REPO"/bin/wf-fetch-handoff "$REPO"/bin/wf-ci-checks "$REPO"/bin/wf-pr-reviews "$CLAUDE/bin/"
cp "$REPO"/hooks/wf-*.sh       "$CLAUDE/hooks/"
chmod +x "$CLAUDE"/bin/wf-exec "$CLAUDE"/bin/wf-fetch-handoff "$CLAUDE"/bin/wf-ci-checks "$CLAUDE"/bin/wf-pr-reviews "$CLAUDE"/hooks/wf-*.sh

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

# --- repo map for multi-repo tickets (machine-specific; never clobber) ----------
# /wf splits a ticket that spans repos into one sub-issue per repo and runs each in the
# checkout this file names. Seed the example once; the user edits the paths.
if [ ! -f "$CLAUDE/wf-repos.json" ]; then
  cp "$REPO/wf-repos.example.json" "$CLAUDE/wf-repos.json"
  warn "Edit $CLAUDE/wf-repos.json with your local checkouts to let /wf build tickets that span repos."
fi

# --- eval harness --------------------------------------------------------------
mkdir -p "$CLAUDE/ticket-workflow-evals"
cp -R "$REPO"/ticket-workflow-evals/. "$CLAUDE/ticket-workflow-evals/"
bash "$CLAUDE/ticket-workflow-evals/setup-fixtures.sh"

say "Files installed."
echo

# --- settings.json: guard hooks + gh allow rules (offer to add what's missing) ---
# The guards are the workflow's enforcement layer: the PreToolUse hook blocks
# unsandboxed project commands in worktrees, the SubagentStop hook blocks
# boundary agents that answer without making a tool call. The workflow RUNS
# without them (agents follow their prompts voluntarily), so a skipped wiring
# step fails silently. Without the gh allow rules, wf-github's gh calls prompt (or
# are denied in auto mode) and a hands-off /wf run stalls with no PR.
#
# So on every run: compare settings.json against settings.hooks.json, list what's
# missing, and offer to add it. The merge only appends (never removes or reorders),
# backs up settings.json first, and writes in place so a symlinked file stays a link.
SETTINGS="$CLAUDE/settings.json"
SNIPPET="$REPO/settings.hooks.json"

# A hook counts as present when an existing command in the same event names the same
# script file, so a user's own path spelling (~ vs $HOME) still matches.
JQ_DEFS='$s[0] as $src
| def present($ev; $entry):
    ([$ev[]?.hooks[]?.command]) as $have
    | all($entry.hooks[].command | split("/") | last; . as $n | any($have[]; contains($n)));
  def missing_rules: ($src.permissions.allow - (.permissions.allow // []));
  def missing_hooks: . as $cur
    | [ $src.hooks | to_entries[] | .key as $k | .value[]
        | select(present($cur.hooks[$k]; .) | not) | {event: $k, entry: .} ];
  def merged: missing_rules as $r | missing_hooks as $h
    | .permissions.allow = ((.permissions.allow // []) + $r)
    | reduce $h[] as $m (.; .hooks[$m.event] = ((.hooks[$m.event] // []) + [$m.entry]));
'

manual_steps() {
  cat <<EOF
  To add them yourself:
    1. Open $SETTINGS.
    2. Add each missing rule to the "permissions.allow" list. Keep your existing rules.
    3. Add each missing hook entry from $SNIPPET
       to the matching array under "hooks". Keep your existing entries.
    4. Run ./install.sh again. This check repeats until nothing is missing.
EOF
}

current='{}'
settings_problem=""
if ! command -v jq >/dev/null 2>&1; then
  settings_problem="jq is not installed, so the installer can't read $SETTINGS."
elif [ -f "$SETTINGS" ]; then
  if jq -e 'type == "object"' "$SETTINGS" >/dev/null 2>&1; then
    current="$(cat "$SETTINGS")"
  else
    settings_problem="$SETTINGS is not a valid JSON object, so the installer won't edit it."
  fi
fi

if [ -n "$settings_problem" ]; then
  err "Can't check the guard hooks and gh allow rules: $settings_problem"
  echo "  Add the \"hooks\" entries and \"permissions.allow\" rules from $SNIPPET"
  echo "  to $SETTINGS by hand. Keep your existing entries."
else
  sq() { printf '%s' "$current" | jq --slurpfile s "$SNIPPET" "$JQ_DEFS $1" "${@:2}"; }
  missing_rules="$(sq 'missing_rules[] | tojson' -r)"
  missing_hooks="$(sq 'missing_hooks[] | "\(.event): \(.entry.hooks[].command | split("/") | last)"' -r)"

  if [ -z "$missing_rules" ] && [ -z "$missing_hooks" ]; then
    say "Settings: guard hooks and gh allow rules all present in $SETTINGS."
  else
    if [ -n "$missing_hooks" ]; then
      err "GUARD HOOKS NOT WIRED: the workflow's security model is NOT enforced."
      err "Nothing blocks unsandboxed project commands in worktrees, or a boundary"
      err "agent fabricating an answer without a real API call. Missing hooks:"
      sed 's/^/    /' <<<"$missing_hooks"
    fi
    if [ -n "$missing_rules" ]; then
      warn "gh allow rules missing: /wf will stop on gh permission prompts. Missing rules:"
      sed 's/^/    /' <<<"$missing_rules"
    fi
    echo

    answer=""
    if [ "$NO_SETTINGS" = false ] && [ -t 0 ]; then
      read -r -p "Add these to $SETTINGS? Existing settings are kept. [y/N] " answer || answer=""
    fi
    case "$answer" in
      [yY]|[yY][eE][sS])
        merged_json="$(sq merged)"
        if [ -f "$SETTINGS" ]; then
          backup="$SETTINGS.wf-backup-$(date +%Y%m%d-%H%M%S)"
          cp "$SETTINGS" "$backup"
          echo "  Backed up the current file to $backup"
        fi
        printf '%s\n' "$merged_json" > "$SETTINGS"
        say "Settings: added the missing entries to $SETTINGS."
        ;;
      *)
        manual_steps
        ;;
    esac
  fi
fi
echo
say "Then, in Claude Code:"
echo "  - Connect the Linear MCP:  /mcp"
echo "  - Verify gh is authed:     gh auth status"
echo "  - Try it, from a repo:     /wf <TICKET-ID> [<TICKET-ID>...]"
echo "  - Optional, vague tickets: /wf-spec <TICKET-ID> first"
