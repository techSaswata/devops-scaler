# 09 — Kubernetes Pods, ReplicaSets & Deployments

**Saswata Das — 24BCS10248**

> **Status: wireframe.** This file is a placeholder describing the planned scope.
> It will be replaced with the completed write-up, captured command output and
> screenshots.

## Planned scope

| # | Topic | Planned deliverable |
|---|---|---|
| 1 | Pods | Single and multi-container Pods, shared network and volume namespace |
| 2 | Pod lifecycle | `Pending`, `Running`, `Succeeded`, `Failed`, `CrashLoopBackOff`, `ImagePullBackOff` — each reproduced deliberately |
| 3 | Probes | Readiness, liveness and startup probes, with a failing probe demonstrated |
| 4 | Init containers | Ordering guarantees before the main container starts |
| 5 | ReplicaSets | Desired state, the selector, and self-healing on pod deletion |
| 6 | Deployments | The Deployment → ReplicaSet → Pod ownership chain |
| 7 | Rollouts | Rolling update, `rollout status`, `rollout history`, `rollout undo` |
| 8 | Strategies | RollingUpdate vs Recreate, plus blue-green and canary patterns |
| 9 | DaemonSets & StatefulSets | Where each applies and how they differ |
| 10 | Troubleshooting | Selector mismatch and a broken image tag, diagnosed from cluster output |

## Planned layout

```
09-k8s-pods-replicasets-deployments/
├── README.md
├── manifests/
├── scripts/
├── outputs/
└── screenshots/
```
