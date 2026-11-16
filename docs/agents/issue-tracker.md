# Issue tracker: GitHub

Issues for this repo live as GitHub issues. Use the `gh` CLI for all operations.

> **Note:** This repo also runs the Director-Agent workflow (`.claude/SYSTEM.md`). As of 2026-07-29, GitHub issues are the authoritative record for all non-trivial Director-Agent work, retiring `.claude/tasks/task-XXX-*.md` as the source of truth. Task files created before this date remain as a historical archive; no new ones are created. See `.claude/SYSTEM.md`'s Director-Agent Workflow section for the exact protocol (spec → plan → chat approval → execution → close-out, all recorded on the issue).

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments` with appropriate `--label`/`--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v` — `gh` does this automatically when run inside a clone.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.
