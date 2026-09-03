#!/usr/bin/env python3
"""
ptyrun.py — run a command in a REAL pseudo-terminal and type answers into it.

Needed because `read -p` only renders its prompt when stdin is a TTY. Piping
input suppresses the prompts, which would make the transcript useless as proof
that the script is genuinely interactive. This drives an actual PTY, so the
prompts appear and the typed answers are echoed, exactly as a human would see.

usage: ptyrun.py <out.txt> <answer1> <answer2> ... -- <command...>
"""
import os, pty, select, sys, time

if "--" not in sys.argv:
    sys.exit("usage: ptyrun.py out.txt ans... -- cmd...")
split = sys.argv.index("--")
out_path = sys.argv[1]
answers = sys.argv[2:split]
cmd = sys.argv[split + 1:]

pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm"
    os.environ["COLUMNS"] = "110"
    os.environ["LINES"] = "50"
    os.execvp(cmd[0], cmd)

buf = b""
queue = list(answers)
last_len = -1
idle = 0.0
deadline = time.time() + 300

while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.3)
    if r:
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
        idle = 0.0
    else:
        idle += 0.3

    # When output has gone quiet and the tail looks like a waiting prompt, type.
    if queue and idle >= 0.6:
        tail = buf.decode("utf-8", "replace").rstrip("\r\n")
        tail = tail.split("\n")[-1] if tail else ""
        if tail.rstrip().endswith((":", ">", "?")) or len(buf) != last_len:
            if tail.rstrip().endswith((":", ">", "?")):
                time.sleep(0.15)
                os.write(fd, (queue.pop(0) + "\n").encode())
                idle = 0.0
        last_len = len(buf)

    if not queue and idle > 3.0:
        break

try:
    os.close(fd)
except OSError:
    pass
try:
    _, status = os.waitpid(pid, 0)
except ChildProcessError:
    status = 0

text = buf.decode("utf-8", "replace").replace("\r\n", "\n").replace("\r", "\n")
with open(out_path, "w", encoding="utf-8") as f:
    f.write(text)
print(f"captured {len(text.splitlines())} lines -> {out_path} (exit {status >> 8})")
