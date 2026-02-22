# bgit Commands

bgit is an opinionated CLI wrapper around git for a simple workflow: sync from remote, stage everything, commit, push. For advanced git operations, use git directly.

All commands support the `-v` flag for verbose/debug output (or set `BGIT_VERBOSE=1`).

---

## Mutating Commands

### `bgit ship`

Safely sync and publish all local changes in one step.

**What it does:**

1. Pulls from remote with `--ff-only` (if upstream is configured)
2. Stages all changes (`git add .`)
3. Commits with an auto-generated message (or a custom one via `-m`)
4. Pushes to remote (sets upstream automatically if needed)

If the working tree is clean and there's nothing to push, it prints "Already up to date." and exits.

**Flags:**

| Flag | Description |
|------|-------------|
| `-m`, `--message "<msg>"` | Use a custom commit message instead of auto-generating one |
| `--dry-run` | Print the git commands that would be executed without running them |
| `-v` | Enable verbose/debug output |

**Auto-generated commit messages** follow the format:
```
<branch>: <diffstat summary> (<timestamp>)
```
Example: `main: 3 files changed, 12 insertions(+), 4 deletions(-) (2026-02-21 14:30:05)`

**Use case:**

You've been editing files and want to save and push everything:
```bash
bgit ship                        # auto-commit message, push
bgit ship -m "fix login bug"     # custom message
bgit ship --dry-run              # see what would happen
```

**Error scenarios:**

- Remote history has diverged → exits with guidance to resolve manually
- Detached HEAD with no upstream → exits with guidance to create a branch
- Not in a git repo → exits with error

---

### `bgit branch <name>`

Switch to a branch safely, or create and publish a new one.

**What it does:**

1. Checks that the working tree is clean (no uncommitted changes)
2. Fetches from remote with `--prune`
3. Resolves the branch:
   - **Exists locally** → switches to it
   - **Exists on remote only** → creates a local tracking branch
   - **Doesn't exist anywhere** → creates a new branch and pushes it to origin
4. Pulls latest changes if the branch has an upstream

**Flags:**

| Flag | Description |
|------|-------------|
| `--dry-run` | Print the git commands that would be executed without running them |
| `-v` | Enable verbose/debug output |

**Use case:**

```bash
bgit branch feature/login     # switch to or create feature/login
bgit branch main              # switch back to main
bgit branch hotfix            # create + push a new branch named hotfix
```

**Error scenarios:**

- Working tree has uncommitted changes → exits with error (exit code 3)
- Remote history diverged after switching → exits with guidance

---

### `bgit merge <source> to <destination>`

Safely merge one branch into another, then ship the result.

**What it does:**

1. Checks that the working tree is clean
2. Fetches from remote with `--prune`
3. Validates both branches exist (locally or on remote)
4. Ensures both branches have no un-shipped local commits
5. Switches to the destination branch and pulls
6. Merges the source branch into the destination with `--no-ff`
7. Automatically ships the merged result (commit + push)

**Flags:**

| Flag | Description |
|------|-------------|
| `-v` | Enable verbose/debug output |

**Use case:**

```bash
bgit merge feature/login to main        # merge feature into main
bgit merge hotfix/crash to develop       # merge hotfix into develop
```

**Error scenarios:**

- Source or destination branch doesn't exist → exits with error
- Either branch has un-shipped local commits → exits with guidance to ship first
- Merge conflicts → exits with guidance to resolve manually, then run `bgit ship`
- Same branch on both sides → exits with error

---

### `bgit undo`

Remove the last commit from the current branch and force-push the result to remote. **This is intentionally destructive.**

**What it does:**

1. Ensures you're on a branch (not detached HEAD)
2. Ensures there is more than one commit (cannot undo the only commit)
3. Runs `git reset --hard HEAD~1` to remove the last commit locally
4. Runs `git push --force` to update the remote

The commit and its changes are permanently lost after this operation.

**Flags:**

| Flag | Description |
|------|-------------|
| `--dry-run` | Print the git commands that would be executed without running them |
| `-v` | Enable verbose/debug output |

**Use case:**

```bash
bgit undo              # remove last commit + force-push
bgit undo --dry-run    # see what would happen
```

You just shipped a commit with a typo or wrong changes and want to completely remove it:
```bash
bgit ship -m "broken change"    # oops
bgit undo                       # remove it from branch + remote
```

**Error scenarios:**

- Detached HEAD → exits with error
- Only one commit on the branch → exits with error
- Not in a git repo → exits with error

---

### `bgit nuke`

Delete ALL local changes and make local branches match the remote. **This is intentionally destructive.**

**What it does:**

1. Fetches from remote with `--prune`
2. Determines the default remote branch
3. Force-updates every local branch to match its remote counterpart
4. Sets upstream tracking for all branches
5. Deletes any local-only branches (not on remote)
6. Switches to the original branch (if it exists on remote) or the default branch
7. Hard-resets and cleans the working tree

After nuke, your local state is identical to the remote.

**Flags:**

| Flag | Description |
|------|-------------|
| `--dry-run` | Print the git commands that would be executed without running them |
| `-v` | Enable verbose/debug output |

**Use case:**

```bash
bgit nuke              # reset everything to match origin
bgit nuke --dry-run    # see what would be destroyed
```
bgit nuke --dry-run    # see what would be destroyed
```

---

## Diagnostic Commands

These commands are read-only and never modify your repository.

### `bgit status`

Show the current state of your repository, including whether a ship would succeed.

**Output includes:**

- Repository root path
- Current working directory
- Current branch
- Upstream tracking branch
- Remote URL
- Clean or dirty state
- Commits ahead/behind remote
- Ship readiness (yes/no with reason)

**Flags:**

| Flag | Description |
|------|-------------|
| `-v` | Enable verbose/debug output |

**Use case:**

```bash
bgit status
# Repo:     /Users/you/projects/myapp
# CWD:      /Users/you/projects/myapp/src
# Branch:   main
# Upstream: origin/main
# Remote:   git@github.com:user/repo.git
# State:    dirty
# Ahead:    0
# Behind:   0
# Ship:     yes (run bgit ship)
```

---

### `bgit log`

Show the last 5 commits on the current branch.

**Output format:**

```
<short_sha> <message> (<relative time>)
```

**Flags:**

| Flag | Description |
|------|-------------|
| `-v` | Enable verbose/debug output |

**Use case:**

```bash
bgit log
# a1b2c3d fix login validation (2 hours ago)
# d4e5f6a add user model (5 hours ago)
# 7890abc initial commit (2 days ago)
```

---

### `bgit help`

Show the command list with short descriptions.

**Use case:**

```bash
bgit help
```

---

### `bgit version`

Show bgit and git versions.

**Use case:**

```bash
bgit version
# bgit 0.1.3
# git version 2.43.0
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Invalid usage (bad arguments, unknown command) |
| 2 | Not a git repository |
| 3 | Dirty working tree (uncommitted changes) |
| 4 | Upstream or remote missing |
| 5 | Pull failed (history diverged) |
| 6 | Local un-shipped commits |
| 7 | Merge conflict |

---

## Global Options

| Option | Description |
|--------|-------------|
| `-v` | Enable verbose debug output. Prints `[bgit] ...` trace messages and `+ git ...` for every mutating git command. Can be placed before or after the subcommand. |
| `BGIT_VERBOSE=1` | Environment variable alternative to `-v`. |
