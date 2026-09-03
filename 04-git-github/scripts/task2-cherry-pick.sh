#!/usr/bin/env bash
# Task 2: git cherry-pick
set -eu
SANDBOX=${1:-/tmp/git-task2}
rm -rf "$SANDBOX"; mkdir -p "$SANDBOX"; cd "$SANDBOX"

git init -q
git config user.name  "Saswata Das"
git config user.email "support@symbiotes.in"
git config commit.gpgsign false
git symbolic-ref HEAD refs/heads/main

GL='git log --oneline --graph --decorate --all'

echo "##################################################################"
echo "#  STEP 1: create 3 commits on main                               #"
echo "##################################################################"

echo "# DevOps Homework — Saswata Das (24BCS10248)" > README.md
git add README.md
git commit -q -m "C1: add README"
echo "  committed C1"

echo "print('hello from app')" > app.py
git add app.py
git commit -q -m "C2: add app.py"
echo "  committed C2"

cat >> README.md <<'EOT'

## Setup
Run `python3 app.py`.
EOT
git add README.md
git commit -q -m "C3: document setup in README"
echo "  committed C3"

echo
echo "##################################################################"
echo "#  STEP 2: view the commits with git log                          #"
echo "##################################################################"
echo
echo "\$ git log --oneline"
git log --oneline
echo
echo "\$ git log --oneline --graph --decorate"
git log --oneline --graph --decorate
echo
echo "\$ git log --stat -1"
git log --stat -1

echo
echo "##################################################################"
echo "#  STEP 3: create a new branch and switch to it                   #"
echo "##################################################################"
echo
echo "\$ git checkout -b feature"
git checkout -b feature
echo
echo "\$ git branch"
git branch

echo
echo "##################################################################"
echo "#  STEP 4: make 3 commits on the feature branch                   #"
echo "##################################################################"

cat > utils.py <<'EOT'
def greet(name):
    return f"Hello, {name}!"
EOT
git add utils.py
git commit -q -m "F1: add utils.py with greet()"
echo "  committed F1 (adds utils.py)"

cat > .gitignore <<'EOT'
__pycache__/
*.pyc
.env
EOT
git add .gitignore
git commit -q -m "F2: add .gitignore  <-- THIS is the one we will cherry-pick"
echo "  committed F2 (adds .gitignore)  <-- the target"

cat > app.py <<'EOT'
from utils import greet

print(greet("DevOps"))
EOT
git add app.py
git commit -q -m "F3: rewrite app.py to use utils.greet()"
echo "  committed F3 (depends on F1 — it imports utils)"

echo
echo "##################################################################"
echo "#  STEP 5: git log to IDENTIFY the specific commit                #"
echo "##################################################################"
echo
echo "\$ git log --oneline"
git log --oneline
echo
echo "\$ git log --oneline --graph --decorate --all"
eval "$GL"
echo
echo "--- find the commit that adds .gitignore ---"
echo "\$ git log --oneline --all -- .gitignore"
git log --oneline --all -- .gitignore
echo
TARGET=$(git log --format=%H --all -- .gitignore | head -1)
SHORT=$(git rev-parse --short "$TARGET")
echo "Identified target commit: $SHORT"
echo
echo "\$ git show --stat $SHORT"
git show --stat "$SHORT"

echo
echo "##################################################################"
echo "#  STEP 6: switch back to main and CHERRY-PICK that one commit    #"
echo "##################################################################"
echo
echo "\$ git checkout main"
git checkout main
echo
echo "--- BEFORE: main does NOT have .gitignore ---"
echo "\$ ls -a"
ls -a
echo "\$ git log --oneline"
git log --oneline
echo
echo "\$ git cherry-pick $SHORT"
git cherry-pick "$SHORT"

echo
echo "##################################################################"
echo "#  STEP 7: VERIFY the change is now on main                       #"
echo "##################################################################"
echo
echo "--- AFTER: .gitignore now exists on main ---"
echo "\$ ls -a"
ls -a
echo
echo "\$ cat .gitignore"
cat .gitignore
echo
echo "\$ git log --oneline"
git log --oneline
echo
echo "\$ git log --oneline --graph --decorate --all"
eval "$GL"

echo
echo "--- proof the file is tracked on main, not just sitting on disk ---"
echo "\$ git ls-files"
git ls-files
echo
echo "\$ git log --oneline main -- .gitignore"
git log --oneline main -- .gitignore

echo
echo "--- the cherry-picked commit has a NEW hash (different commit object) ---"
NEWHASH=$(git rev-parse --short HEAD)
echo "original on feature : $SHORT"
echo "copy on main        : $NEWHASH"
echo
echo "\$ git show --stat HEAD"
git show --stat HEAD
echo
echo "--- but the CONTENT (the tree/patch) is identical ---"
echo "\$ diff <(git show $SHORT -- .gitignore) <(git show HEAD -- .gitignore)"
if diff <(git show "$SHORT" --format="" -- .gitignore) \
        <(git show HEAD    --format="" -- .gitignore) >/dev/null; then
  echo "IDENTICAL patch — same change, new commit."
else
  echo "patches differ"
fi

echo
echo "--- F1 and F3 were NOT brought over: only the one commit was picked ---"
echo "\$ ls"
ls
echo "\$ git log --oneline main"
git log --oneline main
echo ">> utils.py (F1) and the app.py rewrite (F3) are still only on 'feature'."

echo
echo "##################################################################"
echo "#  BONUS: what a cherry-pick CONFLICT looks like                  #"
echo "##################################################################"
echo "--- cherry-pick F3, which rewrites app.py and needs utils.py ---"
F3=$(git log --format=%H feature -- app.py | head -1)
echo "\$ git cherry-pick $(git rev-parse --short "$F3")"
if git cherry-pick "$F3" 2>&1; then
  echo
  echo ">> It applied cleanly, BUT the code is now BROKEN on main:"
  echo "\$ cat app.py"
  cat app.py
  echo "\$ ls utils.py"
  ls utils.py 2>&1 || echo "utils.py does NOT exist on main!"
  echo
  echo ">> This is the real lesson: cherry-pick copies ONE commit, not its"
  echo ">> dependencies. app.py imports utils.greet, but F1 (which created"
  echo ">> utils.py) was never picked. Git cannot know that."
  echo
  echo "\$ git reset --hard HEAD~1   # undo it"
  git reset --hard HEAD~1
else
  echo
  echo ">> CONFLICT. Resolve with: edit the file, git add, git cherry-pick --continue"
  echo "\$ git status --short"
  git status --short
  echo "\$ git cherry-pick --abort"
  git cherry-pick --abort
fi
echo
echo "\$ git log --oneline main   (final state)"
git log --oneline main
