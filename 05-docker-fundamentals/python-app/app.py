"""Hello World web application in Python using Flask."""
import os
import platform
import socket
import sys

from flask import Flask, jsonify

app = Flask(__name__)
PORT = int(os.environ.get("PORT", 5000))

STYLE = """
:root{--bg:#0f1117;--card:#171a23;--line:#252a38;--fg:#e6e9f0;--muted:#8b93a7;--accent:#ffd43b}
*{margin:0;padding:0;box-sizing:border-box}
body{background:var(--bg);color:var(--fg);min-height:100vh;display:grid;place-items:center;
  font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;padding:24px}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:44px 52px;
  max-width:560px;width:100%;box-shadow:0 24px 60px rgba(0,0,0,.5)}
.badge{display:inline-flex;align-items:center;gap:8px;font-size:12px;font-weight:600;
  letter-spacing:.08em;text-transform:uppercase;color:var(--accent);
  background:rgba(255,212,59,.14);border:1px solid rgba(255,212,59,.3);
  padding:6px 12px;border-radius:999px;margin-bottom:22px}
h1{font-size:44px;line-height:1.1;letter-spacing:-.02em;margin-bottom:10px}
h1 span{color:var(--accent)}
.sub{color:var(--muted);font-size:15px;margin-bottom:28px}
dl{display:grid;grid-template-columns:auto 1fr;gap:10px 18px;font-size:14px;
  border-top:1px solid var(--line);padding-top:22px}
dt{color:var(--muted)}
dd{font-family:ui-monospace,'SF Mono',Menlo,monospace}
.foot{margin-top:24px;padding-top:18px;border-top:1px solid var(--line);color:var(--muted);font-size:13px}
"""


@app.route("/")
def hello():
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Hello World — Python</title>
  <style>{STYLE}</style>
</head>
<body>
  <div class="card">
    <div class="badge">● Python / Flask</div>
    <h1>Hello <span>World</span></h1>
    <p class="sub">Served by a Flask application running inside a Docker container.</p>
    <dl>
      <dt>Runtime</dt><dd>Python {platform.python_version()}</dd>
      <dt>Framework</dt><dd>Flask</dd>
      <dt>Platform</dt><dd>{platform.system()} / {platform.machine()}</dd>
      <dt>Container</dt><dd>{socket.gethostname()}</dd>
      <dt>Port</dt><dd>{PORT}</dd>
    </dl>
    <p class="foot">Saswata Das &middot; 24BCS10248 &middot; DevOps Homework</p>
  </div>
</body>
</html>"""


@app.route("/health")
def health():
    return jsonify(status="ok", app="python-app")


if __name__ == "__main__":
    print(f"python-app listening on http://0.0.0.0:{PORT}", file=sys.stderr)
    app.run(host="0.0.0.0", port=PORT)
