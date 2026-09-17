#!/usr/bin/env bash
# Module 10, part 2 — CoreDNS / FQDN, kube-proxy internals, endpoint triage.
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }
M="$(cd "$(dirname "$0")/.." && pwd)/manifests"
CLIENT=net-client
hit(){ kubectl exec "$CLIENT" -- wget -qO- --timeout=3 "$1" 2>/dev/null | tr -d '\r\n'; }

hr "1. COREDNS — the cluster's phonebook"
run "kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide"
run "kubectl get svc -n kube-system kube-dns"
echo ">> CoreDNS runs as an ordinary Deployment, fronted by a ClusterIP Service."
echo ">> Every pod is configured to use that Service IP as its resolver."

hr "2. INSIDE A POD: /etc/resolv.conf"
run "kubectl exec $CLIENT -- cat /etc/resolv.conf"
echo
cat <<'NOTE'
  nameserver 10.96.0.10          <- the kube-dns Service ClusterIP (CoreDNS)
  search default.svc.cluster.local svc.cluster.local cluster.local
                                 <- tried IN ORDER for any SHORT name
  options ndots:5                <- names with FEWER than 5 dots get the
                                    search list appended before being tried
                                    as-is

  This is why "backend-clusterip" works from inside a pod: the resolver tries
  backend-clusterip.default.svc.cluster.local first, and that hits.
NOTE

hr "3. THE ANATOMY OF A KUBERNETES FQDN"
cat <<'NOTE'

    backend-clusterip . default . svc . cluster.local
    ----------------   -------   ---   -------------
         |                |       |          |
         |                |       |          +-- cluster domain (configurable)
         |                |       +------------- "svc" = this is a Service
         |                +--------------------- the NAMESPACE
         +-------------------------------------- the SERVICE name

NOTE
# NOTE: busybox's nslookup applet does NOT walk the resolv.conf search list the
# way the normal resolver does, so it reports NXDOMAIN for the short forms even
# though they work perfectly. Connecting with wget goes through getaddrinfo(),
# which DOES honour `search` and `ndots`, so it is the honest test here.
echo "--- all four forms reach the same Service (resolved via getaddrinfo) ---"
for n in "backend-clusterip" \
         "backend-clusterip.default" \
         "backend-clusterip.default.svc" \
         "backend-clusterip.default.svc.cluster.local"; do
  printf '  %-46s -> ' "$n"
  r=$(hit "http://$n")
  [ -n "$r" ] && echo "OK  ($r)" || echo "FAILED"
done
echo
echo ">> Shorter forms rely on the search list. The FULL FQDN is unambiguous and"
echo ">> is what you should put in config files - it also avoids the extra DNS"
echo ">> lookups that ndots:5 causes for short names."

hr "4. CROSS-NAMESPACE RESOLUTION"
kubectl delete ns team-b --ignore-not-found >/dev/null 2>&1
sleep 2
run "kubectl create namespace team-b"
run "kubectl -n team-b create deployment other --image=nginx:1.27-alpine"
run "kubectl -n team-b expose deployment other --port=80"
kubectl -n team-b rollout status deployment/other --timeout=240s >/dev/null 2>&1
sleep 3
echo
echo "--- the SHORT name fails from the default namespace ---"
run "kubectl exec $CLIENT -- nslookup other 2>&1 | tail -3"
echo ">> Correct: the search list only tries 'default.svc.cluster.local'."
echo
echo "--- namespace-qualified works ---"
run "kubectl exec $CLIENT -- nslookup other.team-b.svc.cluster.local 2>&1 | grep -A1 '^Name:'"
run "kubectl exec $CLIENT -- wget -qO- --timeout=3 http://other.team-b.svc.cluster.local | head -4"
echo ">> Namespaces isolate NAMES, not NETWORK. By default any pod can reach any"
echo ">> other pod across namespaces - you need NetworkPolicies to stop that."
run "kubectl delete namespace team-b --wait=false"

hr "5. POD DNS vs SERVICE DNS"
echo "Services get:  <service>.<ns>.svc.cluster.local"
echo "Pods get:      <pod-ip-with-dashes>.<ns>.pod.cluster.local"
POD_IP=$(kubectl get pods -l app=backend -o jsonpath='{.items[0].status.podIP}')
DASHED=$(echo "$POD_IP" | tr '.' '-')
echo
echo "a backend pod has IP $POD_IP, so its pod DNS name is:"
echo "  $DASHED.default.pod.cluster.local"
printf '  reachable? -> '
r=$(hit "http://$DASHED.default.pod.cluster.local")
[ -n "$r" ] && echo "OK  ($r)" || echo "not resolvable in this cluster"
echo ">> Rarely used directly - it is derived from an EPHEMERAL IP. For stable"
echo ">> per-pod names you want a headless Service + StatefulSet (part 1, §5)."

hr "6. HOW TRAFFIC ACTUALLY FLOWS — kube-proxy"
run "kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide"
CIP=$(kubectl get svc backend-clusterip -o jsonpath='{.spec.clusterIP}')
echo
echo "--- the ClusterIP $CIP belongs to NO interface anywhere ---"
run "kubectl exec $CLIENT -- ip addr show 2>/dev/null | grep -c $CIP || echo '0 matches - the ClusterIP is not on any interface'"
echo
echo "--- it exists only as iptables NAT rules on every node ---"
echo "\$ docker exec devops-hw-worker iptables-save -t nat | grep $CIP"
docker exec devops-hw-worker iptables-save -t nat 2>/dev/null | grep "$CIP" | head -6
echo
echo "\$ docker exec devops-hw-worker iptables-save -t nat | grep -c KUBE-SVC"
docker exec devops-hw-worker iptables-save -t nat 2>/dev/null | grep -c "KUBE-SVC"
echo
cat <<'NOTE'
  THE PATH A PACKET TAKES:

    pod sends to 10.96.x.x:80  (the ClusterIP)
        |
        v
    iptables PREROUTING/OUTPUT -> KUBE-SERVICES chain
        |
        v
    KUBE-SVC-xxxx chain: picks ONE endpoint, statistically
        |
        v
    KUBE-SEP-xxxx chain: DNAT to a real pod IP:port
        |
        v
    the packet is routed to that pod by the CNI

  So the "load balancer" is not a process - it is DNAT rules, refreshed by
  kube-proxy whenever endpoints change. Nothing terminates the connection.

  At large scale iptables becomes slow (rules are evaluated linearly), which is
  why production clusters switch kube-proxy to IPVS mode, or replace it with
  eBPF (Cilium).
NOTE

hr "7. TROUBLESHOOTING: A SERVICE WITH NO ENDPOINTS"
run "kubectl apply -f $M/06-broken-endpoints.yaml"
sleep 3
run "kubectl get svc broken-backend-service"
echo ">> The Service was created successfully and HAS a ClusterIP. Looks healthy."
echo
echo "--- but nothing answers ---"
echo "\$ wget http://broken-backend-service"
printf '  result: '; hit http://broken-backend-service; echo "(empty - connection refused)"
echo
echo "--- STEP 1: check the endpoints. This is always the first move. ---"
run "kubectl get endpoints broken-backend-service"
run "kubectl get endpointslice -l kubernetes.io/service-name=broken-backend-service"
echo ">> ENDPOINTS = <none>. The Service matches ZERO pods."
echo
echo "--- STEP 2: compare the Service selector with the pod labels ---"
run "kubectl get svc broken-backend-service -o jsonpath='service selector: {.spec.selector}{\"\\n\"}'"
run "kubectl get pods -l app=backend -o jsonpath='pod labels:      {.items[0].metadata.labels}{\"\\n\"}'"
echo ">> selector says app=wrong-backend-name, the pods say app=backend."
echo
echo "--- STEP 3: fix the selector ---"
echo "\$ kubectl patch svc broken-backend-service -p '{\"spec\":{\"selector\":{\"app\":\"backend\"}}}'"
kubectl patch svc broken-backend-service -p '{"spec":{"selector":{"app":"backend"}}}'
sleep 3
run "kubectl get endpoints broken-backend-service"
printf '  wget now returns: '; hit http://broken-backend-service; echo
echo
cat <<'NOTE'
  EMPTY ENDPOINTS - THE FOUR CAUSES, IN ORDER OF FREQUENCY:

    1. selector does not match the pod labels        (this drill)
    2. the pods exist but are NOT READY              (readiness probe failing)
    3. targetPort does not match the container port
    4. the pods are in a DIFFERENT NAMESPACE than the Service

  Cause 2 is the sneaky one: `kubectl get pods` shows Running, but READY is
  0/1, and only READY pods are added to endpoints.
NOTE

hr "8. A SERVICE WITHOUT A SELECTOR"
PODIP=$(kubectl get pods -l app=backend -o jsonpath='{.items[0].status.podIP}')
sed "s/PLACEHOLDER_IP/$PODIP/" "$M/07-no-selector.yaml" > /tmp/no-selector.yaml
run "cat /tmp/no-selector.yaml | tail -14"
run "kubectl apply -f /tmp/no-selector.yaml"
sleep 3
run "kubectl get svc manual-endpoints"
run "kubectl get endpointslice -l kubernetes.io/service-name=manual-endpoints"
printf '  wget http://manual-endpoints -> '; hit http://manual-endpoints; echo
echo
echo ">> A Service with no selector does not get endpoints automatically, so you"
echo ">> supply them yourself. This is how you put a stable in-cluster name in"
echo ">> front of something Kubernetes does NOT manage: an external database, a"
echo ">> legacy VM, or a service in another cluster."
echo ">> Compare with ExternalName, which is DNS-only: this form gives you a real"
echo ">> ClusterIP and real load balancing over addresses you choose."

hr "9. CLEAN UP"
kubectl delete -f /tmp/no-selector.yaml >/dev/null 2>&1
run "kubectl get svc"
