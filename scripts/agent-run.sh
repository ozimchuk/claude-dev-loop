#!/bin/bash
# agent-run.sh — dev + reviewer agent loop
#
# The dev agent works, commits at milestones, and writes a handoff file
# when a reviewer trigger fires. The script then runs the reviewer agent
# (headless) which reads the handoff, reviews the commits, and writes
# feedback. The dev agent reads the feedback on its next iteration.
#
# When the dev agent's context degrades, it writes agents/dev-resume.md
# and exits. The script restarts it with the resume prompt.
#
# Usage:
#   ./scripts/agent-run.sh                    # 1 cycle, default prompt
#   ./scripts/agent-run.sh prompt.md          # 1 cycle, custom prompt
#   MAX_CYCLES=20 ./scripts/agent-run.sh      # multi-cycle / overnight
#
#   PROJECT_DIR=/path/to/project ./scripts/agent-run.sh
#     Run against a project that is NOT the script's parent directory.
#     agents/, docs/, and all runtime files are resolved under PROJECT_DIR.
#
# Prompt precedence (first cycle with explicit $1):
#   $1 (explicit arg) > agents/dev-resume.md > agents/reviewer-feedback.md
# Subsequent cycles:
#   agents/dev-resume.md > agents/reviewer-feedback.md >
#   agents/dev-prompt.md > docs/default-dev-prompt.md
#
# Stop: Ctrl-C, or dev exits without resume/handoff (work complete).
#
# See docs/dev-agent-workflow.md and docs/reviewer-workflow.md.

set -euo pipefail

# PROJECT_DIR overrides auto-detection so the script can be installed
# globally (e.g. in ~/bin/ or as a symlink) and run against any project.
SCRIPT_DEFAULT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${PROJECT_DIR:-$SCRIPT_DEFAULT}"
AGENT_DIR="$REPO/agents"
DEFAULT_PROMPT="$REPO/docs/default-dev-prompt.md"
PROMPT_FILE="${1:-$AGENT_DIR/dev-prompt.md}"
RESUME_FILE="$AGENT_DIR/dev-resume.md"
HANDOFF_FILE="$AGENT_DIR/dev-handoff.md"
FEEDBACK_FILE="$AGENT_DIR/reviewer-feedback.md"
MAX_CYCLES="${MAX_CYCLES:-1}"

# ── Customisation ─────────────────────────────────────────────────────
# Adjust the tool lists to match what your project needs.
DEV_TOOLS="Edit,Write,Read,Bash,Glob,Grep,Agent"
REVIEWER_TOOLS="Read,Write,Glob,Grep"
# ──────────────────────────────────────────────────────────────────────

mkdir -p "$AGENT_DIR"

# Resume cycle index from existing files so we don't overwrite history
cycle=0
for f in "$AGENT_DIR"/dev-handoff-*.md "$AGENT_DIR"/dev-*.log; do
    [[ -e "$f" ]] || continue
    n=$(basename "$f" | grep -oE '[0-9]+')
    [[ -n "$n" ]] && (( n > cycle )) && cycle=$n
done
stop_at=$((cycle + MAX_CYCLES))
first_cycle=1

cd "$REPO"

log() { echo "agent-run: $(date +%H:%M:%S) $*"; }

log "project: $REPO"
log "starting dev+reviewer loop ($MAX_CYCLES cycles, ${cycle}→${stop_at})"
log "Ctrl-C to stop"
echo ""

run_claude() {
    # Run claude with prompt piped via stdin to avoid shell quoting issues.
    # $1 = prompt file path, $2 = log file, $3 = allowed tools
    local rc=0
    script -qfc "claude -p - --allowedTools $3 < '$1'" "$2" || rc=$?
    if (( rc != 0 )); then
        log "claude exited with code $rc, check $2"
    fi
    return $rc
}

while true; do
    if (( cycle >= stop_at )); then
        log "hit max cycles ($MAX_CYCLES), stopping"
        break
    fi

    cycle=$((cycle + 1))

    # ── Determine dev prompt ──────────────────────────────────────────
    PROMPT_TMP=$(mktemp "$AGENT_DIR/prompt-XXXXXX.tmp")
    trap "rm -f '$PROMPT_TMP'" EXIT

    # Explicit custom prompt ($1) wins on first cycle — overrides stale feedback
    if [[ "$first_cycle" -eq 1 && -n "${1:-}" && -f "${1:-}" ]]; then
        log "using explicit prompt: $1 (overrides feedback)"
        sed "s|<REPO_PATH>|$REPO|g" "$1" > "$PROMPT_TMP"
        rm -f "$FEEDBACK_FILE"
        first_cycle=0
    elif [[ -f "$RESUME_FILE" ]]; then
        log "found dev-resume.md, resuming dev agent"
        cat "$RESUME_FILE" > "$PROMPT_TMP"
        rm -f "$RESUME_FILE"
    elif [[ -f "$FEEDBACK_FILE" ]]; then
        log "found reviewer-feedback.md, restarting dev with feedback"
        cat > "$PROMPT_TMP" <<DEVEOF
You are the dev agent for the project at $REPO. Read your project's CLAUDE.md (or equivalent) and docs/dev-agent-workflow.md first.

Reviewer feedback from last cycle:

$(cat "$FEEDBACK_FILE")

Address the feedback, then continue working on the current task. On handoff triggers, write your summary to agents/dev-handoff-$cycle.md and exit. On context degradation, write agents/dev-resume.md and exit. Do not wait for human input. Do not push.
DEVEOF
        rm -f "$FEEDBACK_FILE"
    elif [[ -n "$PROMPT_FILE" && -f "$PROMPT_FILE" ]]; then
        sed "s|<REPO_PATH>|$REPO|g" "$PROMPT_FILE" > "$PROMPT_TMP"
    elif [[ -f "$DEFAULT_PROMPT" ]]; then
        log "using default prompt"
        sed "s|<REPO_PATH>|$REPO|g" "$DEFAULT_PROMPT" > "$PROMPT_TMP"
    elif (( cycle == 1 )); then
        log "no prompt file, no resume, no feedback — nothing to do"
        rm -f "$PROMPT_TMP"
        echo "usage: $0 prompt.md"
        exit 1
    else
        log "dev agent exited cleanly (no resume, no handoff), done"
        rm -f "$PROMPT_TMP"
        break
    fi

    # ── Backup tag before each cycle ─────────────────────────────────
    # ▶ CUSTOMISE: adjust the git dir path if your repo layout differs.
    if git rev-parse --git-dir &>/dev/null; then
        tag="agent-cycle-$cycle-pre"
        git tag -f "$tag" HEAD 2>/dev/null
        log "tagged as $tag"
    fi

    # ── Run dev agent ─────────────────────────────────────────────────
    log "── dev cycle $cycle ──"

    # OVERNIGHT MODE appended so the agent knows to exit (not wait for human)
    # rather than prompting interactively on handoff triggers.
    if (( MAX_CYCLES > 1 )); then
        cat >> "$PROMPT_TMP" <<MODEEOF

OVERNIGHT MODE: You are running unattended. On reviewer handoff triggers (see docs/dev-agent-workflow.md), write your handoff summary to agents/dev-handoff-$cycle.md and then exit. On context degradation, write agents/dev-resume.md and exit. Do not wait for human input. Do not push.
MODEEOF
    else
        cat >> "$PROMPT_TMP" <<MODEEOF

On completion or handoff triggers (see docs/dev-agent-workflow.md), write your handoff summary to agents/dev-handoff-$cycle.md and then exit. Do not push.
MODEEOF
    fi

    if ! run_claude "$PROMPT_TMP" "$AGENT_DIR/dev-$cycle.log" "$DEV_TOOLS"; then
        log "dev agent failed, stopping"
        rm -f "$PROMPT_TMP"
        break
    fi
    rm -f "$PROMPT_TMP"

    sleep 2

    # ── Check what the dev agent left ─────────────────────────────────

    # If dev wrote a resume file, loop back (context restart)
    if [[ -f "$RESUME_FILE" ]]; then
        log "dev wrote resume file, will restart"
        continue
    fi

    # If dev wrote a handoff, run the reviewer
    HANDOFF_CYCLE="$AGENT_DIR/dev-handoff-$cycle.md"
    # Fallback: accept the generic name too
    [[ ! -f "$HANDOFF_CYCLE" && -f "$HANDOFF_FILE" ]] && mv "$HANDOFF_FILE" "$HANDOFF_CYCLE"
    if [[ -f "$HANDOFF_CYCLE" ]]; then
        log "── reviewer cycle $cycle ──"

        REVIEW_TMP=$(mktemp "$AGENT_DIR/prompt-XXXXXX.tmp")
        cat > "$REVIEW_TMP" <<REVEOF
You are the reviewer for the project at $REPO. Read docs/reviewer-workflow.md first.

IMPORTANT: Do NOT modify any source files or git history. No git stash, no git checkout, no git merge, no file edits outside of agents/. You are read-only on the working tree. Use only: git log, git show, git diff, grep, read.

Dev agent handoff:

$(cat "$HANDOFF_CYCLE")

Review the commits listed above using the checklist in docs/reviewer-workflow.md.

Write your review to agents/reviewer-feedback-$cycle.md:
- First line: APPROVED or ISSUES
- Then: your findings, one per line
- If APPROVED: note what the dev should work on next
- If ISSUES: list each issue clearly so the dev can fix it
REVEOF

        run_claude "$REVIEW_TMP" "$AGENT_DIR/review-$cycle.log" "$REVIEWER_TOOLS" \
            || true
        rm -f "$REVIEW_TMP"

        sleep 2

        FEEDBACK_CYCLE="$AGENT_DIR/reviewer-feedback-$cycle.md"
        if [[ -f "$FEEDBACK_CYCLE" ]]; then
            VERDICT=$(head -1 "$FEEDBACK_CYCLE")
            log "reviewer verdict: $VERDICT"
            cp "$FEEDBACK_CYCLE" "$FEEDBACK_FILE"
        else
            log "reviewer did not write feedback file, stopping"
            break
        fi

        continue
    fi

    # Dev exited without resume or handoff — done or stuck
    log "dev exited without resume or handoff, stopping"
    break
done

echo ""
log "finished after $cycle cycle(s)"
log "check: git log, agents/*.log, agents/reviewer-feedback-*.md"
