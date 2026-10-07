#!/usr/bin/env bash
# Stop and remove everything this homework created on THIS MACHINE.
#
# Demo containers are left running after each module so the applications can be
# opened in a browser; run this when you are done looking at them.
#
# AWS is NOT touched here, and deliberately so. Modules 17, 18 and 20 create
# real billable resources, and each of those scripts destroys what it made from
# a `trap ... EXIT` and then verifies the deletion against the AWS API before
# exiting. Teardown belongs next to the thing that did the creating, where it
# still knows the resource IDs -- not in a general-purpose cleanup script that
# would have to guess, and could guess wrong on a shared account. To check
# nothing was left behind:
#
#   aws resourcegroupstaggingapi get-resources \
#     --region ap-south-1 --tag-filters Key=Owner,Values=24BCS10248
#
# and resolve any ARN it returns against the service that owns it -- the tagging
# API is an index and keeps entries for already-terminated resources.
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
  nettools net-lab linux-lab-systemd \
  cicd-demo:local devsecops-demo:local task-api:1.0.0 2>/dev/null

# Deleting the cluster removes every namespace, release and Argo CD Application
# with it, so the individual modules need no separate teardown. Named here only
# so it is obvious what goes.
echo "==> deleting the Kubernetes cluster (modules 08-14, 19, 20)"
echo "    with it: ingress-nginx, metrics-server, kube-prometheus-stack,"
echo "    Argo CD, and the finalproject* namespaces"
kind delete cluster --name devops-hw 2>/dev/null || true

echo
echo "Done. Remaining containers:"
docker ps --format 'table {{.Names}}\t{{.Status}}'
