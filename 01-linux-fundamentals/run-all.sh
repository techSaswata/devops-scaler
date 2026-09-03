#!/usr/bin/env bash
# Reproduces every Linux Fundamentals task and regenerates outputs/.
# Requires: Docker. Run from this directory.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p outputs

echo "==> Task 1: soft vs hard links (ubuntu:22.04)"
docker run --rm -v "$PWD/scripts":/scripts:ro ubuntu:22.04 \
  bash /scripts/task1-links.sh > outputs/task1-links.txt 2>&1

echo "==> Task 2: adduser vs useradd (ubuntu:22.04)"
docker run --rm -v "$PWD/scripts":/scripts:ro ubuntu:22.04 bash -c \
  "apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq adduser passwd file >/dev/null 2>&1; \
   bash /scripts/task2-users.sh" > outputs/task2-users.txt 2>&1

echo "==> Task 3: journalctl (custom systemd image)"
docker build -q -t linux-lab-systemd -f lab/Dockerfile.systemd lab/ >/dev/null
docker rm -f lnx-journal >/dev/null 2>&1 || true
docker run -d --name lnx-journal --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw linux-lab-systemd >/dev/null
for _ in $(seq 1 30); do
  s=$(docker exec lnx-journal systemctl is-system-running 2>/dev/null || true)
  [[ "$s" == running || "$s" == degraded ]] && break
  sleep 2
done
docker cp scripts/task3-journalctl.sh lnx-journal:/task3.sh
docker exec lnx-journal bash /task3.sh > outputs/task3-journalctl.txt 2>&1
docker rm -f lnx-journal >/dev/null

echo "==> Task 4: command cheat sheet (ubuntu:22.04)"
docker run --rm -v "$PWD/scripts":/scripts:ro ubuntu:22.04 bash -c \
  "apt-get update -qq >/dev/null 2>&1; \
   apt-get install -y -qq procps iproute2 man-db tree file >/dev/null 2>&1; \
   yes | unminimize >/dev/null 2>&1; \
   bash /scripts/task4-cheatsheet.sh" > outputs/task4-cheatsheet.txt 2>&1

echo
echo "Done. Outputs:"
wc -l outputs/*.txt
