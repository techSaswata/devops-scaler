# What Argo CD syncs

Everything in this directory is applied to the cluster by Argo CD, not by
`kubectl`. `../application.yaml` points at this path, so **this directory is the
desired state** — editing a resource here and pushing is the only legitimate way
to change the running workload.

Two things are deliberately **absent**:

| Absent | Why |
| --- | --- |
| The `Secret` | Git is public. The Secret is created out of band at deploy time, so Argo CD syncs around it rather than owning it. |
| The `PersistentVolumeClaim` | A PVC is stateful. If Argo CD owned it, `prune: true` would be one bad commit away from deleting the data. This copy of the app is stateless (`DATA_DIR=/tmp`). |

This deploys into its **own namespace**, `finalproject-gitops`, separate from the
`kubectl`-applied stack in `finalproject`. That is on purpose: two controllers
owning one Deployment is a genuine anti-pattern — Argo CD would fight whatever
`kubectl apply` had just done, and `selfHeal` would make the loser permanent.
Keeping them apart means the drift correction shown in the README is Argo CD
reacting to *my* change, not to another controller's.
