#!/usr/bin/env python3
"""
termshot.py — render REAL captured command output into a terminal-window PNG.

The text is never invented: it is piped in from an actual command run
(see the scripts/ + outputs/ folders). This just gives it a terminal skin
so it can be embedded as a screenshot in the README.

usage: termshot.py <input.txt> <output.png> [--title "..."] [--cols 100] [--max-lines N]
"""
import html
import os
import subprocess
import sys
import tempfile

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# One Dark-ish palette
CSS = """
*{margin:0;padding:0;box-sizing:border-box}
body{background:#1a1b26;padding:22px;font-family:'SF Mono',Menlo,monospace}
.win{background:#16161e;border-radius:10px;overflow:hidden;
     box-shadow:0 18px 50px rgba(0,0,0,.55);border:1px solid #2a2b3d}
.bar{background:#1f2030;padding:9px 14px;display:flex;align-items:center;gap:8px;
     border-bottom:1px solid #2a2b3d}
.dot{width:11px;height:11px;border-radius:50%%}
.r{background:#ff5f57}.y{background:#febc2e}.g{background:#28c840}
.title{color:#9aa0b5;font-size:12.5px;margin-left:10px;font-weight:500;
       letter-spacing:.02em}
pre{padding:16px 18px;color:#c8d0e0;font-size:%(fs)spx;line-height:1.5;
    white-space:pre;overflow:visible;font-family:'SF Mono',Menlo,monospace}
.p{color:#7dcfff;font-weight:600}
.h{color:#bb9af7;font-weight:600}
.a{color:#9ece6a}
.e{color:#f7768e}
.c{color:#565f89}
"""

def colorize(line: str) -> str:
    e = html.escape(line)
    s = line.lstrip()
    if s.startswith("$ "):
        i = e.index("$ ")
        return e[:i] + '<span class="p">' + e[i:] + "</span>"
    if s.startswith("#####") or s.startswith("=====") or s.startswith("#  ") or s.startswith("###"):
        return '<span class="h">' + e + "</span>"
    if s.startswith(">>"):
        return '<span class="a">' + e + "</span>"
    if s.startswith("---"):
        return '<span class="c">' + e + "</span>"
    low = s.lower()
    if low.startswith(("error", "cat:", "ls:", "ln:", "bash:")) or "no such file" in low \
       or "not permitted" in low or "not allowed" in low:
        return '<span class="e">' + e + "</span>"
    return e

def main():
    src, dst = sys.argv[1], sys.argv[2]
    args = sys.argv[3:]
    title = "Terminal"
    fs, max_lines = 12.5, 4000
    for i, a in enumerate(args):
        if a == "--title": title = args[i + 1]
        if a == "--font": fs = float(args[i + 1])
        if a == "--max-lines": max_lines = int(args[i + 1])

    with open(src, encoding="utf-8", errors="replace") as f:
        lines = f.read().rstrip("\n").split("\n")
    truncated = False
    if len(lines) > max_lines:
        lines = lines[:max_lines]; truncated = True

    width = max((len(l) for l in lines), default=80)
    body = "\n".join(colorize(l) for l in lines)
    if truncated:
        body += '\n<span class="c">... (output truncated — see the .txt file for the full log)</span>'

    doc = ("<html><head><meta charset='utf-8'><style>" + (CSS % {"fs": fs}) +
           "</style></head><body><div class='win'><div class='bar'>"
           "<span class='dot r'></span><span class='dot y'></span><span class='dot g'></span>"
           "<span class='title'>" + html.escape(title) + "</span></div><pre>" +
           body + "</pre></div></body></html>")

    tmp = tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8")
    tmp.write(doc); tmp.close()

    px_w = int(width * fs * 0.605) + 90
    px_w = max(760, min(px_w, 1900))
    px_h = int(len(lines) * fs * 1.5) + 110

    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    subprocess.run([CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=2", "--default-background-color=00000000",
                    f"--screenshot={os.path.abspath(dst)}",
                    f"--window-size={px_w},{px_h}",
                    "file://" + tmp.name],
                   check=True, capture_output=True)
    os.unlink(tmp.name)
    print(f"  shot: {dst}  ({px_w}x{px_h} @2x, {len(lines)} lines)")

if __name__ == "__main__":
    main()
