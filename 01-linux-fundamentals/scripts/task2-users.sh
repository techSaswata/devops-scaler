#!/usr/bin/env bash
# Task 2: adduser vs useradd
set -u

echo "############ Where do the two commands come from? ############"
echo "\$ which useradd adduser"
which useradd adduser
echo
echo "\$ file \$(which adduser)"
file "$(which adduser)"
echo "\$ file \$(which useradd)"
file "$(which useradd)"
echo ">> useradd is a low-level BINARY (shadow-utils)."
echo ">> adduser is a high-level PERL SCRIPT that WRAPS useradd (Debian/Ubuntu only)."
echo
echo "\$ dpkg -S \$(which useradd) \$(which adduser)"
dpkg -S "$(which useradd)" "$(which adduser)" 2>/dev/null

echo
echo "################################################################"
echo "#  A) useradd  — the low-level way (note what it does NOT do)  #"
echo "################################################################"
echo "\$ useradd testuser-low"
useradd testuser-low
echo
echo "--- /etc/passwd entry ---"
grep '^testuser-low:' /etc/passwd
echo
echo "--- was a home directory created? ---"
ls -ld /home/testuser-low 2>&1 || echo ">> NO home directory was created."
echo
echo "--- what shell did it get? ---"
getent passwd testuser-low | awk -F: '{print "login shell = " $7}'
echo ">> Empty/nologin: the user cannot get an interactive shell."
echo
echo "--- password status (passwd -S) ---"
passwd -S testuser-low
echo ">> 'L' = account is LOCKED, no password was set."
echo
echo "--- groups ---"
id testuser-low

echo
echo "################################################################"
echo "#  B) adduser — the recommended way on Debian/Ubuntu            #"
echo "################################################################"
echo "\$ adduser --gecos '' --disabled-password testuser"
echo "   (--gecos '' and --disabled-password only so this runs non-interactively;"
echo "    normally adduser PROMPTS for the password and the GECOS fields.)"
adduser --gecos "" --disabled-password testuser
echo
echo "--- /etc/passwd entry ---"
grep '^testuser:' /etc/passwd
echo
echo "--- home directory created automatically ---"
ls -ld /home/testuser
echo
echo "--- skeleton files copied from /etc/skel ---"
ls -a /home/testuser
echo "--- /etc/skel contains ---"
ls -a /etc/skel
echo
echo "--- login shell ---"
getent passwd testuser | awk -F: '{print "login shell = " $7}'
echo
echo "--- a matching personal GROUP was created ---"
id testuser
grep '^testuser:' /etc/group

echo
echo "--- now set a password interactively-equivalent ---"
echo "testuser:StrongPass123" | chpasswd
passwd -S testuser
echo ">> 'P' = usable password is now set."

echo
echo "############ SIDE-BY-SIDE ############"
printf '%-16s %-6s %-6s %-24s %s\n' USER UID GID HOME SHELL
for u in testuser-low testuser; do
  getent passwd "$u" | awk -F: '{printf "%-16s %-6s %-6s %-24s %s\n", $1,$3,$4,$6,$7}'
done

echo
echo "############ Cleanup demo (deluser / userdel) ############"
echo "\$ deluser --remove-home testuser-low"
deluser --remove-home testuser-low 2>&1 | tail -3
echo ">> 'testuser' is KEPT as the required test user for this homework."
echo
echo "--- final proof the required test user exists ---"
id testuser
