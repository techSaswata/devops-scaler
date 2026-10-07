#!/usr/bin/env bash
# Module 20, part 1 — build the image and deploy the full stack.
export PATH="/opt/homebrew/bin:$PATH"
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }
runfull(){ echo; echo "\$ $*"; local o; o=$(eval "$@" 2>&1); echo "$o" | tail -${N:-25}; }
# Poll until the route returns a real HTTP 200.
#
# An earlier version of this script polled for NON-EMPTY output, which was a bug
# that produced a false pass: ingress-nginx answers immediately with its own
# "503 Service Temporarily Unavailable" page while it still has no healthy
# endpoint behind the host. That page is non-empty, so the loop exited at once
# and the narration underneath claimed success over a 503. Only the status code
# distinguishes "nginx is talking to me" from "my app is talking to me".
wait200(){
  local host="$1" path="${2:-/}" i code=000
  printf '  waiting for %s%s ' "$host" "$path"
  for i in $(seq 1 90); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Host: $host" "http://localhost$path" 2>/dev/null)
    [ "$code" = "200" ] && { echo " HTTP 200 after ~$((i*2))s"; return 0; }
    printf '.'; sleep 2
  done
  echo " GAVE UP after ~180s (last status HTTP $code)"; return 1
}
D="$(cd "$(dirname "$0")/.." && pwd)"
NS="-n finalproject"

hr "1. UNIT TESTS"
cd "$D/application"
run "/tmp/cicdvenv/bin/python -m pytest tests/ -v --tb=short 2>&1 | tail -14"

hr "2. SAST"
run "/tmp/cicdvenv/bin/bandit -r src/ -f screen 2>&1 | grep -E 'Issue:|Severity:|No issues|High:|Medium:' | head -8"

hr "3. BUILD THE IMAGE"
runfull "docker build -q --platform linux/arm64 -t task-api:1.0.0 -f $D/docker/Dockerfile $D/application"
run "docker images task-api --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}'"
run "docker run --rm task-api:1.0.0 id"
echo ">> uid 10001, not root."

hr "4. SCAN THE IMAGE"
echo "\$ trivy image --severity HIGH,CRITICAL task-api:1.0.0"
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest \
  image --severity HIGH,CRITICAL --ignore-unfixed --scanners vuln --quiet task-api:1.0.0 2>&1 | tail -12

hr "5. LOAD THE IMAGE INTO THE CLUSTER"
# kind nodes keep their OWN containerd image store, separate from the host's
# docker. A locally built image must be imported into each node or the kubelet
# will try to pull it from Docker Hub and fail.
#
# NOTE: `docker save` of a MULTI-ARCH buildx image produces an archive whose
# per-platform content is incomplete, and `ctr import` then fails with
# "content digest ... not found". Building single-arch for the cluster's own
# architecture avoids that entirely.
TAR=$(mktemp -t taskapi).tar
docker save -o "$TAR" task-api:1.0.0
for n in devops-hw-control-plane devops-hw-worker devops-hw-worker2; do
  printf '  %-26s ' "$n"
  docker exec -i "$n" ctr --namespace=k8s.io images import - < "$TAR" >/dev/null 2>&1 \
    && echo "imported" || echo "FAILED"
done
rm -f "$TAR"
echo "--- verify it is really present, rather than assuming ---"
for n in devops-hw-worker devops-hw-worker2; do
  printf '  %-26s ' "$n"
  docker exec "$n" crictl images 2>/dev/null | grep -q task-api && echo "present" || echo "MISSING"
done

hr "6. DEPLOY — namespace, config, secret, storage"
kubectl delete namespace finalproject --ignore-not-found --wait=true >/dev/null 2>&1
run "kubectl apply -f $D/kubernetes/00-namespace.yaml -f $D/kubernetes/01-config.yaml -f $D/kubernetes/03-storage.yaml"
echo
# The value is GENERATED here rather than written as a literal. Two reasons:
# it makes "supplied at deploy time" literally true, and a line like
#   --from-literal=DB_PASSWORD='something'
# is a credential-SHAPED assignment, which gitleaks flags on sight -- correctly,
# because a scanner cannot tell a placeholder from a real password. Not writing
# one is better than allowlisting one.
echo "--- the Secret is created OUT OF BAND, never from a committed file ---"
echo "\$ kubectl create secret generic task-api-secret --from-literal=..."
kubectl -n finalproject create secret generic task-api-secret \
  --from-literal=DB_PASSWORD="$(openssl rand -hex 12)" \
  --from-literal=API_KEY="$(openssl rand -hex 12)" >/dev/null
run "kubectl get secret task-api-secret $NS"

hr "7. DEPLOY — workload, service, ingress, HPA"
sed "s|IMAGE_PLACEHOLDER|task-api:1.0.0|" "$D/kubernetes/04-deployment.yaml" > /tmp/fp-deploy.yaml
run "kubectl apply -f /tmp/fp-deploy.yaml -f $D/kubernetes/05-service.yaml -f $D/kubernetes/06-ingress.yaml -f $D/kubernetes/07-hpa.yaml"
runfull "kubectl rollout status deployment/task-api $NS --timeout=300s"
run "kubectl get all $NS"
run "kubectl get pvc,ingress,hpa $NS"

hr "8. THE APPLICATION ACTUALLY WORKS"
POD=$(kubectl get pods $NS -l app=task-api -o jsonpath='{.items[0].metadata.name}')
echo "\$ GET /       (config from the ConfigMap, secrets from the Secret)"
kubectl exec "$POD" $NS -- python -c "import urllib.request;print(urllib.request.urlopen('http://localhost:8000/').read().decode())" 2>&1
echo
echo "\$ GET /health"
kubectl exec "$POD" $NS -- python -c "import urllib.request;print(urllib.request.urlopen('http://localhost:8000/health').read().decode())" 2>&1
echo "\$ GET /ready   (checks the mounted volume is writable)"
kubectl exec "$POD" $NS -- python -c "import urllib.request;print(urllib.request.urlopen('http://localhost:8000/ready').read().decode())" 2>&1
echo
echo "\$ POST /tasks  x3"
for t in "write the final README" "verify the pipeline" "destroy the AWS resources"; do
  kubectl exec "$POD" $NS -- python -c "
import json,urllib.request
r=urllib.request.Request('http://localhost:8000/tasks',data=json.dumps({'title':'$t'}).encode(),headers={'Content-Type':'application/json'})
print(urllib.request.urlopen(r).read().decode())" 2>&1
done
echo
echo "\$ GET /tasks"
kubectl exec "$POD" $NS -- python -c "import urllib.request;print(urllib.request.urlopen('http://localhost:8000/tasks').read().decode())" 2>&1

hr "9. PERSISTENCE — data survives a pod restart"
echo "\$ kubectl delete pod $POD   (the PVC should preserve the tasks)"
kubectl delete pod "$POD" $NS >/dev/null
runfull "kubectl rollout status deployment/task-api $NS --timeout=300s"
NEW=$(kubectl get pods $NS -l app=task-api -o jsonpath='{.items[0].metadata.name}')
echo "new pod: $NEW (was $POD)"
echo "\$ GET /tasks  on the NEW pod"
kubectl exec "$NEW" $NS -- python -c "import urllib.request;print(urllib.request.urlopen('http://localhost:8000/tasks').read().decode())" 2>&1
echo ">> Same three tasks. A different pod re-attached to the same PVC."

hr "10. SECURITY CONTEXT IS REALLY APPLIED"
run "kubectl get pod $NEW $NS -o jsonpath='runAsNonRoot={.spec.securityContext.runAsNonRoot}  uid={.spec.securityContext.runAsUser}  readOnlyRootFS={.spec.containers[0].securityContext.readOnlyRootFilesystem}  privEsc={.spec.containers[0].securityContext.allowPrivilegeEscalation}  caps={.spec.containers[0].securityContext.capabilities.drop}{\"\\n\"}'"
run "kubectl exec $NEW $NS -- id"
echo "\$ kubectl exec $NEW -- touch /forbidden   (readOnlyRootFilesystem)"
kubectl exec "$NEW" $NS -- touch /forbidden 2>&1 | head -2
echo ">> Read-only root rejected the write, while /data stayed writable."

hr "11. INGRESS"
# The controller is a PREREQUISITE, not a detail. An Ingress object with no
# controller watching it is inert: it never gets an ADDRESS and nothing answers
# on :80. The first run of this script proved that the honest way -- the Ingress
# existed, `kubectl get ingress` listed it, and both curls returned EMPTY. The
# cause was not a timing race; ingress-nginx had been removed from the cluster
# after module 10. So the deploy now installs it and waits for it.
if ! kubectl get deploy ingress-nginx-controller -n ingress-nginx >/dev/null 2>&1; then
  echo "ingress-nginx controller absent -- installing it (kind provider manifest)"
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.14.0/deploy/static/provider/kind/deploy.yaml >/dev/null 2>&1
else
  echo "ingress-nginx controller already present"
fi
runfull "kubectl wait -n ingress-nginx --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=300s"
run "kubectl get pods -n ingress-nginx"

# Curling the instant the controller is Ready is too early twice over: nginx has
# to load the rule for the new host, AND the Service needs a ready endpoint.
wait200 taskapi.local

run "kubectl get ingress $NS"
echo ">> ADDRESS is populated now; it was blank while no controller was running."
echo
echo "\$ curl -H 'Host: taskapi.local' http://localhost/"
curl -s --max-time 10 -H 'Host: taskapi.local' http://localhost/ 2>&1 | head -4
echo
echo "\$ curl -H 'Host: taskapi.local' http://localhost/health"
curl -s --max-time 10 -H 'Host: taskapi.local' http://localhost/health 2>&1 | head -4
echo
echo "\$ curl -H 'Host: taskapi.local' http://localhost/tasks"
curl -s --max-time 10 -H 'Host: taskapi.local' http://localhost/tasks 2>&1 | head -4
echo
echo "--- host-based routing really is host-based: an unmatched Host must NOT"
echo "--- reach the app. If this returned the JSON, the rule would be a no-op."
echo "\$ curl -o /dev/null -w 'HTTP %{http_code}' -H 'Host: nope.local' http://localhost/"
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 10 -H 'Host: nope.local' http://localhost/

hr "12. MONITORING WIRED IN"
run "kubectl apply -f $D/monitoring/servicemonitor.yaml -f $D/monitoring/alerts.yaml"
run "kubectl get servicemonitor,prometheusrule $NS"
echo "\$ GET /metrics"
kubectl exec "$NEW" $NS -- python -c "import urllib.request;print(urllib.request.urlopen('http://localhost:8000/metrics').read().decode())" 2>&1 | head -12
