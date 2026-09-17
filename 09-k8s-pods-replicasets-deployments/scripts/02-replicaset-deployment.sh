#!/usr/bin/env bash
# Module 09, part 2 — ReplicaSets, Deployments and rollouts.
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }
M="$(cd "$(dirname "$0")/.." && pwd)/manifests"

kubectl delete deployment,replicaset,pod --all --force --grace-period=0 >/dev/null 2>&1
sleep 3

hr "1. REPLICASET — desired state and self-healing"
run "cat $M/replicaset/backend-rs.yaml"
run "kubectl apply -f $M/replicaset/backend-rs.yaml"
kubectl wait --for=jsonpath='{.status.readyReplicas}'=3 rs/backend-rs --timeout=180s
run "kubectl get rs backend-rs"
run "kubectl get pods -l app=backend"
echo ">> Pod names are <rs-name>-<random>. They are INTERCHANGEABLE."

echo
echo "--- SELF-HEALING: delete a pod and watch the controller replace it ---"
VICTIM=$(kubectl get pods -l app=backend -o jsonpath='{.items[0].metadata.name}')
echo "\$ kubectl delete pod $VICTIM"
kubectl delete pod "$VICTIM"
sleep 4
run "kubectl get pods -l app=backend"
echo ">> Still 3 pods. The ReplicaSet controller noticed actual(2) != desired(3)"
echo ">> and created a replacement. Note the NEW pod has a different name and AGE."
echo ">> Compare with the bare Pod in module 08, which stayed deleted forever."

echo
echo "--- the link is the LABEL SELECTOR, nothing else ---"
run "kubectl get rs backend-rs -o jsonpath='{.spec.selector.matchLabels}{\"\\n\"}'"
echo "\$ kubectl label pod <one-pod> app=orphaned --overwrite   (steal a pod from the RS)"
ORPHAN=$(kubectl get pods -l app=backend -o jsonpath='{.items[0].metadata.name}')
kubectl label pod "$ORPHAN" app=orphaned --overwrite
sleep 4
run "kubectl get pods -L app"
echo ">> Relabelling a pod ORPHANS it: the ReplicaSet no longer matches it, so it"
echo ">> creates yet another pod to get back to 3. The orphan keeps running,"
echo ">> now owned by nobody. Labels are the ONLY link between controller and pod."
kubectl delete pod "$ORPHAN" --force --grace-period=0 >/dev/null 2>&1

run "kubectl scale rs backend-rs --replicas=5"
sleep 5
run "kubectl get rs backend-rs"
run "kubectl delete rs backend-rs"

hr "2. DEPLOYMENT — the ownership chain"
run "kubectl apply -f $M/deployment/web-v1.yaml"
kubectl rollout status deployment/web --timeout=240s
run "kubectl get deployment web"
run "kubectl get rs -l app=web"
run "kubectl get pods -l app=web"
echo
echo "--- Deployment -> ReplicaSet -> Pod, proved by ownerReferences ---"
POD=$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')
RS=$(kubectl get pod "$POD" -o jsonpath='{.metadata.ownerReferences[0].name}')
echo "pod  $POD"
echo "  owned by ReplicaSet  -> $RS"
echo "     owned by Deployment -> $(kubectl get rs "$RS" -o jsonpath='{.metadata.ownerReferences[0].name}')"
echo
echo ">> You manage the Deployment. It manages ReplicaSets. They manage Pods."
echo ">> A Deployment adds exactly one thing over a ReplicaSet: ROLLOUT HISTORY."

hr "3. ROLLING UPDATE"
run "kubectl get deployment web -o jsonpath='{.spec.strategy}{\"\\n\"}'"
echo ">> maxUnavailable:1 = never more than 1 pod down."
echo ">> maxSurge:1       = never more than 1 extra pod above the 4 desired."
echo ">> Capacity therefore stays between 3 and 5 - so there is NO downtime."
echo
echo "\$ kubectl apply -f web-v2.yaml   (nginx 1.27 -> 1.28)"
kubectl apply -f "$M/deployment/web-v2.yaml"
echo "\$ kubectl rollout status deployment/web"
kubectl rollout status deployment/web --timeout=240s
echo
run "kubectl get rs -l app=web"
echo ">> TWO ReplicaSets now: the old one scaled to 0, the new one to 4."
echo ">> The old RS is KEPT - that is what makes rollback instant."
run "kubectl get pods -l app=web -L version"
run "kubectl describe deployment web | sed -n '/^Events:/,\$p' | head -8"

hr "4. ROLLOUT HISTORY AND ROLLBACK"
run "kubectl rollout history deployment/web"
run "kubectl rollout history deployment/web --revision=2"
echo
echo "\$ kubectl rollout undo deployment/web"
kubectl rollout undo deployment/web
kubectl rollout status deployment/web --timeout=240s
run "kubectl get pods -l app=web -L version"
echo ">> Back on v1. Kubernetes just scaled the OLD ReplicaSet back up - it did"
echo ">> not pull or rebuild anything, which is why rollback is near-instant."
run "kubectl rollout history deployment/web"
echo ">> Note revision numbers only ever increase; the rollback became revision 3."

hr "5. A FAILED ROLLOUT DOES NOT TAKE THE SERVICE DOWN"
echo "\$ kubectl apply -f web-v3-broken.yaml   (image tag does not exist)"
kubectl apply -f "$M/deployment/web-v3-broken.yaml"
sleep 25
run "kubectl get deployment web"
run "kubectl get pods -l app=web"
OLD_OK=$(kubectl get pods -l app=web --no-headers | grep -c " Running")
BAD=$(kubectl get pods -l app=web --no-headers | grep -c "ImagePull\|ErrImage")
echo ">> $BAD new pods are stuck pulling an image that does not exist, but"
echo ">> $OLD_OK OLD pods are still Running and serving traffic."
echo ">> That number is exactly replicas(4) - maxUnavailable(1) = 3: the rollout"
echo ">> is allowed to take down ONE healthy pod and no more, so it stalls here"
echo ">> instead of destroying the working release."
echo
echo "\$ kubectl rollout status deployment/web --timeout=20s   (will report the stall)"
kubectl rollout status deployment/web --timeout=20s 2>&1 | head -3
run "kubectl get rs -l app=web"
echo
echo "\$ kubectl rollout undo deployment/web   (abandon the bad release)"
kubectl rollout undo deployment/web
kubectl rollout status deployment/web --timeout=240s
run "kubectl get pods -l app=web"
echo ">> Recovered. THIS is why you use a Deployment with a readiness probe."
run "kubectl delete deployment web"

hr "6. RECREATE STRATEGY — deliberate downtime"
run "kubectl apply -f $M/strategies/recreate-v1.yaml"
kubectl rollout status deployment/recreate-demo --timeout=240s
run "kubectl get pods -l app=recreate-demo"
echo
echo "\$ kubectl apply -f recreate-v2.yaml   (sampling pod count every second)"
kubectl apply -f "$M/strategies/recreate-v2.yaml" >/dev/null
for i in $(seq 1 14); do
  n=$(kubectl get pods -l app=recreate-demo --no-headers 2>/dev/null | grep -c Running)
  t=$(kubectl get pods -l app=recreate-demo --no-headers 2>/dev/null | wc -l | tr -d ' ')
  printf '  t+%-3ss  running=%s  total=%s%s\n' "$i" "$n" "$t" "$([ "$n" = "0" ] && echo '   <-- DOWNTIME: zero pods serving')"
  sleep 1
done
kubectl rollout status deployment/recreate-demo --timeout=240s
run "kubectl get pods -l app=recreate-demo -L version"
echo ">> Recreate terminates ALL old pods BEFORE starting any new one, so there"
echo ">> is a window with zero capacity. Use it only when two versions must"
echo ">> never run simultaneously - e.g. an incompatible DB schema migration."
run "kubectl delete deployment recreate-demo"
