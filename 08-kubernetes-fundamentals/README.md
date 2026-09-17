# 08 — Kubernetes Fundamentals

**Saswata Das — 24BCS10248**

> **Status: wireframe.** This file is a placeholder describing the planned scope.
> It will be replaced with the completed write-up, captured command output and
> screenshots.

## Planned scope

| # | Topic | Planned deliverable |
|---|---|---|
| 1 | Why Kubernetes exists | The problems it solves that Docker alone does not |
| 2 | Cluster architecture | Control plane (`kube-apiserver`, `etcd`, scheduler, controller-manager) vs worker node (`kubelet`, `kube-proxy`, container runtime) |
| 3 | Building a local cluster | A real multi-node cluster, inspected with `kubectl` |
| 4 | Core objects | Node, Namespace, Pod, and how the API server models them |
| 5 | `kubectl` essentials | `get`, `describe`, `logs`, `exec`, `apply`, `delete`, `explain` |
| 6 | Declarative vs imperative | Manifests and the reconciliation loop |

## Planned layout

```
08-kubernetes-fundamentals/
├── README.md        the write-up
├── manifests/       YAML applied to the cluster
├── scripts/         the scripts that produce every result
├── outputs/         raw captured .txt logs
└── screenshots/     PNGs embedded in the README
```
