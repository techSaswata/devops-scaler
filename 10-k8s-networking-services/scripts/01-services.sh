#!/usr/bin/env bash
# Module 10, part 1 — the five Service types.
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }
M="$(cd "$(dirname "$0")/.." && pwd)/manifests"
CLIENT=net-client
hit(){ kubectl exec "$CLIENT" -- wget -qO- --timeout=3 "$1" 2>/dev/null | tr -d '\r\n'; }

kubectl delete deployment,sts,svc,pod --all --force --grace-period=0 >/dev/null 2>&1
kubectl delete pvc --all >/dev/null 2>&1
sleep 4

hr "0. THE BACKEND EVERY SERVICE POINTS AT"
run "kubectl apply -f $M/00-backend.yaml"
kubectl rollout status deployment/backend --timeout=240s
run "kubectl get pods -l app=backend -o wide"
echo ">> Each pod serves its OWN name, so load balancing is visible."
kubectl run "$CLIENT" --image=busybox:1.36 --restart=Never -- sleep infinity >/dev/null 2>&1
kubectl wait --for=condition=Ready pod/"$CLIENT" --timeout=180s >/dev/null 2>&1
echo
echo ">> A pod IP is EPHEMERAL - this is the problem Services exist to solve:"
run "kubectl get pods -l app=backend -o jsonpath='{range .items[*]}{.metadata.name}{\"  \"}{.status.podIP}{\"\\n\"}{end}'"
VICTIM=$(kubectl get pods -l app=backend -o jsonpath='{.items[0].metadata.name}')
OLDIP=$(kubectl get pod "$VICTIM" -o jsonpath='{.status.podIP}')
kubectl delete pod "$VICTIM" >/dev/null 2>&1
kubectl rollout status deployment/backend --timeout=180s >/dev/null 2>&1
echo
echo "deleted $VICTIM (was $OLDIP); after the controller replaced it:"
run "kubectl get pods -l app=backend -o jsonpath='{range .items[*]}{.metadata.name}{\"  \"}{.status.podIP}{\"\\n\"}{end}'"
echo ">> New name, NEW IP. Hard-coding pod IPs is therefore never viable."

hr "1. CLUSTERIP — the default, internal only"
run "kubectl apply -f $M/01-clusterip.yaml"
run "kubectl get svc backend-clusterip"
run "kubectl describe svc backend-clusterip | head -14"
echo
echo "--- the ClusterIP is VIRTUAL: nothing owns it, no interface has it ---"
CIP=$(kubectl get svc backend-clusterip -o jsonpath='{.spec.clusterIP}')
echo "ClusterIP = $CIP"
echo
echo "\$ wget backend-clusterip  x6   (load balanced across the 3 pods)"
for i in $(seq 1 6); do printf '  request %d: ' "$i"; hit http://backend-clusterip; echo; done
echo
echo "--- by NAME, by FQDN, and by IP - all equivalent ---"
run "kubectl exec $CLIENT -- wget -qO- --timeout=3 http://backend-clusterip"
run "kubectl exec $CLIENT -- wget -qO- --timeout=3 http://backend-clusterip.default.svc.cluster.local"
run "kubectl exec $CLIENT -- wget -qO- --timeout=3 http://$CIP"
echo
echo "--- ENDPOINTS: how the Service finds its pods ---"
run "kubectl get endpoints backend-clusterip"
run "kubectl get endpointslice -l kubernetes.io/service-name=backend-clusterip"
echo ">> The Service does not know about pods directly. The endpoints controller"
echo ">> watches for pods matching the selector that are READY, and maintains"
echo ">> this list. kube-proxy then programs it into iptables."
echo
echo "--- NOT reachable from outside the cluster ---"
echo "\$ curl --max-time 3 http://$CIP  (from the macOS host)"
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 3 "http://$CIP" 2>&1 || echo "no route - as expected"
echo ">> ClusterIP is cluster-internal by definition. That is the point."

hr "2. NODEPORT — reachable from outside, on every node"
run "kubectl apply -f $M/02-nodeport.yaml"
run "kubectl get svc backend-nodeport"
echo ">> NodePort ALSO gets a ClusterIP. NodePort is a superset of ClusterIP."
echo
echo "--- the same port is opened on EVERY node ---"
run "kubectl get nodes -o wide --no-headers | awk '{print \$1, \$6}'"
echo
# kube-proxy needs a moment to program the iptables rules for a brand-new
# Service. Curling immediately after `apply` races that and silently returns
# nothing, so poll until the nodePort actually answers.
printf 'waiting for kube-proxy to program the nodePort'
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://localhost:30080/ 2>/dev/null)
  [ "$code" = "200" ] && { echo " - ready after ${i}s"; break; }
  printf '.'; sleep 1
done
echo
echo "\$ curl http://localhost:30080/  (host port 30080 -> control-plane node:30080)"
for i in 1 2 3 4; do
  printf '  request %d: ' "$i"
  curl -s --max-time 5 -w ' [HTTP %{http_code}]' http://localhost:30080/ | tr -d '\n'; echo
done
echo ">> Reached from the macOS host, load balanced across all 3 pods."
echo ">> kind maps host:30080 to the control-plane container's port 30080."
echo
echo "--- hitting a node that runs NO backend pod still works ---"
run "kubectl get pods -l app=backend -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName --no-headers"
echo ">> Any node accepts traffic on the nodePort and forwards it to a pod,"
echo ">> wherever that pod lives. kube-proxy does the redirection."
echo
echo "--- the 4 ports, on one object ---"
run "kubectl get svc backend-nodeport -o jsonpath='port={.spec.ports[0].port}  targetPort={.spec.ports[0].targetPort}  nodePort={.spec.ports[0].nodePort}{\"\\n\"}'"
run "kubectl get deployment backend -o jsonpath='containerPort={.spec.template.spec.containers[0].ports[0].containerPort}{\"\\n\"}'"
echo
cat <<'NOTE'
  nodePort      30080  the port on every NODE            <- external clients
  port          80     the port on the SERVICE           <- other pods
  targetPort    80     the port on the POD               <- where traffic lands
  containerPort 8080   declared in the Deployment        <- DOCUMENTATION ONLY

  Note containerPort says 8080 while nginx really listens on 80, and everything
  still works. containerPort is purely informational; ONLY targetPort decides
  where traffic is sent. This is a deliberate demonstration of a field that
  people routinely believe is load-bearing.
NOTE

hr "3. LOADBALANCER — needs a cloud provider"
run "kubectl apply -f $M/03-loadbalancer.yaml"
sleep 8
run "kubectl get svc backend-loadbalancer"
echo
echo ">> EXTERNAL-IP is <pending>, and it will stay that way. This is EXPECTED:"
echo ">> a LoadBalancer Service asks the cloud-controller-manager to provision a"
echo ">> real load balancer (an AWS ELB, a GCP forwarding rule). A local kind"
echo ">> cluster has no cloud provider, so nobody answers the request."
echo
echo "--- but it still allocated a NodePort, so it IS reachable ---"
run "kubectl get svc backend-loadbalancer -o jsonpath='type={.spec.type}  nodePort={.spec.ports[0].nodePort}  clusterIP={.spec.clusterIP}{\"\\n\"}'"
echo ">> LoadBalancer is a superset of NodePort, which is a superset of ClusterIP."
echo ">> Each type builds on the one before it:"
echo ">>    ClusterIP  ->  + nodePort  =  NodePort  ->  + cloud LB  =  LoadBalancer"
run "kubectl exec $CLIENT -- wget -qO- --timeout=3 http://backend-loadbalancer"
echo ">> Still works internally via its ClusterIP."

hr "4. EXTERNALNAME — a CNAME to something outside the cluster"
run "kubectl apply -f $M/04-externalname.yaml"
run "kubectl get svc external-db"
echo ">> No CLUSTER-IP, no selector, no endpoints - it is pure DNS."
run "kubectl get endpoints external-db 2>&1 | head -3"
echo
echo "--- CoreDNS returns a CNAME, not an A record for a cluster IP ---"
run "kubectl exec $CLIENT -- nslookup external-db.default.svc.cluster.local 2>&1 | head -12"
echo
echo ">> Used to give in-cluster workloads a STABLE INTERNAL NAME for an"
echo ">> external dependency (a managed RDS instance, a third-party API)."
echo ">> Switch environments by changing externalName - the app never changes."
echo
echo ">> CAVEAT: it is DNS only. No proxying, no port remapping, no TLS handling."
echo ">> If the client sends an SNI/Host header, it sends the EXTERNAL name."

hr "5. HEADLESS SERVICE — no virtual IP, direct pod DNS"
run "kubectl apply -f $M/05-headless.yaml"
kubectl rollout status statefulset/sts --timeout=240s
run "kubectl get svc backend-headless sts-headless"
echo ">> CLUSTER-IP is None. There is no virtual IP and no load balancing."
echo
# Query the FULL FQDN. A short name makes busybox walk every entry in
# /etc/resolv.conf's search list and print an NXDOMAIN for each miss, which
# buries the real answer in noise.
echo "--- a NORMAL service resolves to ONE virtual IP ---"
run "kubectl exec $CLIENT -- nslookup backend-clusterip.default.svc.cluster.local 2>&1 | grep -A1 '^Name:'"
run "kubectl get svc backend-clusterip -o jsonpath='the service ClusterIP is {.spec.clusterIP}{\"\\n\"}'"
echo ">> One name, one virtual IP. The client never learns the pod addresses."
echo
echo "--- a HEADLESS service resolves to ALL the POD IPs ---"
run "kubectl exec $CLIENT -- nslookup backend-headless.default.svc.cluster.local 2>&1 | grep -A1 '^Name:'"
run "kubectl get pods -l app=backend -o jsonpath='{range .items[*]}{.status.podIP}{\"\\n\"}{end}'"
echo ">> Same addresses. The client now sees every pod and chooses for itself."
echo
echo "--- with a StatefulSet, each pod gets a STABLE DNS NAME ---"
run "kubectl get pods -l app=sts-demo -o wide"
for p in sts-0 sts-1 sts-2; do
  echo "\$ wget http://$p.sts-headless.default.svc.cluster.local"
  printf '  '; hit "http://$p.sts-headless.default.svc.cluster.local"; echo
done
echo ">> sts-0, sts-1, sts-2 are individually addressable and STABLE."
echo ">> This is exactly what clustered databases need: replicas must be able to"
echo ">> reach a SPECIFIC peer, not 'any one of them'."

hr "6. SUMMARY OF ALL FIVE"
run "kubectl get svc"
cat <<'NOTE'

  TYPE           CLUSTER-IP   EXTERNAL ACCESS        TYPICAL USE
  ------------   ----------   --------------------   ----------------------------
  ClusterIP      virtual IP   no                     internal microservices (default)
  NodePort       virtual IP   <anyNodeIP>:30000+     dev/test, or behind an external LB
  LoadBalancer   virtual IP   cloud LB public IP     production public entry (cloud only)
  ExternalName   none         n/a (CNAME out)        alias an external host
  Headless       None         no                     StatefulSets, client-side LB, peer discovery

NOTE
