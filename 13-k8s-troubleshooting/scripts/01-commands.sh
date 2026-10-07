#!/usr/bin/env bash
# Module 13, part 1 — the troubleshooting command toolkit (Session 14, Task 1).
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-25}; }

kubectl delete pod -l drill=cmds --force --grace-period=0 >/dev/null 2>&1
kubectl run cmd-demo --image=nginx:1.27-alpine --labels=drill=cmds >/dev/null 2>&1
kubectl wait --for=condition=Ready pod/cmd-demo --timeout=180s >/dev/null 2>&1

hr "1. kubectl get — what IS there?"
run "kubectl get pods"
run "kubectl get pods -o wide"
echo ">> -o wide adds IP, NODE and NOMINATED NODE. Always use it first: half of"
echo ">> all 'it works on one pod but not another' problems are node-specific."
run "kubectl get all"
run "kubectl get pods --show-labels"
run "kubectl get pods -o json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[\"items\"][0][\"status\"][\"phase\"])'"
run "kubectl get pods --sort-by=.status.startTime"
run "kubectl get pods -A --field-selector=status.phase!=Running"
echo ">> That last one is the single most useful triage command on a sick cluster:"
echo ">> every pod that is NOT Running, across every namespace."

hr "2. kubectl describe — WHY is it like that?"
echo "\$ kubectl describe pod cmd-demo"
kubectl describe pod cmd-demo 2>&1 | sed -n '1,16p'
echo "   ..."
kubectl describe pod cmd-demo 2>&1 | sed -n '/^Events:/,$p' | head -10
echo
echo ">> The EVENTS block at the bottom is the payload. get tells you the state;"
echo ">> describe tells you how it got there."

hr "3. kubectl logs — what did the APPLICATION say?"
run "kubectl logs cmd-demo --tail=5"
echo
cat <<'NOTE'
  THE FOUR FORMS THAT MATTER:
    kubectl logs <pod>                    current container
    kubectl logs <pod> --previous         the container BEFORE the last restart
                                          <- the only way to see why it crashed
    kubectl logs <pod> -c <container>     a specific container in a multi-container pod
    kubectl logs -l app=web --prefix      every pod matching a label, prefixed
NOTE
run "kubectl logs -l drill=cmds --tail=2 --prefix"

hr "4. kubectl exec — go and look inside"
run "kubectl exec cmd-demo -- nginx -v"
run "kubectl exec cmd-demo -- cat /etc/resolv.conf"
run "kubectl exec cmd-demo -- ls /usr/share/nginx/html"
echo ">> Interactive: kubectl exec -it <pod> -- sh"
echo ">> If the image has no shell (distroless/scratch), use an ephemeral"
echo ">> debug container instead:  kubectl debug -it <pod> --image=busybox"

hr "5. kubectl events — the cluster-wide timeline"
run "kubectl events --for pod/cmd-demo"
run "kubectl get events --sort-by=.lastTimestamp | tail -12"
echo ">> Sorting by timestamp matters - the default order is NOT chronological,"
echo ">> which has misled a lot of people into reading a stale event as current."

hr "6. kubectl explain — the API reference, offline"
run "kubectl explain pod.spec.containers.livenessProbe | head -16"
run "kubectl explain deployment.spec.strategy.rollingUpdate"
echo ">> No web search needed for field names, types or defaults."

hr "7. kubectl top — who is using the resources?"
run "kubectl top nodes"
run "kubectl top pods"
run "kubectl top pods --containers | head -6"
echo ">> Requires metrics-server. Use it to answer 'is this pod being throttled"
echo ">> or OOMKilled?' before blaming the application."

hr "8. PUTTING IT TOGETHER — the triage order"
cat <<'NOTE'

    1. kubectl get pods -o wide            what is broken, and where?
            |
    2. kubectl describe pod <name>         why? -> read EVENTS at the bottom
            |
    3. kubectl logs <name>                 what did the app say?
       kubectl logs <name> --previous      ...before it crashed
            |
    4. kubectl exec -it <name> -- sh       go in and look
            |
    5. kubectl get events --sort-by=...    what else happened at that moment?

  Steps 1 and 2 resolve the large majority of problems on their own.
NOTE
kubectl delete pod cmd-demo --force --grace-period=0 >/dev/null 2>&1
