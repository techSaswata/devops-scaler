# 10 — Kubernetes Networking & Services

**Saswata Das — 24BCS10248**

> **Status: wireframe.** This file is a placeholder describing the planned scope.
> It will be replaced with the completed write-up, captured command output and
> screenshots.

## Planned scope

| # | Topic | Planned deliverable |
|---|---|---|
| 1 | The problem Services solve | Pod IPs are ephemeral; Services are stable |
| 2 | The four ports | `nodePort` vs `port` vs `targetPort` vs `containerPort`, demonstrated not just tabulated |
| 3 | ClusterIP | The default; internal-only access |
| 4 | NodePort | Reaching a Service from outside the cluster |
| 5 | LoadBalancer | Behaviour on a local cluster vs a cloud provider |
| 6 | ExternalName | A CNAME alias to an out-of-cluster host |
| 7 | Headless (`clusterIP: None`) | Per-pod DNS A records, with a StatefulSet |
| 8 | Cluster DNS | CoreDNS, service FQDNs and cross-namespace resolution |
| 9 | Endpoints / EndpointSlice | How a Service actually finds its pods |
| 10 | kube-proxy | How traffic is forwarded under the hood |
| 11 | Troubleshooting | Empty endpoints caused by a selector mismatch |

## Planned layout

```
10-k8s-networking-services/
├── README.md
├── manifests/
├── scripts/
├── outputs/
└── screenshots/
```
