# 17 — Terraform & Infrastructure as Code

**Saswata Das — 24BCS10248**

> **Status: wireframe.** Placeholder describing the planned scope. Will be replaced
> with the completed write-up, captured output and screenshots.

Source: **Session 18** of the DevOps homework document.

## Planned scope

| # | Task | Deliverable |
|---|---|---|
| 1 | Terraform S3 demo | `terraform-s3-demo/` with main/variables/outputs/provider/tfvars, running init → fmt → validate → plan → apply → show → output → destroy |
| 2 | AWS services research | `aws-services/` with `01-iam/`, `02-ec2/`, `03-s3/`, `04-vpc/`, `05-dynamodb-rds/`, each its own README |

## Planned layout

```
17-terraform-iac/
├── README.md        the write-up
├── manifests/       YAML / config applied
├── scripts/         the scripts that produce every result
├── outputs/         raw captured logs
└── screenshots/     PNGs embedded in the README
```
