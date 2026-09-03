#!/usr/bin/env python3
"""Slice a captured output log into chunks at marker lines, for per-topic screenshots."""
import re, sys, os
src, outdir, pattern = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(outdir, exist_ok=True)
lines = open(src, encoding="utf-8", errors="replace").read().split("\n")
rx = re.compile(pattern)
idx = [i for i, l in enumerate(lines) if rx.search(l)]
if not idx: sys.exit("no markers matched")
if idx[0] != 0: idx.insert(0, 0)
idx.append(len(lines))
names = []
for n in range(len(idx) - 1):
    chunk = lines[idx[n]:idx[n + 1]]
    while chunk and not chunk[-1].strip(): chunk.pop()
    if not chunk: continue
    title = rx.sub(lambda m: m.group(0), chunk[0]).strip().strip("#= ").strip()
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:48] or f"part{n}"
    path = os.path.join(outdir, f"{n:02d}-{slug}.txt")
    open(path, "w").write("\n".join(chunk))
    names.append((path, title))
for p, t in names: print(f"{p}\t{t}")
