#!/usr/bin/env bash
# Module 16 — every security control, run locally with the same tools the
# pipeline uses, so the behaviour can be inspected step by step.
export PATH="/opt/homebrew/bin:$PATH"
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }
D="$(cd "$(dirname "$0")/.." && pwd)"
PY=/tmp/cicdvenv/bin

hr "1. UNIT TESTS"
cd "$D/app"
run "$PY/python -m pytest tests/ -v --tb=short 2>&1 | tail -16"

hr "2. SAST — bandit (static analysis of our own code)"
run "$PY/bandit -r src/ -c ../security/bandit.yaml -f screen"
echo
echo "--- what SAST would catch if the code were insecure ---"
cat > /tmp/insecure_demo.py <<'PYEOF'
import hashlib, os, sqlite3, subprocess
def weak(p):            return hashlib.md5(p.encode()).hexdigest()   # B324 weak hash
def shell(cmd):         return subprocess.call(cmd, shell=True)      # B602 shell injection
def sqli(conn, uid):    return conn.execute("SELECT * FROM users WHERE id = %s" % uid)
PASSWORD = "SuperSecret123!"                                          # B105 hardcoded password
PYEOF
echo "\$ bandit /tmp/insecure_demo.py   (a deliberately insecure file)"
$PY/bandit /tmp/insecure_demo.py -f screen 2>&1 | grep -E "Issue:|Severity:|Location:" | head -16
echo
echo ">> Four classes of finding: weak hash, shell injection, SQL built by string"
echo ">> formatting, and a hard-coded password. Our real source has none of these,"
echo ">> which is why the scan above is clean."
rm -f /tmp/insecure_demo.py

hr "3. SCA — pip-audit (CVEs in our DEPENDENCIES)"
echo "--- BEFORE remediation: the pin this project originally used ---"
printf 'Flask==3.0.3\n' > /tmp/req-before.txt
echo "\$ pip-audit -r <Flask==3.0.3>"
$PY/pip-audit -r /tmp/req-before.txt 2>&1 | grep -E "Found|^flask|^Name|^-----" | cut -c1-110 | head -6
echo
echo ">> A REAL finding: PYSEC-2026-2151 in Flask 3.0.3, fixed in 3.1.3."
echo ">> Flask omits the 'Vary: Cookie' header on some session access patterns,"
echo ">> so a caching proxy can serve one user's page to another."
echo
echo "--- AFTER remediation: the pin now committed ---"
run "cat requirements.txt"
run "$PY/pip-audit -r requirements.txt 2>&1 | tail -3"
echo ">> Clean. This is the whole point of SCA: the vulnerability was not in"
echo ">> code we wrote, and no amount of code review would have found it."
rm -f /tmp/req-before.txt
echo ">> SAST checks code WE wrote; SCA checks code we DEPEND ON. Most real"
echo ">> vulnerabilities in an application come from the second category."

hr "4. SECRET SCANNING"
if command -v gitleaks >/dev/null 2>&1; then
  run "gitleaks detect --source $D --config $D/security/.gitleaks.toml --no-banner -v 2>&1 | tail -14"
else
  echo "gitleaks not installed locally; it runs in the pipeline via gitleaks-action."
  echo
  echo "--- demonstrating what it looks for ---"
  # NOTE: the sample values below are deliberately malformed so they cannot be
  # mistaken for live credentials. An earlier version of this script used a
  # realistic "sk_live_..." string and GitHub's own push protection REJECTED the
  # push - the control working exactly as intended, on this very module.
  cat > /tmp/leak_demo.py <<'PYEOF'
AWS_SECRET_ACCESS_KEY = "EXAMPLE0NOT0A0REAL0KEY0000000000000000000"
api_key = "placeholder_0000000000000000000000000"
PYEOF
  echo "\$ grep -nE '(secret|key)\\s*=\\s*\"[A-Za-z0-9/+=_-]{12,}\"' /tmp/leak_demo.py"
  grep -nE '(secret|key)\s*=\s*"[A-Za-z0-9/+=_-]{12,}"' -i /tmp/leak_demo.py
  echo ">> Those two lines are exactly the shape gitleaks flags."
  rm -f /tmp/leak_demo.py
fi
echo
echo "--- our application takes credentials from the ENVIRONMENT, never source ---"
run "grep -n 'os.getenv' $D/app/src/app.py"

hr "5. DOCKER BUILD"
run "docker build -q -t devsecops-demo:scan $D/app"
run "docker images devsecops-demo --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}'"
echo
echo "--- image hardening checks ---"
run "docker inspect devsecops-demo:scan --format 'runs as user: {{.Config.User}}'"
echo "\$ docker run --rm devsecops-demo:scan id"
docker run --rm devsecops-demo:scan id 2>&1
echo ">> uid=10001, not 0. A container running as root shares the host's uid 0."

hr "6. CONTAINER IMAGE SCANNING — Trivy"
if command -v trivy >/dev/null 2>&1; then
  run "trivy image --severity HIGH,CRITICAL --ignore-unfixed devsecops-demo:scan 2>&1 | tail -22"
else
  echo "\$ docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image ..."
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    aquasec/trivy:latest image --severity HIGH,CRITICAL --ignore-unfixed \
    --scanners vuln --quiet devsecops-demo:scan 2>&1 | tail -24
fi
echo
echo ">> --ignore-unfixed matters: a CVE with no available patch cannot be acted"
echo ">> on by us, so failing the build on it would just block all deploys."

hr "7. THE SECURITY GATE"
cat <<'NOTE'
  The gate is STRUCTURAL, not advisory. In the workflow:

      push:
        needs: [security-gate]

      security-gate:
        needs: [test, sast, sca, secret-scan, image-scan]

  GitHub will not start `push` unless every one of those jobs succeeded, so
  there is no path by which a failing scan still ships an image.

  Compare with the common anti-pattern:

      - run: trivy image myapp || true        # <- reports, never blocks

  which produces a dashboard nobody acts on.

  WHERE EACH CONTROL SITS

    SAST          our code            before anything is built
    SCA           our dependencies    before anything is built
    Secret scan   our repository      including full git history
    Image scan    the built artifact  after build, BEFORE push
    Config scan   our manifests       after push, before deploy
NOTE
