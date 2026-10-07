#!/usr/bin/env bash
# Module 12, part 1 — Kubernetes volumes and persistent storage.
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }
M="$(cd "$(dirname "$0")/.." && pwd)/manifests"

kubectl delete pod -l demo=volumes --force --grace-period=0 >/dev/null 2>&1
kubectl delete pvc manual-pvc dynamic-pvc --ignore-not-found >/dev/null 2>&1
kubectl delete pv manual-pv --ignore-not-found >/dev/null 2>&1
sleep 3

hr "1. STORAGECLASSES AVAILABLE ON THIS CLUSTER"
run "kubectl get storageclass"
echo ">> 'standard' is marked (default): a PVC that names no storageClassName"
echo ">> gets this one. kind uses rancher.io/local-path as its provisioner."
run "kubectl get storageclass standard -o jsonpath='provisioner={.provisioner}  reclaimPolicy={.reclaimPolicy}  volumeBindingMode={.volumeBindingMode}{\"\\n\"}'"
echo ">> volumeBindingMode=WaitForFirstConsumer means the volume is NOT created"
echo ">> until a pod actually uses the claim - so it can be placed on the right node."

hr "2. emptyDir — scratch space shared between containers in a pod"
run "kubectl apply -f $M/01-emptydir.yaml"
kubectl wait --for=condition=Ready pod/vol-emptydir --timeout=180s
sleep 6
echo
echo "--- the WRITER container writes ---"
run "kubectl exec vol-emptydir -c writer -- tail -3 /data/log.txt"
echo
echo "--- the READER container sees the SAME file ---"
run "kubectl exec vol-emptydir -c reader -- tail -3 /data/log.txt"
echo ">> Two containers, one volume. This is the main use of emptyDir:"
echo ">> passing data between containers in the same pod."
echo
echo "--- lifecycle: it dies WITH THE POD ---"
run "kubectl get pod vol-emptydir -o jsonpath='{.spec.volumes[0]}{\"\\n\"}'"
echo "\$ kubectl delete pod vol-emptydir && re-apply"
kubectl delete pod vol-emptydir --force --grace-period=0 >/dev/null 2>&1
kubectl apply -f "$M/01-emptydir.yaml" >/dev/null
kubectl wait --for=condition=Ready pod/vol-emptydir --timeout=180s >/dev/null
sleep 3
run "kubectl exec vol-emptydir -c reader -- cat /data/log.txt | wc -l"
echo ">> The line count restarted from 1 - the old data is GONE. emptyDir is"
echo ">> created empty when the pod is scheduled and deleted with it."
kubectl delete pod vol-emptydir --force --grace-period=0 >/dev/null 2>&1

hr "3. hostPath — a directory from the NODE"
run "kubectl apply -f $M/02-hostpath.yaml"
kubectl wait --for=condition=Ready pod/vol-hostpath --timeout=180s
run "kubectl get pod vol-hostpath -o wide"
run "kubectl exec vol-hostpath -- cat /host/data.txt"
echo
echo "--- the file is really on the NODE's filesystem ---"
echo "\$ docker exec devops-hw-worker cat /tmp/hostpath-demo/data.txt"
docker exec devops-hw-worker cat /tmp/hostpath-demo/data.txt 2>&1
echo
echo "--- it SURVIVES pod deletion ---"
kubectl delete pod vol-hostpath --force --grace-period=0 >/dev/null 2>&1
sleep 2
echo "\$ docker exec devops-hw-worker cat /tmp/hostpath-demo/data.txt   (pod is gone)"
docker exec devops-hw-worker cat /tmp/hostpath-demo/data.txt 2>&1
echo
cat <<'NOTE'
  >> BUT the data is tied to THAT ONE NODE. Reschedule the pod onto another
  >> node and it sees an empty directory - which is why the manifest pins
  >> nodeName. hostPath is also a security risk: the pod can read the host
  >> filesystem. Use it for node-level agents (log collectors, monitoring),
  >> never for application data.
NOTE

hr "4. PersistentVolume + PersistentVolumeClaim (STATIC provisioning)"
run "cat $M/03-pv-pvc.yaml | head -22"
run "kubectl apply -f $M/03-pv-pvc.yaml"
kubectl wait --for=condition=Ready pod/pvc-user --timeout=180s
echo
run "kubectl get pv manual-pv"
run "kubectl get pvc manual-pvc"
echo ">> STATUS=Bound on both. The claim found a PV that satisfied it:"
echo ">> same storageClassName, compatible accessModes, capacity >= request."
echo
echo "--- note the claim asked for 64Mi but got the whole 128Mi PV ---"
run "kubectl get pvc manual-pvc -o jsonpath='requested={.spec.resources.requests.storage}  bound capacity={.status.capacity.storage}{\"\\n\"}'"
echo ">> A PVC binds to a WHOLE PV. The extra capacity is not shared out."
echo
run "kubectl exec pvc-user -- cat /data/persisted.txt"
echo
echo "--- the data OUTLIVES the pod ---"
kubectl delete pod pvc-user --force --grace-period=0 >/dev/null 2>&1
sleep 2
kubectl apply -f "$M/03-pv-pvc.yaml" >/dev/null
kubectl wait --for=condition=Ready pod/pvc-user --timeout=180s >/dev/null
run "kubectl exec pvc-user -- cat /data/persisted.txt"
echo ">> Same content after a full pod delete and recreate."

hr "5. DYNAMIC provisioning — no PV created by hand"
run "kubectl apply -f $M/04-dynamic-pvc.yaml"
echo
echo "--- before a pod consumes it, the claim is PENDING ---"
sleep 2
run "kubectl get pvc dynamic-pvc"
echo ">> WaitForFirstConsumer: the provisioner holds off until a pod is scheduled."
kubectl wait --for=condition=Ready pod/dynamic-pvc-user --timeout=240s
echo
run "kubectl get pvc dynamic-pvc"
echo
echo "--- a PV was created AUTOMATICALLY ---"
run "kubectl get pv"
run "kubectl get pvc dynamic-pvc -o jsonpath='bound to PV: {.spec.volumeName}{\"\\n\"}'"
run "kubectl exec dynamic-pvc-user -- cat /data/hello.txt"
echo ">> Nobody wrote a PersistentVolume manifest. The StorageClass provisioner"
echo ">> created it on demand. This is how storage works on every cloud:"
echo ">> the provisioner calls the cloud API and attaches a real disk."

hr "6. SUMMARY"
run "kubectl get pv,pvc"
cat <<'NOTE'

  TYPE              LIFETIME                    SCOPE          TYPICAL USE
  ---------------   -------------------------   ------------   --------------------------
  emptyDir          dies with the POD           one pod        scratch, sharing between
                                                               containers in a pod
  hostPath          survives the pod            ONE NODE       node agents, log collectors
  PV + PVC static   survives the pod            cluster        admin-provisioned storage
  PV + PVC dynamic  survives the pod            cluster        the normal production case
  ConfigMap/Secret  as long as the object       cluster        configuration (module 11)

  THE KEY SEPARATION:
    PersistentVolume       the actual storage   -> the ADMINISTRATOR's concern
    PersistentVolumeClaim  a request for storage -> the DEVELOPER's concern
    StorageClass           how to create one on demand

  A pod never names a PV. It names a CLAIM. That indirection is what lets the
  same manifest run on kind, on EKS and on bare metal unchanged.

  RECLAIM POLICY (on the PV):
    Retain  keep the data after the PVC is deleted - manual cleanup
    Delete  delete the underlying storage too (the cloud default)
NOTE
