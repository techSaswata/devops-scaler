#!/usr/bin/env bash
# Module 14, part 3 — the Session 15 mini project: package and deploy the Notes app.
export PATH="/opt/homebrew/bin:$PATH"
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-28}; }
D="$(cd "$(dirname "$0")/.." && pwd)/mini-project"; cd "$D"
NS="-n notes"

page(){
  kubectl port-forward $NS "svc/$1-notes-chart" 18092:80 >/dev/null 2>&1 &
  local pf=$!; sleep 3
  curl -s http://localhost:18092/ 2>/dev/null | grep -oE '<td style="color:[^"]*">[^<]*</td>' | sed 's/<[^>]*>//g' | paste -sd' | ' -
  { kill "$pf" && wait "$pf"; } 2>/dev/null
}

helm uninstall notes-dev notes-prod $NS >/dev/null 2>&1
kubectl delete namespace notes --ignore-not-found --wait=true >/dev/null 2>&1
sleep 3

hr "1. THE CHART"
run "find notes-chart -type f | sort"
run "cat notes-chart/Chart.yaml"

hr "2. LINT AND RENDER BEFORE INSTALLING"
run "helm lint notes-chart"
run "helm template notes ./notes-chart | grep -E '^kind:|  name:' | head -8"

hr "3. DEV vs PROD — the same chart, two value files"
echo "\$ diff <(helm template notes ./notes-chart) <(helm template notes ./notes-chart -f notes-chart/values-prod.yaml)"
diff <(helm template notes ./notes-chart) \
     <(helm template notes ./notes-chart -f notes-chart/values-prod.yaml) | head -22
echo
echo ">> One chart, two environments. Nothing is duplicated - only values differ."

hr "4. INSTALL THE DEV RELEASE"
run "helm install notes-dev ./notes-chart $NS --create-namespace --wait --timeout 5m 2>&1 | head -7"
run "helm list $NS"
run "kubectl get all $NS"
echo "live page:"; page notes-dev

hr "5. INSTALL THE PROD RELEASE — SAME CHART, SAME CLUSTER"
run "helm install notes-prod ./notes-chart $NS -f notes-chart/values-prod.yaml --wait --timeout 5m 2>&1 | head -7"
run "helm list $NS"
run "kubectl get pods $NS"
echo "live page:"; page notes-prod
echo
echo ">> TWO releases of ONE chart coexisting in the same namespace. The release"
echo ">> name is baked into every resource name by the fullname helper, so there"
echo ">> is no collision. This is the core value of templating."

hr "6. CONFIRM THEY ARE INDEPENDENT"
run "kubectl get deploy $NS -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas --no-headers"
run "helm get values notes-dev $NS"
run "helm get values notes-prod $NS"

hr "7. PACKAGE THE CHART"
run "helm package notes-chart"
run "ls -lh notes-chart-0.1.0.tgz"
echo ">> A .tgz is what you push to a chart repository (ChartMuseum, Harbor,"
echo ">> an OCI registry such as GHCR). Installing from it is identical:"
run "helm install notes-tgz ./notes-chart-0.1.0.tgz $NS --dry-run 2>&1 | head -6"

hr "8. UPGRADE THE DEV RELEASE TO ENABLE A FEATURE FLAG"
echo "\$ helm upgrade notes-dev ./notes-chart $NS --set app.featureFlags.export=true --wait"
helm upgrade notes-dev ./notes-chart $NS --set app.featureFlags.export=true --wait --timeout 5m 2>&1 | head -5
run "helm list $NS"
echo "live page:"; page notes-dev
echo ">> export flag is now true on dev, and prod is untouched."

hr "9. UNINSTALL"
run "helm uninstall notes-dev $NS"
run "helm list $NS"
run "kubectl get all $NS"
echo ">> Uninstalling one release removed exactly its own resources."
echo
run "helm list $NS --uninstalled --all"
echo ">> By default Helm PURGES history on uninstall. Use --keep-history to"
echo ">> retain it so the release can still be rolled back."
helm uninstall notes-prod $NS >/dev/null 2>&1
rm -f notes-chart-0.1.0.tgz
