#!/usr/bin/env bash
# Build and run all six Hello World applications.
set -u
cd "$(dirname "$0")"

# name | folder | image tag | host port | container port
APPS=(
  "nodejs|nodejs-app|hello-nodejs|3001|3000"
  "python|python-app|hello-python|3002|5000"
  "java|java-app|hello-java|3003|8080"
  "apache|Apache-app|hello-apache|3004|80"
  "react|React-app|hello-react|3005|80"
  "nginx|nginx-app|hello-nginx|3006|80"
)

echo "############ CLEAN UP ANY PREVIOUS RUN ############"
for spec in "${APPS[@]}"; do
  IFS='|' read -r name dir tag hport cport <<< "$spec"
  docker rm -f "$tag" >/dev/null 2>&1 || true
done
echo "done"

echo
echo "############ BUILD ALL IMAGES ############"
for spec in "${APPS[@]}"; do
  IFS='|' read -r name dir tag hport cport <<< "$spec"
  echo
  echo "=== docker build -t $tag ./$dir ==="
  docker build -t "$tag" "./$dir" 2>&1 | tail -6
done

echo
echo "############ RUN ALL CONTAINERS ############"
for spec in "${APPS[@]}"; do
  IFS='|' read -r name dir tag hport cport <<< "$spec"
  echo "\$ docker run -d --name $tag -p $hport:$cport $tag"
  docker run -d --name "$tag" -p "$hport:$cport" "$tag"
done

echo
echo "############ WAIT FOR ALL TO ANSWER ############"
for spec in "${APPS[@]}"; do
  IFS='|' read -r name dir tag hport cport <<< "$spec"
  printf '%-14s ' "$tag"
  for i in $(seq 1 40); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$hport/" 2>/dev/null)
    if [ "$code" = "200" ]; then echo "HTTP 200 after ${i}s"; break; fi
    [ "$i" = "40" ] && echo "TIMED OUT (last code=$code)"
    sleep 1
  done
done

echo
echo "############ docker ps ############"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

echo
echo "############ docker images ############"
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' | grep -E 'REPOSITORY|hello-'

echo
echo "############ VERIFY 'Hello World' IS ON EACH PAGE ############"
for spec in "${APPS[@]}"; do
  IFS='|' read -r name dir tag hport cport <<< "$spec"
  printf '%-14s port %-5s ' "$tag" "$hport"
  body=$(curl -s "http://localhost:$hport/")
  if echo "$body" | grep -qi 'Hello' && echo "$body" | grep -qi 'World'; then
    title=$(echo "$body" | grep -o '<title>[^<]*</title>' | head -1 | sed 's/<[^>]*>//g')
    echo "OK — \"Hello World\" present  [$title]"
  else
    echo "FAILED — no Hello World in response"
  fi
done
