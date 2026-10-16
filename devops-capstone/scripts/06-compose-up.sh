#!/usr/bin/env bash
# M4 — the single command the brief asks for, start to finish.
export PATH="/opt/homebrew/bin:$PATH"
set -u
hr(){ echo; echo "=== $* ==="; }
D="$(cd "$(dirname "$0")/.." && pwd)"
cd "$D"

hr "1. docker compose up --build"
echo "\$ docker compose up --build -d"
# --build so the images are genuinely rebuilt from the Dockerfiles rather than
# reused; the brief asks for this exact command.
docker compose up --build -d 2>&1 | grep -vE '^#[0-9]+ ' | tail -30

hr "2. ALL THREE SERVICES, WITH HEALTH"
echo "\$ docker compose ps"
docker compose ps --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}' 2>&1

hr "3. WAIT FOR THE FRONTEND TO ANSWER ON :3000"
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:3000/ 2>/dev/null)
  [ "$code" = "200" ] && { echo "  HTTP 200 after ~$((i*2))s"; break; }
  printf '.'; sleep 2
done
echo "\$ curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/"
curl -s -o /dev/null -w '  frontend HTTP %{http_code}\n' --max-time 10 http://localhost:3000/
echo "\$ curl -s localhost:3000/api/appointments/stats   (API through nginx, same origin)"
curl -s --max-time 10 http://localhost:3000/api/appointments/stats; echo
echo "\$ curl -s localhost:8000/health"
curl -s --max-time 10 http://localhost:8000/health; echo
