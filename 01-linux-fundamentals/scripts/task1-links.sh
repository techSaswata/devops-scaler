#!/usr/bin/env bash
# Task 1: Soft Link (symlink) vs Hard Link — hands-on demo
set -u

demo=/tmp/links-demo
rm -rf "$demo"; mkdir -p "$demo"; cd "$demo"

echo "############ STEP 1: create the original file ############"
echo "Hello from the original file" > original.txt
cat original.txt
echo
echo "--- inode + link count of original.txt ---"
ls -li original.txt

echo
echo "############ STEP 2: create a HARD link ############"
echo "\$ ln original.txt hardlink.txt"
ln original.txt hardlink.txt
ls -li original.txt hardlink.txt
echo ">> Same inode number, and the link count went 1 -> 2."

echo
echo "############ STEP 3: create a SOFT link (symlink) ############"
echo "\$ ln -s original.txt softlink.txt"
ln -s original.txt softlink.txt
ls -li original.txt hardlink.txt softlink.txt
echo ">> softlink.txt has its OWN inode, type 'l', and shows -> original.txt"

echo
echo "--- stat comparison ---"
stat -c 'name=%n  inode=%i  links=%h  type=%F  size=%s' original.txt hardlink.txt softlink.txt

echo
echo "############ STEP 4: edit through each link ############"
echo "line added via hardlink" >> hardlink.txt
echo "line added via softlink" >> softlink.txt
echo "--- contents of original.txt after writing through both links ---"
cat original.txt
echo ">> Both links wrote into the SAME file data."

echo
echo "############ STEP 5: delete the ORIGINAL and see what survives ############"
echo "\$ rm original.txt"
rm original.txt
echo
echo "--- hard link after original is gone ---"
ls -li hardlink.txt
cat hardlink.txt
echo ">> HARD LINK STILL WORKS. It is a second name for the same inode;"
echo ">> the data is freed only when the link count hits 0."
echo
echo "--- soft link after original is gone ---"
ls -li softlink.txt
echo "\$ cat softlink.txt"
cat softlink.txt 2>&1 || true
echo ">> SOFT LINK IS BROKEN (dangling). It only stored the PATH 'original.txt'."
echo "\$ test -e softlink.txt  # follows the link"
test -e softlink.txt && echo "target exists" || echo "target does NOT exist -> dangling symlink"
echo "\$ test -L softlink.txt  # the link itself"
test -L softlink.txt && echo "the symlink file itself still exists"

echo
echo "############ STEP 6: things a hard link CANNOT do ############"
mkdir -p somedir
echo "\$ ln somedir dirhardlink   # hard link to a directory"
ln somedir dirhardlink 2>&1 || true
echo ">> Not permitted: hard links to directories are forbidden (would break the FS tree)."
echo
echo "\$ ln -s somedir dirsoftlink  # soft link to a directory works fine"
ln -s somedir dirsoftlink
ls -ld dirsoftlink

echo
echo "############ STEP 7: cross-filesystem behaviour ############"
echo "\$ df /tmp  and  df /   (hard links cannot cross a filesystem boundary)"
df -h /tmp / | sed 's/^/    /'

echo
echo "############ STEP 8: deleting links ############"
echo "\$ rm softlink.txt     # removes the symlink, not the target"
echo "\$ unlink hardlink.txt # removes one name; data survives while count > 0"
rm -f dirsoftlink softlink.txt
unlink hardlink.txt
ls -la
echo ">> All links removed; the file's data is now unreachable and freed."
