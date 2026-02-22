# bgit

## About

bgit ('better' git or 'bad' git, depending on who you ask) was made to simplify the common workflows of working with git, while maintaining full compatability.

See the [list of commands](commands.md) to learn more about it's features.

## Installation

bgit is a Bash CLI (runtime dependency: `git`).

This repo contains a small launcher script `bgit` that delegates to `bin/bgit`.
Keep `bgit` and the `bin/` directory together.

By default, bgit prints each mutating `git` command it runs (prefixed with `+ git ...`).
To disable that, set `BGIT_VERBOSE=0`.

Minimal: clone + put `bgit` on your PATH

macOS / Linux

    git clone https://github.com/<OWNER>/<REPO>.git
    cd <REPO>
    chmod +x ./bgit ./bin/bgit

    mkdir -p ~/.local/bin
    ln -sf "$PWD/bgit" ~/.local/bin/bgit

    # Ensure ~/.local/bin is on your PATH, then:
    bgit version
    bgit help

Windows

bgit requires a Bash environment. Two common options:

- Git for Windows (Git Bash): install Git, then run `bgit` from a Git Bash shell.
- WSL: install WSL, then run `bgit` inside WSL.

If you want to run it from `cmd.exe` or PowerShell, this repo includes shims:

    bgit.cmd   (cmd.exe)
    bgit.ps1   (PowerShell)

They still require `bash` to be available (from Git for Windows or WSL).

## 1. Overview

bgit is an opinionated CLI wrapper around git that optimizes for one primary workflow:

    Sync from remote → stage everything → commit → push

It is intentionally minimal. It does not expose advanced Git functionality. If a user needs advanced features, they should use git directly.

---

## 2. Core Design Principles

1. Single publishing command: Only `bgit ship` publishes to remote.
2. Fast-forward safety: All pulls must use `--ff-only`.
3. No partial staging: Always `git add .`.
4. No power-user tools: No rebase, stash, amend, partial add, or passthrough.
5. Fail loudly and clearly: When unsafe or ambiguous, exit with actionable guidance.
6. Clean-state bias: Many operations refuse to proceed if the working tree is dirty.
7. Remote assumption: `origin` is the default and only supported remote in v1.

---

## 3. Command Surface (v1)

Mutating commands:
- bgit ship
- bgit branch <name>
- bgit merge <source> to <destination>
- bgit undo
- bgit nuke

Read-only / diagnostic commands:
- bgit status
- bgit log
- bgit help
- bgit version

No other commands are supported.

---

# 4. Command Specifications

---

# 4.1 bgit ship

## Purpose

Safely sync and publish all local changes.

## Behavior

Execution order:

1. Ensure inside a git repository.
2. Ensure remote `origin` exists.
3. Verify working tree state.
4. Run:
    - git pull --ff-only (if upstream exists)
   - git add .
   - git commit -m "<message>"
    - git push (or `git push -u origin <branch>` if no upstream)

## Flags

- -m, --message "<msg>"
  If omitted, prompt:
      Commit message:
  Empty messages are rejected.

- --dry-run
  Print planned git commands without executing.

## Special Handling

If working tree is clean and no new commits:
- After pull, if nothing to commit and nothing to push:
    Print: Already up to date.
    Exit 0.

If pull fails (non fast-forward):
    Print:
        Remote history diverged.
        Resolve using git (e.g., pull --rebase or manual merge), then rerun bgit ship.
    Exit with pull failure code.

If no upstream configured:
    Ship still publishes:
    - Skip pull.
    - Push and set upstream:
        git push -u origin <branch>

    If HEAD is detached:
        Print an error and exit (cannot set upstream).

---

# 4.2 bgit branch <name>

## Purpose

Switch to a branch safely, pulling after switching. This fails if the working branch has un-shipped code.

## Contract

Always:
- Resolve branch
- Switch
- Pull (if upstream exists)

## Algorithm

Step 0 — Preconditions

- Must be inside a git repository.
- <name> required.
- Working tree must be clean:
    git status --porcelain must return empty.
    If not empty:
        Print:
            Working tree has uncommitted changes.
            Use git if you need advanced branch switching.
        Exit.

Step 1 — Fetch

    git fetch origin --prune

Step 2 — Resolve Branch

Case A: Branch exists locally
    git switch <name>

Case B: Branch exists remotely (origin/<name>)
    git switch --track -c <name> origin/<name>

Case C: Branch exists nowhere
    git switch -c <name>
    Print:
        Created new local branch '<name>'.
        Run bgit ship to publish and set upstream.

Step 3 — Pull

If branch has upstream:
    git pull --ff-only

If no upstream:
    Do not error.
    Inform user branch is unpublished.

---

# 4.3 bgit merge <source> to <destination>

## Purpose

Safely merge one branch into another, regardless of current branch.

## Format

    bgit merge <source> to <destination>

Example:

    bgit merge feature/login to main

## Rules

- Always fetch first.
- Always pull both branches.
- Fail if either branch has local un-shipped work.
- Ship after the merge (if merge was successful).

## Algorithm

Step 0 — Parse

Require exact format:
    <source> to <destination>

Reject if:
- Missing keyword
- Same branch on both sides

Step 1 — Preconditions

- Must be in git repo.
- Must have remote origin.
- Current working tree must be clean.

Step 2 — Fetch

    git fetch origin --prune

Step 3 — Ensure Both Branches Exist

For both <source> and <destination>:

- If local exists: OK.
- Else if origin/<name> exists:
    Create tracking branch when needed.
- Else:
    Print:
        Branch '<name>' not found locally or on origin.
    Exit.

Step 4 — Validate Both Branches Have No Un-Shipped Work

For each branch <b>:

1. Switch to branch:
       git switch <b>
   (Create tracking if needed.)

2. Ensure upstream exists:
   If none:
       Print:
           Branch '<b>' has no upstream.
           Cannot verify shipped state.
       Exit.

3. Pull:
       git pull --ff-only

4. Ensure clean working tree:
       git status --porcelain
   Must be empty.

5. Check ahead count:
       git rev-list --left-right --count @{upstream}...HEAD
   If ahead > 0:
       Print:
           Branch '<b>' has local commits not shipped.
           Run bgit ship on '<b>' first.
       Exit.

Step 5 — Perform Merge

1. Switch to destination:
       git switch <destination>

2. Final safety pull:
       git pull --ff-only

3. Merge:
       git merge --no-ff <source>

If merge conflicts occur:
    Print:
        Merge has conflicts.
        Resolve using git.
        After resolving, run bgit ship on '<destination>'.
    Exit.

Otherwise, ship the branch that got merged into:
    bgit ship

---

# 4.4 bgit undo

## Purpose

Remove the last commit from the current branch and force-push the result to remote.

This is intentionally destructive.

## Behavior

Execution order:

1. Ensure inside a git repository.
2. Ensure remote `origin` exists.
3. Ensure not in detached HEAD state.
4. Ensure there is more than one commit (cannot undo the only commit).
5. Confirm intent (unless `--yes`).
6. Run:
     - git reset --hard HEAD~1
     - git push --force

Result:
- The last commit is removed from the branch locally and on remote.
- Any changes from that commit are permanently lost.

## Flags

- --dry-run
    Print planned git commands without executing.

---

# 4.5 bgit nuke

## Purpose

Delete ALL local changes and make local branches match the remote (`origin`).

This is intentionally destructive.

## Behavior

Execution order:

1. Ensure inside a git repository.
2. Ensure remote `origin` exists.
3. Run:
     - git fetch origin --prune
     - Determine the default remote branch from `origin/HEAD`
     - Switch to a detached HEAD at `origin/<default>`
     - For every remote branch `origin/<b>`:
             - Force-create / force-update local branch `<b>` to point at `origin/<b>`
             - Set upstream of `<b>` to `origin/<b>`
     - Delete any local-only branches (branches that do not exist on origin)
     - Switch back to the original branch if it exists on origin; otherwise switch to the default branch
     - git reset --hard origin/<final>
     - git clean -fdx

Result:
- Your working tree becomes identical to the remote branch you end on.
- Any local-only commits/branches are discarded.

## Flags

- --dry-run
    Print planned git commands without executing.


# 5. Diagnostic Commands

## bgit status

Display:
- Repository root path
- Current working directory
- Current branch
- Upstream tracking
- Remote URL
- Clean/dirty
- Ahead/behind
- Ship readiness (yes/no with reason)

## bgit log

Display last 5 commits:
    <short_sha> <message> (<relative time>)

## bgit help

Display:
- Command list
- Short examples
- Statement:
    bgit is for simple workflows.
    For advanced operations, use git directly.

## bgit version

Display:
- bgit version
- git version

---

# 6. Error Handling Philosophy

- Always exit non-zero on failure.
- Print actionable next step.
- Do not attempt to auto-resolve conflicts.
- Never hide git errors.

---

# 7. Exit Codes

0  Success  
1  Invalid usage  
2  Not a git repo  
3  Dirty working tree  
4  Upstream / remote missing  
5  Pull failed (divergence)  
6  Local un-shipped commits  
7  Merge conflict  

---

# 8. Non-Goals

- No rebase support
- No amend
- No interactive staging
- No passthrough to git
- No stash
- No advanced branch surgery
- No conflict resolution tools
- No custom remote selection (origin only in v1)

---

# 9. Mental Model

- Use bgit ship to publish.
- Use bgit branch to move safely.
- Use bgit merge to combine safely.
- Use git for everything advanced.

End of Specification.
