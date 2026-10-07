#!/usr/bin/env bash
# Module 15 — the pipeline stages reproduced locally, then the PUBLISHED image
# deployed to the kind cluster.
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-25}; }
D="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE=ghcr.io/techsaswata/devops-scaler/cicd-demo:latest

hr "1. CI STAGE — LINT (the same command the runner executes)"
cd "$D/app"
run "/tmp/cicdvenv/bin/flake8 src tests --count --select=E9,F63,F7,F82 --show-source --statistics"
echo ">> No syntax errors or undefined names."

hr "2. CI STAGE — UNIT TESTS"
run "/tmp/cicdvenv/bin/python -m pytest tests/ -v --tb=short"

hr "3. CI STAGE — DOCKER BUILD"
run "docker build -q -t cicd-demo:local . "
run "docker images cicd-demo --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}'"

hr "4. CI STAGE — SMOKE TEST THE IMAGE"
docker rm -f cicd-local >/dev/null 2>&1
run "docker run -d --name cicd-local -p 5060:5000 cicd-demo:local"
for i in $(seq 1 30); do curl -fsS http://localhost:5060/health >/dev/null 2>&1 && { echo "healthy after ${i}s"; break; }; sleep 1; done
run "curl -s http://localhost:5060/"
run "curl -s http://localhost:5060/health"
run "curl -s http://localhost:5060/add/2/3"
docker rm -f cicd-local >/dev/null 2>&1

hr "5. CD STAGE — THE IMAGE PUBLISHED BY THE REAL PIPELINE"
echo ">> This image was built and pushed by the CD workflow on GitHub's runners,"
echo ">> not locally. Pulling it here proves the registry step worked."
run "docker pull -q $IMAGE"
echo
echo "\$ docker manifest inspect $IMAGE  (platforms)"
docker manifest inspect "$IMAGE" 2>/dev/null | python3 -c "
import json,sys
for m in json.load(sys.stdin).get('manifests',[]):
    p=m.get('platform',{})
    if p.get('architecture')!='unknown': print('   ', p.get('os')+'/'+p.get('architecture'))
"
echo ">> Multi-arch. The first CD run produced an amd64-only image which could"
echo ">> not be pulled on this arm64 machine - adding QEMU and a platforms list"
echo ">> fixed it."

hr "6. DEPLOY THE PUBLISHED IMAGE TO KUBERNETES"
kubectl delete namespace cicd --ignore-not-found --wait=true >/dev/null 2>&1
kubectl create namespace cicd >/dev/null
sed "s|IMAGE_PLACEHOLDER|$IMAGE|" "$D/k8s/deployment.yaml" > /tmp/cicd-deploy.yaml
run "grep -A1 'image:' /tmp/cicd-deploy.yaml | head -3"
run "kubectl apply -n cicd -f /tmp/cicd-deploy.yaml -f $D/k8s/service.yaml"
kubectl rollout status deployment/cicd-demo -n cicd --timeout=300s
run "kubectl get all -n cicd"
echo
echo "--- reach the deployed app through its Service ---"
kubectl run cicd-client -n cicd --image=busybox:1.36 --restart=Never -- sleep infinity >/dev/null 2>&1
kubectl wait --for=condition=Ready pod/cicd-client -n cicd --timeout=180s >/dev/null 2>&1
echo "\$ kubectl exec cicd-client -n cicd -- wget -qO- http://cicd-demo/"
kubectl exec cicd-client -n cicd -- wget -qO- --timeout=3 http://cicd-demo/ 2>/dev/null; echo
echo "\$ kubectl exec cicd-client -n cicd -- wget -qO- http://cicd-demo/add/7/5"
kubectl exec cicd-client -n cicd -- wget -qO- --timeout=3 http://cicd-demo/add/7/5 2>/dev/null; echo
echo
echo ">> The image built on a GitHub runner, pushed to GHCR, and pulled by a"
echo ">> Kubernetes cluster is now serving traffic. That is the complete"
echo ">> CI -> CD -> registry -> deploy loop."
run "kubectl get pods -n cicd -o wide"
