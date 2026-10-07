# Kubernetes Volumes

**Saswata Das — 24BCS10248** · Session 13, Task 1

Required deliverable: documentation of `emptyDir`, `hostPath`, `PersistentVolume`,
`PersistentVolumeClaim`, `StorageClass` and dynamic provisioning, with practical examples.

Every example here was applied to a live cluster — the captured run is in
[`../outputs/01-volumes.txt`](../outputs/01-volumes.txt) and the manifests in
[`../manifests/`](../manifests/).

---

## The problem volumes solve

A container's filesystem is **ephemeral**. Write a file, let the container restart, and the
file is gone — the container starts again from the image. Anything that must outlive a
restart, or be shared between containers, needs a volume.

Kubernetes volumes come in a spectrum, from "dies with the pod" to "outlives the cluster":

```
 emptyDir  ──▶  hostPath  ──▶  PersistentVolume + PVC  ──▶  dynamic provisioning
 pod scope      node scope       cluster scope                cloud/CSI backed
```

---

## 1. `emptyDir`

Scratch space created **empty** when the pod is scheduled and deleted when the pod is
removed. It survives a *container* restart, but not pod deletion or rescheduling.

```yaml
volumes:
  - name: scratch
    emptyDir: {}          # medium: Memory makes it a tmpfs (RAM-backed)
containers:
  - name: writer
    volumeMounts: [{ name: scratch, mountPath: /data }]
  - name: reader          # a SECOND container, same volume
    volumeMounts: [{ name: scratch, mountPath: /data }]
```

**What the run showed:** a `writer` container appended to `/data/log.txt` while a `reader`
container in the same pod read the identical file. After deleting and recreating the pod,
the line count restarted from 1 — the data was gone.

**Use it for:** passing data between containers in a pod (the sidecar pattern), scratch
space for sorting or caching, and checkpoint files a container rebuilds on restart.

> `emptyDir.medium: Memory` is a tmpfs — fast, but it **counts against the container's
> memory limit**, so a large file can get the pod OOMKilled.

---

## 2. `hostPath`

Mounts a path from the **node's own filesystem** into the pod.

```yaml
volumes:
  - name: node-disk
    hostPath:
      path: /tmp/hostpath-demo
      type: DirectoryOrCreate
```

**What the run showed:** the file written by the pod was readable directly on the node
(`docker exec devops-hw-worker cat /tmp/hostpath-demo/data.txt`) and **survived deleting
the pod**.

**The two catches:**

1. **The data is tied to one node.** Reschedule the pod elsewhere and it sees an empty
   directory. The demo manifest pins `nodeName` precisely because "the data is on the node"
   is otherwise meaningless.
2. **It is a security hole.** A pod with a `hostPath` of `/` can read the entire host
   filesystem. Most clusters restrict it via Pod Security Standards.

**Use it for:** node-level agents that are *meant* to see the host — log collectors reading
`/var/log`, monitoring agents reading `/proc`, CSI drivers. **Never for application data.**

---

## 3. `PersistentVolume` (PV) and `PersistentVolumeClaim` (PVC)

The central idea is a **separation of concerns**:

| Object | Means | Whose job |
|---|---|---|
| **PersistentVolume** | a piece of storage that exists | the **administrator** / the cloud |
| **PersistentVolumeClaim** | a *request* for storage | the **developer** |
| **StorageClass** | how to create storage on demand | the administrator |

A pod **never names a PV**. It names a *claim*. That indirection is what lets the same
manifest run unchanged on kind, on EKS and on bare metal.

### Static provisioning — an admin creates the PV by hand

```yaml
kind: PersistentVolume
spec:
  capacity: { storage: 128Mi }
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
---
kind: PersistentVolumeClaim
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: manual
  resources: { requests: { storage: 64Mi } }
```

Binding happens when the claim finds a PV with a matching `storageClassName`, compatible
`accessModes`, and **capacity ≥ request**.

**What the run showed:** both went `Bound`, and the data written through the PVC survived a
full pod delete-and-recreate.

> **A detail worth knowing:** the claim asked for `64Mi` and bound to the `128Mi` PV — and
> got the **whole thing**. A PVC binds to an entire PV; the extra capacity is not shared out
> or reclaimed.

### Access modes

| Mode | Short | Meaning |
|---|---|---|
| `ReadWriteOnce` | RWO | read-write by **one node** (the common case; most block storage) |
| `ReadOnlyMany` | ROX | read-only by many nodes |
| `ReadWriteMany` | RWX | read-write by many nodes — needs a shared filesystem (NFS, EFS, CephFS) |
| `ReadWriteOncePod` | RWOP | read-write by exactly **one pod** |

> RWO is per-**node**, not per-pod. Two pods on the *same* node can share an RWO volume;
> two pods on different nodes cannot. This surprises people constantly.

### Reclaim policy

| Policy | On PVC deletion |
|---|---|
| `Retain` | the PV and its data are kept; an admin cleans up manually |
| `Delete` | the PV **and the underlying storage** are deleted — the cloud default |

---

## 4. `StorageClass` and dynamic provisioning

With a StorageClass, **nobody writes a PV**. The provisioner creates one on demand.

```yaml
kind: PersistentVolumeClaim
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: standard     # kind's default: rancher.io/local-path
  resources: { requests: { storage: 100Mi } }
```

**What the run showed:**

```
# before any pod consumed the claim
dynamic-pvc   Pending    standard

# after the pod was scheduled
dynamic-pvc   Bound   pvc-c1c3f71b-784f-4f43-8608-01da21c5c9b8   100Mi   RWO   standard
```

A PV named `pvc-<uuid>` appeared that nobody wrote.

### `volumeBindingMode` — the field that explains the `Pending`

```
provisioner=rancher.io/local-path  reclaimPolicy=Delete  volumeBindingMode=WaitForFirstConsumer
```

`WaitForFirstConsumer` means the volume is **not created until a pod actually uses the
claim**. That is deliberate: the provisioner needs to know *which node* the pod landed on so
it can create the disk in the right place or availability zone.

> So a PVC sitting at `Pending` with no pod is **normal**, not broken. A PVC still `Pending`
> *with* a pod means something is actually wrong — no matching PV, no default StorageClass,
> or the provisioner is down.

### Provisioners by platform

| Platform | Default provisioner | Backing storage |
|---|---|---|
| kind (here) | `rancher.io/local-path` | a directory on the node |
| AWS EKS | `ebs.csi.aws.com` | EBS volume |
| GCP GKE | `pd.csi.storage.gke.io` | Persistent Disk |
| Azure AKS | `disk.csi.azure.com` | Azure Disk |

The manifest is identical across all four. Only the StorageClass name changes.

---

## 5. Choosing

| Need | Use |
|---|---|
| Scratch space, or sharing between containers in a pod | `emptyDir` |
| A node agent that must see the host filesystem | `hostPath` |
| Data that must survive the pod | **PVC** (dynamic) |
| Per-pod storage for a clustered database | `volumeClaimTemplates` in a StatefulSet |
| Configuration or credentials | ConfigMap / Secret ([module 11](../../11-k8s-ingress-configmaps-secrets/)) |

---

## Commands

| Task | Command |
|---|---|
| List storage classes | `kubectl get storageclass` |
| Which is default? | look for `(default)` in the NAME column |
| List volumes and claims | `kubectl get pv,pvc` |
| Why is a PVC Pending? | `kubectl describe pvc <name>` → read **Events** |
| What is a PV bound to? | `kubectl get pv -o custom-columns=NAME:.metadata.name,CLAIM:.spec.claimRef.name` |
| Which pod uses a PVC? | `kubectl get pods -o json \| jq '.items[] \| select(.spec.volumes[]?.persistentVolumeClaim.claimName=="x")'` |
