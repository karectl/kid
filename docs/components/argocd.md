# Argo CD

[Argo CD](https://argo-cd.readthedocs.io/) implements **GitOps**: the desired state of the TRE lives
in Git, and Argo CD continuously makes the cluster match it. Git history becomes the change log,
pull requests become change control, and manual drift gets reverted automatically (`selfHeal`).

## App of apps

```text
root  (Application, created by bootstrap.sh from gitops/root-app.yaml)
 └─ gitops/apps  (Helm chart)  renders:
     ├─ platform          gitops/platform            wave 0
     ├─ keycloak          gitops/keycloak            wave 0
     ├─ portal            gitops/portal              wave 0
     ├─ kyverno           kyverno Helm repo 3.3.4    wave 0
     ├─ jupyterhub        gitops/jupyterhub          wave 1
     ├─ network-policies  gitops/network-policies    wave 1
     ├─ kyverno-policies  gitops/kyverno             wave 1
     ├─ project-alpha     gitops/projects/chart      wave 2
     └─ project-beta      gitops/projects/chart      wave 2
```

The root Application passes `repoURL` and `revision` down to the chart, so **every** child app
follows the same fork and branch that `bootstrap.sh` detected.

## Using it

* UI: **`/argocd/`**, user `admin`, password from `tre info`.
* CLI (inside the dev container):

    ```bash
    argocd login --core            # talk to the cluster directly via kubeconfig
    kubectl config set-context --current --namespace=argocd
    argocd app list
    argocd app get project-alpha
    argocd app diff jupyterhub
    kubectl config set-context --current --namespace=default
    ```

* Or simply: `kubectl -n argocd get applications` / `tre status`.

## Sync behaviour

| Setting | Value | Meaning |
|---|---|---|
| `automated.prune` | true | Things removed from Git are deleted from the cluster |
| `automated.selfHeal` | true | Manual changes to managed objects are reverted |
| `timeout.reconciliation` | 60s | How often Git is polled (`tre sync` forces it now) |
| `retry` | 10×, backoff | Gives CRDs from other apps time to appear |
| `ServerSideApply` | true | Handles large CRDs (Kyverno) cleanly |

!!! tip "Try it"
    `kubectl -n project-alpha delete resourcequota project-quota` and then run
    `kubectl -n project-alpha get resourcequota` a few times. Argo CD puts it back within
    seconds. Objects you create yourself (not in Git) are left alone.

## Why it matters for a TRE

* **Auditability**: every change to the platform is a commit with an author and a review.
* **Reproducibility**: a new environment is `bootstrap.sh` plus a Git URL.
* **Drift control**: no quiet manual firewall exceptions that nobody remembers.
* **Environment promotion**: K8TRE promotes the same Git content through dev → stg → prod.

## Memory trimming

KID scales the Dex (SSO), notifications and ApplicationSet controllers to zero because the demo
doesn't use them. See `bootstrap.sh`.
