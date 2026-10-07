# 14 — Helm

**Saswata Das — 24BCS10248** · Session 15

Every Helm command in the task list, the full rollback workflow, and a mini project —
all run against the live cluster. Chart in [`webapp/`](webapp/), mini project in
[`mini-project/`](mini-project/), raw logs (777 lines) in [`outputs/`](outputs/).

```bash
./scripts/01-helm-commands.sh   # create, lint, template, install, list, status, get, repo, search
./scripts/02-rollback.sh        # install → upgrade → verify → upgrade → verify → rollback → verify
./scripts/03-mini-project.sh    # the Notes app, dev + prod from one chart
```

## Task coverage

| # | Task | Status |
|---|---|---|
| 1 | `create` `install` `list` `status` `get` `upgrade` `history` `rollback` `uninstall` `repo` `search` | ✔ all executed, output captured |
| 2 | Rollback workflow: install → upgrade → verify → upgrade → verify → rollback → verify | ✔ [Part 2](#part-2--the-rollback-workflow) |
| 3 | Mini project | ✔ [Part 3](#part-3--mini-project--the-notes-app) |

---

# Part 1 — Helm commands

## What Helm solves

Plain Kubernetes YAML has no variables. Running the same app in dev and prod means either
copy-pasting manifests and editing them by hand, or bolting on `sed`. Helm adds templating,
a values file, and — crucially — **release history**, so an upgrade can be undone.

## `helm create` and chart anatomy

![create and anatomy](screenshots/hc1-create-anatomy.png)

```
Chart.yaml        metadata: name, version, appVersion
values.yaml       DEFAULT configuration — everything overridable
templates/        Go templates rendered into manifests
  _helpers.tpl      reusable named templates (naming, labels)
  NOTES.txt         printed after install
.helmignore       excluded when packaging
```

> **`version` vs `appVersion`** are independent on purpose. `version` is the **chart's**
> version — bump it when the templates change. `appVersion` is the **application's** — bump
> it when the image changes. You can ship a chart fix without the app changing.

## `helm lint` and `helm template`

![lint and template](screenshots/hc2-lint-template.png)

```bash
helm lint webapp          # structural validation
helm template web webapp  # render locally, install NOTHING
```

> **`helm template` is the most useful debugging command in Helm.** It shows exactly what
> *would* be sent to the API server. When a chart misbehaves, render it first — the bug is
> usually visible in the output, not in the cluster.

## `--dry-run` and `helm install`

![dry run and install](screenshots/hc3-dryrun-install.png)

`--dry-run` goes further than `template`: it also runs **server-side validation**, so it
catches schema errors that local rendering can't.

```
NAME: web          STATUS: deployed          REVISION: 1
```

`NOTES.txt` is rendered too — the release name, namespace and revision in it are all
template values.

## `helm list` and `helm status`

![list and status](screenshots/hc4-list-status.png)

## `helm get` — what was actually installed

![get](screenshots/hc5-get.png)

```bash
helm get values web          # USER-SUPPLIED values only (empty on a default install)
helm get values web --all    # merged with chart defaults
helm get manifest web        # the rendered Kubernetes objects
helm get notes web
```

> The distinction between `get values` and `get values --all` matters when debugging: the
> first tells you what *someone chose to override*, the second what the app is *actually
> running with*.

## Verifying it runs

![verify](screenshots/hc6-verify-running.png)

The deployed page reports its own release name, revision and values:

![webapp release in browser](screenshots/browser-1-webapp-release.png)

## `helm repo`, `helm search`, `helm show`

![repo search show](screenshots/hc7-repo-search-show.png)

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm search repo bitnami/nginx     # repos you have added
helm search hub prometheus         # Artifact Hub, over the network
helm show chart bitnami/nginx      # inspect WITHOUT installing
helm show values bitnami/nginx     # see every tunable before committing
```

---

# Part 2 — The rollback workflow

The required sequence, executed end to end.

![install and upgrade](screenshots/rb1-install-upgrade.png)
![verify rev 2](screenshots/rb2-verify-rev2.png)
![upgrade to rev 3](screenshots/rb3-upgrade-rev3.png)

| Step | Action | Result |
|---|---|---|
| 1 | `helm install` | rev 1 — development, 2 replicas |
| 2 | `helm upgrade --set replicaCount=4 --set config.environment=staging` | rev 2 — staging, 4 replicas |
| 3 | verify | live page reports `env=staging replicas=4` |
| 4 | `helm upgrade -f values-prod.yaml` | rev 3 — production, 4 replicas |
| 5 | verify | live page reports `env=production` |
| 6 | `helm rollback web 2` | **rev 4**, carrying rev-2 content |
| 7 | verify | live page back to `env=staging` |

### `helm history` — the audit trail

```
REVISION  STATUS      CHART             DESCRIPTION
1         superseded  webapp-0.1.0      Install complete
2         superseded  webapp-0.1.0      Upgrade complete
3         superseded  webapp-0.1.0      Upgrade complete
4         superseded  webapp-0.1.0      Rollback to 2
5         deployed    webapp-0.1.0      Rollback to 3
```

![rollback](screenshots/rb4-rollback.png)

> **A rollback creates a NEW revision.** Rolling back to 2 produced revision **4**, not 2.
> History is append-only and never rewritten, so you can always roll forward again. The
> `DESCRIPTION` column records `Rollback to 2`.

![rollback to previous](screenshots/rb5-rollback-previous.png)

With **no revision number**, `helm rollback` goes back exactly one revision — from 4 to 3,
which was production. So it undid the previous rollback.

### Where the state lives

```
$ kubectl get secrets -n helm-demo -l owner=helm
sh.helm.release.v1.web.v1 ... v5     type: helm.sh/release.v1
```

**One Secret per revision, in the release namespace.** There is no external database — that
is the entire Helm state store, which is why `kubectl delete secret` on those is a way to
corrupt a release.

### Two flags worth knowing

| Flag | Effect |
|---|---|
| `--wait` | block until resources are actually Ready, so a failed upgrade surfaces immediately |
| `--atomic` | roll back automatically if the upgrade fails — `--wait` plus auto-undo |

---

# Part 3 — Mini project — the Notes app

[`mini-project/notes-chart/`](mini-project/notes-chart/) packages a Notes app with dev
defaults and a production overrides file.

![chart, dev vs prod](screenshots/mp1-chart-dev-prod.png)

Rendering both and diffing shows exactly what changes — and nothing is duplicated:

```
<   <tr><td>flag: export</td> ... false        ← dev
<   replicas: 1
---
>   <tr><td>flag: export</td> ... true         ← prod
>   replicas: 3
```

## Two releases of one chart, same cluster

![two releases](screenshots/mp2-two-releases.png)

```
NAME         NAMESPACE  REVISION  STATUS    CHART
notes-dev    notes      1         deployed  notes-chart-0.1.0
notes-prod   notes      1         deployed  notes-chart-0.1.0

notes-dev-notes-chart-64f9c9c-zrgwf        1/1  Running
notes-prod-notes-chart-5bdd64579b-78qm5    1/1  Running
notes-prod-notes-chart-5bdd64579b-7nhk7    1/1  Running
notes-prod-notes-chart-5bdd64579b-tcgqb    1/1  Running
```

**Two releases of the same chart coexisting in one namespace**, with no collision — because
the `fullname` helper bakes the release name into every resource name. That is the core
value of templating.

![notes dev](screenshots/browser-2-notes-dev.png)
![notes prod](screenshots/browser-3-notes-prod.png)

1 replica / development / `export: false` on the left; 3 replicas / production /
`export: true` on the right. Same chart.

## Packaging and independence

![independent and package](screenshots/mp3-independent-package.png)

```bash
helm package notes-chart        # → notes-chart-0.1.0.tgz
```

A `.tgz` is what you push to a chart repository (ChartMuseum, Harbor, or an OCI registry
such as GHCR). Installing from it is identical to installing from the directory.

![upgrade and uninstall](screenshots/mp4-upgrade-uninstall.png)

Upgrading dev to enable a feature flag left prod completely untouched.

> **`helm uninstall` purges history by default.** Pass `--keep-history` if you want the
> release to remain rollback-able after removal.

---

## The template feature that matters most

```yaml
annotations:
  checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

Hashing the ConfigMap into the pod template means a **values-only change rolls the pods**.
Without it, `helm upgrade --set config.message=...` would update the ConfigMap and leave
the running pods serving the old content — a genuinely confusing failure, because
`helm list` would show a new revision while the app behaved as before.

This is the Helm-native version of the same pattern noted in
[module 11](../11-k8s-ingress-configmaps-secrets/#12-what-happens-when-config-changes).

---

## Command reference

| Task | Command |
|---|---|
| Scaffold a chart | `helm create <name>` |
| Validate | `helm lint <chart>` |
| **Render without installing** | `helm template <release> <chart>` |
| Validate server-side | `helm install ... --dry-run` |
| Install | `helm install <release> <chart> -n <ns> --create-namespace --wait` |
| List releases | `helm list -n <ns>` / `helm list -A` |
| Release detail | `helm status <release>` |
| What was supplied? | `helm get values <release>` (`--all` to merge defaults) |
| Rendered manifests | `helm get manifest <release>` |
| Upgrade | `helm upgrade <release> <chart> --set k=v` / `-f values.yaml` |
| **Audit trail** | `helm history <release>` |
| Roll back | `helm rollback <release> [revision]` |
| Remove | `helm uninstall <release>` (`--keep-history`) |
| Repositories | `helm repo add\|list\|update` |
| Find charts | `helm search repo\|hub <term>` |
| Inspect a chart | `helm show chart\|values <chart>` |
| Package | `helm package <chart>` |

---

## Files in this folder

```
14-helm/
├── README.md
├── webapp/                       the chart used in parts 1 and 2
│   ├── Chart.yaml  values.yaml  values-prod.yaml
│   └── templates/  _helpers.tpl configmap.yaml deployment.yaml service.yaml NOTES.txt
├── mini-project/notes-chart/     the Notes app chart (dev + prod values)
├── scripts/                      3 capture scripts
├── outputs/                      777 lines of captured output
└── screenshots/                  19 PNGs — 16 terminal + 3 browser
```
