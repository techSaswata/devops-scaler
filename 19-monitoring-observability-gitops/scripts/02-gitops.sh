#!/usr/bin/env bash
# Module 19, part 3 — GitOps with Argo CD (Session 20, Task 3).
export PATH="/opt/homebrew/bin:$PATH"
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-28}; }
APP="gitops-demo"

hr "1. WHAT GITOPS IS"
cat <<'NOTE'
  The deployment model most teams start with is PUSH:

      developer / CI  ──kubectl apply──▶  cluster
      CI needs cluster credentials; nobody knows what is actually running.

  GitOps is PULL:

      git (desired state)  ◀──watches──  agent INSIDE the cluster  ──applies──▶ cluster

  FOUR PRINCIPLES
    1. Declarative      the whole system is described as data, not scripts
    2. Versioned        git is the single source of truth, with history
    3. Pulled           an agent in the cluster fetches; CI never gets creds
    4. Reconciled       drift is corrected CONTINUOUSLY, not just at deploy time

  Point 4 is the one that distinguishes GitOps from "CI that runs kubectl".
NOTE

hr "2. THE ARGO CD INSTALLATION"
run "kubectl get pods -n argocd"
run "kubectl get crd | grep argoproj"
echo ">> Three CRDs: Application (one deployable unit), AppProject (guardrails"
echo ">> on what an Application may do), ApplicationSet (templating many Apps)."

hr "3. THE APPLICATION — the git-to-cluster contract"
run "cat ../gitops/application.yaml | sed -n '/^spec:/,\$p'"
run "kubectl get application $APP -n argocd"
run "kubectl get application $APP -n argocd -o jsonpath='repo={.spec.source.repoURL}{\"\\n\"}path={.spec.source.path}{\"\\n\"}revision={.spec.source.targetRevision}{\"\\n\"}dest={.spec.destination.namespace}{\"\\n\"}'"

hr "4. WHAT IT DEPLOYED — with no kubectl apply"
run "kubectl get all -n gitops-demo"
run "kubectl get application $APP -n argocd -o jsonpath='{range .status.resources[*]}  {.kind}/{.name}  {.status}{\"\\n\"}{end}'"
echo ">> Argo CD created every one of those by pulling this repository."
echo
kubectl -n gitops-demo run gd-client --image=busybox:1.36 --restart=Never -- sleep infinity >/dev/null 2>&1
kubectl wait --for=condition=Ready pod/gd-client -n gitops-demo --timeout=120s >/dev/null 2>&1
echo "\$ wget -qO- http://gitops-demo | grep -o '<h1>.*</h1>'"
kubectl exec gd-client -n gitops-demo -- wget -qO- --timeout=3 http://gitops-demo 2>/dev/null | grep -o '<h1>[^<]*</h1>'

hr "5. SELF-HEALING — the part that is NOT just automated deployment"
echo "Git says replicas: 2. Change it by hand and watch Argo CD revert it."
run "kubectl get deployment gitops-demo -n gitops-demo -o jsonpath='replicas now: {.spec.replicas}{\"\\n\"}'"
echo
echo "\$ kubectl scale deployment gitops-demo -n gitops-demo --replicas=5   (a manual change)"
kubectl scale deployment gitops-demo -n gitops-demo --replicas=5 >/dev/null
# Sample immediately and often: Argo CD reverts this in SECONDS, so a sleep
# before the first read misses the drift entirely.
echo "sampling every 2s - watch it get reverted:"
for i in $(seq 1 20); do
  r=$(kubectl get deployment gitops-demo -n gitops-demo -o jsonpath='{.spec.replicas}' 2>/dev/null)
  printf '  t+%-3ss  spec.replicas=%s%s\n' "$((i*2-2))" "$r" \
    "$([ "$r" = "2" ] && [ "$i" -gt 1 ] && echo '   <-- Argo CD reverted it')"
  [ "$r" = "2" ] && [ "$i" -gt 1 ] && break
  [ "$i" = "20" ] && echo "  still $r after 40s"
  sleep 2
done
run "kubectl get deployment gitops-demo -n gitops-demo -o jsonpath='replicas: {.spec.replicas}{\"\\n\"}'"
run "kubectl get application $APP -n argocd"
echo
echo ">> THIS is the difference between GitOps and CI-that-runs-kubectl."
echo ">> A push pipeline deploys and then stops caring. Argo CD keeps comparing"
echo ">> the cluster against git FOREVER, so a 3am manual hotfix is reverted"
echo ">> rather than silently becoming undocumented production state."

hr "6. SYNC AND HEALTH STATUS"
run "kubectl get application $APP -n argocd -o jsonpath='sync={.status.sync.status}  health={.status.health.status}  revision={.status.sync.revision}{\"\\n\"}'"
echo
cat <<'NOTE'
  SYNC STATUS     is the cluster what git says?
    Synced        yes
    OutOfSync     no - something differs
    Unknown       cannot tell (repo unreachable, bad path)

  HEALTH STATUS   is what is deployed actually WORKING?
    Healthy       all resources report ready
    Progressing   a rollout is in flight
    Degraded      something failed
    Missing       declared in git, absent from the cluster

  They are independent, and the interesting case is Synced + Degraded: the
  cluster matches git exactly, and git is wrong.
NOTE

hr "7. SYNC HISTORY — the audit trail"
run "kubectl get application $APP -n argocd -o jsonpath='{range .status.history[*]}  revision={.revision}  deployedAt={.deployedAt}{\"\\n\"}{end}'"
echo ">> Every sync is recorded with the git SHA that produced it. Rolling back"
echo ">> means reverting the commit - the cluster follows automatically. There"
echo ">> is no separate deployment tool to interrogate."

hr "8. PRUNE — deleting from git deletes from the cluster"
run "kubectl get application $APP -n argocd -o jsonpath='prune={.spec.syncPolicy.automated.prune}  selfHeal={.spec.syncPolicy.automated.selfHeal}{\"\\n\"}'"
echo ">> prune:true means a resource removed from git is DELETED from the"
echo ">> cluster. Without it, deleting a file leaves the object orphaned"
echo ">> forever - running, unmanaged, and invisible to code review."

hr "9. GITOPS vs PUSH-BASED CI/CD"
cat <<'NOTE'

                      PUSH (module 15 CI/CD)        PULL (GitOps)
  ------------------  ----------------------------  ---------------------------
  Who applies         the CI runner                 an agent in the cluster
  Cluster credentials held by CI, outside the       never leave the cluster
                      cluster
  Drift               undetected                    continuously corrected
  Rollback            re-run an older pipeline      git revert
  Audit               CI logs                       git history + sync history
  New cluster         re-run every pipeline         point Argo CD at the repo

  THE SECURITY ARGUMENT: with pull, your CI system never holds kubeconfig
  credentials. A compromised CI pipeline cannot reach the cluster at all.

  WHERE EACH BELONGS: CI builds and tests and pushes the IMAGE (module 15).
  CD updates the image TAG in git. GitOps deploys it. The pipeline's last
  step becomes a commit, not a kubectl apply.
NOTE

kubectl -n gitops-demo delete pod gd-client --force --grace-period=0 >/dev/null 2>&1
