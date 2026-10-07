#!/usr/bin/env bash
# Module 13, part 3 — the Session 14 troubleshooting mini project.
# Five planted faults, found and fixed one at a time.
set -u
hr(){ echo; echo "=== $* ==="; }
sub(){ echo; echo "--- $* ---"; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-22}; }
MP="$(cd "$(dirname "$0")/.." && pwd)/mini-project"
NS="-n tsproject"

kubectl delete namespace tsproject --ignore-not-found --wait=true >/dev/null 2>&1
sleep 3

hr "0. DEPLOY THE BROKEN STACK"
run "kubectl apply -f $MP/broken-stack.yaml"
sleep 40
run "kubectl get all $NS"
echo
echo ">> Nothing works. Rather than guess, triage in order."

hr "1. TRIAGE — what is not Running?"
run "kubectl get pods $NS -o wide"
run "kubectl get pods $NS --field-selector=status.phase!=Running"
echo ">> Two different frontend failures and a backend that is Running but not READY."

hr "FAULT 1 — frontend Pending"
sub "INVESTIGATE"
run "kubectl describe pod $NS -l app=frontend | sed -n '/Events:/,\$p' | head -6"
sub "ROOT CAUSE"
echo "requests.cpu is 32; no node has that much allocatable."
run "kubectl get nodes -o custom-columns=NODE:.metadata.name,CPU:.status.allocatable.cpu --no-headers"
sub "FIX"
echo "\$ kubectl set resources deployment/frontend $NS --requests=cpu=100m"
kubectl set resources deployment/frontend $NS --requests=cpu=100m >/dev/null
sleep 20
run "kubectl get pods $NS -l app=frontend"
echo ">> Scheduled now - which EXPOSES the next fault."

hr "FAULT 2 — frontend ImagePullBackOff"
sub "INVESTIGATE"
run "kubectl describe pod $NS -l app=frontend | sed -n '/Events:/,\$p' | head -7"
sub "ROOT CAUSE"
echo "Image tag nginx:1.27-alpine-nonexistent does not exist."
sub "FIX"
echo "\$ kubectl set image deployment/frontend web=nginx:1.27-alpine $NS"
kubectl set image deployment/frontend web=nginx:1.27-alpine $NS >/dev/null
sleep 25
run "kubectl get pods $NS -l app=frontend"
echo ">> Still not Running - a THIRD fault is underneath."

hr "FAULT 3 — frontend CreateContainerConfigError"
sub "INVESTIGATE"
run "kubectl describe pod $NS -l app=frontend | sed -n '/Events:/,\$p' | head -6"
run "kubectl get configmap app-config $NS -o jsonpath='keys: {.data}{\"\\n\"}'"
sub "ROOT CAUSE"
echo "The deployment references configMapKeyRef key LOG_LEVEL, which is absent."
sub "FIX"
echo "\$ kubectl patch configmap app-config $NS -p '{\"data\":{\"LOG_LEVEL\":\"INFO\"}}'"
kubectl patch configmap app-config $NS -p '{"data":{"LOG_LEVEL":"INFO"}}' >/dev/null
kubectl rollout restart deployment/frontend $NS >/dev/null
kubectl rollout status deployment/frontend $NS --timeout=240s
run "kubectl get pods $NS -l app=frontend"
run "kubectl exec $NS deploy/frontend -- printenv LOG_LEVEL"

hr "FAULT 4 — backend Running but 0/1 READY"
sub "INVESTIGATE"
run "kubectl get pods $NS -l app=backend"
run "kubectl describe pod $NS -l app=backend | sed -n '/Events:/,\$p' | head -6"
sub "ROOT CAUSE"
echo "The readiness probe requests /healthz; nginx returns 404 for it."
sub "FIX"
echo "\$ patch the readiness probe path to /"
kubectl patch deployment backend $NS --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/"}]' >/dev/null
kubectl rollout status deployment/backend $NS --timeout=240s
run "kubectl get pods $NS -l app=backend"

hr "FAULT 5 — backend Service has no endpoints"
sub "INVESTIGATE"
run "kubectl get endpoints backend $NS"
run "kubectl get svc backend $NS -o jsonpath='selector: {.spec.selector}{\"\\n\"}'"
run "kubectl get pods $NS -l app=backend -o jsonpath='labels:   {.items[0].metadata.labels}{\"\\n\"}'"
sub "ROOT CAUSE"
echo "Service selects app=backend-api; pods are labelled app=backend."
sub "FIX"
kubectl patch svc backend $NS -p '{"spec":{"selector":{"app":"backend"}}}' >/dev/null
sleep 5
run "kubectl get endpoints backend $NS"

hr "FINAL VERIFICATION — end-to-end"
run "kubectl get all $NS"
echo
echo "\$ frontend pod -> backend Service (the path the app would actually use)"
kubectl exec $NS deploy/frontend -- wget -qO- --timeout=3 http://backend 2>/dev/null | grep -o '<title>.*</title>'
echo
run "kubectl get pods $NS --field-selector=status.phase!=Running"
echo "(no output above = every pod is Running)"
echo
cat <<'NOTE'
  WHAT THIS DRILL TEACHES:

  Fixing one fault EXPOSES the next. The frontend went
      Pending -> ImagePullBackOff -> CreateContainerConfigError -> Running
  and each state was only visible once the previous blocker was cleared.

  That is why you iterate rather than trying to diagnose everything at once
  from the first `kubectl get pods`. The first error is rarely the only error.

  The loop:
      kubectl get pods --field-selector=status.phase!=Running
      kubectl describe <the first one>   -> read Events
      fix
      repeat until the query returns nothing
NOTE
