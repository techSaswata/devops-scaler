#!/usr/bin/env bash
# Verify all six Hello World apps are running and serving.
cd "$(dirname "$0")"

APPS=(
  "hello-nodejs:3001" "hello-python:3002" "hello-java:3003"
  "hello-apache:3004" "hello-react:3005"  "hello-nginx:3006"
)

echo "############ docker ps — all six containers running ############"
echo '$ docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

echo
echo "############ health status of every container ############"
echo '$ docker inspect --format "{{.State.Health.Status}}" <container>'
for spec in "${APPS[@]}"; do
  name="${spec%%:*}"
  h=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}' "$name")
  printf '%-14s %s\n' "$name" "$h"
done

echo
echo "############ image sizes ############"
echo '$ docker images | grep hello-'
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' | grep -E 'REPOSITORY|hello-'

echo
echo "############ HTTP verification — curl each app ############"
for spec in "${APPS[@]}"; do
  name="${spec%%:*}"; port="${spec##*:}"
  echo
  echo "--- $name  ->  http://localhost:$port ---"
  echo "\$ curl -s -o /dev/null -w '...' http://localhost:$port/"
  curl -s -o /dev/null -w "HTTP %{http_code} in %{time_total}s (%{size_download} bytes)\n" "http://localhost:$port/"
  echo "\$ curl -s http://localhost:$port/ | grep -o '<title>.*</title>'"
  curl -s "http://localhost:$port/" | grep -o '<title>[^<]*</title>'
  echo "\$ curl -s http://localhost:$port/ | grep -o 'Hello <span>World</span>'"
  curl -s "http://localhost:$port/" | grep -o 'Hello <span>World</span>' | head -1
done

echo
echo "############ container logs — proof each server started ############"
for spec in "${APPS[@]}"; do
  name="${spec%%:*}"
  echo
  echo "\$ docker logs $name"
  docker logs "$name" 2>&1 | head -3
done
