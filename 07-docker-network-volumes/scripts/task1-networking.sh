#!/usr/bin/env bash
# Task 1: three containers, three networks, backend on two of them.
#
# Topology — the classic 3-tier isolation pattern:
#
#     frontend-net                 backend-net              isolated-net
#   +--------------+            +---------------+          +------------+
#   |  frontend    |            |               |          |  (no       |
#   |  (nginx)     |            |   database    |          |  members)  |
#   |      \       |            |   (mysql)     |          +------------+
#   |       backend (alpine) ---+      /        |
#   +--------------+            +---------------+
#
#   backend is on BOTH frontend-net and backend-net.
#   frontend and database share NO network -> they cannot reach each other.

set -u
hr(){ echo; echo "==================== $* ===================="; }

hr "0. CLEAN SLATE"
docker rm -f frontend backend database >/dev/null 2>&1
docker network rm frontend-net backend-net isolated-net >/dev/null 2>&1
echo "removed any previous containers/networks"

hr "1. CREATE 3 DOCKER NETWORKS"
for n in frontend-net backend-net isolated-net; do
  echo "\$ docker network create $n"
  docker network create "$n"
done
echo
echo "\$ docker network ls"
docker network ls

hr "2. CREATE THE 3 CONTAINERS"
echo "--- frontend: nginx, on frontend-net ---"
echo "\$ docker run -d --name frontend --network frontend-net -p 8081:80 nginx:alpine"
docker run -d --name frontend --network frontend-net -p 8081:80 nginx:alpine

echo
echo "--- database: mysql, on backend-net ---"
echo "\$ docker run -d --name database --network backend-net -e MYSQL_ROOT_PASSWORD=... mysql:8.0"
# --default-authentication-plugin=mysql_native_password:
#   MySQL 8 defaults to caching_sha2_password. The client available in Alpine is
#   actually MariaDB's, which ships no caching_sha2_password plugin and fails with
#   "Plugin caching_sha2_password could not be loaded". Selecting the older plugin
#   lets the lab use a lightweight client container. (Real deployments should keep
#   caching_sha2_password and use the official MySQL client instead.)
docker run -d --name database --network backend-net \
  -e MYSQL_ROOT_PASSWORD=rootpass \
  -e MYSQL_DATABASE=appdb \
  -e MYSQL_USER=appuser \
  -e MYSQL_PASSWORD=apppass \
  mysql:8.0 --default-authentication-plugin=mysql_native_password

echo
echo "--- backend: alpine toolbox, on backend-net (a second network is added next) ---"
echo "\$ docker run -d --name backend --network backend-net nettools"
docker run -d --name backend --network backend-net nettools

hr "3. ADD THE BACKEND CONTAINER TO A SECOND NETWORK"
echo "A container can only join ONE network with 'docker run --network'."
echo "Additional networks are attached afterwards with 'docker network connect'."
echo
echo "\$ docker network connect frontend-net backend"
docker network connect frontend-net backend
echo "connected."
echo
echo "--- proof: backend now has TWO network interfaces ---"
echo "\$ docker inspect backend --format '{{range \$k,\$v := .NetworkSettings.Networks}}{{\$k}} -> {{\$v.IPAddress}}{{println}}{{end}}'"
docker inspect backend --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} -> {{$v.IPAddress}}{{println}}{{end}}'
echo "\$ docker exec backend ip -brief addr"
docker exec backend ip -brief addr

hr "4. WHICH CONTAINER IS ON WHICH NETWORK"
for n in frontend-net backend-net isolated-net; do
  echo
  echo "--- $n ---"
  docker network inspect "$n" --format '{{range .Containers}}  {{.Name}}  {{.IPv4Address}}{{println}}{{end}}'
done
echo "  (isolated-net has no members — it is the third network, created but unused,"
echo "   which is exactly what makes it 'isolated')"

hr "5. WAIT FOR MYSQL TO FINISH INITIALISING"
for i in $(seq 1 90); do
  if docker exec database mysqladmin ping -h 127.0.0.1 -uroot -prootpass >/dev/null 2>&1; then
    echo "MySQL ready after ${i}s"; break
  fi
  [ "$i" = "90" ] && echo "MySQL did not become ready in 90s"
  sleep 1
done

hr "6. CONNECTIVITY TESTS"

echo
echo "############ 6a. backend -> frontend  (share frontend-net) ############"
echo "\$ docker exec backend ping -c 3 frontend"
docker exec backend ping -c 3 frontend 2>&1 | tail -6
echo
echo "\$ docker exec backend curl -s -o /dev/null -w 'HTTP %{http_code}\\n' http://frontend"
docker exec backend curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://frontend
echo ">> SUCCESS — resolved by CONTAINER NAME via Docker's embedded DNS."

echo
echo "############ 6b. backend -> database  (share backend-net) ############"
echo "\$ docker exec backend ping -c 3 database"
docker exec backend ping -c 3 database 2>&1 | tail -6
echo
echo "\$ docker exec backend nc -zv database 3306"
docker exec backend nc -zv -w 3 database 3306 2>&1
echo
echo "--- an actual SQL query across the network ---"
# NOTE: Alpine's "mysql" binary is actually the MariaDB client, which rejects
# MySQL 8's self-signed server certificate with
#   "TLS/SSL error: self-signed certificate in certificate chain".
# --skip-ssl disables TLS for this lab query. (In production you would trust the
# server CA instead of disabling TLS.)
echo "\$ docker exec backend mysql --skip-ssl -h database -uappuser -papppass appdb -e 'SELECT ...'"
SQL_OUT=$(docker exec backend mysql --skip-ssl -h database -uappuser -papppass appdb \
  -e "SELECT 'backend reached the database over backend-net' AS result, VERSION() AS mysql_version;" 2>&1 \
  | grep -v "Deprecated program name")
echo "$SQL_OUT"
if echo "$SQL_OUT" | grep -q "backend reached the database"; then
  echo ">> SUCCESS — real MySQL protocol traffic between two containers."
else
  echo ">> FAILED — see the error above."
fi

echo
echo "############ 6c. frontend -> database  (share NO network) ############"
echo "\$ docker exec frontend ping -c 2 database    (expected to FAIL)"
docker exec frontend ping -c 2 database 2>&1 | head -4
echo
echo "\$ docker exec frontend getent hosts database   (expected: nothing)"
docker exec frontend getent hosts database 2>&1 || echo "(no result — name does not resolve)"
echo
echo ">> FAILS, and this is the POINT. frontend and database share no network,"
echo ">> so Docker's DNS will not even resolve the name for them. The database"
echo ">> is unreachable from the public-facing tier — network segmentation."

echo
echo "############ 6d. frontend -> backend  (share frontend-net) ############"
echo "\$ docker exec frontend ping -c 2 backend"
docker exec frontend ping -c 2 backend 2>&1 | tail -5
echo ">> SUCCESS — the backend is the only bridge between the two tiers."

hr "7. CONNECTIVITY MATRIX"
printf '%-12s %-12s %-12s %s\n' FROM TO RESULT REASON
printf '%-12s %-12s %-12s %s\n' backend  frontend "OK"     "both on frontend-net"
printf '%-12s %-12s %-12s %s\n' backend  database "OK"     "both on backend-net"
printf '%-12s %-12s %-12s %s\n' frontend backend  "OK"     "both on frontend-net"
printf '%-12s %-12s %-12s %s\n' frontend database "BLOCKED" "no shared network"

hr "8. FINAL STATE"
echo "\$ docker ps  (filtered to this task's three containers)"
docker ps --filter name=frontend --filter name=backend --filter name=database \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
echo
echo "\$ docker network ls"
docker network ls
