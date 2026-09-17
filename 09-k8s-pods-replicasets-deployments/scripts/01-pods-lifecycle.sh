#!/usr/bin/env bash
# Module 09, part 1 — Pods, the pod lifecycle, and probes.
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-25}; }
M="$(cd "$(dirname "$0")/.." && pwd)/manifests"

kubectl delete pod --all --force --grace-period=0 >/dev/null 2>&1
sleep 2

hr "1. MULTI-CONTAINER POD — the sidecar pattern"
run "kubectl apply -f $M/pods/multi-container.yaml"
kubectl wait --for=condition=Ready pod/multi-container --timeout=180s
run "kubectl get pod multi-container"
echo ">> READY 2/2 — two containers in ONE pod."
run "kubectl get pod multi-container -o jsonpath='{range .spec.containers[*]}{.name}{\"\\n\"}{end}'"
echo
echo "--- the sidecar writes, the web container serves the same file ---"
run "kubectl logs multi-container -c writer --tail=2"
sleep 6
run "kubectl exec multi-container -c web -- cat /usr/share/nginx/html/index.html"
run "kubectl exec multi-container -c web -- curl -s http://localhost/"
echo ">> They share a VOLUME (emptyDir) and a NETWORK namespace, which is why"
echo ">> the web container reaches its own port on plain localhost."
run "kubectl get pod multi-container -o jsonpath='{.status.podIP}{\"\\n\"}'"
echo ">> ONE pod IP for both containers - that is the definition of a pod."

hr "2. INIT CONTAINERS — ordered setup before the app starts"
run "kubectl apply -f $M/pods/init-container.yaml"
sleep 4
echo "\$ kubectl get pod init-demo   (caught mid-initialisation)"
kubectl get pod init-demo 2>&1
kubectl wait --for=condition=Ready pod/init-demo --timeout=180s >/dev/null 2>&1
run "kubectl get pod init-demo"
run "kubectl logs init-demo -c init-1-fetch"
run "kubectl logs init-demo -c init-2-verify"
run "kubectl exec init-demo -- cat /usr/share/nginx/html/index.html"
echo ">> init-1 ran to completion, THEN init-2, THEN the app container."
echo ">> Init containers are how you wait for a database or fetch config"
echo ">> without putting that logic in your application image."

hr "3. POD LIFECYCLE — every phase, reproduced deliberately"

echo
echo "--- 3a. PENDING: the scheduler cannot place it ---"
run "kubectl apply -f $M/lifecycle/pending.yaml"
sleep 5
run "kubectl get pod lc-pending"
echo "\$ kubectl describe pod lc-pending | grep -A4 Events"
kubectl describe pod lc-pending 2>&1 | sed -n '/^Events:/,$p' | head -8
echo ">> 'Insufficient cpu' — the pod requests 500 CPUs and no node has that."
echo ">> PENDING always means: not yet scheduled, or image not yet pulled."

echo
echo "--- 3b. RUNNING ---"
run "kubectl get pod multi-container -o jsonpath='{.status.phase}{\"\\n\"}'"

echo
echo "--- 3c. SUCCEEDED: exits 0, restartPolicy Never ---"
run "kubectl apply -f $M/lifecycle/succeeded.yaml"
sleep 8
run "kubectl get pod lc-succeeded"
run "kubectl logs lc-succeeded"
echo ">> Completed / phase=Succeeded. A terminal state — it will not restart."

echo
echo "--- 3d. FAILED: exits non-zero, restartPolicy Never ---"
run "kubectl apply -f $M/lifecycle/failed.yaml"
sleep 8
run "kubectl get pod lc-failed"
run "kubectl get pod lc-failed -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}{\"\\n\"}'"
echo ">> Error / phase=Failed, exit code 1."

echo
echo "--- 3e. CRASHLOOPBACKOFF: keeps dying, keeps being restarted ---"
run "kubectl apply -f $M/lifecycle/crashloop.yaml"
echo "watching the restart count climb:"
for i in 1 2 3 4; do
  sleep 12
  printf '  t+%-3ss  ' "$((i*12))"
  kubectl get pod lc-crashloop --no-headers 2>&1 | awk '{printf "STATUS=%-18s RESTARTS=%s\n", $3, $4}'
done
run "kubectl logs lc-crashloop --tail=3"
echo "\$ kubectl describe pod lc-crashloop | grep -A5 Events"
kubectl describe pod lc-crashloop 2>&1 | sed -n '/^Events:/,$p' | head -9
echo ">> CrashLoopBackOff is NOT an error type - it is Kubernetes BACKING OFF."
echo ">> Restart delays double: 10s, 20s, 40s, 80s, 160s, capped at 5 minutes."
echo ">> The real error is in the LOGS, not in the status."

echo
echo "--- 3f. IMAGEPULLBACKOFF: the image tag does not exist ---"
run "kubectl apply -f $M/lifecycle/imagepull.yaml"
sleep 20
run "kubectl get pod lc-imagepull"
echo "\$ kubectl describe pod lc-imagepull | grep -A6 Events"
kubectl describe pod lc-imagepull 2>&1 | sed -n '/^Events:/,$p' | head -10
echo ">> Note the pod never reaches Running. ErrImagePull -> ImagePullBackOff."
echo ">> Causes: wrong tag, typo, private registry with no imagePullSecret."

echo
echo "--- summary of every phase created above ---"
run "kubectl get pods -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount"

hr "4. PROBES"
echo "--- 4a. all three probes on a healthy pod ---"
run "kubectl apply -f $M/probes/probes.yaml"
kubectl wait --for=condition=Ready pod/probe-demo --timeout=180s
run "kubectl get pod probe-demo"
run "kubectl get pod probe-demo -o jsonpath='{range .spec.containers[0]}startup={.startupProbe.httpGet.path} readiness={.readinessProbe.httpGet.path} liveness={.livenessProbe.httpGet.path}{end}{\"\\n\"}'"
echo
cat <<'NOTE'
  startupProbe    runs FIRST and alone; while it fails, the other two are
                  disabled. Gives a slow-booting app time WITHOUT weakening
                  the liveness probe forever.
  readinessProbe  "can this pod serve traffic right now?"
                  Failing -> removed from Service endpoints. NOT restarted.
  livenessProbe   "is this container wedged?"
                  Failing -> the kubelet KILLS and restarts the container.
NOTE

echo
echo "--- 4b. a FAILING LIVENESS probe restarts a perfectly healthy container ---"
run "kubectl apply -f $M/probes/failing-liveness.yaml"
for i in 1 2 3; do
  sleep 15
  printf '  t+%-3ss  ' "$((i*15))"
  kubectl get pod bad-liveness --no-headers 2>&1 | awk '{printf "STATUS=%-12s RESTARTS=%s\n", $3, $4}'
done
echo "\$ kubectl describe pod bad-liveness | grep -A4 Events"
kubectl describe pod bad-liveness 2>&1 | sed -n '/^Events:/,$p' | head -7
echo ">> nginx is fine. The PROBE is wrong, and it is killing the container."
echo ">> A bad liveness probe turns a healthy app into a restart loop - which is"
echo ">> why you should make liveness probes generous and readiness probes strict."

echo
echo "--- 4c. a FAILING READINESS probe does NOT restart anything ---"
run "kubectl apply -f $M/probes/failing-readiness.yaml"
sleep 20
run "kubectl get pod bad-readiness"
echo ">> Running, 0/1 READY, RESTARTS=0. The pod is alive but kept OUT of"
echo ">> Service endpoints, so it simply receives no traffic."
run "kubectl get endpoints -l app=readiness-test 2>/dev/null || echo '(no Service defined for it - see module 10)'"

hr "5. GRACEFUL TERMINATION — what 'kubectl delete pod' really does"
run "kubectl apply -f $M/lifecycle/termination.yaml"
kubectl wait --for=condition=Ready pod/lc-termination --timeout=180s
run "kubectl get pod lc-termination"
run "kubectl logs lc-termination"
echo
# Follow the logs in the background FIRST, otherwise the pod (and its logs)
# are gone by the time we could ask for them.
kubectl logs -f lc-termination > /tmp/termination.log 2>&1 &
LOGPID=$!
sleep 1
echo "\$ kubectl delete pod lc-termination     (timing the whole shutdown)"
START=$(date +%s)
kubectl delete pod lc-termination
END=$(date +%s)
kill $LOGPID 2>/dev/null
echo "deletion took $((END-START))s"
echo
echo "--- what the container logged while it was shutting down ---"
cat /tmp/termination.log
echo
echo ">> The preStop hook ran, THEN SIGTERM arrived, THEN the app drained for 5s"
echo ">> and exited 0 on its own - it was never SIGKILLed. Total ~9s, well inside"
echo ">> the 30s grace period."
echo
cat <<'NOTE'
  THE SEQUENCE Kubernetes runs on delete:

    1. pod marked Terminating, and REMOVED FROM SERVICE ENDPOINTS
       (this happens first, so no new traffic is routed to it)
    2. the preStop hook runs
    3. SIGTERM is sent to PID 1
    4. Kubernetes waits up to terminationGracePeriodSeconds (30s here)
    5. still alive? SIGKILL

  Steps 2 and 3 share the same grace period - a preStop that sleeps longer
  than the grace period leaves no time for SIGTERM handling at all.

  WHY preStop EXISTS: endpoint removal is eventually consistent. Every
  kube-proxy has to be told. A short preStop sleep covers that window so
  in-flight requests are not sent to a pod that has already shut down.

  THE COMMON BUG: if your app runs under a shell wrapper, the shell is PID 1
  and SIGTERM never reaches your process - the pod is SIGKILLed after the full
  grace period every time. Use 'exec' in your entrypoint, or a tiny init.
NOTE

hr "6. CLEAN UP"
run "kubectl delete pod --all --force --grace-period=0"
