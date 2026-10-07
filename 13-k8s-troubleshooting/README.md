# 13 — Kubernetes Troubleshooting

**Saswata Das — 24BCS10248**

> **Status: wireframe.** Placeholder describing the planned scope. Will be replaced
> with the completed write-up, captured output and screenshots.

Source: **Session 14** of the DevOps homework document.

## Planned scope

| # | Task | Deliverable |
|---|---|---|
| 1 | Troubleshooting commands | `get`, `describe`, `logs`, `exec`, `events`, `explain`, `top`, `get -o wide` |
| 2 | Common issues | CrashLoopBackOff, ImagePullBackOff, ErrImagePull, Pending, ContainerCreating, Service connectivity, DNS, Pod networking, configuration — each identified, investigated, root-caused, fixed and verified |
| 3 | Mini project | The Session 14 troubleshooting mini project |

## Planned layout

```
13-k8s-troubleshooting/
├── README.md        the write-up
├── manifests/       YAML / config applied
├── scripts/         the scripts that produce every result
├── outputs/         raw captured logs
└── screenshots/     PNGs embedded in the README
```
