#!/usr/bin/env bash
# Module 14, part 2 — the rollback workflow (Session 15, Task 2):
#   install -> upgrade -> verify -> upgrade again -> verify -> rollback -> verify
export PATH="/opt/homebrew/bin:$PATH"
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-28}; }
D="$(cd "$(dirname "$0")/.." && pwd)"; cd "$D"
NS="-n helm-demo"

# Show the live page's key values without a browser.
page(){
  kubectl port-forward $NS svc/web-webapp 18091:80 >/dev/null 2>&1 &
  local pf=$!; sleep 3
  curl -s http://localhost:18091/ 2>/dev/null \
    | grep -oE '<td style="color:#e6e9f0">[^<]*</td>' | sed 's/<[^>]*>//g' \
    | paste -d'|' - - - - - - - \
    | awk -F'|' '{printf "    release=%s revision=%s chart=%s env=%s replicas=%s\n",$1,$3,$4,$6,$7}'
  # Silence the shell's "Terminated: 15" job-control notice, which otherwise
  # prints into the middle of the captured output.
  { kill "$pf" && wait "$pf"; } 2>/dev/null
}

hr "STEP 1 — INSTALL (revision 1)"
helm uninstall web $NS >/dev/null 2>&1; sleep 4
run "helm install web webapp $NS --create-namespace --wait --timeout 5m 2>&1 | head -8"
run "helm list $NS"
echo "live page:"; page
run "kubectl get pods $NS"

hr "STEP 2 — UPGRADE (revision 2): change values only"
echo "\$ helm upgrade web webapp $NS --set replicaCount=4 --set config.environment=staging --wait"
helm upgrade web webapp $NS --set replicaCount=4 \
  --set config.environment=staging \
  --set config.message="Hello from Helm (staging)" --wait --timeout 5m 2>&1 | head -8

hr "STEP 3 — VERIFY revision 2"
run "helm list $NS"
run "helm get values web $NS"
echo ">> helm get values now shows ONLY the overrides - this is the user-supplied layer."
echo "live page:"; page
run "kubectl get pods $NS"
echo ">> 4 replicas, environment=staging. Note the pods were RECREATED even though"
echo ">> only a ConfigMap value changed - that is the checksum/config annotation"
echo ">> in the pod template doing its job."

hr "STEP 4 — UPGRADE AGAIN (revision 3): use a values FILE"
run "cat webapp/values-prod.yaml"
echo "\$ helm upgrade web webapp $NS -f webapp/values-prod.yaml --wait"
helm upgrade web webapp $NS -f webapp/values-prod.yaml --wait --timeout 5m 2>&1 | head -8

hr "STEP 5 — VERIFY revision 3"
run "helm list $NS"
run "helm get values web $NS"
echo "live page:"; page
run "kubectl get pods $NS"
echo ">> 4 replicas, environment=production."

hr "STEP 6 — helm history: the full audit trail"
run "helm history web $NS"
echo ">> Every revision, with its status and description. This is what makes"
echo ">> rollback possible: Helm stores each release's full manifest in a Secret."
run "kubectl get secrets $NS -l owner=helm"
echo ">> One Secret per revision, type helm.sh/release.v1."

hr "STEP 7 — ROLLBACK to revision 2"
echo "\$ helm rollback web 2 $NS --wait"
helm rollback web 2 $NS --wait --timeout 5m 2>&1 | head -5
run "helm list $NS"
echo ">> REVISION is now 4, not 2. A rollback creates a NEW revision whose"
echo ">> content equals the old one - history is append-only and never rewritten."

hr "STEP 8 — VERIFY the rollback"
run "helm get values web $NS"
echo "live page:"; page
run "kubectl get pods $NS"
echo ">> Back to environment=staging - the revision-2 state."
run "helm history web $NS"
echo ">> The description column records 'Rollback to 2'."

hr "STEP 9 — ROLLBACK WITH NO ARGUMENT = previous revision"
echo "\$ helm rollback web $NS --wait      (no revision number)"
helm rollback web $NS --wait --timeout 5m 2>&1 | head -3
run "helm history web $NS"
echo "live page:"; page
echo ">> With no number, Helm rolls back ONE revision - from 4 to 3, which was"
echo ">> production. So this undid the previous rollback."

hr "SUMMARY"
cat <<'NOTE'

  install  -> rev 1  development, 2 replicas
  upgrade  -> rev 2  staging,     4 replicas   (--set)
  upgrade  -> rev 3  production,  4 replicas   (-f values-prod.yaml)
  rollback -> rev 4  == rev 2 content (staging)
  rollback -> rev 5  == rev 3 content (production)

  KEY POINTS

  1. A rollback CREATES A NEW REVISION. History is append-only, so you can
     always roll forward again. `helm history` is a complete audit trail.

  2. Helm stores every revision's rendered manifest in a Kubernetes Secret
     (type helm.sh/release.v1) in the release namespace. That is the state
     store - there is no external database.

  3. `helm get values` shows only USER-SUPPLIED values; add --all to see them
     merged with the chart defaults.

  4. --wait makes Helm block until the resources are actually Ready, so a
     failed upgrade is visible immediately instead of at the next page load.
     Add --atomic to roll back automatically if the upgrade fails.

  5. The checksum/config annotation is what makes a values-only change restart
     the pods. Without it, the ConfigMap would update and the running pods
     would keep serving the old content.
NOTE
