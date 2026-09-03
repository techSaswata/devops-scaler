#!/usr/bin/env bash
# Stop and remove everything this homework created.
# The demo containers are left running after each section so the apps can be
# opened in a browser; run this when you are done looking at them.
set -u

echo "==> removing containers"
docker rm -f \
  hello-nodejs hello-python hello-java hello-apache hello-react hello-nginx \
  deploy-nodejs deploy-python deploy-java \
  multistage-app \
  frontend backend database \
  apache-host apache-bridge nginx-bind nginx-copy \
  lnx-journal shell-lab 2>/dev/null

echo "==> removing the compose stack"
(cd "$(dirname "$0")/06-dockerfiles-and-images/deployment" && docker compose down 2>/dev/null)

echo "==> leaving swarm (if active)"
docker swarm leave --force 2>/dev/null

echo "==> removing networks"
docker network rm frontend-net backend-net isolated-net app-overlay 2>/dev/null

echo "==> removing images built here"
docker rmi -f \
  hello-nodejs hello-python hello-java hello-apache hello-react hello-nginx \
  deploy-nodejs:1.0 deploy-python:1.0 deploy-java:1.0 \
  multistage-app:latest singlestage-app:latest \
  nettools net-lab linux-lab-systemd 2>/dev/null

echo
echo "Done. Remaining containers:"
docker ps --format 'table {{.Names}}\t{{.Status}}'
