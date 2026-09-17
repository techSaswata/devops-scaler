# 11 — Kubernetes Ingress, ConfigMaps & Secrets

**Saswata Das — 24BCS10248**

> **Status: wireframe.** This file is a placeholder describing the planned scope.
> It will be replaced with the completed write-up, captured command output and
> screenshots.

## Planned scope

| # | Topic | Planned deliverable |
|---|---|---|
| 1 | ConfigMaps | Creating them imperatively and declaratively |
| 2 | Consuming ConfigMaps | As environment variables and as mounted files |
| 3 | Secrets | Creation, and what `Opaque` actually stores |
| 4 | The base64 gotcha | Secrets are **encoded, not encrypted** — demonstrated by decoding one |
| 5 | Consuming Secrets | `envFrom`, `secretKeyRef`, and volume mounts |
| 6 | Live config updates | Which changes propagate to a running pod and which need a restart |
| 7 | Ingress controller | Installing one and understanding controller vs resource |
| 8 | Path-based routing | One host, several backends |
| 9 | Host-based routing | Several hostnames on one entry point |
| 10 | TLS termination | A self-signed certificate served through Ingress |
| 11 | Full demo | Frontend + backend wired to a ConfigMap, a Secret and an Ingress |
| 12 | Troubleshooting | A malformed base64 value in a Secret, diagnosed from cluster output |

## Planned layout

```
11-k8s-ingress-configmaps-secrets/
├── README.md
├── manifests/
├── scripts/
├── outputs/
└── screenshots/
```
