# 20 — Final DevOps Project

**Saswata Das — 24BCS10248**

> **Status: wireframe.** Placeholder describing the planned scope. Will be replaced
> with the completed write-up, captured output and screenshots.

Source: **Session 21** of the DevOps homework document.

## Planned scope

End-to-end project: Application → Git → GitHub → CI → Build/Test → Security Scanning →
Docker Image → Registry → Kubernetes → Helm → Monitoring → GitOps.

```
final-devops-project/
├── application/   docker/      kubernetes/
├── helm/          terraform/   .github/workflows/
├── security/      monitoring/  gitops/
└── README.md
```

Plus the final troubleshooting challenge: introduce faults deliberately, then identify,
investigate, root-cause, fix, verify and document each one.

## Planned layout

```
20-final-devops-project/
├── README.md        the write-up
├── manifests/       YAML / config applied
├── scripts/         the scripts that produce every result
├── outputs/         raw captured logs
└── screenshots/     PNGs embedded in the README
```
