#!/usr/bin/env bash
# Task 1: git commit -m   vs   git commit -a -m
set -u
SANDBOX=${1:-/tmp/git-task1}
rm -rf "$SANDBOX"; mkdir -p "$SANDBOX"; cd "$SANDBOX"

git init -q
git config user.name  "Saswata Das"
git config user.email "support@symbiotes.in"
git config commit.gpgsign false
git symbolic-ref HEAD refs/heads/main

echo "############ SETUP: one tracked file, committed ############"
echo "version 1" > tracked.txt
git add tracked.txt
git commit -q -m "Initial commit: add tracked.txt"
echo "\$ git log --oneline"
git log --oneline
echo
echo "\$ cat tracked.txt"
cat tracked.txt

echo
echo "##################################################################"
echo "#  EXPERIMENT A:  git commit -m   (WITHOUT -a)                    #"
echo "##################################################################"
echo
echo "--- modify the tracked file, and create a NEW untracked file ---"
echo "version 2 (modified)" > tracked.txt
echo "brand new file" > untracked.txt
echo
echo "\$ git status --short"
git status --short
echo "  M = modified but NOT staged   ?? = untracked"
echo
echo "\$ git commit -m 'try to commit without staging'"
git commit -m "try to commit without staging" 2>&1 || true
echo
echo ">>>> NOTHING WAS COMMITTED. 'git commit -m' only commits what is in the"
echo ">>>> STAGING AREA (the index). We never ran 'git add', so the index is empty."
echo
echo "\$ git log --oneline"
git log --oneline

echo
echo "--- the correct 2-step way with plain 'git commit -m' ---"
echo "\$ git add tracked.txt"
git add tracked.txt
echo "\$ git status --short"
git status --short
echo "  M in the LEFT column = staged"
echo
echo "\$ git commit -m 'commit -m: staged change only'"
git commit -m "commit -m: staged change only"
echo
echo "\$ git status --short"
git status --short
echo ">>>> untracked.txt is STILL not committed. Correct: it was never added."

echo
echo "##################################################################"
echo "#  EXPERIMENT B:  git commit -a -m                                #"
echo "##################################################################"
echo
echo "--- modify the tracked file again (untracked.txt still lying around) ---"
echo "version 3 (modified again)" > tracked.txt
echo
echo "\$ git status --short"
git status --short
echo
echo "\$ git commit -a -m 'commit -a -m: auto-stage tracked files'"
git commit -a -m "commit -a -m: auto-stage tracked files"
echo
echo ">>>> IT WORKED WITH NO 'git add'. -a auto-staged the modified TRACKED file."
echo
echo "\$ git status --short"
git status --short
echo
echo ">>>> BUT untracked.txt is STILL uncommitted!"
echo ">>>> -a does NOT pick up NEW (untracked) files. This is the key limitation."

echo
echo "##################################################################"
echo "#  EXPERIMENT C:  does -a handle DELETIONS?                       #"
echo "##################################################################"
echo "--- add a second tracked file, commit it, then delete it ---"
echo "delete me" > doomed.txt
git add doomed.txt
git commit -q -m "add doomed.txt"
echo
echo "\$ rm doomed.txt"
rm doomed.txt
echo "\$ git status --short"
git status --short
echo "  D = deleted, not staged"
echo
echo "\$ git commit -a -m 'commit -a: also stages deletions'"
git commit -a -m "commit -a: also stages deletions"
echo
echo "\$ git status --short"
git status --short
echo ">>>> YES: -a stages MODIFICATIONS and DELETIONS of tracked files."

echo
echo "##################################################################"
echo "#  Getting untracked.txt in requires an explicit 'git add'        #"
echo "##################################################################"
echo "\$ git add untracked.txt && git commit -m 'add the new file explicitly'"
git add untracked.txt
git commit -q -m "add the new file explicitly"
echo "\$ git status --short   (now clean)"
git status --short
echo "(no output above = working tree clean)"

echo
echo "##################################################################"
echo "#  SUMMARY                                                        #"
echo "##################################################################"
echo
echo "\$ git log --oneline"
git log --oneline
echo
cat <<'TABLE'

                      | git commit -m         | git commit -a -m
  --------------------|-----------------------|--------------------------
  Modified TRACKED    | needs `git add` first | staged AUTOMATICALLY
  Deleted TRACKED     | needs `git add`/`rm`  | staged AUTOMATICALLY
  NEW (untracked)     | needs `git add`       | STILL needs `git add`  <-- !!
  Staged changes      | committed             | committed
  Skips staging area? | no                    | yes, for tracked files only

  Mental model: `-a` means "git add -u" (update tracked) immediately before
  committing. It is NOT "git add -A" / "git add ." — new files are never
  included. That is the single most common misconception about this flag.

TABLE
