#!/usr/bin/env bash
# Task 3: journalctl — reading the systemd journal
set -u
echo "############ 0. What is journalctl reading? ############"
echo "\$ systemctl is-active systemd-journald"
systemctl is-active systemd-journald
echo ">> systemd-journald is the logging daemon. It collects messages from the kernel,"
echo ">> from initrd, from service stdout/stderr and from syslog, and stores them in a"
echo ">> BINARY, INDEXED journal. 'journalctl' is the query tool for that journal."
echo
echo "\$ ls /var/log/journal/*"
ls /var/log/journal/* 2>/dev/null | head -5
echo
echo "\$ journalctl --disk-usage"
journalctl --disk-usage

echo
echo "############ 1. View ALL logs (oldest first) ############"
echo "\$ journalctl --no-pager | head -15"
journalctl --no-pager 2>/dev/null | head -15

echo
echo "############ 2. Most recent N lines ############"
echo "\$ journalctl -n 10 --no-pager"
journalctl -n 10 --no-pager

echo
echo "############ 3. Kernel messages only (like dmesg) ############"
echo "\$ journalctl -k --no-pager | head -8"
journalctl -k --no-pager 2>/dev/null | head -8 || echo "(kernel ring buffer not exposed to this container)"

echo
echo "############ 4. LOGS FOR A SPECIFIC SERVICE  <-- the required task ############"
echo "\$ systemctl status nginx --no-pager"
systemctl status nginx --no-pager 2>&1 | head -12
echo
echo "\$ journalctl -u nginx --no-pager"
journalctl -u nginx --no-pager

echo
echo "--- restart the service, then re-read ITS logs ---"
echo "\$ systemctl restart nginx"
systemctl restart nginx
sleep 1
echo "\$ journalctl -u nginx -n 20 --no-pager"
journalctl -u nginx -n 20 --no-pager

echo
echo "############ 5. Filter by PRIORITY (severity) ############"
echo "priorities: 0 emerg  1 alert  2 crit  3 err  4 warning  5 notice  6 info  7 debug"
echo "\$ journalctl -p err --no-pager -n 10"
journalctl -p err --no-pager -n 10

echo
echo "############ 6. Filter by TIME ############"
echo "\$ journalctl --since \"10 minutes ago\" --no-pager -n 5"
journalctl --since "10 minutes ago" --no-pager -n 5
echo
echo "\$ journalctl --since today -u nginx --no-pager -n 5"
journalctl --since today -u nginx --no-pager -n 5

echo
echo "############ 7. Provoke a REAL failure and read the error from the journal ############"
echo "--- break the nginx config on purpose ---"
echo "this is not valid nginx config" > /etc/nginx/conf.d/broken.conf
echo "\$ systemctl restart nginx   (this will fail)"
systemctl restart nginx 2>&1 || true
sleep 1
echo
echo "\$ systemctl is-failed nginx"
systemctl is-failed nginx 2>&1 || true
echo
echo "\$ journalctl -u nginx -n 15 --no-pager   <-- the journal shows WHY it failed"
journalctl -u nginx -n 15 --no-pager
echo
echo "--- fix it and confirm recovery is also logged ---"
rm -f /etc/nginx/conf.d/broken.conf
systemctl restart nginx && echo "nginx restarted OK"
sleep 1
journalctl -u nginx -n 6 --no-pager

echo
echo "############ 8. Useful output formats ############"
echo "\$ journalctl -u nginx -n 1 -o json-pretty --no-pager"
journalctl -u nginx -n 1 -o json-pretty --no-pager 2>/dev/null | head -22
echo
echo "\$ journalctl -u nginx -n 3 -o short-iso --no-pager"
journalctl -u nginx -n 3 -o short-iso --no-pager

echo
echo "############ 9. Boot-scoped + maintenance ############"
echo "\$ journalctl --list-boots --no-pager"
journalctl --list-boots --no-pager 2>&1 | head -5
echo
echo "\$ journalctl -b -n 5 --no-pager   # current boot only"
journalctl -b -n 5 --no-pager
echo
echo "\$ journalctl --vacuum-time=2d      # retention / cleanup"
journalctl --vacuum-time=2d 2>&1 | tail -3
echo
echo ">> NOTE: 'journalctl -f' follows logs live (like tail -f) — not run here"
echo ">> because it never exits. 'journalctl -u nginx -f' is the everyday debug command."
