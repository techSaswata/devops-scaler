#!/usr/bin/env bash
# Module 14, part 1 — every Helm command in the task list (Session 15, Task 1).
export PATH="/opt/homebrew/bin:$PATH"
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-28}; }
D="$(cd "$(dirname "$0")/.." && pwd)"
cd "$D"

helm uninstall web -n helm-demo >/dev/null 2>&1
kubectl delete namespace helm-demo --ignore-not-found --wait=true >/dev/null 2>&1
sleep 3

hr "1. helm version"
run "helm version"

hr "2. helm create — scaffold a chart"
echo "\$ helm create webapp    (already run; the generated boilerplate was then"
echo "                          replaced with the smaller chart below)"
run "find webapp -type f | sort"
echo
cat <<'NOTE'
  CHART ANATOMY

    Chart.yaml     metadata: name, version, appVersion, dependencies
    values.yaml    DEFAULT configuration - every value overridable
    templates/     Go templates rendered into Kubernetes manifests
      _helpers.tpl   reusable named templates (naming, labels)
      NOTES.txt      printed after install
    .helmignore    files excluded when packaging

  version vs appVersion:
    version    = the CHART's version   - bump when the TEMPLATES change
    appVersion = the APPLICATION's     - bump when the IMAGE changes
  They are independent on purpose.
NOTE
run "cat webapp/Chart.yaml"

hr "3. helm lint — validate before installing"
run "helm lint webapp"

hr "4. helm template — render locally, install nothing"
echo "\$ helm template web webapp | head -40"
helm template web webapp 2>&1 | sed -n '30,70p'
echo ">> This is the single most useful debugging command in Helm: see exactly"
echo ">> what WOULD be sent to the API server, without sending it."

hr "5. helm install --dry-run --debug"
run "helm install web webapp -n helm-demo --create-namespace --dry-run 2>&1 | head -18"
echo ">> --dry-run also runs server-side validation, so it catches schema errors"
echo ">> that 'helm template' alone would not."

hr "6. helm install"
run "helm install web webapp -n helm-demo --create-namespace --wait --timeout 5m"
echo ">> NOTES.txt was rendered and printed - note the release name, namespace"
echo ">> and revision are all template values."

hr "7. helm list"
run "helm list -n helm-demo"
run "helm list -A"
echo ">> REVISION 1, STATUS deployed."

hr "8. helm status"
run "helm status web -n helm-demo"

hr "9. helm get — what was actually installed?"
run "helm get values web -n helm-demo"
echo ">> Empty: no overrides were supplied, so all defaults were used."
run "helm get values web -n helm-demo --all | head -22"
echo
run "helm get manifest web -n helm-demo | grep -E '^kind:|^  name:' | head -10"
echo
run "helm get notes web -n helm-demo"
echo
echo ">> helm get has sub-commands: values, manifest, notes, hooks, metadata, all."

hr "10. VERIFY IT ACTUALLY RUNS"
run "kubectl get all -n helm-demo"
kubectl port-forward -n helm-demo svc/web-webapp 18090:80 >/dev/null 2>&1 &
PF=$!; sleep 4
echo "\$ curl -s http://localhost:18090/ | grep -E 'revision|environment|replicas' -A1"
curl -s http://localhost:18090/ 2>/dev/null | grep -oE '<td style="color:#e6e9f0">[^<]*</td>' | sed 's/<[^>]*>//g' | head -7
kill $PF 2>/dev/null
echo ">> The rendered page reports the release name, revision and values."

hr "11. helm repo — working with chart repositories"
run "helm repo add bitnami https://charts.bitnami.com/bitnami"
run "helm repo list"
run "helm repo update 2>&1 | tail -3"

hr "12. helm search"
run "helm search repo bitnami/nginx | head -6"
run "helm search repo database | head -8"
echo
run "helm search hub prometheus --max-col-width 60 2>&1 | head -6"
echo ">> 'search repo' looks in repos you have added; 'search hub' queries"
echo ">> Artifact Hub over the network."

hr "13. helm show — inspect a chart WITHOUT installing it"
run "helm show chart bitnami/nginx 2>&1 | head -12"
run "helm show values bitnami/nginx 2>&1 | head -12"
