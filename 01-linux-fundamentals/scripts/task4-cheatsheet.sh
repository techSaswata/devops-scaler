#!/usr/bin/env bash
# Task 4: Linux command cheat sheet — every command actually executed
set -u
hr(){ echo; echo "==================== $* ===================="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-12}; }

mkdir -p /tmp/cheat && cd /tmp/cheat
printf 'apple 5\nbanana 3\ncherry 9\napple 2\ndate 7\n' > fruits.txt
printf 'root:x:0:0\ndaemon:x:1:1\nsaswata:x:1000:1000\n' > users.txt

hr "1. NAVIGATION & ORIENTATION"
run pwd
run "ls -la | head -8"
run "ls -lh /etc/hostname"
run "cd /etc && pwd && cd /tmp/cheat && pwd"
run whoami
run id
run hostname
run "uname -a"
run "uptime"
run date

hr "2. FILE & DIRECTORY OPERATIONS"
run "mkdir -p demo/sub/deep && ls -R demo"
run "touch demo/a.txt demo/b.txt && ls demo"
run "cp fruits.txt demo/fruits-copy.txt && ls demo"
run "mv demo/b.txt demo/renamed.txt && ls demo"
run "rm demo/a.txt && ls demo"
run "rm -rf demo/sub && ls demo"
run "find /tmp/cheat -name '*.txt'"
run "tree -L 2 /tmp/cheat || find /tmp/cheat -maxdepth 2"

hr "3. VIEWING FILE CONTENT"
run "cat fruits.txt"
run "head -2 fruits.txt"
run "tail -2 fruits.txt"
run "wc -l fruits.txt"
run "wc fruits.txt"
run "nl fruits.txt"
echo
echo "\$ less fruits.txt   # pager: scroll with arrows, q to quit (interactive)"
echo "\$ more fruits.txt   # simpler pager"
echo ">> Not executed here because a pager needs an interactive terminal."

hr "4. SEARCHING — grep / find"
run "grep apple fruits.txt"
run "grep -n apple fruits.txt"
run "grep -c apple fruits.txt"
run "grep -i APPLE fruits.txt"
run "grep -v apple fruits.txt"
run "grep -E '^(apple|date)' fruits.txt"
run "find / -maxdepth 2 -name 'passwd' -type f"

hr "5. TEXT PROCESSING — awk / sed / sort / uniq / cut"
run "awk '{print \$1}' fruits.txt"
run "awk '{sum+=\$2} END {print \"total =\", sum}' fruits.txt"
run "awk -F: '{print \$1, \$3}' users.txt"
run "sed 's/apple/APPLE/g' fruits.txt"
run "sed -n '2,3p' fruits.txt"
run "sort fruits.txt"
run "sort -k2 -n fruits.txt"
run "sort fruits.txt | cut -d' ' -f1 | uniq"
run "sort fruits.txt | cut -d' ' -f1 | uniq -c"
run "cut -d: -f1,3 users.txt"
run "tr 'a-z' 'A-Z' < fruits.txt"

hr "6. PERMISSIONS & OWNERSHIP"
run "touch perm.sh && ls -l perm.sh"
run "chmod 755 perm.sh && ls -l perm.sh"
run "chmod u+x,g-w perm.sh && ls -l perm.sh"
run "chmod 600 perm.sh && ls -l perm.sh"
echo
echo ">> rwx = 4+2+1. 755 = rwxr-xr-x ; 644 = rw-r--r-- ; 600 = rw-------"
run "chown root:root perm.sh && ls -l perm.sh"
run "umask"

hr "7. PROCESS MANAGEMENT"
run "ps aux | head -6"
run "ps -ef | head -6"

# run directly (not via the piped helper) so the background job stays in THIS shell
echo
echo "\$ sleep 300 &"
sleep 300 &
SLEEP_PID=$!
echo "started background job with PID $SLEEP_PID"
echo
echo "\$ jobs"
jobs
echo
echo "\$ pgrep -a sleep"
pgrep -a sleep
echo
echo "\$ ps -p $SLEEP_PID -o pid,ppid,stat,cmd"
ps -p $SLEEP_PID -o pid,ppid,stat,cmd
echo
echo "\$ kill $SLEEP_PID      # send SIGTERM"
kill $SLEEP_PID
sleep 1
echo "\$ ps -p $SLEEP_PID -o pid,cmd   # gone"
ps -p $SLEEP_PID -o pid,cmd 2>&1 || echo "process $SLEEP_PID no longer exists"
echo
echo "--- now demonstrate SIGKILL on a process that ignores TERM ---"
echo "\$ sleep 300 & ; kill -9 <pid>"
sleep 300 &
K=$!
kill -9 $K
sleep 1
pgrep -a sleep || echo "no sleep processes remain"

run "ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -6"
echo
echo ">> kill <pid> = TERM (polite) ; kill -9 <pid> = KILL (forced)"
echo ">> top / htop = live process view (interactive, not run here)"

hr "8. DISK & MEMORY"
run "df -h"
run "du -sh /tmp/cheat"
run "du -h --max-depth=1 /tmp"
run "free -h"
run "cat /proc/meminfo | head -4"
run "nproc"

hr "9. ARCHIVES & COMPRESSION"
run "tar -czf fruits.tar.gz fruits.txt users.txt && ls -lh fruits.tar.gz"
run "tar -tzf fruits.tar.gz"
run "mkdir -p extract && tar -xzf fruits.tar.gz -C extract && ls extract"
run "gzip -k fruits.txt && ls -l fruits.txt.gz"
run "gunzip fruits.txt.gz && ls fruits.txt"

hr "10. I/O REDIRECTION & PIPES"
run "echo 'written with >' > out.txt && cat out.txt"
run "echo 'appended with >>' >> out.txt && cat out.txt"
run "ls /nonexistent 2> err.txt ; cat err.txt"
run "ls /nonexistent > all.txt 2>&1 ; cat all.txt"
run "cat fruits.txt | grep apple | wc -l"
run "echo 'to both' | tee tee.txt"

hr "11. ENVIRONMENT & VARIABLES"
run "echo \$HOME"
run "echo \$PATH"
run "export MYVAR='devops' && echo \$MYVAR"
run "env | head -6"
run "which ls grep"
run "type cd"

hr "12. USERS, GROUPS & SUDO"
run "getent passwd root"
run "cat /etc/passwd | tail -3"
run "groups root"
run "cat /etc/group | head -4"
echo
echo ">> sudo <cmd> runs one command as root ; su - <user> switches user"

hr "13. NETWORK (basics — full detail in 03-networking)"
run "hostname -I || hostname -i"
run "ip -brief addr"
run "cat /etc/hosts"

hr "14. PACKAGE MANAGEMENT (Debian/Ubuntu)"
run "apt-cache policy nginx | head -4"
run "dpkg -l | head -6"
echo
echo ">> apt update / apt install <pkg> / apt remove <pkg> / apt list --installed"
echo ">> RHEL family uses yum or dnf instead of apt"

hr "15. HELP"
run "man ls | head -5"
run "ls --help | head -5"
run "whatis grep"

echo
echo "==================== CHEAT SHEET COMPLETE ===================="
