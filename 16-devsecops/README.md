# 16 — Complete CI/CD & DevSecOps

**Saswata Das — 24BCS10248**

> **Status: wireframe.** Placeholder describing the planned scope. Will be replaced
> with the completed write-up, captured output and screenshots.

Source: **Session 17** of the DevOps homework document.

## Planned scope

| # | Stage | Deliverable |
|---|---|---|
| 1 | CI/CD | build → unit test → Docker image → registry → Kubernetes deploy |
| 2 | Security | SAST, SCA, secret scanning, container image scanning, security gates |
| 3 | Flow | Code → Build → Test → SAST → SCA → Secret Scan → Docker Build → Image Scan → Gate → Push → Deploy |

## Planned layout

```
16-devsecops/
├── README.md        the write-up
├── manifests/       YAML / config applied
├── scripts/         the scripts that produce every result
├── outputs/         raw captured logs
└── screenshots/     PNGs embedded in the README
```
