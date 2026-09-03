# DevOps Homework — Complete Submission

**Saswata Das · 24BCS10248**

Every task from the DevOps homework, worked end to end. Nothing here is transcribed from
documentation — **every command was actually executed and its real output captured**, then
embedded as a screenshot alongside an explanation of what it shows and why it matters.

| | |
|---|---|
| Sections | 7 |
| Screenshots | **113** |
| Captured output | 3,250+ lines across 19 raw logs |
| Scripts | 19 (every result is reproducible) |
| Dockerfiles | 11 |
| Applications built & run | 8 (Node, Python, Java, Apache, React, Nginx, Go, MySQL) |

---

## Contents

| # | Section | Tasks covered |
|---|---|---|
| **01** | [Linux Fundamentals](01-linux-fundamentals/) | soft vs hard links · `adduser` vs `useradd` · `journalctl` · command cheat sheet |
| **02** | [Shell Scripting](02-shell-scripting/) | `sysinfo.sh` — date, hostname, user, `df`, `ps`, variables, `read -p`, `mkdir`, `touch`, `>` |
| **03** | [Networking](03-networking/) | interfaces · routing · ARP · DNS · ping · traceroute · `ss` · `nc` · `curl` · `tcpdump` · `nmap` |
| **04** | [Git / GitHub](04-git-github/) | `git commit -a -m` vs `git commit -m` · cherry-pick |
| **05** | [Docker Fundamentals](05-docker-fundamentals/) | 6 Hello World apps, each containerized and verified in a browser |
| **06** | [Dockerfiles & Images](06-dockerfiles-and-images/) | multi-stage build on port 8080 · 3-runtime deployment |
| **07** | [Docker Network & Volumes](07-docker-network-volumes/) | 3 networks · host network · bind mount · overlay network |

---

## Highlights

A few results worth looking at first:

**A real service failure diagnosed from the journal** — [01](01-linux-fundamentals/#task-3--journalctl).
I broke an nginx config on purpose inside a systemd-enabled container, and the journal
produced the actual root cause that `systemctl` refused to give:

```
nginx[108]: nginx: [emerg] unexpected end of file, expecting ";" or "}" in /etc/nginx/conf.d/broken.conf:2
systemd[1]: nginx.service: Failed with result 'exit-code'.
```

**A 46× smaller image, measured not asserted** — [06](06-dockerfiles-and-images/).
The same Go application built two ways: **440 MB** single-stage vs **6.53 MB** multi-stage
on `scratch`. The final image is one layer containing only the static binary — with no
shell an attacker could use.

**Network segmentation proved at the DNS layer** — [07](07-docker-network-volumes/#task-1--docker-container-networking).
`frontend` → `database` doesn't time out; the name doesn't even resolve, because Docker's
embedded DNS only answers for containers sharing a network.

**An overlay network actually running** — [07](07-docker-network-volumes/#task-4--overlay-networks).
Rather than only researching overlays, I initialised a swarm and ran one: VIP service
discovery, `tasks.<service>` round-robin, load balancing and the routing mesh.

**A live bind mount, proved by timestamp** — [07](07-docker-network-volumes/#task-3--bind-mount).
Edited on the host, reflected instantly, with identical `StartedAt` before and after to
show the container never restarted.

---

## How everything was produced

The host is macOS, but most of this homework is about Linux. Rather than substitute
approximations, **every Linux-specific command was run in a genuine Linux environment**:

| Need | How it was met |
|---|---|
| `useradd`, `adduser`, inode/`ln` semantics | `ubuntu:22.04` containers |
| `journalctl` with a real journal | a purpose-built **systemd + journald** image — a plain container has no PID 1 systemd, so there would be no journal to query |
| GNU networking tools (`ip`, `ss`, `dig`, `tcpdump`, `nmap`) | a custom `net-lab` image |
| A real gateway, ARP cache and internet traceroute | the macOS host, where those are genuine |
| Overlay networking | a real single-node **Docker Swarm** |

Two small tools support the evidence gathering:

- [`tools/ptyrun.py`](tools/ptyrun.py) — runs a command in a **real pseudo-terminal**.
  Needed because `read -p` only renders its prompt when stdin is a TTY; piping input would
  have hidden the prompts and made the shell-scripting transcript useless as proof.
- [`tools/termshot.py`](tools/termshot.py) — renders captured output into a terminal-window
  PNG. The text is never invented; it is piped from the `.txt` logs in each `outputs/` folder,
  which are committed so any screenshot can be checked against its source.
- [`tools/webshot.sh`](tools/webshot.sh) — **real headless-Chrome screenshots** of the
  running applications at their live `localhost` URLs.

### Reproducing it

Every section has a script. With Docker running:

```bash
./01-linux-fundamentals/run-all.sh
./02-shell-scripting/sysinfo.sh
./03-networking/scripts/netcommands.sh        # or via the net-lab image
./04-git-github/scripts/task1-commit-a.sh
./04-git-github/scripts/task2-cherry-pick.sh
./05-docker-fundamentals/build-and-run.sh && ./05-docker-fundamentals/verify.sh
./06-dockerfiles-and-images/run-multistage.sh
./07-docker-network-volumes/scripts/task1-networking.sh
```

### Cleaning up

The demo containers are left running after each section so the applications can be opened
in a browser. When you're done:

```bash
./cleanup.sh
```

### Ports used

| Port | What |
|---|---|
| 3001–3006 | the six Hello World apps (Node, Python, Java, Apache, React, Nginx) |
| 4001–4003 | the Compose deployment (Node, Python, Java) |
| 8080 | **the multi-stage build app** |
| 8081, 8083, 8085 | networking / bind-mount / swarm demos |

---

## Things that went wrong, and were fixed

Documented rather than hidden, because the debugging is where the learning is:

| Problem | Cause | Fix |
|---|---|---|
| Apache container reported **`unhealthy`** while serving fine | its `HEALTHCHECK` called `curl`, and the `httpd` image ships neither `curl` nor `wget` | used bash's `/dev/tcp` built-in — no extra package |
| `sysinfo.sh` reported **0 processes** on macOS | `ps -e --no-headers \| wc -l \|\| fallback` tests **`wc`'s** exit status, which always succeeds | test `ps` itself before choosing the branch |
| "no shell in the image" proof **hung** instead of failing | with `ENTRYPOINT`, the trailing `/bin/sh` became an *argument* to the server, not a replacement | use `--entrypoint` to override |
| MySQL query failed with `caching_sha2_password could not be loaded` | Alpine's `mysql` is really **MariaDB's** client | started MySQL with `mysql_native_password` (and `--skip-ssl` for its self-signed cert) |
| Bind-mounted page served **truncated** | a live mount has no copy step, so the request caught the file mid-write | let the write settle before requesting |
| Compose verification reported **HTTP 000** for Python | curl arrived before Flask finished binding | poll until ready instead of assuming |

Two claims were also corrected after checking them against the captured output rather than
assuming: the container MTU is **65535** (a virtual `veth`, not the 1500 of physical
Ethernet), and image size has **two legitimate measures** — unpacked on disk vs compressed
content — which differ under Docker Desktop's containerd store.

---

## A note on privacy

The networking section captured the **MAC addresses of other people's devices** from the
ARP cache of a shared network, along with this machine's public IP and the ISP router's
hostname. Since this repository is public, those are redacted by
[`03-networking/scripts/redact.py`](03-networking/scripts/redact.py). Every command's output
structure is preserved, so nothing is lost pedagogically.

**Publishing your ARP cache verbatim leaks your neighbours' device identifiers** — worth
knowing before pushing a networking assignment to GitHub.

---

## Repository layout

```
devops-scaler/
├── README.md                     <- this file
├── docs/DevOps Homework.pdf      <- the original assignment
├── tools/                        <- ptyrun.py, termshot.py, webshot.sh, slice.py
├── 01-linux-fundamentals/
├── 02-shell-scripting/
├── 03-networking/
├── 04-git-github/
├── 05-docker-fundamentals/
├── 06-dockerfiles-and-images/
└── 07-docker-network-volumes/

Each section contains:
  README.md      the write-up, with screenshots and explanations
  scripts/       the scripts that produced every result
  outputs/       the raw captured .txt logs
  screenshots/   the PNGs embedded in the README
```
