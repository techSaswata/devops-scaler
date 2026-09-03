#!/usr/bin/env bash
# Task 3: deploy three different types of application with Docker Compose.
cd "$(dirname "$0")"

echo "############ 1. TEAR DOWN any previous deployment ############"
echo '$ docker compose down'
docker compose down 2>&1 | tail -5

echo
echo "############ 2. BUILD AND DEPLOY all three ############"
echo '$ docker compose up -d --build'
docker compose up -d --build 2>&1 | tail -20

echo
echo "############ 3. docker compose ps ############"
echo '$ docker compose ps'
docker compose ps

echo
echo "############ 4. the network Compose created ############"
echo '$ docker network ls | grep deployment'
docker network ls | grep -E 'NETWORK|deployment'
echo
echo '$ docker network inspect deployment_appnet --format "{{range .Containers}}{{.Name}} {{.IPv4Address}}{{println}}{{end}}"'
docker network inspect deployment_appnet --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{println}}{{end}}'

echo
echo "############ 5. WAIT for each service to become ready ############"
# Flask in particular takes a moment to bind; polling avoids a false HTTP 000.
for spec in "nodejs:4001" "python:4002" "java:4003"; do
  name="${spec%%:*}"; port="${spec##*:}"
  printf '%-8s ' "$name"
  for i in $(seq 1 40); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/" 2>/dev/null)
    if [ "$code" = "200" ]; then echo "ready after ${i}s"; break; fi
    [ "$i" = "40" ] && echo "TIMED OUT (last=$code)"
    sleep 1
  done
done

echo
echo "############ 6. VERIFY all three respond ############"
for spec in "nodejs:4001" "python:4002" "java:4003"; do
  name="${spec%%:*}"; port="${spec##*:}"
  printf '%-8s port %-5s ' "$name" "$port"
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/")
  title=$(curl -s "http://localhost:$port/" | grep -o '<title>[^<]*</title>' | sed 's/<[^>]*>//g')
  echo "HTTP $code  — $title"
done

echo
echo "############ 7. service-to-service DNS inside the compose network ############"
echo "Compose puts all three on one network and registers each SERVICE NAME in DNS,"
echo "so containers reach each other by name — no IP addresses, no --link."
echo
echo '$ docker compose exec -T nodejs wget -qO- http://python:5000/health'
docker compose exec -T nodejs wget -qO- http://python:5000/health 2>&1 | head -2
echo
echo '$ docker compose exec -T python python -c "import urllib.request; print(urllib.request.urlopen(\"http://java:8080/health\").read().decode())"'
docker compose exec -T python python -c "import urllib.request; print(urllib.request.urlopen('http://java:8080/health').read().decode())" 2>&1 | head -2

echo
echo "############ 8. logs from all three services ############"
echo '$ docker compose logs --tail=3'
docker compose logs --tail=3 2>&1 | head -20
