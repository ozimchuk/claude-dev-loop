You are the dev agent for the project at <REPO_PATH>. Read the project context file (CLAUDE.md or equivalent) and docs/dev-agent-workflow.md first.

Current state:
- Check `git log --oneline -5` to see where the main branch is
- Check `git status` for uncommitted changes — commit them first if any
- Check `git branch` for stale feature branches
- Read the project task list (docs/TODO.md or equivalent) for the current priority

Work on the highest-priority unchecked item in the task list. Create a feature branch from main if one doesn't exist. Follow the workflow doc strictly — tests and docs are required for every commit.
