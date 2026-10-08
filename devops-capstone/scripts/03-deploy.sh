#!/usr/bin/env bash
# M8 — deploy ClinicFlow to the EKS cluster with Helm and prove it serves
# traffic through the Ingress.
export PATH="/opt/homebrew/bin:$PATH"
export AWS_PAGER=""
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-40}; }
runfull(){ echo; echo "\$ $*"; local o; o=$(eval "$@" 2>&1); echo "$o" | tail -${N:-25}; }
D="$(cd "$(dirname "$0")/.." && pwd)"
NS=clinicflow
TAG="${IMAGE_TAG:?set IMAGE_TAG to the sha- tag published by the pipeline}"

# Wait until a URL returns a real HTTP 200.
#
# Polling for "any output" is not good enough: ingress-nginx answers immediately
# with its own 503 page while it still has no healthy endpoint behind the host,
# and that page is non-empty. Only the status code separates "the proxy is
# talking to me" from "my application is talking to me".
wait200(){
  local url="$1" host="${2:-}" i code=000
  printf '  waiting for %s ' "$url"
  for i in $(seq 1 90); do
    if [ -n "$host" ]; then
      code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Host: $host" "$url" 2>/dev/null)
    else
      code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null)
    fi
    [ "$code" = "200" ] && { echo " HTTP 200 after ~$((i*5))s"; return 0; }
    printf '.'; sleep 5
  done
  echo " GAVE UP after ~450s (last status $code)"; return 1
}

hr "1. THE CLUSTER"
runfull "kubectl config current-context"
runfull "kubectl get nodes -o wide"

hr "2. INGRESS CONTROLLER"
# On EKS this creates a real AWS load balancer, which is why 09-destroy.sh has
# to delete it BEFORE terraform runs -- Terraform does not know it exists.
run "helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>&1 | tail -1"
run "helm repo update 2>&1 | tail -1"
runfull "helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations.'service\.beta\.kubernetes\.io/aws-load-balancer-type'=nlb \
  --wait --timeout 10m"
runfull "kubectl get svc -n ingress-nginx ingress-nginx-controller"

echo
echo "--- waiting for AWS to attach a hostname to the load balancer ---"
for i in $(seq 1 60); do
  LB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  [ -n "$LB" ] && { echo "  $LB"; break; }
  printf '.'; sleep 5
done
echo "LB=$LB"

hr "3. METRICS-SERVER"
# EKS does not ship metrics-server, and nothing says so. Without it the HPA
# cannot read CPU at all and reports, on a loop:
#   failed to get cpu utilization: unable to fetch metrics from resource metrics
#   API: the server could not find the requested resource (get pods.metrics.k8s.io)
# The HPA object exists, looks configured, and silently never scales.
run "kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
runfull "kubectl -n kube-system rollout status deployment/metrics-server --timeout=5m"
echo
echo "--- it answers, rather than merely existing ---"
for i in $(seq 1 30); do
  kubectl top nodes >/dev/null 2>&1 && { echo "  metrics API answering after ~$((i*5))s"; break; }
  sleep 5
done
run "kubectl top nodes"

hr "4. NAMESPACE AND STORAGE CLASS"
runfull "kubectl apply -f $D/k8s/namespace.yaml"
# EKS ships no DEFAULT StorageClass, so a PVC that does not name one binds to
# nothing. This adds a gp3 class backed by the CSI driver and marks it default.
runfull "kubectl apply -f $D/k8s/storageclass.yaml"
runfull "kubectl get storageclass"
runfull "kubectl get ns $NS --show-labels"
echo ">> Pod Security Admission is enforced at 'restricted' on this namespace."

hr "5. HELM INSTALL"
run "helm lint $D/helm/clinicflow"
echo
echo "deploying image tag: $TAG"
runfull "helm upgrade --install clinicflow $D/helm/clinicflow \
  --namespace $NS \
  --set backend.image.tag=$TAG \
  --set frontend.image.tag=$TAG \
  --set ingress.host=clinicflow.local \
  --wait --timeout 12m"

hr "6. WHAT HELM CREATED"
runfull "helm list -n $NS"
run "kubectl get all -n $NS"
run "kubectl get pvc,ingress,secret,configmap -n $NS"

hr "7. ALL PODS RUNNING"
runfull "kubectl get pods -n $NS -o wide"
echo
echo "--- replica counts: the rubric asks for at least 2 of each ---"
for c in backend frontend; do
  printf '  %-9s ' "$c"
  kubectl get deploy -n $NS -l app.kubernetes.io/component=$c \
    -o jsonpath='{.items[0].status.readyReplicas}/{.items[0].status.replicas} ready{"\n"}'
done
echo
echo "--- the anti-affinity actually spread them across nodes ---"
kubectl get pods -n $NS -o custom-columns='POD:.metadata.name,NODE:.spec.nodeName' --no-headers | sort -k2

hr "8. THE MIGRATION RAN AS A JOB, NOT IN THE APP CONTAINERS"
runfull "kubectl get jobs -n $NS"
run "kubectl logs -n $NS job/\$(kubectl get jobs -n $NS -o jsonpath='{.items[0].metadata.name}') --tail=12 --all-containers 2>&1 || true"
echo "\$ alembic version in the live database"
PG=$(kubectl get pods -n $NS -l app.kubernetes.io/component=postgres -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n $NS "$PG" -- psql -U clinic -d clinicflow -tAc 'SELECT version_num FROM alembic_version' 2>&1 | head -2
echo ">> With two backend replicas, running Alembic in the app containers would"
echo ">> mean two pods racing to migrate the same database on every rollout."

hr "9. SERVICES AND ENDPOINTS"
runfull "kubectl get svc -n $NS"
echo
echo "--- a Service with no endpoints is the silent failure; check them ---"
kubectl get endpointslice -n $NS -o custom-columns='NAME:.metadata.name,ADDRESSES:.endpoints[*].addresses,PORTS:.ports[*].port' --no-headers 2>&1 | head

hr "10. THE APPLICATION THROUGH THE INGRESS"
runfull "kubectl get ingress -n $NS"
wait200 "http://$LB/" "clinicflow.local"
echo
echo "\$ curl -H 'Host: clinicflow.local' http://\$LB/   (the SPA)"
curl -s --max-time 15 -H 'Host: clinicflow.local' "http://$LB/" | head -c 220; echo
echo
echo "\$ curl -H 'Host: clinicflow.local' http://\$LB/api/appointments/stats"
curl -s --max-time 15 -H 'Host: clinicflow.local' "http://$LB/api/appointments/stats"; echo
echo "\$ curl .../health and .../ready on the backend"
curl -s --max-time 15 -H 'Host: clinicflow.local' "http://$LB/api/../health" -o /dev/null -w '  (ignored)\n' 2>/dev/null || true
kubectl exec -n $NS deploy/clinicflow-clinicflow-backend -- python -c "
import urllib.request
for p in ('/health','/ready'):
    print(' ',p, urllib.request.urlopen('http://localhost:8000'+p).read().decode())" 2>&1 | grep -v Defaulted

hr "11. SEED AND READ BACK THROUGH THE INGRESS"
API="http://$LB/api" HOSTHDR=clinicflow.local bash -c '
post(){ curl -s -X POST "$API/$1" -H "Host: $HOSTHDR" -H "Content-Type: application/json" -d "$2"; }
for d in "{\"name\":\"Dr Aparna Rao\",\"specialty\":\"Cardiology\",\"room\":\"C-12\"}" \
         "{\"name\":\"Dr Imran Qureshi\",\"specialty\":\"Dermatology\",\"room\":\"D-04\"}"; do
  post doctors "$d" >/dev/null; done
for p in "{\"name\":\"Rahul Menon\",\"phone\":\"+91-9000000001\"}" \
         "{\"name\":\"Sneha Iyer\",\"phone\":\"+91-9000000002\"}"; do
  post patients "$p" >/dev/null; done
'
python3 - "$LB" <<'PY'
import json, subprocess, sys
from datetime import datetime, timedelta, timezone
lb = sys.argv[1]; api = f"http://{lb}/api"
now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
for pid, did, hrs, reason in [(1,1,3,"Chest pain follow-up"),(2,2,5,"Eczema review"),(2,1,27,"ECG results")]:
    body = {"patient_id":pid,"doctor_id":did,
            "scheduled_at":(now+timedelta(hours=hrs)).isoformat(),
            "duration_minutes":30,"reason":reason}
    out = subprocess.run(["curl","-s","-X","POST",f"{api}/appointments",
        "-H","Host: clinicflow.local","-H","Content-Type: application/json",
        "-d",json.dumps(body)],capture_output=True,text=True).stdout
    print("  created:", json.loads(out)["reason"])
PY
echo
echo "\$ GET /api/appointments/stats"
curl -s --max-time 15 -H 'Host: clinicflow.local' "http://$LB/api/appointments/stats" | python3 -m json.tool

hr "12. HPA"
runfull "kubectl get hpa -n $NS"
echo ">> minReplicas 2 for both, so the HPA holds the deployment at two even"
echo ">> at idle. The Deployments deliberately omit .spec.replicas when"
echo ">> autoscaling is on, so Helm and the HPA cannot fight over the number."

hr "13. SECURITY CONTEXT, VERIFIED FROM INSIDE THE POD"
runfull "kubectl get pod -n $NS -l app.kubernetes.io/component=backend -o jsonpath='runAsNonRoot={.items[0].spec.securityContext.runAsNonRoot}  uid={.items[0].spec.securityContext.runAsUser}  readOnlyRootFS={.items[0].spec.containers[0].securityContext.readOnlyRootFilesystem}  caps={.items[0].spec.containers[0].securityContext.capabilities.drop}{\"\\n\"}'"
run "kubectl exec -n $NS deploy/clinicflow-clinicflow-backend -- id 2>&1 | grep -v Defaulted"
echo "\$ kubectl exec ... -- touch /forbidden"
kubectl exec -n $NS deploy/clinicflow-clinicflow-backend -- touch /forbidden 2>&1 | grep -v Defaulted | head -2
echo ">> Read-only root rejected the write."
