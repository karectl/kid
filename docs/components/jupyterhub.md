# JupyterHub

[JupyterHub](https://jupyterhub.readthedocs.io/) is the **workspace orchestrator**. It
authenticates users, shows them what they may launch, and asks Kubernetes (through
[KubeSpawner](https://jupyterhub-kubespawner.readthedocs.io/)) to create a pod per user. It is
deployed with the [Zero to JupyterHub](https://z2jh.jupyter.org/) (Z2JH) Helm chart, version 4.0.0.

## Files

| File | Purpose |
|---|---|
| `gitops/jupyterhub/kustomization.yaml` | Inflates the Z2JH chart, adds RBAC, ingress and the config file |
| `gitops/jupyterhub/values.yaml` | Chart values: auth, storage, culling, fallbacks |
| `gitops/jupyterhub/files/tre_config.py` | **The project logic**: discovery, profiles, access checks |
| `gitops/jupyterhub/rbac.yaml` | `tre-workspace-spawner` and `tre-project-reader` ClusterRoles |
| `gitops/network-policies/jupyterhub.yaml` | Network policy for hub and proxy |

## Components

* **hub**: the Python application. It holds the user database (SQLite on a PVC) and runs the
  spawner and the idle culler.
* **proxy** (configurable-http-proxy): routes `/jupyter/user/<name>/` to the right pod IP. The hub
  updates its routing table on every spawn.
* **singleuser server**: the JupyterLab process inside each workspace pod. It calls back to the
  hub API to check who the browser belongs to.

## Projects and profiles

JupyterHub has no built-in idea of a "project". KID adds one in `tre_config.py`:

```python
c.KubeSpawner.profile_list = project_profiles     # what the user is offered
c.KubeSpawner.pre_spawn_hook = require_a_project  # refuse users with no project
```

`project_profiles(spawner)`:

1. Lists namespaces labelled `k8tre.io/type=project`. It may do this thanks to the
   `tre-project-reader` ClusterRole.
2. Keeps those whose `k8tre.io/project` label matches one of the user's JupyterHub groups.
3. Returns one **profile** per project, overriding `namespace`, `image`, labels and environment, with
   **size** options built from the namespace's `k8tre.io/sizes` annotation.

KubeSpawner calls the function again when the server actually starts and rejects any profile that
isn't in the list, so a user can't reach another project by crafting an API call. The tests in
`tests/test_tre_config.py` check this.

## Workspace pods

| Property | Value | From |
|---|---|---|
| Name | `jupyter-<username>` | KubeSpawner default |
| Namespace | `project-<project>` | profile override |
| Labels | `component=singleuser-server`, `k8tre.io/project=<project>`, `hub.jupyter.org/username=...` | KubeSpawner + profile |
| Image | e.g. `quay.io/jupyter/minimal-notebook:2026-08-10` | namespace annotation |
| CPU/memory | size option | namespace annotation |
| Home | PVC `home-<username>` → `/home/jovyan` | `singleuser.storage` |
| Shared | PVC `project-shared` → `/home/jovyan/shared` | `singleuser.storage.extraVolumes` |
| User | uid 1000 (`jovyan`), not root | Z2JH default |
| Env | `K8TRE_PROJECT=<project>` | profile override |

## Culling

Idle servers are stopped after **1 hour** (`cull.timeout`), checked every 5 minutes. This saves
resources and shortens the window in which an unattended session could be misused.

## Admin panel

Log in as `tre-admin` (member of `tre-admins`, mapped via `admin_groups`) and go to
**`/jupyter/hub/admin`**. `tre-admin` isn't in any project, so the automatic spawn after login fails
with a "not a member of any research project" message. That's expected; the admin panel still
works. From there you can see all users and their groups, and start or stop their servers.

!!! info "Admins can access user servers"
    By default JupyterHub admins can open other users' servers. That is data access. In a real
    TRE, think carefully about who holds this role and audit its use.

## Hub logs

```bash
kubectl -n jupyterhub logs deploy/hub -f
kubectl -n jupyterhub logs deploy/hub | grep "may use projects"
```
