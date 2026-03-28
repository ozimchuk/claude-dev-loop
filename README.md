# claude-dev-loop

Two-agent dev+reviewer loop for Claude Code. The dev agent writes
code and commits at milestones; the reviewer validates each batch before
merge; the human gates all pushes. One shell script, four markdown docs.

---

## How it works

```
agent-run.sh
  ├─ dev agent (claude)       → commits code, exits on trigger
  │       ↓ agents/dev-handoff-N.md
  ├─ reviewer agent (claude)  → validates commits, writes verdict
  │       ↓ agents/reviewer-feedback-N.md
  └─ loop restarts dev with feedback
```

See `docs/agent-system.md` for the full architecture diagram and file list.

---

## Setup

### 1. Copy into your project

```bash
cp -r claude-dev-loop/scripts   your-project/
cp -r claude-dev-loop/docs      your-project/
cp    claude-dev-loop/.gitignore your-project/.gitignore   # or merge it
mkdir -p your-project/agents
```

Or add it as a subtree / submodule if you want to track upstream changes.

### 2. Adapt the four doc files

All project-specific sections are marked with `▶ CUSTOMISE`.

| File | What to customise |
|------|------------------|
| `docs/dev-agent-workflow.md` | Project-specific rules, test commands, reference docs |
| `docs/reviewer-workflow.md` | Boundary checks, domain-specific review items |
| `docs/default-dev-prompt.md` | Fill in `<REPO_PATH>` and the task list filename |
| `docs/agent-system.md` | Optional — mostly generic, update if your loop differs |

### 3. Create a project context file

The dev agent reads a context file on every startup (e.g. `CLAUDE.md`,
`AGENTS.md`, or `PROJECT.md`). It should cover:

- What the project is and does
- Directory layout
- Build and test commands
- Known gotchas and invariants
- What must never appear in commits (secrets, private paths, etc.)

### 4. Customise tool lists (optional)

In `scripts/agent-run.sh`, two variables control which Claude tools
each agent is allowed to use:

```bash
DEV_TOOLS="Edit,Write,Read,Bash,Glob,Grep,Agent"
REVIEWER_TOOLS="Read,Glob,Grep,Bash"
```

`Write` is intentionally absent from the reviewer's tool list. The
reviewer writes its feedback file via `Bash` redirection, making the
source-read-only constraint structural rather than purely instructional.
Removing `Bash` as well forces the reviewer to use only grep/read —
the strongest read-only guarantee.

### 5. Run

```bash
# From inside the project (script auto-detects the project root)
./scripts/agent-run.sh

# With a one-off task prompt
./scripts/agent-run.sh my-task-prompt.md

# Multi-cycle overnight
MAX_CYCLES=20 ./scripts/agent-run.sh

# From anywhere — point at a different project
PROJECT_DIR=/path/to/myproject ./scripts/agent-run.sh
PROJECT_DIR=/path/to/myproject MAX_CYCLES=10 ./scripts/agent-run.sh prompt.md

# Installed globally (e.g. ~/bin/agent-run.sh or a symlink)
PROJECT_DIR=$(pwd) agent-run.sh
```

`PROJECT_DIR` overrides auto-detection. All runtime files (`agents/`,
`docs/default-dev-prompt.md`, etc.) are resolved under it. The script
logs the resolved project path at startup so you can verify it.

---

## Prompt precedence

On the first cycle, an explicit `$1` wins (overrides stale feedback):

1. `$1` (explicit arg) — clears stale feedback
2. `agents/dev-resume.md` — context-degradation restart
3. `agents/reviewer-feedback.md` — feedback from last reviewer cycle
4. `agents/dev-prompt.md` — persistent override (gitignored)
5. `docs/default-dev-prompt.md` — tracked default (lowest priority)

Subsequent cycles drop `$1` and follow 2→5.

---

## Handoff triggers (dev → reviewer)

The dev agent exits and writes a handoff when:

1. Feature milestone reached (new behavior works end-to-end)
2. 5+ commits accumulated without review
3. Architectural decision needed
4. Boundary uncertainty
5. Dead end or strategy pivot
6. Ready for merge
7. New feature on a merge-ready branch (request merge first)

---

## Safety features

- **Backup tags** — `agent-cycle-N-pre` tag created before each cycle
- **Cycle index resume** — cycle numbers continue from existing files
- **Explicit prompt override** — `$1` overrides stale feedback on first cycle
- **Error handling** — non-zero claude exit breaks the loop with a message
- **Pre-push history check** — reviewer checks all unpushed commits, not just HEAD

---

## Files

```
claude-dev-loop/
├── scripts/
│   └── agent-run.sh          # orchestration loop
├── docs/
│   ├── agent-system.md       # architecture + file reference
│   ├── dev-agent-workflow.md # dev rules (▶ CUSTOMISE)
│   ├── reviewer-workflow.md  # reviewer checklist (▶ CUSTOMISE)
│   └── default-dev-prompt.md # default startup prompt (▶ CUSTOMISE)
├── agents/                   # runtime files — gitignored
│   └── .gitkeep
├── .gitignore
└── README.md
```

Runtime files in `agents/` are gitignored:
- `agents/dev-N.log`, `agents/review-N.log` — session logs
- `agents/dev-handoff-N.md` — dev → reviewer handoff per cycle
- `agents/reviewer-feedback-N.md` — reviewer verdict per cycle
- `agents/reviewer-feedback.md` — latest feedback (consumed next cycle)
- `agents/dev-resume.md` — context restart prompt (transient)
- `agents/dev-prompt.md` — persistent prompt override

---

## Design decisions

- **Prompts via stdin** (`claude -p -`) — avoids shell quoting failures
  when prompts contain `"` or `$` characters.
- **OVERNIGHT MODE only for multi-cycle** — single-cycle runs get lighter
  instructions without "do not wait for human input".
- **Reviewer has no Bash** — `Read,Write,Glob,Grep` only. Structural
  read-only guarantee, not just prompt instruction.
- **Cycle-stamped files** — `dev-handoff-1.md`, `reviewer-feedback-2.md`
  etc. preserve full history across runs.
- **`<REPO_PATH>` substitution** — prompts and default-dev-prompt use
  `<REPO_PATH>` placeholder, replaced at runtime with the actual project
  path.
