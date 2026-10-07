#!/usr/bin/env bash
# Module 20, part 4 - THE FINAL TROUBLESHOOTING CHALLENGE.
#
# Applies troubleshooting/broken-stack.yaml, which contains six planted faults,
# and works through them in the order the CLUSTER reveals them -- not the order
# they appear in the file. Each one follows the same six steps the brief asks
# for: identify, investigate, root cause, fix, verify, document.
#
# The ordering matters and was discovered by running it, not assumed. Scheduling
# happens before image pull, image pull before container config, config before
# the probes, and the probes before anything about the Service. So the faults
# surface bottom-up through the stack, and each fix uncovers the next.
export PATH="/opt/homebrew/bin:$PATH"
set -u
hr(){ echo; echo "=== $* ==="; }
step(){ echo; echo "--- $* ---"; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | grep -v 'v1 Endpoints is deprecated' | head -${N:-30}; }
NS="-n finalproject-broken"
D="$(cd "$(dirname "$0")/.." && pwd)"

# The name of the one pod that is actually Running, ignoring the doomed
# ReplicaSets left behind by each failed rollout.
livepod(){ kubectl get pods $NS -l app=task-api --field-selector=status.phase=Running \
             -o jsonpath='{.items[0].metadata.name}' 2>/dev/null; }

# Ask the app itself, from inside the cluster, through a given URL.
getjson(){ kubectl exec "$(livepod)" $NS -- python -c "
import urllib.request,sys
try:
    print(urllib.request.urlopen('$1', timeout=6).read().decode())
except Exception as e:
    print('FAILED:', type(e).__name__, e)" 2>&1 | grep -v '^Defaulted'; }

hr "0. APPLY THE BROKEN STACK"
kubectl delete namespace finalproject-broken --ignore-not-found --wait=true >/dev/null 2>&1
run "kubectl apply -f $D/troubleshooting/broken-stack.yaml"
sleep 10

# ===========================================================================
hr "FAULT 1 of 6 - the pod never starts"
step "IDENTIFY"
run "kubectl get pods $NS"
echo ">> Pending. Not Running-and-broken: never scheduled onto a node at all."

step "INVESTIGATE"
run "kubectl describe pod -l app=task-api $NS | sed -n '/^Events:/,\$p'"

step "ROOT CAUSE"
echo "  FailedScheduling: 'Insufficient cpu' on the 2 workers, and the"
echo "  control-plane is excluded by its own taint. The container requests 16"
echo "  CPUs:"
run "kubectl get deploy task-api $NS -o jsonpath='requests: {.spec.template.spec.containers[0].resources.requests}{\"\\n\"}'"
run "kubectl get nodes -o custom-columns='NODE:.metadata.name,ALLOCATABLE_CPU:.status.allocatable.cpu' --no-headers"
echo "  6 allocatable per node < 16 requested. A request is a SCHEDULING"
echo "  contract: the scheduler will not overcommit it, so no node qualifies"
echo "  and the pod waits forever rather than starting and being throttled."

step "FIX"
run "kubectl patch deployment task-api $NS --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/resources/requests/cpu\",\"value\":\"100m\"},{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/resources/limits/cpu\",\"value\":\"500m\"}]'"
sleep 12

step "VERIFY"
run "kubectl get pods $NS"
echo ">> Scheduled now, and the next fault is already visible."

# ===========================================================================
hr "FAULT 2 of 6 - scheduled, but no image"
step "IDENTIFY"
run "kubectl get pods $NS --field-selector=status.phase!=Succeeded"
echo ">> ErrImagePull / ImagePullBackOff on the new ReplicaSet's pod."

step "INVESTIGATE"
run "kubectl describe pod $NS -l app=task-api | grep -E 'Failed to pull|Error: Err|Back-off' | head -4"

step "ROOT CAUSE"
run "kubectl get deploy task-api $NS -o jsonpath='image: {.spec.template.spec.containers[0].image}{\"\\n\"}'"
echo "  Tag 1.0.1 was never built. Only task-api:1.0.0 was imported into the"
echo "  nodes:"
run "docker exec devops-hw-worker crictl images 2>/dev/null | grep -E 'IMAGE|task-api'"
echo "  A bare name with no registry is resolved as docker.io/library/task-api,"
echo "  so the kubelet asks Docker Hub for a repository that does not exist --"
echo "  which is why the error says 'pull access denied' rather than 'no such"
echo "  tag'. Hub will not confirm the absence of a private-looking repo."

step "FIX"
run "kubectl set image deployment/task-api api=task-api:1.0.0 $NS"
sleep 12

step "VERIFY"
run "kubectl get pods $NS --field-selector=status.phase!=Succeeded"

# ===========================================================================
hr "FAULT 3 of 6 - image pulled, container will not be created"
step "IDENTIFY"
echo ">> CreateContainerConfigError. The image is fine; the kubelet cannot"
echo ">> assemble the container's configuration."

step "INVESTIGATE"
run "kubectl describe pod $NS -l app=task-api | grep -E 'Error:|Warning' | head -5"

step "ROOT CAUSE"
run "kubectl get deploy task-api $NS -o jsonpath='envFrom: {.spec.template.spec.containers[0].envFrom}{\"\\n\"}'"
run "kubectl get secret $NS"
echo "  The Deployment pulls its environment from a Secret named"
echo "  task-api-secret, and no such Secret exists in this namespace. A"
echo "  secretRef is REQUIRED unless marked optional:true, so the kubelet"
echo "  refuses to start the container rather than running it with the"
echo "  credentials silently missing. That is the right default."

step "FIX"
echo "\$ kubectl create secret generic task-api-secret --from-literal=..."
kubectl $NS create secret generic task-api-secret \
  --from-literal=DB_PASSWORD='supplied-at-deploy-time' \
  --from-literal=API_KEY='supplied-at-deploy-time' 2>&1
sleep 25

step "VERIFY"
run "kubectl get pods $NS --field-selector=status.phase!=Succeeded"
echo ">> Running at last -- but 0/1 READY. Not the same thing."

# ===========================================================================
hr "FAULT 4 of 6 - Running, but never Ready"
step "IDENTIFY"
run "kubectl get pods $NS -l app=task-api --field-selector=status.phase=Running"
echo ">> STATUS Running with READY 0/1. The process is up; Kubernetes is"
echo ">> refusing to call it serviceable."

step "INVESTIGATE"
run "kubectl describe pod $(kubectl get pods -n finalproject-broken -l app=task-api --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}') $NS | grep -i 'readiness probe' | head -3"

step "ROOT CAUSE"
run "kubectl get deploy task-api $NS -o jsonpath='readiness path: {.spec.template.spec.containers[0].readinessProbe.httpGet.path}{\"\\n\"}'"
echo "  The probe asks for /healthz. This app serves /health and /ready --"
echo "  /healthz is Go-ecosystem convention, not this application's API. The"
echo "  404 counts as a probe failure, so the pod is held out of the Service"
echo "  endpoints. Proof the app itself is healthy on its real paths:"
echo
echo "\$ GET /health  from inside the pod"
getjson "http://localhost:8000/health"
echo "\$ GET /healthz from inside the pod"
getjson "http://localhost:8000/healthz"
echo ">> The probe was right to fail. The PATH was wrong, not the app."

step "FIX"
run "kubectl patch deployment task-api $NS --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/readinessProbe/httpGet/path\",\"value\":\"/ready\"}]'"
sleep 25

step "VERIFY"
run "kubectl get pods $NS -l app=task-api --field-selector=status.phase=Running"
echo ">> 1/1 READY."

# ===========================================================================
hr "FAULT 5 of 6 - a healthy pod that nothing can reach"
step "IDENTIFY"
echo "\$ GET / through the Service DNS name"
getjson "http://task-api.finalproject-broken.svc.cluster.local/"
echo ">> Name resolves, connection goes nowhere. The pod is 1/1 Ready."

step "INVESTIGATE"
run "kubectl get endpoints task-api $NS"
echo ">> ENDPOINTS <none>. The Service has no backends, so there is nothing"
echo ">> for kube-proxy to forward to. Compare what it SELECTS with what the"
echo ">> pod actually CARRIES:"
run "kubectl get svc task-api $NS -o jsonpath='service selector: {.spec.selector}{\"\\n\"}'"
run "kubectl get pod $(kubectl get pods -n finalproject-broken -l app=task-api --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}') $NS -o jsonpath='pod labels:       {.metadata.labels}{\"\\n\"}'"

step "ROOT CAUSE"
echo "  selector app=taskapi, label app=task-api. One hyphen. A Service builds"
echo "  its endpoint list purely by label match, and there is no warning event"
echo "  for a selector that matches nothing -- the Service is reported as"
echo "  perfectly healthy. This is why 'the pod is Running' is never enough"
echo "  evidence that a service works."

step "FIX"
run "kubectl patch svc task-api $NS --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/selector/app\",\"value\":\"task-api\"}]'"
sleep 6

step "VERIFY"
run "kubectl get endpoints task-api $NS"
echo ">> An endpoint exists now. Read the PORT on it before celebrating."

# ===========================================================================
hr "FAULT 6 of 6 - endpoints exist, connection refused"
step "IDENTIFY"
echo "\$ GET / through the Service DNS name"
getjson "http://task-api.finalproject-broken.svc.cluster.local/"
echo ">> Connection refused -- a different failure from fault 5. Refused means"
echo ">> something routed us to an address and nothing was listening there."

step "INVESTIGATE"
run "kubectl get endpoints task-api $NS"
run "kubectl get svc task-api $NS -o jsonpath='port: {.spec.ports[0].port}  targetPort: {.spec.ports[0].targetPort}{\"\\n\"}'"
run "kubectl get deploy task-api $NS -o jsonpath='containerPort: {.spec.template.spec.containers[0].ports[0].containerPort}  name: {.spec.template.spec.containers[0].ports[0].name}{\"\\n\"}'"

step "ROOT CAUSE"
echo "  The endpoint is :8080; the container listens on :8000. targetPort was"
echo "  hard-coded to 8080 and matches nothing. Proof that the app is fine and"
echo "  only the Service's target is wrong:"
echo
echo "\$ GET / on the pod's REAL port, 8000"
getjson "http://localhost:8000/"
echo ">> The app answers. The Service was pointing at a port nobody opened."

step "FIX"
echo "  Fixed by NAME rather than by number. The container declares"
echo "  'name: http' on its port, so targetPort: http follows the container if"
echo "  the number ever changes -- the whole reason named ports exist."
run "kubectl patch svc task-api $NS --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/ports/0/targetPort\",\"value\":\"http\"}]'"
sleep 6

step "VERIFY"
run "kubectl get endpoints task-api $NS"
echo "\$ GET / through the Service DNS name"
getjson "http://task-api.finalproject-broken.svc.cluster.local/"
echo "\$ GET /ready"
getjson "http://task-api.finalproject-broken.svc.cluster.local/ready"
echo "\$ POST /tasks then GET /tasks"
kubectl exec "$(livepod)" $NS -- python -c "
import json,urllib.request
u='http://task-api.finalproject-broken.svc.cluster.local/tasks'
r=urllib.request.Request(u,data=json.dumps({'title':'all six faults fixed'}).encode(),headers={'Content-Type':'application/json'})
print(urllib.request.urlopen(r,timeout=6).read().decode())
print(urllib.request.urlopen(u,timeout=6).read().decode())" 2>&1 | grep -v '^Defaulted'

hr "FINAL STATE - all six fixed"
run "kubectl get pods,svc,endpoints $NS"
echo
echo ">> Six faults, six different diagnostic surfaces:"
echo ">>   1  scheduler events      Pending / Insufficient cpu"
echo ">>   2  kubelet events        ErrImagePull"
echo ">>   3  kubelet events        CreateContainerConfigError"
echo ">>   4  probe events          Running but 0/1 READY"
echo ">>   5  endpoint list         Ready pod, no endpoints (label mismatch)"
echo ">>   6  endpoint PORT         endpoints present, connection refused"
echo ">>"
echo ">> None of them was found by reading the manifest. Each was found from"
echo ">> the cluster's own account of what it was refusing to do."

hr "CLEANUP"
# Every fix above was an imperative patch against the live object, so the
# namespace is now out of step with the file on disk. Deleting it means the
# next run starts from the same broken state rather than a half-fixed one.
run "kubectl delete namespace finalproject-broken --wait=true"
