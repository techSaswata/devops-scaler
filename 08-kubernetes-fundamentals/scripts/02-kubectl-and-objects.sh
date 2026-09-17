#!/usr/bin/env bash
# Module 08 — kubectl essentials, the object model, and the reconciliation loop.
set -u
hr(){ echo; echo "==================== $* ===================="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-25}; }

DIR="$(cd "$(dirname "$0")/.." && pwd)"
kubectl delete pod hello-pod nginx-imperative --ignore-not-found >/dev/null 2>&1
kubectl delete ns demo --ignore-not-found >/dev/null 2>&1

hr "1. IMPERATIVE vs DECLARATIVE"
echo "IMPERATIVE — you tell Kubernetes WHAT TO DO, step by step:"
run "kubectl run nginx-imperative --image=nginx:1.27-alpine"
run "kubectl get pod nginx-imperative"
echo
echo ">> Fine for a quick test. But there is no file, so nothing is reviewable,"
echo ">> version-controlled or repeatable."
echo
echo "DECLARATIVE — you describe the DESIRED STATE in a file and apply it:"
echo "\$ cat manifests/first-pod.yaml"
cat "$DIR/manifests/first-pod.yaml"
run "kubectl apply -f $DIR/manifests/first-pod.yaml"
echo
echo ">> This is the form that belongs in git, and the form to use everywhere."
echo ">> 'apply' is idempotent - run it twice and the second is a no-op:"
run "kubectl apply -f $DIR/manifests/first-pod.yaml"
echo ">> 'unchanged', not 'created' - Kubernetes diffed it and found nothing to do."

hr "2. WAIT FOR THE POD, THEN INSPECT IT"
kubectl wait --for=condition=Ready pod/hello-pod --timeout=180s
run "kubectl get pods"
run "kubectl get pod hello-pod -o wide"
echo
echo ">> The pod has its OWN IP (10.244.x.x) from the CNI, and a NODE it landed on."

hr "3. kubectl get — output formats"
run "kubectl get pod hello-pod"
run "kubectl get pod hello-pod -o yaml | head -25"
run "kubectl get pod hello-pod -o jsonpath='{.status.podIP}{\"\\n\"}'"
run "kubectl get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP,STATUS:.status.phase"
run "kubectl get pods --show-labels"
run "kubectl get pods -l app=hello"
echo ">> Label selectors are the backbone of Kubernetes - Services, ReplicaSets"
echo ">> and Deployments all find their pods this way (modules 09 and 10)."

hr "4. kubectl describe — the field-level view plus EVENTS"
echo "\$ kubectl describe pod hello-pod"
kubectl describe pod hello-pod 2>&1 | sed -n '1,20p'
echo "   ..."
kubectl describe pod hello-pod 2>&1 | sed -n '/^Events:/,$p' | head -12
echo
echo ">> The Events block is the first place to look when anything is wrong."
echo ">> Scheduled -> Pulling -> Pulled -> Created -> Started is the happy path."

hr "5. kubectl logs / exec / port-forward"
run "kubectl logs hello-pod --tail=5"
run "kubectl exec hello-pod -- nginx -v"
run "kubectl exec hello-pod -- hostname"
run "kubectl exec hello-pod -- curl -s -o /dev/null -w 'self HTTP %{http_code}\\n' http://localhost"
echo
echo "--- port-forward: reach a pod from the host without any Service ---"
kubectl port-forward pod/hello-pod 18080:80 >/dev/null 2>&1 &
PF=$!
sleep 3
echo "\$ kubectl port-forward pod/hello-pod 18080:80 &"
echo "\$ curl -s -o /dev/null -w 'HTTP %{http_code}\\n' http://localhost:18080/"
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 5 http://localhost:18080/
kill $PF 2>/dev/null
echo ">> Useful for debugging. NOT a substitute for a Service (module 10)."

hr "6. kubectl explain — the built-in API reference"
run "kubectl explain pod.spec.containers.resources | head -14"
echo
echo ">> No need to search the web for field names; the API server documents itself."

hr "7. THE RECONCILIATION LOOP — the single most important idea"
echo "A bare Pod has NO controller watching it. Delete it and it stays dead:"
run "kubectl delete pod nginx-imperative"
run "kubectl get pods"
echo
echo ">> 'nginx-imperative' is gone for good. Nothing is reconciling it."
echo ">> That is precisely why you use Deployments instead of bare Pods -"
echo ">> demonstrated in module 09."

hr "8. NAMESPACES IN PRACTICE"
run "kubectl create namespace demo"
run "kubectl run ns-test --image=nginx:1.27-alpine -n demo"
run "kubectl get pods -n demo"
echo
echo "--- the same name can exist in two namespaces without colliding ---"
run "kubectl get pods --all-namespaces -l run=ns-test"
echo
echo "--- objects are invisible across namespaces unless you ask ---"
run "kubectl get pods | grep ns-test || echo '(not visible in the default namespace)'"
run "kubectl delete namespace demo"
echo ">> Deleting a namespace deletes EVERYTHING inside it. Handle with care."

hr "9. CLEAN UP"
run "kubectl delete -f $DIR/manifests/first-pod.yaml"
run "kubectl get pods"
