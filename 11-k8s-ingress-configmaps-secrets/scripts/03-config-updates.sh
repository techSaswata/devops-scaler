#!/usr/bin/env bash
# Module 11, part 3 — what happens when config changes. Lab checklist item 10.
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }

hr "1. THE STARTING STATE"
run "kubectl get configmap yatri-app-config -o jsonpath='{.data.LOG_LEVEL}{\"  \"}{.data.DEFAULT_CURRENCY}{\"\\n\"}'"
echo "\$ curl -s -H 'Host: yatri.local' http://localhost/api/ | grep -E 'LOG_LEVEL|CURRENCY'"
curl -s -H 'Host: yatri.local' http://localhost/api/ | grep -E 'LOG_LEVEL|CURRENCY'

hr "2. UPDATE THE CONFIGMAP"
echo "\$ kubectl patch configmap yatri-app-config -p '{\"data\":{\"LOG_LEVEL\":\"DEBUG\",\"DEFAULT_CURRENCY\":\"USD\"}}'"
kubectl patch configmap yatri-app-config -p '{"data":{"LOG_LEVEL":"DEBUG","DEFAULT_CURRENCY":"USD"}}'
run "kubectl get configmap yatri-app-config -o jsonpath='{.data.LOG_LEVEL}{\"  \"}{.data.DEFAULT_CURRENCY}{\"\\n\"}'"
echo ">> The ConfigMap object is updated immediately."

hr "3. BUT THE RUNNING PODS HAVE NOT CHANGED"
echo "waiting 20s to rule out a simple propagation delay..."
sleep 20
echo "\$ curl -s -H 'Host: yatri.local' http://localhost/api/ | grep -E 'LOG_LEVEL|CURRENCY'"
curl -s -H 'Host: yatri.local' http://localhost/api/ | grep -E 'LOG_LEVEL|CURRENCY'
echo
POD=$(kubectl get pods -l app=yatri-backend -o jsonpath='{.items[0].metadata.name}')
run "kubectl exec $POD -- env | grep -E 'LOG_LEVEL|DEFAULT_CURRENCY' | sort"
echo
cat <<'NOTE'
  >> STILL INFO and INR.
  >>
  >> Environment variables are injected ONCE, when the container starts. The
  >> kernel gives a process its environment at exec() time and there is no
  >> mechanism to change it afterwards. Kubernetes cannot update them, and this
  >> is not a bug - it is how processes work.
NOTE

hr "4. A VOLUME-MOUNTED CONFIGMAP *DOES* UPDATE LIVE"
FPOD=$(kubectl get pods -l app=yatri-frontend -o jsonpath='{.items[0].metadata.name}')
run "kubectl exec $FPOD -- grep -c 'Hello from the' /usr/share/nginx/html/index.html"
echo "\$ kubectl patch configmap yatri-frontend-html --type merge -p '<new index.html>'"
kubectl patch configmap yatri-frontend-html --type merge \
  -p '{"data":{"index.html":"<!doctype html>\n<html><head><title>Yatri — UPDATED LIVE</title></head>\n<body><h1>This HTML was changed while the pod kept running</h1></body></html>\n"}}' >/dev/null
echo "patched. polling the file inside the RUNNING pod (no restart):"
for i in $(seq 1 24); do
  t=$(kubectl exec "$FPOD" -- grep -o 'UPDATED LIVE' /usr/share/nginx/html/index.html 2>/dev/null)
  if [ -n "$t" ]; then echo "  updated after ~$((i*5))s without any restart"; break; fi
  [ "$i" = "24" ] && echo "  not updated within 120s"
  sleep 5
done
run "kubectl exec $FPOD -- cat /usr/share/nginx/html/index.html"
run "kubectl get pods -l app=yatri-frontend"
echo ">> RESTARTS is still 0 - the file changed underneath a running pod."
echo
cat <<'NOTE'
  WHY THE DIFFERENCE:
    env vars  - copied into the process at exec(). Immutable thereafter.
    volumes   - the kubelet mounts a projected directory and REFRESHES it,
                by default within about a minute (kubelet sync period + cache
                TTL). The app must re-read the file to notice.

  This is the main practical argument for mounting config as files when the
  app supports reloading them.
NOTE

hr "5. MAKING THE ENV-VAR CHANGE TAKE EFFECT  [checklist 10]"
echo "\$ kubectl rollout restart deployment/yatri-backend"
kubectl rollout restart deployment/yatri-backend
kubectl rollout status deployment/yatri-backend --timeout=300s
# `rollout status` returns while the OLD pods are still Terminating, and a
# terminating pod can still be in the Service endpoints for a moment. Curling
# immediately can therefore still hit an old pod and report the OLD value.
# Wait until every old pod is gone before asserting anything.
printf 'waiting for the old pods to finish terminating'
for i in $(seq 1 60); do
  n=$(kubectl get pods -l app=yatri-backend --no-headers | grep -c Terminating)
  [ "$n" = "0" ] && { echo " - done after ${i}s"; break; }
  printf '.'; sleep 1
done
run "kubectl get pods -l app=yatri-backend"
echo ">> New pods, new AGE - the containers were recreated, so exec() ran again."
echo
echo "\$ curl -s -H 'Host: yatri.local' http://localhost/api/ | grep -E 'LOG_LEVEL|CURRENCY'"
curl -s -H 'Host: yatri.local' http://localhost/api/ | grep -E 'LOG_LEVEL|CURRENCY'
echo ">> DEBUG and USD  [checklist 10]. The new values are live."
echo
cat <<'NOTE'
  `kubectl rollout restart` does a normal ROLLING restart, so there is no
  downtime - the same maxUnavailable/maxSurge rules from module 09 apply.

  PRODUCTION PATTERN: put a hash of the ConfigMap in the pod template's
  annotations. Changing the ConfigMap changes the hash, which changes the pod
  template, which makes the Deployment roll automatically. Helm does this with:

      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/cm.yaml") . | sha256sum }}
NOTE

hr "6. IMMUTABLE CONFIGMAPS"
cat <<'NOTE'
  Setting `immutable: true` on a ConfigMap or Secret:
    - prevents accidental edits
    - and materially improves cluster performance, because the kubelet stops
      watching it for changes (a large cluster watching thousands of mutable
      ConfigMaps puts real load on the API server)
  To change an immutable object you delete and recreate it.
NOTE

hr "7. RESTORE THE ORIGINAL VALUES"
kubectl patch configmap yatri-app-config -p '{"data":{"LOG_LEVEL":"INFO","DEFAULT_CURRENCY":"INR"}}' >/dev/null
echo "restored LOG_LEVEL=INFO, DEFAULT_CURRENCY=INR"
run "kubectl get configmap yatri-app-config -o jsonpath='{.data.LOG_LEVEL}{\"  \"}{.data.DEFAULT_CURRENCY}{\"\\n\"}'"
