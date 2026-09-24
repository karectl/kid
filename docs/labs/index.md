# Labs

The labs build on each other; do them in order. Each has **objectives**, **steps**, **what just
happened** notes and a few **check your understanding** questions for discussing in pairs.

| # | Lab | Time | You will... |
|---|---|---|---|
| 1 | [Orientation](01-orientation.md) | 20 min | Find your way around the cluster with `kubectl` |
| 2 | [Workspaces on demand](02-workspaces.md) | 30 min | Launch workspaces as different users and find them in Kubernetes |
| 3 | [Project isolation](03-project-isolation.md) | 30 min | Prove projects can't reach each other, and watch it in Hubble |
| 4 | [Internet egress](04-internet-egress.md) | 30 min | Block and then selectively allow outbound access |
| 5 | [Storage](05-storage.md) | 25 min | Follow data from a notebook to a directory on the node |
| 6 | [CPU and memory](06-resources.md) | 25 min | Hit limits, LimitRanges and quotas on purpose |
| 7 | [A new project](07-new-project.md) | 30 min | Add project *gamma* through GitOps and Keycloak |
| 8 | [Guardrails with Kyverno](08-kyverno.md) | 25 min | Get rejected by policy, then read the reports |
| 9 | [Posture with Kubescape](09-kubescape.md) | 20 min | Scan the cluster and triage findings |
| 10 | [Challenges](10-challenges.md) | open | Stretch exercises |

## Conventions

* `$` blocks run in the **dev container terminal**.
* **Notebook** blocks run in a JupyterLab notebook cell inside a workspace.
* Replace `<...>` with your own values.
* `k` is an alias for `kubectl` in the dev container.

!!! tip "If something doesn't match"
    Check [Troubleshooting](../reference/troubleshooting.md) first. Most surprises come from Argo CD
    still syncing, or from being logged in as the wrong user in the browser.
