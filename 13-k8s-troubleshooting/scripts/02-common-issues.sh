#!/usr/bin/env bash
# Module 13, part 2 — the nine common failures (Session 14, Task 2).
# For each: identify -> investigate -> root cause -> fix -> verify.
set -u
hr(){ echo; echo "=== $* ==="; }
sub(){ echo; echo "--- $* ---"; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-22}; }
M="$(cd "$(dirname "$0")/.." && pwd)/manifests"

cleanup(){
  kubectl delete pod,deploy,svc -l drill=troubleshooting --force --grace-period=0 >/dev/null 2>&1
  kubectl delete pod ts-crashloop ts-crashloop-fixed ts-imagepull ts-imagepull-fixed \
    ts-pending ts-pending-fixed ts-pending-pvc ts-containercreating ts-config-error \
    --force --grace-period=0 >/dev/null 2>&1
  kubectl delete deploy ts-web --ignore-not-found >/dev/null 2>&1
  kubectl delete svc ts-web-svc ts-web-badport --ignore-not-found >/dev/null 2>&1
  kubectl delete pvc ts-bad-pvc --ignore-not-found >/dev/null 2>&1
  kubectl delete cm ts-app-config ts-partial-config --ignore-not-found >/dev/null 2>&1
  kubectl delete secret ts-missing-secret --ignore-not-found >/dev/null 2>&1
}
cleanup; sleep 3

############################################################
hr "ISSUE 1 of 9 — CrashLoopBackOff"
sub "IDENTIFY"
kubectl apply -f "$M/01-crashloopbackoff.yaml" >/dev/null
sleep 45
run "kubectl get pod ts-crashloop"
sub "INVESTIGATE"
run "kubectl describe pod ts-crashloop | sed -n '/Events:/,\$p' | head -9"
echo ">> Events say 'Back-off restarting failed container' - that is the SYMPTOM."
echo ">> It never says WHY. For that, read the logs."
run "kubectl logs ts-crashloop --tail=4"
run "kubectl logs ts-crashloop --previous --tail=4"
run "kubectl get pod ts-crashloop -o jsonpath='lastState.terminated.exitCode={.status.containerStatuses[0].lastState.terminated.exitCode}  reason={.status.containerStatuses[0].lastState.terminated.reason}{\"\\n\"}'"
sub "ROOT CAUSE"
echo "The application exits 1 because /etc/app/config.yaml is missing."
echo "Exit code 1 = application error (not 137=OOMKilled, not 143=SIGTERM)."
sub "FIX + VERIFY"
kubectl apply -f "$M/01-crashloopbackoff-fixed.yaml" >/dev/null
kubectl wait --for=condition=Ready pod/ts-crashloop-fixed --timeout=180s >/dev/null 2>&1
run "kubectl get pod ts-crashloop-fixed"
run "kubectl logs ts-crashloop-fixed"
echo ">> Running, 0 restarts, config found."

############################################################
hr "ISSUE 2 of 9 — ImagePullBackOff / ErrImagePull"
sub "IDENTIFY"
kubectl apply -f "$M/02-imagepullbackoff.yaml" >/dev/null
sleep 35
run "kubectl get pod ts-imagepull"
sub "INVESTIGATE"
run "kubectl describe pod ts-imagepull | sed -n '/Events:/,\$p' | head -9"
run "kubectl get pod ts-imagepull -o jsonpath='state={.status.containerStatuses[0].state.waiting.reason}  msg={.status.containerStatuses[0].state.waiting.message}{\"\\n\"}'"
sub "ROOT CAUSE"
echo "The tag nginx:1.27-alpine-this-tag-does-not-exist is not in the registry."
echo "ErrImagePull is the first failure; ImagePullBackOff is the retry backoff."
echo "Other causes: a typo in the image name, a private registry with no"
echo "imagePullSecret, or rate limiting from Docker Hub."
sub "FIX + VERIFY"
kubectl apply -f "$M/02-imagepullbackoff-fixed.yaml" >/dev/null
kubectl wait --for=condition=Ready pod/ts-imagepull-fixed --timeout=180s >/dev/null 2>&1
run "kubectl get pod ts-imagepull-fixed"

############################################################
hr "ISSUE 3 of 9 — Pending (unschedulable: insufficient resources)"
sub "IDENTIFY"
kubectl apply -f "$M/03-pending.yaml" >/dev/null
sleep 12
run "kubectl get pod ts-pending"
echo ">> Note: no NODE assigned, and it is Pending rather than ContainerCreating."
sub "INVESTIGATE"
run "kubectl describe pod ts-pending | sed -n '/Events:/,\$p' | head -7"
run "kubectl get pod ts-pending -o jsonpath='requested cpu={.spec.containers[0].resources.requests.cpu}{\"\\n\"}'"
run "kubectl get nodes -o custom-columns=NODE:.metadata.name,ALLOCATABLE_CPU:.status.allocatable.cpu --no-headers"
sub "ROOT CAUSE"
echo "The pod requests 64 CPUs. No node has that much allocatable, so the"
echo "scheduler filters out every node and the pod stays unscheduled."
sub "FIX + VERIFY"
kubectl apply -f "$M/03-pending-fixed.yaml" >/dev/null
kubectl wait --for=condition=Ready pod/ts-pending-fixed --timeout=180s >/dev/null 2>&1
run "kubectl get pod ts-pending-fixed -o wide"

############################################################
hr "ISSUE 4 of 9 — Pending (a DIFFERENT cause: unbound PVC)"
sub "IDENTIFY"
kubectl apply -f "$M/04-pending-pvc.yaml" >/dev/null
sleep 12
run "kubectl get pod ts-pending-pvc"
echo ">> Also Pending - but for a completely different reason. This is why you"
echo ">> never stop at the STATUS; always read the events."
sub "INVESTIGATE"
run "kubectl describe pod ts-pending-pvc | sed -n '/Events:/,\$p' | head -6"
run "kubectl get pvc ts-bad-pvc"
run "kubectl describe pvc ts-bad-pvc | sed -n '/Events:/,\$p' | head -6"
run "kubectl get storageclass"
sub "ROOT CAUSE"
echo "The PVC names storageClassName: nonexistent-storage-class, which does not"
echo "exist. The claim can never bind, so the pod can never be scheduled."
sub "FIX + VERIFY"
echo "\$ recreate the PVC with storageClassName: standard"
kubectl delete pod ts-pending-pvc --force --grace-period=0 >/dev/null 2>&1
kubectl delete pvc ts-bad-pvc >/dev/null 2>&1
sed 's/nonexistent-storage-class/standard/' "$M/04-pending-pvc.yaml" | kubectl apply -f - >/dev/null
kubectl wait --for=condition=Ready pod/ts-pending-pvc --timeout=240s >/dev/null 2>&1
run "kubectl get pvc ts-bad-pvc"
run "kubectl get pod ts-pending-pvc"

############################################################
hr "ISSUE 5 of 9 — ContainerCreating (stuck)"
sub "IDENTIFY"
kubectl apply -f "$M/05-containercreating.yaml" >/dev/null
sleep 20
run "kubectl get pod ts-containercreating"
echo ">> ContainerCreating, NOT Pending: the pod WAS scheduled onto a node."
echo ">> The kubelet is now stuck trying to set it up."
sub "INVESTIGATE"
run "kubectl describe pod ts-containercreating | sed -n '/Events:/,\$p' | head -7"
run "kubectl get secret ts-missing-secret 2>&1 | head -3"
sub "ROOT CAUSE"
echo "The pod mounts a Secret named ts-missing-secret that does not exist."
echo "The kubelet retries the mount forever."
echo "Same symptom, other causes: an unattachable volume, or a CNI failure."
sub "FIX + VERIFY"
echo "\$ kubectl create secret generic ts-missing-secret --from-literal=token=abc123"
kubectl create secret generic ts-missing-secret --from-literal=token=abc123
for i in $(seq 1 30); do
  s=$(kubectl get pod ts-containercreating --no-headers 2>/dev/null | awk '{print $3}')
  [ "$s" = "Running" ] && { echo "  Running after $((i*5))s - no pod recreation needed"; break; }
  [ "$i" = "30" ] && echo "  still $s after 150s"
  sleep 5
done
run "kubectl get pod ts-containercreating"
echo ">> The kubelet's next retry succeeded. Creating the missing object was"
echo ">> enough; the pod did not have to be deleted."

############################################################
hr "ISSUE 6 of 9 — Service connectivity (selector mismatch)"
sub "IDENTIFY"
kubectl apply -f "$M/06-service-connectivity.yaml" >/dev/null
kubectl rollout status deployment/ts-web --timeout=240s >/dev/null 2>&1
kubectl run ts-client --image=busybox:1.36 --labels=drill=troubleshooting --restart=Never -- sleep infinity >/dev/null 2>&1
kubectl wait --for=condition=Ready pod/ts-client --timeout=180s >/dev/null 2>&1
run "kubectl get svc ts-web-svc"
echo "\$ kubectl exec ts-client -- wget -qO- --timeout=3 http://ts-web-svc"
kubectl exec ts-client -- wget -qO- --timeout=3 http://ts-web-svc 2>&1 | head -3
echo ">> No response. But the Service exists and has a ClusterIP."
sub "INVESTIGATE"
run "kubectl get endpoints ts-web-svc"
echo ">> ENDPOINTS is empty. ALWAYS check this first for Service problems."
run "kubectl get svc ts-web-svc -o jsonpath='service selector: {.spec.selector}{\"\\n\"}'"
run "kubectl get pods -l app=ts-web -o jsonpath='pod labels:      {.items[0].metadata.labels}{\"\\n\"}'"
sub "ROOT CAUSE"
echo "The Service selects app=ts-webserver; the pods are labelled app=ts-web."
echo "No pod matches, so the endpoints list is empty and nothing can be routed."
sub "FIX + VERIFY"
echo "\$ kubectl patch svc ts-web-svc -p '{\"spec\":{\"selector\":{\"app\":\"ts-web\"}}}'"
kubectl patch svc ts-web-svc -p '{"spec":{"selector":{"app":"ts-web"}}}' >/dev/null
sleep 4
run "kubectl get endpoints ts-web-svc"
echo "\$ kubectl exec ts-client -- wget -qO- --timeout=3 http://ts-web-svc | head -4"
kubectl exec ts-client -- wget -qO- --timeout=3 http://ts-web-svc 2>/dev/null | head -4

############################################################
hr "ISSUE 7 of 9 — Service connectivity (wrong targetPort)"
sub "IDENTIFY"
kubectl apply -f "$M/07-wrong-targetport.yaml" >/dev/null
sleep 4
run "kubectl get svc ts-web-badport"
run "kubectl get endpoints ts-web-badport"
echo ">> ENDPOINTS IS POPULATED this time - so the selector is fine."
echo "\$ kubectl exec ts-client -- wget -qO- --timeout=3 http://ts-web-badport"
kubectl exec ts-client -- wget -qO- --timeout=3 http://ts-web-badport 2>&1 | head -3
echo ">> ...and yet it still fails. A very different bug with the same symptom."
sub "INVESTIGATE"
run "kubectl get svc ts-web-badport -o jsonpath='port={.spec.ports[0].port}  targetPort={.spec.ports[0].targetPort}{\"\\n\"}'"
run "kubectl get pods -l app=ts-web -o jsonpath='containerPort={.items[0].spec.containers[0].ports[0].containerPort}{\"\\n\"}'"
echo "\$ kubectl exec ts-client -- wget -qO- --timeout=2 http://<podIP>:80   (direct)"
PODIP=$(kubectl get pods -l app=ts-web -o jsonpath='{.items[0].status.podIP}')
kubectl exec ts-client -- wget -qO- --timeout=2 "http://$PODIP:80" 2>/dev/null | head -2
echo ">> The pod answers on 80. So the pod is fine and the Service is misrouting."
sub "ROOT CAUSE"
echo "targetPort is 8080, but nginx listens on 80. The endpoints exist, traffic"
echo "is forwarded, and nothing is listening at the other end."
sub "FIX + VERIFY"
kubectl patch svc ts-web-badport --type=json -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":80}]' >/dev/null
sleep 4
echo "\$ kubectl exec ts-client -- wget -qO- --timeout=3 http://ts-web-badport | head -4"
kubectl exec ts-client -- wget -qO- --timeout=3 http://ts-web-badport 2>/dev/null | head -4

############################################################
hr "ISSUE 8 of 9 — DNS resolution"
sub "IDENTIFY"
echo "\$ kubectl exec ts-client -- wget -qO- --timeout=3 http://ts-web-svc.wrong-namespace"
kubectl exec ts-client -- wget -qO- --timeout=3 http://ts-web-svc.wrong-namespace 2>&1 | head -3
sub "INVESTIGATE"
run "kubectl get pods -n kube-system -l k8s-app=kube-dns"
echo ">> CoreDNS is Running, so DNS itself is up."
run "kubectl exec ts-client -- cat /etc/resolv.conf"
echo "\$ kubectl exec ts-client -- nslookup ts-web-svc.default.svc.cluster.local"
kubectl exec ts-client -- nslookup ts-web-svc.default.svc.cluster.local 2>&1 | grep -A1 '^Name:' | head -4
sub "ROOT CAUSE"
echo "The name resolves fine in the CORRECT namespace. 'wrong-namespace' does"
echo "not exist, so the FQDN ts-web-svc.wrong-namespace.svc.cluster.local has"
echo "no record. The search list only appends the POD's own namespace."
sub "FIX + VERIFY"
echo "\$ use the right FQDN: <service>.<namespace>.svc.cluster.local"
kubectl exec ts-client -- wget -qO- --timeout=3 http://ts-web-svc.default.svc.cluster.local 2>/dev/null | head -3
echo
echo ">> DNS TRIAGE ORDER: 1) are the CoreDNS pods Running?"
echo ">>                   2) does /etc/resolv.conf point at the kube-dns ClusterIP?"
echo ">>                   3) does the FULL FQDN resolve?"
echo ">>                   4) kubectl logs -n kube-system -l k8s-app=kube-dns"

############################################################
hr "ISSUE 9 of 9 — Configuration error (missing ConfigMap key)"
sub "IDENTIFY"
kubectl apply -f "$M/08-config-error.yaml" >/dev/null
sleep 20
run "kubectl get pod ts-config-error"
echo ">> CreateContainerConfigError - distinct from CrashLoopBackOff. The"
echo ">> container was never even created."
sub "INVESTIGATE"
run "kubectl describe pod ts-config-error | sed -n '/Events:/,\$p' | head -7"
run "kubectl get configmap ts-partial-config -o jsonpath='keys present: {.data}{\"\\n\"}'"
run "kubectl get pod ts-config-error -o jsonpath='key requested: {.spec.containers[0].env[0].valueFrom.configMapKeyRef.key}{\"\\n\"}'"
sub "ROOT CAUSE"
echo "The pod references key ABSENT_KEY; the ConfigMap only contains PRESENT_KEY."
sub "FIX + VERIFY"
echo "\$ kubectl patch configmap ts-partial-config -p '{\"data\":{\"ABSENT_KEY\":\"now-present\"}}'"
kubectl patch configmap ts-partial-config -p '{"data":{"ABSENT_KEY":"now-present"}}' >/dev/null
for i in $(seq 1 30); do
  s=$(kubectl get pod ts-config-error --no-headers 2>/dev/null | awk '{print $3}')
  [ "$s" = "Running" ] && { echo "  Running after $((i*5))s"; break; }
  [ "$i" = "30" ] && echo "  still $s after 150s"
  sleep 5
done
run "kubectl get pod ts-config-error"
run "kubectl exec ts-config-error -- printenv MISSING"

hr "SUMMARY — symptom to cause"
cat <<'NOTE'

  STATUS                         FIRST THING TO CHECK          USUAL CAUSE
  ----------------------------   ---------------------------   ----------------------------
  Pending                        describe -> Events            unschedulable: resources,
                                                               taints, or an unbound PVC
  ContainerCreating (stuck)      describe -> Events            missing Secret/ConfigMap,
                                                               volume or CNI failure
  ErrImagePull / ImagePullBackOff describe -> Events           bad tag, typo, no pull secret
  CrashLoopBackOff               logs --previous               the app itself is exiting
  CreateContainerConfigError     describe -> Events            missing ConfigMap/Secret KEY
  Running but 0/1 READY          describe -> readiness probe   probe failing
  Running, OOMKilled restarts    get -o yaml -> lastState      memory limit too low
  Service refuses connections    get endpoints                 selector mismatch (empty),
                                                               or wrong targetPort (populated)
  DNS name not found             nslookup the FULL FQDN        wrong namespace in the name

  THE ONE RULE: the STATUS tells you the symptom, the EVENTS tell you the cause,
  and the LOGS tell you what the application thought. Issues 6 and 7 above are
  the proof - identical symptom, completely different bug, and the thing that
  separates them is `kubectl get endpoints`.
NOTE
cleanup
