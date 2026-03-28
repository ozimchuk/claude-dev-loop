# Dev Agent Workflow

Instructions for the AI dev agent. Adapt the project-specific sections
(marked ▶ CUSTOMISE) for your codebase.

---

## Workflow

**Continue until a decision is needed.** Don't stop to ask unless you're
genuinely blocked or the next action has significant risk (destructive git
ops, architectural changes, pushing to remote).

**Commit when progress is made.** A commit requires ALL of:
- Fix landed (code change)
- New tests cover it (if testable behavior changed)
- Test suite passes with zero new failures
- Docs updated with findings (see checklist below)

Do NOT batch multiple fixes into one commit. Do NOT start the next
investigation before committing the current fix — the commit is the
checkpoint.

**Do NOT push without explicit instruction.** Commits are fine; `git push`
requires the human's approval.

**Stop and hand off to the reviewer** when any of these happen:

1. **Feature milestone reached** — a new feature, command, or subsystem
   works end-to-end (even partially). Commit, then write a summary with:
   what changed, what works, what doesn't, and test results.
2. **Batch of 5+ commits accumulated** — don't let the branch grow
   unbounded without review. Stop and summarize.
3. **Architectural decision needed** — changes with wide blast radius.
   Reviewer should sanity-check before you continue.
4. **Boundary uncertainty** — if you're unsure whether a change leaks
   private or sensitive information, stop and ask rather than guess.
5. **Dead end or pivot** — if an approach failed and you're switching
   strategy, summarize what was tried and why it failed before continuing.
6. **Ready for merge** — feature complete, tests pass, docs updated.
   Reviewer validates before merge.
7. **New feature on a merge-ready branch** — if the reviewer has
   approved the branch for merge, do NOT add unrelated work to it.
   Hand off requesting the merge first. Do pending fixes only, then
   hand off again.
   **Exception**: if the branch is fully reviewed and only minor items
   remain (doc fixes, test counts), you may continue on the same
   branch. Note this in the handoff so the reviewer knows the scope
   expanded.

The handoff message should include:
- Numbered list of commits since last review
- What works / what doesn't (with test output if available)
- Known issues or dead code flagged for cleanup
- Any pending uncommitted files

**Context management.** Before every commit, check whether you can still
recall the details of your first fix this session (function names, specific
values, the specific bug). If you can't, your context is degraded:

1. Commit current work (also do this after every 3 commits in a session,
   regardless of context state — forced restart prevents silent degradation)
2. Write a resume prompt to `agents/dev-resume.md` with:
   - Branch name and current commit
   - What you were working on and where you left off
   - Uncommitted changes (if any — commit first if possible)
   - Key context the next session needs
3. Exit the session

The wrapper script will restart you with the resume prompt. On startup,
check if `agents/dev-resume.md` exists — if so, read it for continuation
context, then delete it.

Also check `agents/reviewer-feedback.md` on startup. If it exists, address
the feedback before continuing new work, then delete the file.

**Overnight mode.** When your prompt contains "OVERNIGHT MODE", you are
running unattended in a loop with a reviewer agent. On handoff triggers,
write your summary to `agents/dev-handoff-N.md` (where N is the cycle
number from your prompt) and then exit. The wrapper script will run the
reviewer, which writes feedback to `agents/reviewer-feedback.md`, then
restarts you with that feedback. Do not wait for human input. Do not push.

---

## Rules

- **No debug output in commits.** Remove `fprintf(stderr, "DEBUG`,
  temporary `printf`, and diagnostic dumps before committing. Structured
  logging is fine.
- **Include test output in handoffs.** Every handoff must include the
  actual test count (`N passed, N failed, N skipped`) so the reviewer
  can verify tests ran and the count matches docs.
- **Zero compiler warnings.** Hard requirement.
- **Always use code/tools for arithmetic.** Never mental maths for offsets,
  sizes, or derived constants.
- **Prefer behavioral tests over source-grep tests.** Test what the code
  does, not what it contains.

▶ CUSTOMISE: Add project-specific rules here. Examples:
  - Coding style constraints
  - Security-sensitive areas to flag before changing
  - Specific syscalls, APIs, or patterns that are banned
  - Public/private boundary rules for your repo layout

---

## Doc update checklist

Each progress commit must update ALL relevant docs:

▶ CUSTOMISE: Replace with your project's doc files. Common examples:
  - `docs/CHANGELOG.md` or `CHANGELOG.md` — new entry
  - `docs/architecture.md` — if a new component or interface was added
  - `docs/TODO.md` — mark completed items, add discovered gaps
  - Project context file (`CLAUDE.md` or equivalent) — if test count
    or major facts changed

Do NOT commit code-only changes that leave docs stale.

---

## Investigation methodology

When you hit a crash or unexpected failure:

### 1. Reproduce minimally

Find the smallest input or call sequence that triggers the failure before
changing anything. Write it as a test if possible.

### 2. Read the logs / error output

Identify the exact location (file, line, function) of the failure. Map
any numeric addresses or identifiers back to named symbols.

### 3. Trace the data flow

Follow the relevant data from its origin to the crash site:
- What are the inputs?
- Where does the value go wrong?
- What invariant is violated?

### 4. Cross-reference with authoritative sources

▶ CUSTOMISE: List the primary references for your domain. Examples:
  - Upstream source, specs, or RFCs
  - A reference implementation you trust
  - The project's own design docs

### 5. Fix + test + verify

- Add the fix (one small change)
- Add test (behavioral preferred)
- Run the test suite
- Commit (see workflow above)

---

## Test harness

▶ CUSTOMISE: Describe how to run tests in your project. Example:

```bash
# All tests
./scripts/test-all.sh          # or: pytest, cargo test, make test, etc.

# Specific subset
pytest tests/unit/
pytest tests/integration/
```

When adding a new feature, add tests in the appropriate test directory.

---

## Key references

▶ CUSTOMISE: Link the files an agent should read first when starting a
session. Examples:
- `CLAUDE.md` (or equivalent) — project structure, build instructions
- `docs/architecture.md` — component overview
- `docs/TODO.md` — current priorities
