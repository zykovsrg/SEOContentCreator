# Current Task

Status: active

Allowed statuses: empty / active / review / blocked / done / paused

Stage: implementation

Allowed stages: intake / spec / planning / implementation / review / task-finish

## Mode

implementation / review / task-finish / architecture-update

## Goal

Safely inspect local and remote Git branches, merge the relevant local work so the repository state is synchronized with the local version, and push the synchronized result to GitHub.

## Use Superpowers

yes

## Relevant files

Git branches, repository history, local working tree

## Done criteria

- Local and remote branch state inspected before merging.
- User-owned/unrelated local changes are not silently discarded.
- Relevant branches are merged or a blocker is clearly reported.
- GitHub remote is pushed after the repository is verified safe enough to publish.

## Agent handoff

Last agent: Codex

What changed:
Task recorded through task-intake.


Open risks:
Merging every branch can pull unfinished or conflicting work; verify branch intent and working tree state before merge/push.


Next agent should check:
`git status`, local/remote branches, remotes, and any uncommitted user changes before performing merge or push.
