# Troubleshooting lab

Four faults, each a different diagnostic surface, applied to a copy of the stack
in the `clinicflow-broken` namespace so the working deployment is untouched.

Each one is diagnosable **from the cluster alone** — none requires reading the
manifest that caused it, which is the point. In a real incident nobody hands you
the broken YAML.

| # | File | Symptom | Where the answer is |
| --- | --- | --- | --- |
| 1 | `01-broken-image.yaml` | `ErrImagePull` / `ImagePullBackOff` | `kubectl describe pod` events |
| 2 | `02-broken-service.yaml` | Pod `Running`, nothing can reach it | `kubectl get endpoints` — empty |
| 3 | `03-broken-probe.yaml` | `Running` but `0/1 READY` forever | probe events in `describe` |
| 4 | `04-broken-resources.yaml` | `Pending`, never scheduled | scheduler events |

Run the whole lab, which applies each fault, diagnoses it, fixes it and verifies
the fix:

```bash
./scripts/04-troubleshooting.sh
```

## Why these four

They cover the four layers a request has to pass through, bottom-up:

1. **Can the container exist at all?** (image)
2. **Can the scheduler place it?** (resources)
3. **Is Kubernetes willing to send it traffic?** (probes)
4. **Does the Service actually point at it?** (selector)

A fault at any layer produces a *different* symptom, and the skill being
practised is reading the symptom backwards to the layer — not memorising YAML.
