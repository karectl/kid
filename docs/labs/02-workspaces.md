# Lab 2: Workspaces on demand

**Objectives**: launch workspaces as different users, find them in Kubernetes, and trace how
project membership turns into a pod in a project namespace.

Keep [Life of a workspace](../concepts/workspace-lifecycle.md) open alongside.

## 1. Log in as researcher1

Open **JupyterHub** from the portal and sign in with Keycloak as `researcher1` / `researcher`.

The spawn page offers only **Project Alpha**, with a single **Small** size. Click **Start**.

While it starts, watch from the terminal:

```bash
kubectl -n project-alpha get pods,pvc -w
```

`Ctrl+C` once the pod is `Running`.

## 2. Inspect the workspace pod

```bash
kubectl -n project-alpha get pod jupyter-researcher1 --show-labels
kubectl -n project-alpha describe pod jupyter-researcher1
```

Find in the output:

- [ ] the **image**
- [ ] CPU and memory **requests** and **limits**
- [ ] the two **volumes** (home and shared) and their mount paths
- [ ] the `K8TRE_PROJECT` environment variable
- [ ] the label `k8tre.io/project=alpha`
- [ ] the **node** and **IP**

Or all at once:

```bash
tre workspaces
```

## 3. Look from the inside

In JupyterLab open **File → New → Terminal** and run:

```bash
whoami; id
echo $K8TRE_PROJECT
df -h ~ ~/shared
env | grep -i jupyterhub_ | sort
```

You are `jovyan` (uid 1000), not root. `JUPYTERHUB_API_URL` points at
`hub.jupyterhub.svc.cluster.local`: the workspace runs in `project-alpha`, a different namespace
from the hub.

## 4. A user in two projects

Open a **private window**, go to `/jupyter/`, and log in as `researcher3`.

Now there are two choices, and **Project Beta** offers **Small** and **Medium**. Pick
**Project Beta → Medium** and start.

```bash
tre workspaces
```

researcher3's pod is in `project-beta` with a 1 CPU / 2 GiB limit.

## 5. A user in no project

In another private window log in as `researcher4`. Instead of a launch menu you get:

> **You are not a member of any research project.** Ask a TRE administrator to add you to a
> project group in Keycloak, then log out and back in.

Click **Start** anyway: the hub refuses (`pre_spawn_hook`), and no pod or volume is created.

Look for the reason in the hub log:

```bash
kubectl -n jupyterhub logs deploy/hub --since=10m | grep -E "may use projects|not a member"
```

## 6. Can a user pick another project anyway?

JupyterHub has a REST API, and a clever user could try to start a server with
`{"profile": "beta"}` while only being in `alpha`. Read `project_profiles()` and
`require_a_project()` in `gitops/jupyterhub/files/tre_config.py`, then the test
`test_cannot_request_a_project_you_are_not_in` in `tests/test_tre_config.py`.

**Why** does re-checking at spawn time matter, when the form already hides other projects?

## 7. Stop and restart

As researcher1: **File → Hub Control Panel → Stop My Server**.

```bash
kubectl -n project-alpha get pods,pvc
```

The **pod** is gone; the **PVCs** remain. Start the server again and your files are still there.

## What just happened

* Keycloak put `groups: [alpha]` in researcher1's userinfo. JupyterHub copied that into its own groups.
* `project_profiles()` listed namespaces labelled `k8tre.io/type=project` and kept the ones matching
  the user's groups.
* The chosen profile set KubeSpawner's **namespace**, **image** and **limits**.
* The hub could create the pod in `project-alpha` only because the project's RoleBinding lets it.

## Check your understanding

1. Where would you change the image used by project beta? (Two places: which one does Argo CD own?)
2. What stops researcher1 from starting a workspace in `project-beta`? Name *two* independent
   mechanisms.
3. Why are home directories per user **per project**, rather than one home per user?
