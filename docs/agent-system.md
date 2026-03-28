# Agent System

Two-agent dev+reviewer loop for autonomous development with human oversight.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  agent-run.sh                                       │
│                                                     │
│  ┌───────────┐   handoff   ┌────────────┐          │
│  │ Dev agent ├────────────►│  Reviewer  │          │
│  │ (claude)  │◄────────────┤  (claude)  │          │
│  └─────┬─────┘  feedback   └──────┬─────┘          │
│        │                          │                 │
│        ▼                          ▼                 │
│   git commits              read-only review         │
│   in repo                  (no git writes)          │
└─────────────────────────────────────────────────────┘
         │                          │
         ▼                          ▼
    agents/dev-handoff-N.md    agents/reviewer-feedback-N.md
    agents/dev-N.log           agents/review-N.log
```

The **dev agent** writes code, commits at milestones, and exits with a
handoff file when a trigger fires. The **reviewer agent** runs headless,
validates the commits, and writes feedback. The script restarts the dev
agent with the feedback. Human is the final gatekeeper for pushes and
merges.

---

## Quick start

```bash
# Single cycle (default) — dev works, reviewer validates
./scripts/agent-run.sh

# Single cycle with a one-off prompt
./scripts/agent-run.sh /path/to/prompt.md

# Multi-cycle / overnight
MAX_CYCLES=20 ./scripts/agent-run.sh

# Check results
git log --oneline          # commits made
cat agents/reviewer-feedback-1.md   # review verdict
cat agents/dev-1.log                # dev session log
```

---

## Prompt precedence

On the **first cycle**, an explicit custom prompt (`$1`) takes highest
priority — overriding any stale feedback from a previous run. On
subsequent cycles, feedback from the reviewer takes precedence:

**First cycle with explicit `$1`:**
1. Custom arg (`$1`) — overrides everything, clears stale feedback
2. `agents/dev-resume.md` — context degradation restart
3. `agents/reviewer-feedback.md` — feedback from previous cycle
4. `agents/dev-prompt.md` — persistent override (gitignored)
5. `docs/default-dev-prompt.md` — tracked default, self-orienting

**Subsequent cycles:**
1. `agents/dev-resume.md` — context degradation restart
2. `agents/reviewer-feedback.md` — feedback from previous cycle
3. `agents/dev-prompt.md` — persistent override (gitignored)
4. `docs/default-dev-prompt.md` — tracked default, self-orienting

The default prompt reads repo state and picks the highest-priority
unchecked item from the project task list. Override by passing a file
or placing `agents/dev-prompt.md`.

---

## Files

### Tracked (in git)

| File | Purpose |
|------|---------|
| `scripts/agent-run.sh` | Loop script — launches dev and reviewer |
| `docs/default-dev-prompt.md` | Default dev prompt (self-orienting) |
| `docs/dev-agent-workflow.md` | Dev agent rules, handoff triggers, commit protocol |
| `docs/reviewer-workflow.md` | Reviewer checklist, read-only rules |

### Runtime (gitignored via `agents/`)

| File | Purpose |
|------|---------|
| `agents/dev-prompt.md` | Optional persistent prompt override |
| `agents/dev-handoff-N.md` | Dev → reviewer handoff (per cycle) |
| `agents/reviewer-feedback-N.md` | Reviewer → dev feedback (per cycle) |
| `agents/reviewer-feedback.md` | Latest feedback (consumed by next dev cycle) |
| `agents/dev-resume.md` | Dev context restart prompt (transient) |
| `agents/dev-N.log` | Dev session log (per cycle) |
| `agents/review-N.log` | Reviewer session log (per cycle) |

---

## Dev agent

### What it does

- Reads the project context file and `docs/dev-agent-workflow.md`
- Commits at milestones (one fix per commit)
- Runs tests, updates docs with each commit
- Exits with a handoff file on trigger conditions

### Handoff triggers

The dev agent stops and writes `agents/dev-handoff-N.md` when:

1. **Feature milestone** — new feature or fix works end-to-end
2. **5+ commits accumulated** — batch review
3. **Architectural decision** — changes with wide blast radius
4. **Boundary uncertainty** — unsure if something should be public/private
5. **Dead end or pivot** — approach change
6. **Ready for merge** — feature complete, tests pass, docs updated
7. **New feature on merge-ready branch** — hand off requesting merge
   first (exception: minor fixes on a fully-reviewed branch)

### Context management

- After every 3 commits, write `agents/dev-resume.md` and exit
- The script restarts with the resume prompt (fresh context)
- Heuristic: if you can't recall your first fix this session, exit

### Opportunistic refactoring

If the dev agent is editing a function that has a matching item in the
refactoring section of the project task list, fix it in the same commit.
Don't seek out refactors — only pick them up when already in the code.

---

## Reviewer agent

### What it does

- Runs headless (`claude -p`) — no human interaction
- Reads the branch via git log/diff/show
- Writes verdict to `agents/reviewer-feedback-N.md`

### Read-only rule

The reviewer must NOT modify the working tree. No `git checkout`,
`git stash`, `git merge`, or file edits to source. This prevents
interference with the dev agent's state.

### Review checklist

Adapt `docs/reviewer-workflow.md` to your project's specific concerns.
The generic baseline:

1. No project-private content leaked into public artifacts
2. Dead code, debug output, or abandoned implementations
3. Correctness of new code
4. Branch scope — commits match the branch purpose
5. Handoff includes test output (pass/fail/skip counts)
6. **BLOCKING**: test coverage — new behavior needs tests
7. **BLOCKING**: doc staleness — all docs checked, not just a hardcoded list
8. **BLOCKING**: commits on wrong branch (new features on merge-ready branch)

### Verdict format

```
APPROVED
- findings...
- next steps...
```

or

```
ISSUES
- issue 1: description
- issue 2: description
```

ISSUES blocks the dev from continuing until fixed.

---

## Human role

The human is the final gatekeeper:

- **Pushes** — neither agent can push. Human approves and runs `git push`.
- **Merges** — human approves squash-merge after reviewer gives APPROVED.
- **Prompt updates** — human edits `agents/dev-prompt.md` or passes a
  custom file to steer the dev agent's priorities.
- **Override** — human can intervene at any point by editing files,
  switching branches, or stopping the script.

---

## Safety features

- **Backup tags**: each cycle creates `agent-cycle-N-pre` tag before the
  dev agent starts. Recover with `git reset --hard agent-cycle-N-pre`.
- **Cycle index resume**: cycle numbers continue from existing files, so
  restarting the script doesn't overwrite prior handoffs/logs.
- **Explicit prompt override**: passing `$1` on first cycle overrides
  stale reviewer feedback, preventing the dev from ignoring your intent.
- **Error handling**: non-zero claude exit breaks the loop with a log
  message instead of silently continuing.
- **Pre-push history check**: reviewer checks every unpushed commit
  (not just HEAD) for leaks. Squash leak+fix before pushing.

---

## Troubleshooting

**Dev exits without handoff or resume**
- Check `agents/dev-N.log` for errors
- Common cause: tool permission denied, or dev finished all work

**Reviewer can't write feedback file**
- Ensure `Write` is in the reviewer's `--allowedTools`
- Check `agents/review-N.log`

**Log files are empty**
- `script` command forces unbuffered output; if still empty, the session
  may have crashed before producing output

**Dev agent ignores tests/docs requirement**
- The reviewer should block with ISSUES verdict
- If reviewer also misses it, add the check to `docs/reviewer-workflow.md`
  and to your project's main context file

**Context degradation (dev makes mistakes late in session)**
- The 3-commit restart rule mitigates this
- If still occurring, reduce to 2 commits per session
