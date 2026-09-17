#!/usr/bin/env bash
# Module 09, part 3 — blue-green, canary, DaemonSet, StatefulSet, troubleshooting.
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }
M="$(cd "$(dirname "$0")/.." && pwd)/manifests"
# A single long-lived client pod. Creating a throwaway pod per request (with
# `kubectl run --rm`) races with its own cleanup and prints deletion noise into
# the middle of the results, so one persistent client is both faster and clean.
CLIENT=net-client
hit(){ kubectl exec "$CLIENT" -- wget -qO- --timeout=3 "$1" 2>/dev/null | tr -d '\r\n'; }

kubectl delete deployment,rs,sts,ds,svc,pod --all --force --grace-period=0 >/dev/null 2>&1
kubectl delete pvc --all >/dev/null 2>&1
sleep 4

# bring up the client used for all in-cluster HTTP checks
kubectl run "$CLIENT" --image=busybox:1.36 --restart=Never -- sleep infinity >/dev/null 2>&1
kubectl wait --for=condition=Ready pod/"$CLIENT" --timeout=180s >/dev/null 2>&1

hr "1. BLUE-GREEN DEPLOYMENT"
run "kubectl apply -f $M/strategies/blue-green.yaml"
kubectl rollout status deployment/app-blue --timeout=240s
kubectl rollout status deployment/app-green --timeout=240s
run "kubectl get deployments -l app=bg-demo"
run "kubectl get pods -l app=bg-demo -L slot"
echo ">> BOTH versions are running at full capacity, at the same time."
echo
echo "--- the Service selector decides who gets traffic ---"
run "kubectl get svc bg-service -o jsonpath='{.spec.selector}{\"\\n\"}'"
echo
echo "\$ curl bg-service  (5 requests, currently pointing at BLUE)"
for i in 1 2 3 4 5; do
  printf '  request %d: ' "$i"; hit http://bg-service; echo
done
run "kubectl get endpoints bg-service"

echo
echo "--- THE CUTOVER: flip the selector from blue to green ---"
echo "\$ kubectl patch svc bg-service -p '{\"spec\":{\"selector\":{\"app\":\"bg-demo\",\"slot\":\"green\"}}}'"
kubectl patch svc bg-service -p '{"spec":{"selector":{"app":"bg-demo","slot":"green"}}}'
sleep 3
run "kubectl get svc bg-service -o jsonpath='{.spec.selector}{\"\\n\"}'"
echo
echo "\$ curl bg-service  (5 requests, now pointing at GREEN)"
for i in 1 2 3 4 5; do
  printf '  request %d: ' "$i"; hit http://bg-service; echo
done
run "kubectl get endpoints bg-service"
echo ">> Instant cutover with no pod restarts. Rollback is the same patch in"
echo ">> reverse and is equally instant, because BLUE is still running."
echo ">> The cost: you pay for double the capacity during the transition."
run "kubectl delete -f $M/strategies/blue-green.yaml"

hr "2. CANARY DEPLOYMENT"
run "kubectl apply -f $M/strategies/canary.yaml"
kubectl rollout status deployment/app-stable --timeout=240s
kubectl rollout status deployment/app-canary --timeout=240s
run "kubectl get deployments -l app=canary-demo"
run "kubectl get pods -l app=canary-demo -L track"
echo
echo "--- ONE Service selects BOTH, because it matches only app=canary-demo ---"
run "kubectl get svc canary-service -o jsonpath='{.spec.selector}{\"\\n\"}'"
run "kubectl get endpoints canary-service"
echo ">> 5 endpoints: 4 stable + 1 canary. Traffic splits by POD COUNT,"
echo ">> so 1 in 5 = roughly 20% reaches the canary."
echo
echo "\$ curl canary-service x20  (counting which version answers)"
STABLE=0; CANARY=0; OTHER=0
for i in $(seq 1 20); do
  r=$(hit http://canary-service)
  case "$r" in
    *STABLE*) STABLE=$((STABLE+1));;
    *CANARY*) CANARY=$((CANARY+1));;
    *)        OTHER=$((OTHER+1));;
  esac
done
echo "  STABLE: $STABLE / 20"
echo "  CANARY: $CANARY / 20   (expected ~4, i.e. 1 in 5)"
[ "$OTHER" -gt 0 ] && echo "  no reply: $OTHER / 20"
echo
echo "--- promote the canary: scale it up, scale stable down ---"
run "kubectl scale deployment app-canary --replicas=4"
run "kubectl scale deployment app-stable --replicas=0"
sleep 8
run "kubectl get pods -l app=canary-demo -L track"
run "kubectl get endpoints canary-service"
echo ">> Kubernetes splits canary traffic by REPLICA RATIO only. For percentage"
echo ">> control by header, cookie or weight you need an ingress controller or a"
echo ">> service mesh - plain Services cannot do it."
run "kubectl delete -f $M/strategies/canary.yaml"

hr "3. DAEMONSET — exactly one pod per node"
run "kubectl apply -f $M/workloads/daemonset.yaml"
sleep 12
run "kubectl get daemonset node-agent"
run "kubectl get pods -l app=node-agent -o wide"
echo
echo "--- one pod per SCHEDULABLE node; the control plane is tainted, so it is skipped ---"
run "kubectl get nodes --no-headers | wc -l"
run "kubectl get pods -l app=node-agent --no-headers | wc -l"
echo ">> You never set 'replicas' on a DaemonSet - the NODE COUNT decides."
echo ">> Add a node and a pod appears on it automatically."
run "kubectl logs -l app=node-agent --tail=1 --prefix"
echo ">> Each pod reports its own node via the downward API (spec.nodeName)."
echo ">> Real uses: log shippers (Fluent Bit), node exporters, CNI agents, CSI drivers."
run "kubectl delete -f $M/workloads/daemonset.yaml"

hr "4. STATEFULSET — stable identity and per-pod storage"
run "kubectl apply -f $M/workloads/statefulset.yaml"
echo
echo "--- pods are created IN ORDER, one at a time ---"
for i in 1 2 3 4 5 6; do
  printf '  t+%-3ss  ' "$((i*5))"
  kubectl get pods -l app=stateful-demo --no-headers 2>/dev/null | awk '{printf "%s(%s) ", $1, $3}'; echo
  sleep 5
done
kubectl rollout status statefulset/web --timeout=240s
run "kubectl get statefulset web"
run "kubectl get pods -l app=stateful-demo"
echo ">> Names are ORDINAL and STABLE: web-0, web-1, web-2 - not random suffixes."
echo ">> web-1 only starts after web-0 is Ready. Deletion happens in reverse."
echo
echo "--- each pod gets its OWN PersistentVolumeClaim ---"
run "kubectl get pvc"
echo ">> One PVC per pod, created from volumeClaimTemplates. If web-1 is deleted,"
echo ">> its replacement is still called web-1 and re-attaches to the SAME volume."
echo ">> That is the whole point: a Deployment's pods are interchangeable,"
echo ">> a StatefulSet's pods have identity."
echo
echo "--- prove identity survives deletion ---"
kubectl exec web-1 -- sh -c 'echo "data written by the original web-1" > /usr/share/nginx/html/index.html'
run "kubectl exec web-1 -- cat /usr/share/nginx/html/index.html"
echo "\$ kubectl delete pod web-1"
kubectl delete pod web-1
kubectl wait --for=condition=Ready pod/web-1 --timeout=240s
run "kubectl get pods -l app=stateful-demo"
run "kubectl exec web-1 -- cat /usr/share/nginx/html/index.html"
echo ">> Same name, same data. The new pod re-attached to web-1's own PVC."
run "kubectl delete -f $M/workloads/statefulset.yaml"
kubectl delete pvc --all >/dev/null 2>&1

hr "5. TROUBLESHOOTING"
echo "--- 5a. SELECTOR MISMATCH ---"
run "cat $M/troubleshooting/selector-mismatch.yaml"
echo "\$ kubectl apply -f selector-mismatch.yaml   (expected to FAIL)"
kubectl apply -f "$M/troubleshooting/selector-mismatch.yaml" 2>&1 | head -5
echo
echo ">> The API server REJECTS it up front: \`selector\` does not match the"
echo ">> template labels. Without that validation the ReplicaSet would create"
echo ">> pods it could never recognise, and would keep creating them forever."
echo ">> Fix: make spec.selector.matchLabels identical to the template labels."

echo
echo "--- 5b. BROKEN IMAGE inside a Deployment ---"
run "kubectl create deployment broken-image --image=nginx:no-such-tag-123"
sleep 20
run "kubectl get pods -l app=broken-image"
echo "\$ kubectl describe pod -l app=broken-image | grep -A6 Events"
kubectl describe pod -l app=broken-image 2>&1 | sed -n '/^Events:/,$p' | head -9
echo
echo ">> DIAGNOSIS ORDER that works every time:"
echo ">>   1. kubectl get pods            - what is the STATUS?"
echo ">>   2. kubectl describe pod <name> - read EVENTS at the bottom"
echo ">>   3. kubectl logs <name>         - if it started at all"
echo ">>   4. kubectl logs <name> --previous - if it is crash-looping"
run "kubectl delete deployment broken-image"

kubectl delete pod "$CLIENT" --force --grace-period=0 >/dev/null 2>&1

hr "6. FINAL STATE"
run "kubectl get all"
