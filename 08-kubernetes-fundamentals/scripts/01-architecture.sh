#!/usr/bin/env bash
# Module 08 — Kubernetes cluster architecture, inspected on a REAL cluster.
set -u
hr(){ echo; echo "==================== $* ===================="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }

hr "1. THE CLUSTER"
run "kubectl cluster-info"
run "kubectl version"
run "kind get clusters"
echo
echo ">> Each kind 'node' is a Docker container running a real kubelet and"
echo ">> containerd. The control-plane / worker split below is genuine."
run "docker ps --filter name=devops-hw --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'"

hr "2. NODES"
run "kubectl get nodes"
run "kubectl get nodes -o wide"
echo
echo "--- the control plane is marked by a role LABEL and protected by a TAINT ---"
run "kubectl get node devops-hw-control-plane -o jsonpath='{.metadata.labels}' | tr ',' '\n' | head -12"
echo
run "kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints[*].key"
echo
echo ">> 'node-role.kubernetes.io/control-plane:NoSchedule' is why ordinary"
echo ">> workloads land on the workers and not on the control plane."

hr "3. WHAT A NODE REPORTS TO THE API SERVER"
echo "\$ kubectl describe node devops-hw-worker"
kubectl describe node devops-hw-worker 2>&1 | sed -n '1,12p'
echo "   ..."
kubectl describe node devops-hw-worker 2>&1 | sed -n '/^Conditions:/,/^Addresses:/p' | head -14
echo "   ..."
kubectl describe node devops-hw-worker 2>&1 | sed -n '/^Capacity:/,/^System Info:/p' | head -16
echo
echo ">> The kubelet on each node continuously posts this status. When it stops,"
echo ">> the node-controller marks the node NotReady and evicts its pods."

hr "4. CONTROL PLANE COMPONENTS — running as real pods"
run "kubectl get pods -n kube-system -o wide"
echo
cat <<'NOTE'

  WHAT EACH ONE DOES

  kube-apiserver        The front door. EVERY read and write goes through it -
                        kubectl, the kubelets, the controllers. It is the only
                        component that talks to etcd.

  etcd                  The database. A distributed key-value store holding the
                        entire cluster state. Lose etcd and you lose the cluster;
                        this is the one thing you must back up.

  kube-scheduler        Watches for Pods with no node assigned, and picks one -
                        by filtering nodes that CAN run it (resources, taints,
                        affinity), then scoring the survivors.

  kube-controller-      Runs the control loops: node, replicaset, deployment,
  manager               endpoint, job controllers and more. Each loop compares
                        DESIRED state with ACTUAL state and acts on the gap.

  ON EVERY NODE (including the control plane)

  kubelet               The node agent. Takes the PodSpecs assigned to its node
                        and makes them true, via the container runtime. Reports
                        node and pod status back to the API server.
                        NOTE: it is NOT a pod - see section 5.

  kube-proxy            Programs the node's iptables/IPVS rules so Service IPs
                        resolve to real pod IPs. This is what makes a ClusterIP
                        actually route (module 10).

  kindnet               The CNI plugin in this cluster - gives every pod a
                        routable IP. On a cloud cluster this would be Calico,
                        Cilium, flannel, etc.

NOTE

hr "5. THE KUBELET IS NOT A POD — it is a host process"
echo "\$ docker exec devops-hw-worker systemctl is-active kubelet"
docker exec devops-hw-worker systemctl is-active kubelet 2>&1
echo
echo "\$ docker exec devops-hw-worker ps -o pid,comm -C kubelet"
docker exec devops-hw-worker ps -o pid,comm -C kubelet 2>&1 | head -3
echo
echo ">> This is the bootstrap problem: something must start the pods, so it"
echo ">> cannot itself be a pod. The kubelet runs as a systemd service on the host."

hr "6. STATIC PODS — how the control plane bootstraps itself"
echo "\$ docker exec devops-hw-control-plane ls /etc/kubernetes/manifests/"
docker exec devops-hw-control-plane ls /etc/kubernetes/manifests/ 2>&1
echo
echo ">> The kubelet watches this directory and runs whatever it finds, WITHOUT"
echo ">> going through the API server. That is how kube-apiserver itself gets"
echo ">> started - a pod that the scheduler could not possibly have scheduled."
echo
echo "\$ kubectl get pods -n kube-system kube-apiserver-devops-hw-control-plane -o jsonpath='{.metadata.ownerReferences}'"
kubectl get pods -n kube-system kube-apiserver-devops-hw-control-plane -o jsonpath='{.metadata.ownerReferences[*].kind}' 2>&1
echo
echo ">> Owned by 'Node', not by a ReplicaSet - the signature of a static pod."

hr "7. NAMESPACES"
run "kubectl get namespaces"
echo
cat <<'NOTE'
  default           where your objects go if you do not say otherwise
  kube-system       the cluster's own components - do not put your apps here
  kube-public       world-readable; holds cluster-info for bootstrapping
  kube-node-lease   node heartbeat Lease objects (cheaper than status updates)
  local-path-storage  kind's default StorageClass provisioner
NOTE
run "kubectl get pods --all-namespaces --no-headers | wc -l"
echo "(total pods running across the whole cluster)"

hr "8. WHAT THE API SERVER ACTUALLY EXPOSES"
run "kubectl api-resources --namespaced=true | head -14"
echo
run "kubectl api-resources --namespaced=false | head -10"
echo
echo ">> Note the SHORTNAMES column - 'po', 'svc', 'deploy', 'rs', 'ns', 'cm'."
echo ">> Also note APIVERSION: 'v1' for core objects, 'apps/v1' for Deployments."
