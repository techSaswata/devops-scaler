# Security Policy

## Pipeline controls

| Stage | Tool | What it catches | Gate |
|---|---|---|---|
| SAST | **bandit** | insecure code patterns — weak hashes, `shell=True`, SQL built by string formatting, `debug=True` | fail on HIGH |
| SCA | **pip-audit** + **Trivy fs** | known CVEs in declared dependencies | fail on HIGH/CRITICAL with a fix available |
| Secret scanning | **gitleaks** | credentials committed to the repo or its history | fail on any finding |
| Image scanning | **Trivy image** | CVEs in OS packages and app libraries inside the built image | fail on HIGH/CRITICAL with a fix available |
| Gate | job dependencies | no image is pushed unless every scan passed | blocking |

## Reporting

Open a private security advisory rather than a public issue.

## Secrets

No credential is ever committed. The application reads `DB_PASSWORD` and `API_KEY` from the
environment, supplied in Kubernetes by a `Secret`. CI authenticates to the registry with the
auto-injected `GITHUB_TOKEN`, which is scoped to the repository and expires with the job.
