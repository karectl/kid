---
name: kid-workspace-config
description: Change how research workspaces are launched in the KID training TRE - JupyterHub/KubeSpawner settings, workspace sizes (CPU/memory), notebook images, home and shared storage, idle culling, pod security settings, and the project-aware spawner logic in tre_config.py. Use when the user wants to change what a workspace gets or how JupyterHub picks projects.
---

# Workspace configuration in KID

## Where each setting lives

| Setting | File | Notes |
|---|---|---|
| Size catalogue (CPU/memory per size) | `gitops/projects/chart/values.yaml` → `sizeCatalogue` | KubeSpawner reads `1G` as **1 GiB** |
| Sizes/image offered by a project | `gitops/apps/values.yaml` → project `sizes`, `image` | written to namespace annotations |
| Per-container ceiling | `gitops/projects/chart/templates/limitrange.yaml` | sizes must fit `max` |
| Project totals | `gitops/projects/chart/templates/resourcequota.yaml` (values `quota`) | |
| Home volume size/class/name | `gitops/jupyterhub/values.yaml` → `singleuser.storage` | `home-{username}`, class `tre-user-home` |
| Shared volume mount | `gitops/jupyterhub/values.yaml` → `singleuser.storage.extraVolumes/extraVolumeMounts` | PVC `project-shared` in every project |
| Idle culling | `gitops/jupyterhub/values.yaml` → `cull.timeout` (seconds) | |
| Login, groups, admins | `gitops/jupyterhub/values.yaml` → `hub.config.GenericOAuthenticator` | |
| Which projects a user gets, namespace/image/size overrides | `gitops/jupyterhub/files/tre_config.py` | `project_profiles()`, `spawn_form()`, `require_a_project()` |
| Pod/container security context | `gitops/jupyterhub/values.yaml` → `singleuser.extraPodConfig` / `singleuser.extraContainerConfig` | test against Pod Security and Kyverno |

Z2JH value reference: https://z2jh.jupyter.org/en/stable/resources/reference.html (chart 4.0.0).

## Rules

- Keep `singleuser.cloudMetadata.blockWithIptables: false`: the chart's default adds a privileged
  init container that Pod Security/Kyverno reject; Cilium policy already blocks metadata access.
- Images must be `quay.io/jupyter/*` with a pinned tag (Kyverno). Large images (scipy, datascience)
  take minutes to pull on first use.
- `tre_config.py` is executed by the hub (`c` is the config object). Keep the membership re-check:
  KubeSpawner calls `project_profiles()` again at spawn time, so a forged profile is rejected.
  `c.JupyterHub.hub_connect_url` must stay the FQDN (workspaces run in other namespaces).
- `gitops/jupyterhub/files/tre_config.py` is packaged by a kustomize `configMapGenerator` with a
  hash suffix, so a pushed change restarts the hub automatically.

## Test changes

```bash
pip install -r tests/requirements.txt
pytest tests                    # unit tests for tre_config.py (add a test for new behaviour)
tests/e2e/run.sh                # real hub + proxy vs fake k8s API; checks the pod against policies
                                # (needs kustomize, helm, node/npm; kubeconform/kyverno optional)
helm template root gitops/apps >/dev/null && helm template p gitops/projects/chart --set name=t >/dev/null
```

## Roll out and verify

Commit + push + `tre sync`, then watch `kubectl -n jupyterhub get pods -w` (hub restarts on config
change). Running workspaces keep old settings until they are stopped and started again. Check a
new workspace with `tre workspaces` and `kubectl -n project-<p> describe pod jupyter-<user>`. If the
hub crash-loops: `kubectl -n jupyterhub logs deploy/hub --previous`.
