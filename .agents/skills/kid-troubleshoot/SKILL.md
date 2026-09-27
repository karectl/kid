---
name: kid-troubleshoot
description: Diagnose and fix problems with the KID training TRE environment - dev container bootstrap failures, Argo CD apps not syncing, Keycloak or JupyterHub login problems, workspaces that won't start, Hubble not connecting, and memory pressure on laptops or Codespaces. Use when something in the environment is broken, stuck, slow or returning errors.
---

# Troubleshooting KID

Work from the outside in, using read-only commands first. Explain each finding to the trainee.
Full symptom list: `docs/reference/troubleshooting.md`.

## 1. Overview

```bash
tre status        # Argo CD apps (Sync/Health) + pods not Running/Completed
tre usage         # node and pod memory; memory pressure causes most odd failures
kubectl get events -A --sort-by=.lastTimestamp | tail -30
```

## 2. By symptom

**Bootstrap failed / no cluster**: log at `/tmp/kid-bootstrap.log`. `kubectl get nodes` fails →
the k3s container isn't up: `docker ps` (look for `k3s-server`), `docker logs <id> | tail`.
Re-run with `tre bootstrap` (idempotent). Cilium stuck: `cilium status`,
`kubectl -n kube-system get pods -l k8s-app=cilium`. Docker Desktop needs ≥ 8 GB memory.

**Argo CD app OutOfSync/Degraded/Unknown**:
```bash
kubectl -n argocd get application <app> -o jsonpath='{.status.conditions}{"\n"}{.status.operationState.message}{"\n"}'
kubectl -n argocd get application root -o jsonpath='{.spec.source.repoURL} {.spec.source.targetRevision}{"\n"}'
```
- `unable to resolve ... to a commit SHA` → branch not pushed, or wrong `KID_GITOPS_REVISION`.
- `authentication required` → fork is private (make it public or add repo credentials).
- `no matches for kind ClusterPolicy/CiliumNetworkPolicy` right after bootstrap → CRDs not ready
  yet; Argo CD retries. `tre sync` to nudge.
- Local change not applied → not committed/pushed to the branch Argo CD follows.

**Login problems** (redirect loops, `Invalid redirect_uri`, wrong host):
`kubectl -n jupyterhub get cm cluster-domain -o yaml` must show the URL the browser uses. If not:
`tre bootstrap`, then `kubectl -n keycloak rollout restart deploy/keycloak` and
`kubectl -n jupyterhub rollout restart deploy/hub`. Codespaces: open the forwarded port from the
same browser as your GitHub login (private port). Keycloak slow/restarting:
`kubectl -n keycloak logs deploy/keycloak`, check OOMKilled in `kubectl -n keycloak describe pod`.

**Workspace won't start**: find the reason in this order:
1. Spawn page message ("not a member of any research project" = no project group → skill
   `kid-new-project`).
2. `kubectl -n jupyterhub logs deploy/hub --since=10m | grep -iE "error|forbidden|quota|profile"`
3. `kubectl -n project-<p> describe pod jupyter-<user>`: Events show `exceeded quota`,
   `Insufficient memory`, image pulls, Kyverno/PSA denials.
4. `kubectl -n project-<p> get pvc`: `Pending` PVCs (storage class, quota).
Starts then 503/spinning → proxy↔pod or pod→hub traffic dropped:
`hubble observe --namespace project-<p> --verdict DROPPED` and `--namespace jupyterhub`.

**Hubble**: `hubble observe` "connection refused" → `tre hubble` (port-forward). UI 404 → use
`/hubble/` (trailing slash); check `kubectl -n kube-system get pods -l k8s-app=hubble-ui` and that the
UI image matches `HUBBLE_UI_VERSION` in `.devcontainer/versions.env`.

**Slow / out of memory**: stop idle workspaces (Hub Control Panel), run one or two at a time, set
`KID_ENABLE_KYVERNO=false` and rebuild on small laptops. See `docs/reference/resource-budget.md`.

## 3. Reset options (confirm with the trainee; some lose data)

| Problem | Reset |
|---|---|
| Keycloak users/groups messed up | `kubectl -n keycloak rollout restart deploy/keycloak` (re-imports realm; console changes lost) |
| Hub in a bad state | `kubectl -n jupyterhub rollout restart deploy/hub` |
| One project broken | `kubectl delete ns project-<p>` then `tre sync` (**deletes the project's home volumes**) |
| Bad commit on the fork | `git revert <sha> && git push && tre sync` |
| Everything | new codespace / rebuild dev container; local full reset needs deleting the Docker volumes |
