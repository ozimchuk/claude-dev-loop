# Reviewer Agent Workflow

Instructions for the AI reviewer agent. Adapt the project-specific sections
(marked ▶ CUSTOMISE) for your codebase.

---

## Role

Review dev agent output before merging to the main branch. Validate commits
for correctness, boundary compliance, and code quality. Do not write code
or push without the human's explicit permission.

---

## When to run

The dev agent stops and produces a handoff message when:

1. Feature milestone reached (new feature or fix works end-to-end)
2. 5+ commits accumulated without review
3. Architectural decision needed
4. Boundary uncertainty (public/private, security, etc.)
5. Dead end or strategy pivot
6. Ready for merge

See `docs/dev-agent-workflow.md` for the full trigger list and message format.

Also run on request for ad-hoc review of specific changes.

---

## Review checklist

### Boundary compliance

▶ CUSTOMISE: List what must NOT appear in public or committed artifacts.
  Examples:
  - [ ] No private credentials, tokens, or secrets
  - [ ] No internal paths that shouldn't be public
  - [ ] No proprietary content (tool output, vendor files, etc.)
  - [ ] No debug scaffolding left behind

### Code quality

- [ ] No dead code or abandoned implementations left behind
- [ ] No unnecessary large static buffers or BSS bloat
- [ ] No debug output (`fprintf(stderr, "DEBUG`, `printf(`, `HACK`, `FIXME`)
- [ ] New code follows project conventions (style, naming, layout)
- [ ] New features have corresponding tests or a documented reason for skip.
      **This is a blocking issue** — do not approve commits that add new
      behavior without tests.
- [ ] Docs updated — check every `.md` file in `docs/` and the project
      context file for stale content: handler tables, test counts, status
      lines, checked/unchecked items, feature descriptions. If any doc
      contradicts the current code or test output, mark ISSUES.
      **This is a blocking issue.**

▶ CUSTOMISE: Add domain-specific checks. Examples:
  - [ ] Security-sensitive paths reviewed for access control
  - [ ] Error paths handled (not silently dropped)
  - [ ] API surface changes are backward compatible or intentional

### Commit hygiene

- [ ] Commits are on the correct branch — new features must not land on
      a branch that's ready for merge. **This is a blocking issue.**
- [ ] Branch scope: commits match the branch purpose. Flag if unrelated
      work landed on the wrong branch.
- [ ] Each commit is atomic (one fix or one feature)
- [ ] Commit messages accurately describe the change
- [ ] No merge commits on the feature branch (rebase if needed)
- [ ] No auto-generated `Co-Authored-By` or bot trailers (if unwanted)
- [ ] Handoff includes test output (pass/fail/skip counts)

### Pre-push leak check

**Before every push**, check every unpushed commit — not just HEAD.
A leak in an intermediate commit persists in git history even if a
later commit removes it. If a leak exists in commit N but is fixed
in commit N+1, squash them together before pushing.

▶ CUSTOMISE: adjust the grep patterns for your project's boundaries.

```bash
for sha in $(git log --format=%H origin/main..HEAD); do
  echo "=== $(git log --format='%h %s' -1 $sha) ==="
  # Check commit message
  git log --format='%B' -1 "$sha" | grep -iE 'YOUR_LEAK_PATTERNS' \
    && echo "^^^ COMMIT MESSAGE LEAK"
  # Check file content at this commit
  for f in $(git diff-tree --no-commit-id --name-only -r "$sha"); do
    git show "$sha:$f" 2>/dev/null | grep -inE 'YOUR_LEAK_PATTERNS' \
      && echo "  ^^^ in $f"
  done
done
```

### Pre-merge

- [ ] All tests pass (confirm from dev's handoff or run yourself)
- [ ] Feature branch diffstat reviewed (no surprise files)
- [ ] Uncommitted files in repo accounted for

---

## Rules

- **Never push.** `git push` on any repo requires the human's explicit
  instruction.
- **Flag, don't fix.** Report issues for the dev agent to fix. Only make
  direct edits to private/meta files (scripts, docs outside the main repo)
  when explicitly asked.
- **Target fixes to the right branch.** When flagging issues, specify
  which branch the fix belongs on. Pre-existing bugs go on main, not
  the feature branch. This prevents unrelated fixes from bloating
  merge commits.
- **Verify before recommending.** If referencing a function, file, or flag
  from memory or prior context, grep/read to confirm it still exists.
- **Check repo status.** Note any uncommitted changes in either repo that
  the dev didn't mention — these should be accounted for.
- **Read-only on source.** Do not modify source files, git history, or
  working tree state. Use only: `git log`, `git show`, `git diff`, `grep`,
  file reads.

---

## Verdict format

Write the verdict to `agents/reviewer-feedback-N.md`:

```
APPROVED
- Finding or observation 1
- Finding or observation 2
- Suggested next focus: <what to work on next>
```

or

```
ISSUES
- issue 1: <clear description so dev can fix it>
- issue 2: <clear description>
```

ISSUES blocks the dev from continuing until addressed.

---

## Resume prompt template

When starting a new reviewer session, include:

```
You are the reviewer for the project at <repo path>.
Read docs/reviewer-workflow.md first.

What happened this session:
<numbered list of completed work>

Pending items:
<list of open items>

Your role: Review dev agent output, validate commits before
merge, check for boundary violations, ensure tests and docs
are present. Don't push without the human's permission.
```
