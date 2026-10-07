#!/usr/bin/env bash
# Module 12, part 2 — Horizontal Pod Autoscaler, end to end.
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }
M="$(cd "$(dirname "$0")/.." && pwd)/manifests"

kubectl delete -f "$M/06-load-generator.yaml" --ignore-not-found >/dev/null 2>&1
kubectl delete -f "$M/05-hpa.yaml" --ignore-not-found >/dev/null 2>&1
sleep 5

hr "1. METRICS-SERVER — the HPA's data source"
run "kubectl get deployment metrics-server -n kube-system"
run "kubectl top nodes"
echo ">> Without metrics-server, 'kubectl top' fails and every HPA reports"
echo ">> TARGETS <unknown>. It is the single most common reason an HPA does nothing."
echo
echo ">> NOTE for kind: metrics-server needs --kubelet-insecure-tls, because the"
echo ">> kubelet serving certs are not signed by the cluster CA. Without that flag"
echo ">> the pod runs but never becomes Ready."

hr "2. DEPLOY THE APPLICATION AND THE HPA"
run "cat $M/05-hpa.yaml | sed -n '1,30p'"
run "kubectl apply -f $M/05-hpa.yaml"
kubectl rollout status deployment/hpa-demo --timeout=300s
run "kubectl get deployment hpa-demo"
run "kubectl get hpa hpa-demo"
echo
echo "--- wait for the HPA to collect its first metrics ---"
for i in $(seq 1 30); do
  t=$(kubectl get hpa hpa-demo -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)
  if [ -n "$t" ]; then echo "  metrics available after $((i*5))s: ${t}%"; break; fi
  [ "$i" = "30" ] && echo "  no metrics after 150s"
  sleep 5
done
run "kubectl get hpa hpa-demo"
echo ">> TARGETS now shows an actual percentage, not <unknown>."
echo
echo "--- why requests.cpu is mandatory ---"
run "kubectl get deployment hpa-demo -o jsonpath='requests.cpu={.spec.template.spec.containers[0].resources.requests.cpu}{\"\\n\"}'"
echo ">> averageUtilization: 50 means 50% OF THE REQUEST (200m), i.e. 100m per pod."
echo ">> With no CPU request there is nothing to take a percentage of, and the"
echo ">> HPA can never compute a target."

hr "3. BASELINE — idle"
run "kubectl get hpa hpa-demo"
run "kubectl get pods -l app=hpa-demo"
run "kubectl top pods -l app=hpa-demo"
echo ">> 1 replica, CPU near zero."

hr "4. GENERATE LOAD"
run "kubectl apply -f $M/06-load-generator.yaml"
kubectl rollout status deployment/load-generator --timeout=300s
run "kubectl get pods -l app=load-generator"
echo
echo "--- watching the HPA react (sampled every 15s for 5 minutes) ---"
printf '%-8s %-12s %-10s %-9s %s\n' "TIME" "TARGET%" "REPLICAS" "DESIRED" "POD CPU"
MAXREP=1
for i in $(seq 1 20); do
  cur=$(kubectl get hpa hpa-demo -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)
  rep=$(kubectl get hpa hpa-demo -o jsonpath='{.status.currentReplicas}' 2>/dev/null)
  des=$(kubectl get hpa hpa-demo -o jsonpath='{.status.desiredReplicas}' 2>/dev/null)
  cpu=$(kubectl top pods -l app=hpa-demo --no-headers 2>/dev/null | awk '{s+=$2} END {print s"m total"}')
  printf '%-8s %-12s %-10s %-9s %s\n' "t+$((i*15))s" "${cur:-<none>}%" "${rep:-?}" "${des:-?}" "${cpu:-n/a}"
  [ -n "${rep:-}" ] && [ "${rep:-1}" -gt "$MAXREP" ] && MAXREP=$rep
  sleep 15
done
echo
echo "peak replica count observed: $MAXREP"

hr "5. SCALED UP"
run "kubectl get hpa hpa-demo"
run "kubectl get pods -l app=hpa-demo -o wide"
run "kubectl top pods -l app=hpa-demo"
run "kubectl describe hpa hpa-demo | sed -n '/Events:/,\$p'"
echo ">> The Events show SuccessfulRescale with the reason, which is the audit"
echo ">> trail for every autoscaling decision."

hr "6. REMOVE THE LOAD AND WATCH IT SCALE BACK DOWN"
run "kubectl delete -f $M/06-load-generator.yaml"
echo
printf '%-8s %-12s %-10s %s\n' "TIME" "TARGET%" "REPLICAS" "POD CPU"
for i in $(seq 1 14); do
  cur=$(kubectl get hpa hpa-demo -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)
  rep=$(kubectl get hpa hpa-demo -o jsonpath='{.status.currentReplicas}' 2>/dev/null)
  cpu=$(kubectl top pods -l app=hpa-demo --no-headers 2>/dev/null | awk '{s+=$2} END {print s"m total"}')
  printf '%-8s %-12s %-10s %s\n' "t+$((i*15))s" "${cur:-<none>}%" "${rep:-?}" "${cpu:-n/a}"
  sleep 15
done
run "kubectl get hpa hpa-demo"
run "kubectl get pods -l app=hpa-demo"
echo
cat <<'NOTE'
  >> Scale-DOWN is deliberately slower than scale-up. Kubernetes defaults to a
  >> 300s stabilisation window so a brief dip in traffic does not destroy
  >> capacity you are about to need again. This manifest lowers it to 30s via
  >> spec.behavior.scaleDown.stabilizationWindowSeconds so the effect fits in a
  >> demo; leave the default in production.

  THE HPA ALGORITHM:

      desiredReplicas = ceil( currentReplicas x ( currentMetric / targetMetric ) )

  With 4 pods averaging 90% against a 50% target:
      ceil(4 x (90/50)) = ceil(7.2) = 8   -> capped at maxReplicas

  WHY AN HPA REPORTS <unknown>:
    1. metrics-server is not installed, or not Ready
    2. the container has NO resources.requests.cpu
    3. the pods are too new - give it ~30s after start
NOTE

hr "7. USEFUL COMMANDS"
run "kubectl get hpa"
run "kubectl get pods"
run "kubectl top pods"
run "kubectl describe hpa hpa-demo | head -18"
