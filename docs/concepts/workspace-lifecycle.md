# Life of a workspace

This page follows `researcher1` from the login page to a running JupyterLab, naming every
component on the way. Keep it open during [lab 2](../labs/02-workspaces.md).

```mermaid
sequenceDiagram
  autonumber
  actor R as researcher1 (browser)
  participant P as JupyterHub proxy
  participant H as JupyterHub hub
  participant K as Keycloak
  participant A as Kubernetes API
  participant Y as Kyverno / Pod Security
  participant C as Cilium
  participant W as Workspace pod
  R->>P: GET /jupyter/
  P->>H: not logged in
  H-->>R: redirect to Keycloak (authorize_url)
  R->>K: username + password
  K-->>R: redirect back with ?code=
  R->>H: /jupyter/hub/oauth_callback?code=
  H->>K: exchange code for token, call userinfo (in-cluster)
  K-->>H: preferred_username=researcher1, groups=[alpha]
  H->>H: sync JupyterHub groups to [alpha]
  R->>H: open spawn page
  H->>A: list namespaces with k8tre.io/type=project
  H-->>R: form offers "Project Alpha" only
  R->>H: start (profile=alpha, size=small)
  H->>H: pre_spawn_hook: must be in a project,<br/>profile re-checked against membership
  H->>A: create PVC home-researcher1 in project-alpha
  H->>A: create Pod jupyter-researcher1 in project-alpha
  A->>A: LimitRange defaults, ResourceQuota check
  A->>Y: validate (baseline PSS, Kyverno policies)
  Y-->>A: allowed
  A-->>H: created
  Note over A,W: scheduler binds, local-path provisions volumes,<br/>kubelet pulls image, Cilium assigns IP + identity
  C->>W: apply workspace-baseline + default-deny policies
  W->>H: jupyterhub-singleuser registers (8081) ✅
  H->>P: add route /jupyter/user/researcher1 → pod IP:8888
  R->>P: /jupyter/user/researcher1/lab
  P->>W: proxied ✅
```

## Where each decision is made

| Step | Decision | Configured in |
|---|---|---|
| 8–9 | Which groups the user is in | Keycloak realm (`gitops/keycloak/realm-tre.json`), group mapper on the `jupyterhub` client |
| 10 | Groups copied into JupyterHub | `manage_groups`, `auth_state_groups_key` in `gitops/jupyterhub/values.yaml` |
| 12–13 | Which projects are offered | `project_profiles()` in `gitops/jupyterhub/files/tre_config.py` |
| 15 | Refuse users without a project; refuse forged profiles | `require_a_project()` + KubeSpawner's profile validation |
| 16 | Where home directories live and how big | `singleuser.storage` in `values.yaml`, StorageClass `tre-user-home` |
| 17 | Image, CPU, memory, namespace | Namespace annotations written by `gitops/projects/chart` |
| 18 | Default limits, project totals | `limitrange.yaml`, `resourcequota.yaml` in the project chart |
| 19 | What may run at all | Namespace PSA labels, `gitops/kyverno/*.yaml` |
| 21 | Who may talk to the workspace and where it may connect | `networkpolicy.yaml` in the project chart, Kyverno `generate-default-deny` |
| end | When the workspace is stopped | `cull.timeout` (1 hour idle) in `values.yaml` |

## Stopping

When the user clicks **Stop My Server** (or the culler stops it after an hour idle), the hub deletes
the **pod**. The **PVCs stay**, so files in `~` and `~/shared` are still there next time. The
project's `ResourceQuota` usage drops straight away.
