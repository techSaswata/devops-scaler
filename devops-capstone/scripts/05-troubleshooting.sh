#!/usr/bin/env bash
# The troubleshooting lab: four faults, each diagnosed from the cluster alone.
export PATH="/opt/homebrew/bin:$PATH"
set -u
hr(){ echo; echo "=== $* ==="; }
step(){ echo; echo "--- $* ---"; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | grep -v 'v1 Endpoints is deprecated' | head -${N:-28}; }
D="$(cd "$(dirname "$0")/.." && pwd)"
NS=clinicflow-broken
TAG="${IMAGE_TAG:?set IMAGE_TAG to a published sha- tag}"
IMG="ghcr.io/techsaswata/devops-scaler/clinicflow-backend:$TAG"

kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
apply(){ sed "s|IMAGE_PLACEHOLDER|$IMG|" "$D/troubleshooting/$1" | kubectl apply -n $NS -f - ; }

# =========================================================================
hr "FAULT 1 of 4 — the pod never starts"
step "IDENTIFY"
apply 01-broken-image.yaml
sleep 25
run "kubectl get pods -n $NS -l fault=image"
echo ">> ErrImagePull, then ImagePullBackOff."

step "INVESTIGATE"
run "kubectl describe pod -n $NS -l fault=image | sed -n '/^Events:/,\$p'"

step "ROOT CAUSE"
run "kubectl get deploy broken-image -n $NS -o jsonpath='image: {.spec.template.spec.containers[0].image}{\"\\n\"}'"
echo "  Tag v9.9.9-does-not-exist was never built. Note what the registry says:"
echo "  'may require authorization', NOT 'no such tag'. A registry will not"
echo "  confirm the absence of a possibly-private repository, so a typo and a"
echo "  permissions problem are indistinguishable from outside."

step "FIX"
run "kubectl set image deployment/broken-image backend=$IMG -n $NS"
sleep 30
step "VERIFY"
run "kubectl get pods -n $NS -l fault=image"

# =========================================================================
hr "FAULT 2 of 4 — Pending, never scheduled"
step "IDENTIFY"
apply 04-broken-resources.yaml
sleep 20
run "kubectl get pods -n $NS -l fault=resources"
echo ">> Pending. Not running-and-broken: never placed on a node at all."

step "INVESTIGATE"
run "kubectl describe pod -n $NS -l fault=resources | sed -n '/^Events:/,\$p'"
run "kubectl get nodes -o custom-columns='NODE:.metadata.name,ALLOCATABLE_CPU:.status.allocatable.cpu' --no-headers"

step "ROOT CAUSE"
run "kubectl get deploy broken-resources -n $NS -o jsonpath='requests: {.spec.template.spec.containers[0].resources.requests}{\"\\n\"}'"
echo "  16 CPUs requested; a t3.medium has 2 allocatable. A request is a"
echo "  SCHEDULING CONTRACT, not a cap -- the scheduler will not overcommit it,"
echo "  so the pod waits indefinitely rather than starting and being throttled."

step "FIX"
run "kubectl patch deployment broken-resources -n $NS --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/resources/requests/cpu\",\"value\":\"100m\"},{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/resources/limits/cpu\",\"value\":\"500m\"}]'"
sleep 30
step "VERIFY"
run "kubectl get pods -n $NS -l fault=resources"

# =========================================================================
hr "FAULT 3 of 4 — Running, but never Ready"
step "IDENTIFY"
apply 03-broken-probe.yaml
sleep 40
run "kubectl get pods -n $NS -l fault=probe"
echo ">> STATUS Running with READY 0/1. The process is up; Kubernetes is"
echo ">> refusing to call it serviceable, so it joins no Service."

step "INVESTIGATE"
run "kubectl describe pod -n $NS -l fault=probe | grep -i 'readiness probe' | head -3"

step "ROOT CAUSE"
run "kubectl get deploy broken-probe -n $NS -o jsonpath='readiness path: {.spec.template.spec.containers[0].readinessProbe.httpGet.path}{\"\\n\"}'"
echo "  /healthz is Go-ecosystem convention; this app serves /health and /ready."
echo "  The probe did exactly what it was told. Proof the app is fine:"
POD=$(kubectl get pods -n $NS -l fault=probe -o jsonpath='{.items[0].metadata.name}')
echo "\$ GET /health from inside the pod"
kubectl exec -n $NS "$POD" -- python -c "
import urllib.request;print(' ',urllib.request.urlopen('http://localhost:8000/health').read().decode())" 2>&1 | grep -v Defaulted
echo "\$ GET /healthz from inside the pod"
kubectl exec -n $NS "$POD" -- python -c "
import urllib.request,urllib.error
try: print(' ',urllib.request.urlopen('http://localhost:8000/healthz').read().decode())
except urllib.error.HTTPError as e: print('  HTTP',e.code,e.reason)" 2>&1 | grep -v Defaulted
echo ">> The probe was right to fail. The PATH was wrong, not the application."

step "FIX"
# /health, NOT /ready -- and the difference matters here.
#
# /ready deliberately queries the database, and this lab pod has no database:
# it is a bare Deployment with a deliberately bogus DATABASE_URL, because the
# fault being demonstrated is about probe PATHS, not about Postgres. Pointing
# readiness at /ready would swap a 404 for a 503 and the pod would still never
# become Ready -- which is exactly what happened on the first run of this lab,
# and it then made fault 4 unreproducible because an unready pod has no
# endpoints regardless of the Service selector.
run "kubectl patch deployment broken-probe -n $NS --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/readinessProbe/httpGet/path\",\"value\":\"/health\"}]'"
printf '  waiting for the pod to become Ready '
for i in $(seq 1 40); do
  kubectl get pods -n $NS -l fault=probe --no-headers 2>/dev/null | grep -q '1/1 *Running' \
    && { echo " Ready after ~$((i*5))s"; break; }
  printf '.'; sleep 5
done
step "VERIFY"
run "kubectl get pods -n $NS -l fault=probe"

# =========================================================================
hr "FAULT 4 of 4 — a healthy pod that nothing can reach"
step "IDENTIFY"
# Reuses the now-healthy pods from fault 3. Nothing is relabelled: an earlier
# version of this script tried to overwrite the pod template's `app` label, and
# the API server rejected it because the Deployment's own selector is immutable
# and would no longer have matched its template -- so the Service was pointed at
# a label that never existed and the "fix" could not work either.
kubectl apply -n $NS -f "$D/troubleshooting/02-broken-service.yaml" >/dev/null
sleep 8
sleep 8
run "kubectl get svc broken-service -n $NS"
run "kubectl get endpoints broken-service -n $NS"
echo ">> ENDPOINTS <none>, while a healthy pod sits right there. No event, no"
echo ">> warning: the Service is reported as perfectly fine."

step "INVESTIGATE"
run "kubectl get svc broken-service -n $NS -o jsonpath='service selector: {.spec.selector}{\"\\n\"}'"
run "kubectl get pods -n $NS -l app=broken-probe -o jsonpath='pod labels:       {.items[0].metadata.labels}{\"\\n\"}'"

step "ROOT CAUSE"
echo "  selector app=brokenprobe, label app=broken-probe. One"
echo "  hyphen. A Service builds its endpoint list purely by label match, and"
echo "  nothing warns about a selector that matches nothing. This is why 'the"
echo "  pod is Running' is never sufficient evidence that a service works."

step "FIX"
run "kubectl patch svc broken-service -n $NS --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/selector/app\",\"value\":\"broken-probe\"}]'"
sleep 8
step "VERIFY"
printf '  waiting for the endpoint to appear '
for i in $(seq 1 24); do
  kubectl get endpoints broken-service -n $NS -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | grep -q . \
    && { echo " populated after ~$((i*5))s"; break; }
  printf '.'; sleep 5
done
run "kubectl get endpoints broken-service -n $NS"
echo "\$ GET / through the Service DNS name"
kubectl run tsprobe -n $NS --rm -i --restart=Never --image=curlimages/curl:8.11.1 --quiet -- \
  curl -s --max-time 10 http://broken-service.$NS.svc.cluster.local:8000/health 2>&1 | head -3

hr "SUMMARY"
run "kubectl get pods -n $NS"
echo
echo ">> Four faults, four different diagnostic surfaces:"
echo ">>   1  kubelet events     ErrImagePull"
echo ">>   2  scheduler events   Pending / Insufficient cpu"
echo ">>   3  probe events       Running but 0/1 READY"
echo ">>   4  endpoint list      Ready pod, no endpoints"
echo ">>"
echo ">> None was found by reading the manifest. Each came from the cluster's"
echo ">> own account of what it was refusing to do."

hr "CLEANUP"
run "kubectl delete namespace $NS --wait=true"
