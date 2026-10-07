# Security — Final Project

## Controls in the pipeline

| Stage | Tool | Catches | Gate |
|---|---|---|---|
| SAST | bandit | insecure patterns in our code | fail on HIGH |
| SCA | pip-audit / Trivy fs | CVEs in dependencies | fail on HIGH/CRITICAL (fixable) |
| Secret scanning | gitleaks | credentials in the repo and its history | fail on any |
| Image scanning | Trivy | CVEs inside the built image | fail on HIGH/CRITICAL (fixable) |
| Config scanning | Trivy config | misconfigured manifests | report |
| Gate | job `needs:` | no push without every control passing | blocking |

## Runtime hardening

| Setting | Why |
|---|---|
| `runAsNonRoot` + `runAsUser: 10001` | a container running as root shares the host's uid 0 |
| `readOnlyRootFilesystem: true` | an attacker cannot drop a binary into the container |
| `allowPrivilegeEscalation: false` | blocks setuid escalation |
| `capabilities.drop: [ALL]` | removes every Linux capability |
| `seccompProfile: RuntimeDefault` | restricts the syscall surface |
| resource `limits` | a runaway container cannot starve the node |

## Secrets

No credential is committed. `DB_PASSWORD` and `API_KEY` are read from the environment,
supplied by a Kubernetes Secret created **out of band**:

```bash
kubectl -n finalproject create secret generic task-api-secret \
  --from-literal=DB_PASSWORD='<real>' --from-literal=API_KEY='<real>'
```

`kubernetes/02-secret.example.yaml` documents the shape with `REPLACE_ME` placeholders only.

CI authenticates to the registry with the auto-injected `GITHUB_TOKEN`, scoped to this
repository and expiring with the job — there is no stored registry credential.

## Reporting

Open a private security advisory rather than a public issue.
