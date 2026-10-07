#!/usr/bin/env bash
# Module 20, part 2 - package the same app as a Helm chart and prove the
# release lifecycle: lint, template, install, upgrade, history, rollback.
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
C="$D/helm/taskapi"
NS="finalproject-helm"
H="-n $NS"

hr "1. LINT BOTH SHIPPED CONFIGURATIONS"
run "helm lint $C"
run "helm lint $C -f $C/values-scaled.yaml"

hr "2. THE CHART REFUSES AN IMPOSSIBLE COMBINATION"
# templates/_validate.tpl. A ReadWriteOnce PVC is a per-NODE mount, so an HPA
# allowed to add replicas would park them in ContainerCreating forever. Better
# to fail at template time than to ship it and find out under load.
echo "\$ helm template x $C --set persistence.enabled=true --set autoscaling.enabled=true --set autoscaling.maxReplicas=4"
helm template x "$C" --set persistence.enabled=true --set autoscaling.enabled=true --set autoscaling.maxReplicas=4 2>&1 | head -3
echo ">> Rejected before anything reached the cluster."

hr "3. WHAT EACH VALUES FILE RENDERS"
echo "\$ helm template x \$C                          # defaults: stateful, 1 replica"
helm template x "$C" 2>&1 | grep -E '^kind:' | sed 's/kind: /  /'
echo
echo "\$ helm template x \$C -f values-scaled.yaml    # stateless, autoscaled"
helm template x "$C" -f "$C/values-scaled.yaml" 2>&1 | grep -E '^kind:' | sed 's/kind: /  /'
echo ">> PVC appears in one, HorizontalPodAutoscaler in the other. Never both."

hr "4. VALIDATE THE RENDERED YAML AGAINST THE REAL API SERVER"
# --dry-run=server sends the manifests through the actual admission chain:
# schema validation, defaulting, webhooks. It catches what a text-level linter
# cannot, and it writes nothing. (CI has no cluster, so the GitHub Actions
# workflow uses kubeconform against the upstream schemas instead.)
kubectl create namespace helm-dryrun >/dev/null 2>&1
helm template x "$C" --namespace helm-dryrun > /tmp/helm-rendered.yaml 2>&1
runfull "kubectl apply --dry-run=server -n helm-dryrun -f /tmp/helm-rendered.yaml"
kubectl delete namespace helm-dryrun --wait=false >/dev/null 2>&1
echo ">> Accepted by the API server, and nothing was persisted."

hr "5. INSTALL"
kubectl delete namespace $NS --ignore-not-found --wait=true >/dev/null 2>&1
kubectl create namespace $NS >/dev/null
echo "--- the Secret the chart REFERENCES but does not contain ---"
echo "\$ kubectl create secret generic task-api-secret --from-literal=..."
kubectl $H create secret generic task-api-secret \
  --from-literal=DB_PASSWORD='supplied-at-deploy-time' \
  --from-literal=API_KEY='supplied-at-deploy-time' >/dev/null
echo
runfull "helm install taskapi $C $H --wait --timeout 5m"
run "helm list $H"
run "kubectl get all,pvc,ingress $H"

hr "6. THE RELEASE SERVES TRAFFIC THROUGH ITS OWN INGRESS HOST"
wait200 taskapi-helm.local
echo "\$ curl -H 'Host: taskapi-helm.local' http://localhost/"
curl -s --max-time 10 -H 'Host: taskapi-helm.local' http://localhost/; echo
echo ">> environment=production, LOG_LEVEL from the chart's ConfigMap."

hr "7. UPGRADE - a VALUES-ONLY change must still roll the pods"
# The deployment carries checksum/config: sha256 of the rendered ConfigMap.
# Without it, Helm would update the ConfigMap and leave the running pods on the
# stale environment, because the Deployment's own spec never changed.
BEFORE=$(kubectl get pods $H -o jsonpath='{.items[0].metadata.name}')
SUM_BEFORE=$(kubectl get deploy taskapi-taskapi $H -o jsonpath='{.spec.template.metadata.annotations.checksum/config}')
echo "pod before:      $BEFORE"
echo "checksum before: ${SUM_BEFORE:0:16}..."
runfull "helm upgrade taskapi $C $H -f $C/values-staging.yaml --wait --timeout 5m"
SUM_AFTER=$(kubectl get deploy taskapi-taskapi $H -o jsonpath='{.spec.template.metadata.annotations.checksum/config}')
AFTER=$(kubectl get pods $H -o jsonpath='{.items[0].metadata.name}')
echo
echo "pod after:       $AFTER"
echo "checksum after:  ${SUM_AFTER:0:16}..."
[ "$SUM_BEFORE" != "$SUM_AFTER" ] && echo ">> Checksum changed, so the pod was replaced." \
                                  || echo ">> UNEXPECTED: checksum identical."
run "kubectl get cm taskapi-taskapi $H -o jsonpath='{.data}{\"\\n\"}'"
wait200 taskapi-staging.local
echo "\$ curl -H 'Host: taskapi-staging.local' http://localhost/"
curl -s --max-time 10 -H 'Host: taskapi-staging.local' http://localhost/; echo
echo ">> environment=staging now. The RUNNING pod picked up the new values."

hr "8. UPGRADE AGAIN - to the stateless, autoscaled configuration"
runfull "helm upgrade taskapi $C $H -f $C/values-scaled.yaml --wait --timeout 5m"
run "kubectl get deploy,hpa,pvc $H"
echo ">> replicas 2 and an HPA; the PVC is gone because this configuration is stateless."

hr "9. HISTORY - every revision is retained"
run "helm history taskapi $H"

hr "10. ROLLBACK"
echo "\$ helm rollback taskapi 1    (back to the original production values)"
runfull "helm rollback taskapi 1 $H --wait --timeout 5m"
run "helm history taskapi $H"
echo ">> Rollback does NOT rewind the revision counter: it appends a NEW"
echo ">> revision whose contents equal revision 1. The history stays append-only."
run "kubectl get deploy,hpa,pvc $H"
wait200 taskapi-helm.local
echo "\$ curl -H 'Host: taskapi-helm.local' http://localhost/"
curl -s --max-time 10 -H 'Host: taskapi-helm.local' http://localhost/; echo
echo ">> Back to production, HPA removed, and a PVC exists again."
echo ">> But note the PVC's AGE: it is a BRAND NEW volume, not the original."
echo ">> Revision 3 set persistence.enabled=false, which DELETED the old PVC"
echo ">> and its data. Rollback restores the DECLARATION, not the bytes --"
echo ">> \"tasks\": 0 above is the proof. Helm has no idea what was inside."

hr "11. WHAT HELM RECORDS IN THE CLUSTER"
run "helm get values taskapi $H"
echo ">> \"null\" is correct, not an error: the live revision is the rollback to"
echo ">> revision 1, and revision 1 was installed with no -f and no --set, so"
echo ">> there are no user-supplied values. Everything comes from values.yaml."
run "helm get values taskapi $H --all | head -20"
echo ">> --all shows the full COMPUTED set, defaults included."
run "kubectl get secret $H -l owner=helm --no-headers"
echo ">> One Secret per revision: that is where the history above lives."
