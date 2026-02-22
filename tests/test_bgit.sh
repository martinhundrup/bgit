#!/usr/bin/env bash
#
# bgit test suite
#
# Creates a temporary bare repo (fake origin) + clone, runs bgit commands,
# and asserts expected outcomes.  No dependencies beyond bash + git.
#
# Usage:
#   bash tests/test_bgit.sh          # run all tests
#   bash tests/test_bgit.sh -v       # verbose (show bgit output)
#

set -uo pipefail

# ── locate bgit ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BGIT="$REPO_ROOT/bin/bgit"

if [[ ! -x "$BGIT" ]]; then
  echo "ERROR: $BGIT not found or not executable" >&2
  exit 1
fi

# ── colours ──────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  GREEN=$'\033[32m' RED=$'\033[31m' YELLOW=$'\033[33m' RESET=$'\033[0m'
else
  GREEN="" RED="" YELLOW="" RESET=""
fi

# ── counters ─────────────────────────────────────────────────────────────
PASS=0 FAIL=0 SKIP=0
SHOW_OUTPUT=0
[[ "${1:-}" == "-v" ]] && SHOW_OUTPUT=1

# ── temp dir ─────────────────────────────────────────────────────────────
TMPDIR_ROOT=""
cleanup() {
  if [[ -n "$TMPDIR_ROOT" && -d "$TMPDIR_ROOT" ]]; then
    rm -rf "$TMPDIR_ROOT"
  fi
}
trap cleanup EXIT

TMPDIR_ROOT="$(mktemp -d)"
BARE_REPO="$TMPDIR_ROOT/origin.git"
WORK_REPO="$TMPDIR_ROOT/work"

# ── helpers ──────────────────────────────────────────────────────────────

# Initialise a fresh bare repo + clone for each test group
setup_repos() {
  rm -rf "$BARE_REPO" "$WORK_REPO"
  git init --bare "$BARE_REPO" >/dev/null 2>&1

  git clone "$BARE_REPO" "$WORK_REPO" >/dev/null 2>&1
  pushd "$WORK_REPO" >/dev/null || return 1

  # Seed with an initial commit so main exists
  git checkout -b main >/dev/null 2>&1
  echo "init" > README.md
  git add . && git commit -m "initial" >/dev/null 2>&1
  git push -u origin main >/dev/null 2>&1

  popd >/dev/null || true
}

# Run bgit inside the work repo.  Captures stdout+stderr and exit code.
# Sets: BGIT_OUT, BGIT_EXIT
run_bgit() {
  pushd "$WORK_REPO" >/dev/null || return 1
  BGIT_OUT=""
  BGIT_EXIT=0
  BGIT_OUT="$(BGIT_VERBOSE=0 "$BGIT" "$@" 2>&1)" || BGIT_EXIT=$?
  if [[ "$SHOW_OUTPUT" -eq 1 ]]; then
    printf "  [cmd] bgit %s\n" "$*"
    if [[ -n "$BGIT_OUT" ]]; then
      printf "  [out] %s\n" "$BGIT_OUT"
    fi
    printf "  [exit] %d\n" "$BGIT_EXIT"
  fi
  popd >/dev/null || true
}

# Run plain git inside the work repo
work_git() {
  git -C "$WORK_REPO" "$@"
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$label"
    ((PASS++))
  else
    printf "  %s✗%s %s  (expected: '%s'  got: '%s')\n" "$RED" "$RESET" "$label" "$expected" "$actual"
    ((FAIL++))
  fi
}

assert_exit() {
  local label="$1" expected="$2"
  assert_eq "$label (exit=$expected)" "$expected" "$BGIT_EXIT"
}

assert_contains() {
  local label="$1" needle="$2"
  if printf "%s" "$BGIT_OUT" | grep -qF "$needle"; then
    printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$label"
    ((PASS++))
  else
    printf "  %s✗%s %s  (output missing: '%s')\n" "$RED" "$RESET" "$label" "$needle"
    ((FAIL++))
  fi
}

assert_branch() {
  local label="$1" expected="$2"
  local actual
  actual="$(work_git branch --show-current 2>/dev/null)"
  assert_eq "$label" "$expected" "$actual"
}

section() {
  printf "\n%s── %s ──%s\n" "$YELLOW" "$1" "$RESET"
}


# ═════════════════════════════════════════════════════════════════════════
#  TESTS
# ═════════════════════════════════════════════════════════════════════════

# ── help / version ───────────────────────────────────────────────────────
section "help & version"
setup_repos

run_bgit help
assert_exit "bgit help exits 0" 0
assert_contains "help mentions ship" "bgit ship"

run_bgit version
assert_exit "bgit version exits 0" 0
assert_contains "version shows bgit" "bgit"

run_bgit
assert_exit "bgit (no args) exits 0" 0

# ── ship: auto-commit + push ────────────────────────────────────────────
section "ship: auto-commit message"
setup_repos

echo "hello" > "$WORK_REPO/file.txt"
run_bgit ship
assert_exit "ship exits 0" 0

# Verify the commit landed on origin
ORIGIN_LOG="$(git -C "$BARE_REPO" log main --oneline -1 2>/dev/null)"
if printf "%s" "$ORIGIN_LOG" | grep -q "main:"; then
  printf "  %s✓%s auto-generated commit message pushed to origin\n" "$GREEN" "$RESET"
  ((PASS++))
else
  printf "  %s✗%s auto-generated commit message not found on origin (got: '%s')\n" "$RED" "$RESET" "$ORIGIN_LOG"
  ((FAIL++))
fi

# ── ship: custom message ────────────────────────────────────────────────
section "ship: custom message (-m)"
setup_repos

echo "data" > "$WORK_REPO/custom.txt"
run_bgit ship -m "my custom message"
assert_exit "ship -m exits 0" 0

ORIGIN_LOG="$(git -C "$BARE_REPO" log main --oneline -1 2>/dev/null)"
if printf "%s" "$ORIGIN_LOG" | grep -qF "my custom message"; then
  printf "  %s✓%s custom message on origin\n" "$GREEN" "$RESET"
  ((PASS++))
else
  printf "  %s✗%s custom message missing (got: '%s')\n" "$RED" "$RESET" "$ORIGIN_LOG"
  ((FAIL++))
fi

# ── ship: already up to date ────────────────────────────────────────────
section "ship: already up to date"
setup_repos

run_bgit ship
assert_exit "ship clean exits 0" 0
assert_contains "prints already up to date" "Already up to date."

# ── ship: --dry-run ─────────────────────────────────────────────────────
section "ship: --dry-run"
setup_repos

echo "dry" > "$WORK_REPO/dry.txt"
run_bgit ship --dry-run
assert_exit "ship --dry-run exits 0" 0
assert_contains "dry-run shows + git" "+ git"

# Verify nothing was actually pushed
ORIGIN_COUNT="$(git -C "$BARE_REPO" rev-list --count main 2>/dev/null)"
assert_eq "origin still has 1 commit" "1" "$ORIGIN_COUNT"

# ── branch: switch to existing ──────────────────────────────────────────
section "branch: switch to existing local branch"
setup_repos

# Create a second branch via git
pushd "$WORK_REPO" >/dev/null
git checkout -b other >/dev/null 2>&1
echo "x" > other.txt && git add . && git commit -m "other" >/dev/null 2>&1
git push -u origin other >/dev/null 2>&1
git checkout main >/dev/null 2>&1
popd >/dev/null

run_bgit branch other
assert_exit "branch switch exits 0" 0
assert_branch "now on other" "other"

# ── branch: create new (should push) ────────────────────────────────────
section "branch: create new branch (auto-push)"
setup_repos

run_bgit branch feat-xyz
assert_exit "branch create exits 0" 0
assert_branch "now on feat-xyz" "feat-xyz"
assert_contains "published message" "Created and published"

# Verify it exists on origin
if git -C "$BARE_REPO" show-ref --verify --quiet "refs/heads/feat-xyz" 2>/dev/null; then
  printf "  %s✓%s feat-xyz exists on origin\n" "$GREEN" "$RESET"
  ((PASS++))
else
  printf "  %s✗%s feat-xyz NOT on origin\n" "$RED" "$RESET"
  ((FAIL++))
fi

# ── branch: track remote-only branch ────────────────────────────────────
section "branch: track remote-only branch"
setup_repos

# Push a branch from a second clone so it only exists on origin
WORK2="$TMPDIR_ROOT/work2"
git clone "$BARE_REPO" "$WORK2" >/dev/null 2>&1
pushd "$WORK2" >/dev/null
git checkout -b remote-only >/dev/null 2>&1
echo "r" > r.txt && git add . && git commit -m "remote" >/dev/null 2>&1
git push -u origin remote-only >/dev/null 2>&1
popd >/dev/null
rm -rf "$WORK2"

run_bgit branch remote-only
assert_exit "branch track remote exits 0" 0
assert_branch "now on remote-only" "remote-only"

# ── branch: dirty tree rejected ─────────────────────────────────────────
section "branch: dirty tree rejected"
setup_repos

echo "dirty" > "$WORK_REPO/dirty.txt"
run_bgit branch some-branch
assert_exit "branch dirty exits 3" 3
assert_contains "error mentions uncommitted" "uncommitted"

# ── merge: basic merge + ship ───────────────────────────────────────────
section "merge: source -> destination"
setup_repos

# Create feature branch with a commit
pushd "$WORK_REPO" >/dev/null
git checkout -b feature >/dev/null 2>&1
echo "feature work" > feature.txt
git add . && git commit -m "feature commit" >/dev/null 2>&1
git push -u origin feature >/dev/null 2>&1
git checkout main >/dev/null 2>&1
popd >/dev/null

run_bgit merge feature '->' main
assert_exit "merge exits 0" 0
assert_branch "now on main" "main"

# Check feature.txt exists on main
if [[ -f "$WORK_REPO/feature.txt" ]]; then
  printf "  %s✓%s feature.txt present on main after merge\n" "$GREEN" "$RESET"
  ((PASS++))
else
  printf "  %s✗%s feature.txt missing on main\n" "$RED" "$RESET"
  ((FAIL++))
fi

# ── merge: invalid format ───────────────────────────────────────────────
section "merge: invalid format"
setup_repos

run_bgit merge foo bar
assert_exit "merge bad format exits 1" 1

run_bgit merge same '->' same
assert_exit "merge same branch exits 1" 1

# ── nuke ─────────────────────────────────────────────────────────────────
section "nuke"
setup_repos

# Make local-only changes and a local branch
pushd "$WORK_REPO" >/dev/null
echo "local junk" > junk.txt
git add . && git commit -m "local only" >/dev/null 2>&1
git checkout -b local-only >/dev/null 2>&1
echo "more" > more.txt
git add . && git commit -m "local branch" >/dev/null 2>&1
git checkout main >/dev/null 2>&1
popd >/dev/null

run_bgit nuke
assert_exit "nuke exits 0" 0
assert_contains "nuke confirmation" "Nuked"

# local-only branch should be gone
if work_git show-ref --verify --quiet "refs/heads/local-only" 2>/dev/null; then
  printf "  %s✗%s local-only branch still exists\n" "$RED" "$RESET"
  ((FAIL++))
else
  printf "  %s✓%s local-only branch deleted\n" "$GREEN" "$RESET"
  ((PASS++))
fi

# junk.txt should be gone (reset --hard + clean)
if [[ -f "$WORK_REPO/junk.txt" ]]; then
  printf "  %s✗%s junk.txt still present\n" "$RED" "$RESET"
  ((FAIL++))
else
  printf "  %s✓%s junk.txt cleaned\n" "$GREEN" "$RESET"
  ((PASS++))
fi

# ── undo ─────────────────────────────────────────────────────────────────
section "undo"
setup_repos

# Ship two commits so we have something to undo
echo "first" > "$WORK_REPO/first.txt"
run_bgit ship -m "first commit"
assert_exit "ship first exits 0" 0

echo "second" > "$WORK_REPO/second.txt"
run_bgit ship -m "second commit"
assert_exit "ship second exits 0" 0

# Verify second.txt exists
if [[ -f "$WORK_REPO/second.txt" ]]; then
  printf "  %s✓%s second.txt exists before undo\n" "$GREEN" "$RESET"
  ((PASS++))
else
  printf "  %s✗%s second.txt missing before undo\n" "$RED" "$RESET"
  ((FAIL++))
fi

run_bgit undo
assert_exit "undo exits 0" 0
assert_contains "undo confirmation message" "Undone"

# second.txt should be gone after undo
if [[ -f "$WORK_REPO/second.txt" ]]; then
  printf "  %s✗%s second.txt still exists after undo\n" "$RED" "$RESET"
  ((FAIL++))
else
  printf "  %s✓%s second.txt removed after undo\n" "$GREEN" "$RESET"
  ((PASS++))
fi

# first.txt should still be there
if [[ -f "$WORK_REPO/first.txt" ]]; then
  printf "  %s✓%s first.txt still exists after undo\n" "$GREEN" "$RESET"
  ((PASS++))
else
  printf "  %s✗%s first.txt missing after undo\n" "$RED" "$RESET"
  ((FAIL++))
fi

# Verify origin also lost the commit (force-push)
ORIGIN_LOG="$(git -C "$BARE_REPO" log main --oneline 2>/dev/null)"
if printf "%s" "$ORIGIN_LOG" | grep -qF "second commit"; then
  printf "  %s✗%s origin still has 'second commit'\n" "$RED" "$RESET"
  ((FAIL++))
else
  printf "  %s✓%s origin no longer has 'second commit'\n" "$GREEN" "$RESET"
  ((PASS++))
fi

# ── undo: --dry-run ─────────────────────────────────────────────────────
section "undo --dry-run"
setup_repos

echo "dryundo" > "$WORK_REPO/dryundo.txt"
run_bgit ship -m "dry undo commit"

COMMIT_BEFORE="$(work_git rev-parse HEAD 2>/dev/null)"
run_bgit undo --dry-run
assert_exit "undo --dry-run exits 0" 0
assert_contains "dry-run shows + git" "+ git"

COMMIT_AFTER="$(work_git rev-parse HEAD 2>/dev/null)"
assert_eq "commit unchanged after dry-run" "$COMMIT_BEFORE" "$COMMIT_AFTER"

# ── undo: only one commit ───────────────────────────────────────────────
section "undo: only one commit (rejected)"
setup_repos

run_bgit undo
assert_exit "undo single commit exits 1" 1
assert_contains "error mentions cannot undo" "Cannot undo"

# ── status ───────────────────────────────────────────────────────────────
section "status"
setup_repos

run_bgit status
assert_exit "status exits 0" 0
assert_contains "status shows branch" "Branch:"
assert_contains "status shows state" "State:"

# ── status dirty ─────────────────────────────────────────────────────────
section "status: dirty"
setup_repos

echo "x" > "$WORK_REPO/x.txt"
run_bgit status
assert_exit "status dirty exits 0" 0
assert_contains "status shows dirty" "dirty"
assert_contains "status suggests ship" "bgit ship"

# ── check ────────────────────────────────────────────────────────────────
section "check"
setup_repos

run_bgit check
assert_exit "check exits 0" 0
assert_contains "check shows branch" "Branch:"
assert_contains "check shows would ship" "Would ship succeed?"

# ── where ────────────────────────────────────────────────────────────────
section "where"
setup_repos

run_bgit where
assert_exit "where exits 0" 0
assert_contains "where shows Repo:" "Repo:"
assert_contains "where shows Branch:" "Branch:"

# ── log ──────────────────────────────────────────────────────────────────
section "log"
setup_repos

run_bgit log
assert_exit "log exits 0" 0
assert_contains "log shows initial commit" "initial"

# ── remote ───────────────────────────────────────────────────────────────
section "remote"
setup_repos

run_bgit remote
assert_exit "remote exits 0" 0
assert_contains "remote shows origin" "origin"

# ── not a git repo ──────────────────────────────────────────────────────
section "error: not a git repo"
NOT_REPO="$TMPDIR_ROOT/not-a-repo"
mkdir -p "$NOT_REPO"
pushd "$NOT_REPO" >/dev/null
BGIT_OUT=""
BGIT_EXIT=0
BGIT_OUT="$(BGIT_VERBOSE=0 "$BGIT" ship 2>&1)" || BGIT_EXIT=$?
popd >/dev/null
assert_eq "not-a-repo exits 2" "2" "$BGIT_EXIT"

# ── unknown command ─────────────────────────────────────────────────────
section "error: unknown command"
setup_repos

run_bgit foobar
assert_exit "unknown cmd exits 1" 1

# ── -v flag ──────────────────────────────────────────────────────────────
section "-v flag"
setup_repos

echo "v" > "$WORK_REPO/v.txt"
pushd "$WORK_REPO" >/dev/null
BGIT_OUT="$(BGIT_VERBOSE=0 "$BGIT" -v ship -m "verbose test" 2>&1)" || BGIT_EXIT=$?
popd >/dev/null
if printf "%s" "$BGIT_OUT" | grep -qF "[bgit]"; then
  printf "  %s✓%s -v flag enables debug output\n" "$GREEN" "$RESET"
  ((PASS++))
else
  printf "  %s✗%s -v flag did not enable debug output\n" "$RED" "$RESET"
  ((FAIL++))
fi

# ═════════════════════════════════════════════════════════════════════════
#  SUMMARY
# ═════════════════════════════════════════════════════════════════════════

printf "\n%s════════════════════════════════════%s\n" "$YELLOW" "$RESET"
printf "  %s%d passed%s  " "$GREEN" "$PASS" "$RESET"
if [[ "$FAIL" -gt 0 ]]; then
  printf "%s%d failed%s  " "$RED" "$FAIL" "$RESET"
else
  printf "0 failed  "
fi
printf "%d skipped\n" "$SKIP"
printf "%s════════════════════════════════════%s\n" "$YELLOW" "$RESET"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
