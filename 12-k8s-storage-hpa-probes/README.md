# 12 — Kubernetes Storage, HPA & Probes

**Saswata Das — 24BCS10248**

> **Status: wireframe.** Placeholder describing the planned scope. Will be replaced
> with the completed write-up, captured output and screenshots.

Source: **Session 13** of the DevOps homework document.

## Planned scope

| # | Task | Deliverable |
|---|---|---|
| 1 | Kubernetes Volumes | `01-kubernetes-volumes/README.md` covering emptyDir, hostPath, PersistentVolume, PersistentVolumeClaim, StorageClass and dynamic provisioning, with working examples |
| 2 | HPA hands-on | Deploy app, configure HPA, deploy a load generator, drive CPU up, observe scaling via `kubectl get hpa` / `top pods` / `describe hpa` |
| 3 | Mini project | The Session 13 mini project |

## Planned layout

```
12-k8s-storage-hpa-probes/
├── README.md        the write-up
├── manifests/       YAML / config applied
├── scripts/         the scripts that produce every result
├── outputs/         raw captured logs
└── screenshots/     PNGs embedded in the README
```
