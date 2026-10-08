#!/usr/bin/env bash
# Evidence for M1-M4 and M6: the application, its tests, its images and the
# full stack running under docker compose.
export PATH="/opt/homebrew/bin:$PATH"
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }
runfull(){ echo; echo "\$ $*"; local o; o=$(eval "$@" 2>&1); echo "$o" | tail -${N:-25}; }
D="$(cd "$(dirname "$0")/.." && pwd)"
VENV="${VENV:-/private/tmp/claude-501/-Users-techsaswata-Downloads-devops-scaler/f093fc6e-0617-4fda-a13c-38eb7d93c9dd/scratchpad/cfvenv}"
API=http://localhost:3000/api

hr "1. THE APPLICATION'S TESTS"
cd "$D/backend"
run "$VENV/bin/python -m pytest -q 2>&1 | tail -22"

hr "2. WHAT THE TESTS ACTUALLY COVER"
run "grep -h '^def test' tests/*.py | sed 's/def //; s/(.*//' | nl"
echo ">> 16 cases over the probes, doctors/patients, and the full appointment"
echo ">> lifecycle. The suite runs on SQLite so it needs no database service in"
echo ">> CI -- and the partial index is declared for BOTH engines so the"
echo ">> double-booking conflict is genuinely exercised, not skipped."

hr "3. IMAGES: MULTI-STAGE AND NON-ROOT"
cd "$D"
run "docker compose images"
echo
echo "--- the runtime stage carries no build toolchain ---"
echo "\$ docker compose exec backend sh -c 'command -v gcc || echo \"no compiler in the runtime image\"'"
docker compose exec -T backend sh -c 'command -v gcc || echo "no compiler in the runtime image"' 2>&1
echo "\$ docker compose exec frontend sh -c 'command -v node || echo \"no node in the runtime image\"'"
docker compose exec -T frontend sh -c 'command -v node || echo "no node in the runtime image"' 2>&1
echo
echo "--- neither runs as root ---"
for s in backend frontend; do printf '  %-9s ' "$s"; docker compose exec -T "$s" id 2>&1 | head -1; done
echo
echo "--- and the read-only root filesystem is real, not asserted ---"
echo "\$ docker compose exec backend touch /forbidden"
docker compose exec -T backend sh -c 'touch /forbidden 2>&1 || true' 2>&1 | head -2

hr "4. THE STACK IS UP"
run "docker compose ps --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'"
echo ">> The backend waits on postgres's HEALTH check, not merely its start:"
echo ">> Postgres accepts TCP for a second or two before it accepts queries."

hr "5. THE DATABASE SCHEMA CAME FROM A MIGRATION"
run "docker compose exec -T postgres psql -U clinic -d clinicflow -c '\\dt'"
run "docker compose exec -T postgres psql -U clinic -d clinicflow -c 'SELECT version_num FROM alembic_version'"
echo
echo "--- the booking rule is enforced by the DATABASE, not by a handler ---"
docker compose exec -T postgres psql -U clinic -d clinicflow -c '\d appointments' 2>&1 | sed -n '/Indexes/,/Foreign-key/p'

hr "6. THE API"
run "curl -s $API/../ -o /dev/null -w 'GET /        HTTP %{http_code}\n'"
echo "\$ GET /health"; curl -s --max-time 10 http://localhost:8000/health; echo
echo "\$ GET /ready    (this one DOES query Postgres)"; curl -s --max-time 10 http://localhost:8000/ready; echo
echo
echo "\$ GET /api/appointments/stats"
curl -s --max-time 10 "$API/appointments/stats" | python3 -m json.tool
echo
echo "\$ GET /api/appointments  (first two)"
curl -s --max-time 10 "$API/appointments" | python3 -c "
import json,sys
for a in json.load(sys.stdin)[:2]:
    print(f\"  {a['id']:>2}  {a['scheduled_at'][:16]}  {a['patient_name']:<16} {a['doctor_name']:<20} {a['status']}\")"

hr "7. THE BOOKING CONFLICT IS A RACE, SO THE DATABASE SETTLES IT"
WHEN=$(python3 -c "from datetime import datetime,timedelta,timezone;print((datetime.now(timezone.utc)+timedelta(days=30)).replace(microsecond=0).isoformat())")
echo "slot: $WHEN"
echo
echo "\$ POST /api/appointments   doctor 1  (first booking)"
curl -s -o /dev/null -w '  HTTP %{http_code}\n' -X POST "$API/appointments" -H 'Content-Type: application/json' \
  -d "{\"patient_id\":1,\"doctor_id\":1,\"scheduled_at\":\"$WHEN\"}"
echo "\$ POST /api/appointments   doctor 1, SAME instant, different patient"
curl -s -w '\n  HTTP %{http_code}\n' -X POST "$API/appointments" -H 'Content-Type: application/json' \
  -d "{\"patient_id\":2,\"doctor_id\":1,\"scheduled_at\":\"$WHEN\"}" | sed 's/^{/  {/'
echo "\$ POST /api/appointments   DIFFERENT doctor, same instant (must succeed)"
curl -s -o /dev/null -w '  HTTP %{http_code}\n' -X POST "$API/appointments" -H 'Content-Type: application/json' \
  -d "{\"patient_id\":2,\"doctor_id\":2,\"scheduled_at\":\"$WHEN\"}"
echo "\$ POST /api/appointments   naive datetime, no timezone offset"
curl -s -o /dev/null -w '  HTTP %{http_code}\n' -X POST "$API/appointments" -H 'Content-Type: application/json' \
  -d '{"patient_id":1,"doctor_id":3,"scheduled_at":"2027-01-01T10:00:00"}'
echo
echo ">> 409 from a unique index, not from a pre-flight SELECT. Two concurrent"
echo ">> bookings can both pass an 'is it free?' check before either inserts, so"
echo ">> only the database can decide. 422 for the naive datetime: a clinic that"
echo ">> books across a DST boundary should not be guessing the timezone."

hr "8. SAME ORIGIN: THE BROWSER NEVER SEES THE BACKEND"
echo "The bundle contains no backend hostname. nginx proxies /api, so the same"
echo "image works in compose and in Kubernetes without a rebuild."
run "grep -c 'localhost:8000' $D/frontend/dist/assets/*.js || echo '0 occurrences of a backend URL in the built bundle'"
echo "\$ curl -s localhost:3000/api/appointments/stats   (through nginx)"
curl -s --max-time 10 http://localhost:3000/api/appointments/stats | head -c 140; echo
echo "\$ curl -s -o /dev/null -w '%{http_code}' localhost:3000/healthz   (nginx's own probe)"
curl -s -o /dev/null -w '  HTTP %{http_code}\n' --max-time 10 http://localhost:3000/healthz

hr "9. PROMETHEUS METRICS"
echo "\$ curl -s localhost:8000/metrics | head"
curl -s --max-time 10 http://localhost:8000/metrics | grep -E '^# (HELP|TYPE)|^http_requests_total' | head -10
echo
echo "metric families exposed:"
curl -s --max-time 10 http://localhost:8000/metrics | grep -c '^# HELP'
