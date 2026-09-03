# DevOps Homework — Submission

| | |
|---|---|
| **Student** | Saswata Das |
| **Enrollment number** | 24BCS10248 |
| **Repository** | https://github.com/techSaswata/devops-scaler |
| **Modules submitted** | 7 of 7 |
| **Status** | Complete |

---

## 1. Overview

This repository contains the complete submission for all seven modules of the DevOps
homework: Linux Fundamentals, Shell Scripting, Networking Fundamentals, Git/GitHub, Docker
Fundamentals, Dockerfiles & Images, and Docker Networking.

Every command documented here was executed, and its output captured to a log file before
being rendered as a screenshot. No output has been transcribed from documentation or
reproduced from memory. Each screenshot can be checked against its source log in the
corresponding `outputs/` directory, and every result can be regenerated using the scripts
in the corresponding `scripts/` directory.

### Submission metrics

| Artefact | Count |
|---|---|
| Modules | 7 |
| Screenshots | 113 |
| Captured output logs | 19 files, 3,250+ lines |
| Executable scripts | 20 |
| Dockerfiles | 11 |
| Applications built and verified | 8 |

---

## 2. Assignment coverage

Each requirement of the assignment is mapped below to the deliverable that satisfies it.

### 2.1 Linux Fundamentals → [`01-linux-fundamentals/`](01-linux-fundamentals/)

| # | Requirement | Deliverable | Status |
|---|---|---|---|
| 1 | Learn the difference between soft and hard links | Comparison table, inode-level explanation | ✔ |
| 1 | Learn the commands to create both | `ln` / `ln -s`, with `ls -li`, `stat`, `readlink` | ✔ |
| 1 | Practice creating and deleting them | [`scripts/task1-links.sh`](01-linux-fundamentals/scripts/task1-links.sh) — 8-step demonstration | ✔ |
| 1 | Prepare as an interview question | Four model answers included | ✔ |
| 2 | Difference between `adduser` and `useradd` | Demonstrated side by side, with `file`/`dpkg -S` proof of the wrapper relationship | ✔ |
| 2 | Which is preferred on Ubuntu and why | Documented for both interactive and scripted use | ✔ |
| 2 | Create a test user with the recommended command | `adduser testuser`, verified with `id` and `passwd -S` | ✔ |
| 3 | Learn what `journalctl` is used for | Documented with the journald architecture | ✔ |
| 3 | View system and service logs | 20+ `journalctl` invocations executed | ✔ |
| 3 | Check logs for a specific service | `journalctl -u nginx`, including a diagnosed service failure | ✔ |
| 4 | Review and practise the command cheat sheet | 15 categories, ~90 commands executed | ✔ |

### 2.2 Shell Scripting → [`02-shell-scripting/`](02-shell-scripting/)

Deliverable: [`sysinfo.sh`](02-shell-scripting/sysinfo.sh)

| # | Requirement | Implementation | Status |
|---|---|---|---|
| 1 | Print the current date | `CURRENT_DATE=$(date)` | ✔ |
| 2 | Print the hostname | `HOST_NAME=$(hostname)` | ✔ |
| 3 | Print the username | `USER_NAME=$(whoami)` | ✔ |
| 4 | Print the disk usage | `df -h` | ✔ |
| 5 | Print the running processes | `ps -ef` | ✔ |
| 6 | Use variables to store and use data | 8 variables used throughout | ✔ |
| 7 | Take user input using `read -p` | 3 prompts | ✔ |
| 8 | Create a directory using `mkdir` | `mkdir -p "$DIR_NAME"` | ✔ |
| 9 | Create a file using `touch` | `touch "$REPORT_FILE"` | ✔ |
| 10 | Store running processes in the file using `>` | `ps -ef > "$PROC_ONLY_FILE"` | ✔ |
| — | Public GitHub repository | This repository | ✔ |
| — | README with all command outputs | [Module README](02-shell-scripting/README.md) | ✔ |

### 2.3 Networking Fundamentals → [`03-networking/`](03-networking/)

| # | Requirement | Deliverable | Status |
|---|---|---|---|
| 1 | Practise networking commands | 40+ commands across 14 categories, executed in two environments | ✔ |
| 2 | Create a Markdown file | [Module README](03-networking/README.md) | ✔ |
| 2 | Execute the commands and add the output/screenshots | 22 screenshots, 642 lines of captured output | ✔ |
| 2 | Add a short explanation of each command | "What I understood" note for every command group | ✔ |

Commands covered: `ip addr`, `ifconfig`, `ip link`, `ip route`, `netstat -rn`, `route`,
`ip neigh`, `arp`, `dig`, `nslookup`, `host`, `getent`, `ping`, `traceroute`, `ss`,
`netstat`, `lsof`, `nc`, `curl`, `wget`, `tcpdump`, `nmap`, `whois`, `ip -s link`.

### 2.4 Git / GitHub → [`04-git-github/`](04-git-github/)

| # | Requirement | Deliverable | Status |
|---|---|---|---|
| 1 | Practise `git commit -a -m` | [`scripts/task1-commit-a.sh`](04-git-github/scripts/task1-commit-a.sh) | ✔ |
| 1 | Understand the difference from `git commit -m` | Three controlled experiments (modification, new file, deletion) | ✔ |
| 1 | Test both and observe the difference | Both executed; outcomes tabulated | ✔ |
| 2 | Create 2–4 commits on main | 3 commits (C1–C3) | ✔ |
| 2 | Use `git log` to view them | `--oneline`, `--graph --decorate`, `--stat` | ✔ |
| 2 | Create a new branch | `git checkout -b feature` | ✔ |
| 2 | Make 2–3 commits on the branch | 3 commits (F1–F3) | ✔ |
| 2 | Use `git log` to identify a specific commit | `git log --all -- .gitignore`, confirmed with `git show` | ✔ |
| 2 | Cherry-pick that commit into main | `git cherry-pick fb1c045` | ✔ |
| 2 | Verify the change is on main | Four independent checks | ✔ |
| — | Screenshots or .md showing commands and output | 14 screenshots | ✔ |

### 2.5 Docker Fundamentals → [`05-docker-fundamentals/`](05-docker-fundamentals/)

Required folder structure implemented exactly as specified.

| Folder | Application | Image | Host port | Hello World verified |
|---|---|---|---|---|
| [`nodejs-app/`](05-docker-fundamentals/nodejs-app/) | Node.js HTTP server | `hello-nodejs` | 3001 | ✔ browser + curl |
| [`python-app/`](05-docker-fundamentals/python-app/) | Python / Flask | `hello-python` | 3002 | ✔ browser + curl |
| [`java-app/`](05-docker-fundamentals/java-app/) | Java HTTP server | `hello-java` | 3003 | ✔ browser + curl |
| [`Apache-app/`](05-docker-fundamentals/Apache-app/) | Apache httpd 2.4 | `hello-apache` | 3004 | ✔ browser + curl |
| [`React-app/`](05-docker-fundamentals/React-app/) | React 18 + Vite | `hello-react` | 3005 | ✔ browser |
| [`nginx-app/`](05-docker-fundamentals/nginx-app/) | Nginx | `hello-nginx` | 3006 | ✔ browser + curl |

For each application: application code added, Dockerfile created, image built, container
run, and "Hello World" confirmed on the rendered web page. All six containers additionally
report `healthy` under `docker ps`.

### 2.6 Dockerfiles & Images → [`06-dockerfiles-and-images/`](06-dockerfiles-and-images/)

| # | Requirement | Deliverable | Status |
|---|---|---|---|
| 1 | Build the image using the multi-stage Dockerfile | [`multistage-app/Dockerfile`](06-dockerfiles-and-images/multistage-app/Dockerfile) | ✔ |
| 1 | Run a container from the image | `docker run -d -p 8080:8080` | ✔ |
| 1 | Access the application | HTTP 200 via curl and browser | ✔ |
| 1 | Verify it displays `Hello World from Docker multi-stage build` | Exact string confirmed | ✔ |
| 1 | Verify the running container using `docker ps` | Screenshot included | ✔ |
| 1 | Confirm the application runs on port 8080 | `docker port` output included | ✔ |
| 2 | Your name | Saswata Das | ✔ |
| 2 | Your enrollment number | 24BCS10248 | ✔ |
| 2 | Screenshot of the application running | Browser screenshot | ✔ |
| 2 | Screenshot of `docker ps` on port 8080 | Included | ✔ |
| 3 | Deploy at least 3 types of application | Node.js, Python and Java via Docker Compose | ✔ |

A single-stage Dockerfile for the identical application is included so the size reduction
is measured rather than asserted.

### 2.7 Docker Networking & Volumes → [`07-docker-network-volumes/`](07-docker-network-volumes/)

| # | Requirement | Deliverable | Status |
|---|---|---|---|
| 1 | Create frontend, backend and database containers | nginx, Alpine toolbox, MySQL 8.0 | ✔ |
| 1 | Use Nginx or Alpine for frontend and backend | nginx (frontend), Alpine (backend) | ✔ |
| 1 | Use the MySQL image for the database | `mysql:8.0` | ✔ |
| 1 | Create 3 different Docker networks | `frontend-net`, `backend-net`, `isolated-net` | ✔ |
| 1 | Add the backend container to 2 networks | `docker network connect`; two interfaces verified | ✔ |
| 1 | Check connectivity between the containers | Full matrix, including a live SQL query | ✔ |
| 2 | Pull the Apache2 image | `docker pull httpd:2.4` | ✔ |
| 2 | Create an Apache2 container using the host network | `docker run --network host httpd:2.4` | ✔ |
| 2 | Access the Apache website on port 80 | HTTP 200 on `localhost:80` (see §6.1) | ✔ |
| 3 | Create a folder and an `index.html` with "Hello students" | [`bind-mount-site/`](07-docker-network-volumes/bind-mount-site/) | ✔ |
| 3 | Bind mount the folder to an Nginx container | `-v "$PWD/bind-mount-site":/usr/share/nginx/html:ro` | ✔ |
| 3 | Access the site and verify the content | Browser screenshot | ✔ |
| 3 | Modify `index.html` | Edited on the host | ✔ |
| 3 | Verify changes without restarting the container | Identical `StartedAt` before and after | ✔ |
| 4 | Research overlay networks | Documented, plus a working swarm overlay demonstration | ✔ |
| 4 | Understand their use cases | Use cases and driver-selection guidance | ✔ |
| 4 | Understand how they work across multiple hosts | VXLAN encapsulation, control plane, required ports | ✔ |
| — | Screenshots added to the README | 17 screenshots | ✔ |

---

## 3. Test environment

| Component | Version |
|---|---|
| Host | macOS (Darwin 25.5.0, arm64) |
| Docker Engine | 28.5.1 (Docker Desktop) |
| Git | 2.49.0 |
| Node.js | 22.21.1 |
| Python | 3.14.5 |
| Java | OpenJDK 26.0.1 |

Because the host is macOS and the majority of the assignment concerns Linux, all
Linux-specific commands were executed inside genuine Linux environments rather than
substituting macOS equivalents:

| Requirement | Environment used | Rationale |
|---|---|---|
| `useradd`, `adduser`, inode and `ln` semantics | `ubuntu:22.04` | These commands do not exist on macOS |
| `journalctl` | Custom systemd + journald image ([`Dockerfile.systemd`](01-linux-fundamentals/lab/Dockerfile.systemd)) | A standard container has no PID 1 systemd, so no journal exists to query |
| GNU networking tools (`ip`, `ss`, `dig`, `tcpdump`, `nmap`) | Custom `net-lab` image ([`Dockerfile`](03-networking/lab/Dockerfile)) | macOS ships BSD variants with different flags |
| Default gateway, ARP cache, internet traceroute | macOS host | These are only meaningful on a machine attached to a real network |
| Overlay networking | Docker Swarm (single node) | Overlay networks require swarm mode |

---

## 4. Reproducing the results

All results can be regenerated. Docker must be running.

```bash
# Module 01 — Linux Fundamentals
./01-linux-fundamentals/run-all.sh

# Module 02 — Shell Scripting
./02-shell-scripting/sysinfo.sh

# Module 03 — Networking
docker build -t net-lab 03-networking/lab/
docker run --rm --cap-add=NET_ADMIN --cap-add=NET_RAW \
  -v "$PWD/03-networking/scripts":/scripts:ro net-lab bash /scripts/netcommands.sh

# Module 04 — Git
./04-git-github/scripts/task1-commit-a.sh
./04-git-github/scripts/task2-cherry-pick.sh

# Module 05 — Docker Fundamentals
./05-docker-fundamentals/build-and-run.sh
./05-docker-fundamentals/verify.sh

# Module 06 — Multi-stage builds and deployment
./06-dockerfiles-and-images/run-multistage.sh
./06-dockerfiles-and-images/deployment/deploy.sh

# Module 07 — Docker Networking and Volumes
./07-docker-network-volumes/scripts/task1-networking.sh
./07-docker-network-volumes/scripts/task2-host-network.sh
./07-docker-network-volumes/scripts/task3-bind-mount.sh
./07-docker-network-volumes/scripts/task4-overlay.sh

# Tear down all demo containers, networks and images
./cleanup.sh
```

Demo containers are intentionally left running after each module so the applications can be
opened in a browser.

### Port allocation

| Port(s) | Purpose |
|---|---|
| 3001–3006 | Module 05 — the six Hello World applications |
| 4001–4003 | Module 06 — Compose deployment (Node.js, Python, Java) |
| **8080** | **Module 06 — the multi-stage build application** |
| 8081 | Module 07 — frontend container |
| 8083 | Module 07 — bind-mount demonstration |
| 8085 | Module 07 — swarm service (overlay network) |

---

## 5. Selected results

| Result | Module | Evidence |
|---|---|---|
| A service failure diagnosed from the journal — a deliberately invalid nginx configuration, with the root cause recovered from `journalctl -u nginx` where `systemctl` reported only a generic failure | 01 | [Task 3](01-linux-fundamentals/#task-3--journalctl) |
| Multi-stage build reduces the image from **440 MB to 6.53 MB** (one layer, containing only the static binary) | 06 | [Size comparison](06-dockerfiles-and-images/#2-size-comparison--the-whole-point) |
| Network segmentation enforced at the DNS layer — `frontend` cannot resolve `database`, because Docker's embedded DNS only answers for containers sharing a network | 07 | [Task 1](07-docker-network-volumes/#task-1--docker-container-networking) |
| A functioning overlay network with VIP service discovery, `tasks.<service>` round-robin resolution, load balancing and the routing mesh | 07 | [Task 4](07-docker-network-volumes/#task-4--overlay-networks) |
| Bind-mount live update confirmed by identical container `StartedAt` timestamps before and after the edit | 07 | [Task 3](07-docker-network-volumes/#task-3--bind-mount) |

---

## 6. Notes and limitations

### 6.1 Host networking on macOS

Docker Desktop runs containers inside a Linux virtual machine rather than directly on
macOS. `--network host` therefore places the container in the network namespace of that
Linux VM, not of macOS.

The requirement — Apache reachable on port 80 of the host network — is satisfied and
verified: the container reports the host's hostname (`docker-desktop`) and IP, has no
container IP of its own, and returns HTTP 200 at plain `localhost:80` when queried from
another host-network container. A bridge-network container correctly fails the same
request.

A request issued from macOS itself returns no connection, which is expected under this
architecture. On a native Linux Docker host the same command returns HTTP 200 directly.
Docker Desktop 4.34+ provides an opt-in host-networking feature that bridges this gap; it
was not enabled, as doing so requires restarting Docker Desktop. Full detail is in
[Module 07, Task 2](07-docker-network-volumes/#task-2--host-network).

### 6.2 Multi-stage source repository

The assignment refers to cloning a repository containing a multi-stage Dockerfile, but no
repository URL was supplied with it. The application and its multi-stage Dockerfile were
therefore written for this submission, producing the exact required output string on the
required port. A single-stage Dockerfile for the same application is included so the
comparison is quantified rather than described.

### 6.3 Redaction of network data

The networking module captured MAC addresses belonging to other devices on a shared
network, together with this machine's public IP address and the ISP router's reverse-DNS
hostname. As this repository is public, those values are masked by
[`03-networking/scripts/redact.py`](03-networking/scripts/redact.py). The structure of every
command's output is preserved.

### 6.4 Defects identified and resolved

Issues encountered during preparation, retained here as part of the engineering record:

| Issue | Root cause | Resolution |
|---|---|---|
| Apache container reported `unhealthy` while serving correctly | The `HEALTHCHECK` invoked `curl`, which the `httpd` image does not ship | Replaced with bash's `/dev/tcp` built-in, avoiding an added package |
| `sysinfo.sh` reported a process count of 0 on macOS | `ps -e --no-headers \| wc -l \|\| fallback` evaluates `wc`'s exit status, which always succeeds | Test `ps` directly before selecting the branch |
| Verification of "no shell in the image" hung instead of failing | With `ENTRYPOINT`, a trailing `/bin/sh` is passed as an argument rather than replacing the command | Used `--entrypoint` to override |
| MySQL query failed with `caching_sha2_password could not be loaded` | Alpine's `mysql` binary is the MariaDB client, which lacks that plugin | Started MySQL with `mysql_native_password`; added `--skip-ssl` for its self-signed certificate |
| Bind-mounted page served truncated content | A live bind mount has no copy step, so a request can read a file mid-write | Allowed the write to settle before requesting |
| Compose verification reported HTTP 000 for the Python service | The request preceded Flask completing its bind | Poll for readiness rather than assuming it |

Two documented claims were also corrected against the captured output: the container MTU
is 65535 (a virtual `veth` interface, not the 1500 of physical Ethernet), and image size
has two distinct measures — unpacked on disk versus compressed content — which differ under
Docker Desktop's containerd image store. Both measures are reported where relevant.

---

## 7. Repository structure

```
devops-scaler/
├── README.md                     This document
├── cleanup.sh                    Removes all demo containers, networks and images
├── tools/                        Evidence-capture utilities (see §8)
├── 01-linux-fundamentals/
├── 02-shell-scripting/
├── 03-networking/
├── 04-git-github/
├── 05-docker-fundamentals/
├── 06-dockerfiles-and-images/
└── 07-docker-network-volumes/
```

Each module directory follows the same layout:

| Path | Contents |
|---|---|
| `README.md` | The module write-up, with embedded screenshots and explanations |
| `scripts/` | The scripts that produced every documented result |
| `outputs/` | Raw captured `.txt` logs, committed so screenshots can be verified against source |
| `screenshots/` | The PNG files embedded in the module README |
| `lab/` | Supporting Dockerfiles, where a purpose-built environment was required |

---

## 8. Evidence-capture tooling

Three small utilities support the collection of verifiable evidence.

| Tool | Purpose |
|---|---|
| [`tools/ptyrun.py`](tools/ptyrun.py) | Executes a command in a real pseudo-terminal. Required because `read -p` renders its prompt only when stdin is a TTY; piping input would have suppressed the prompts and invalidated the Shell Scripting transcript as evidence. |
| [`tools/termshot.py`](tools/termshot.py) | Renders captured terminal output into a PNG. Input is read from the committed `.txt` logs, so every screenshot is traceable to its source. |
| [`tools/webshot.sh`](tools/webshot.sh) | Captures headless-Chrome screenshots of the running applications at their live `localhost` URLs. |
