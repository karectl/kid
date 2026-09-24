# Lab 7: A new project

**Objectives**: onboard project **gamma** the GitOps way, give a user access in Keycloak, and
see which parts are automatic and which are deliberate. Then try to shortcut the process and
watch it fail safely.

## Part A: create project gamma

=== "With a fork (GitOps)"

    Edit `gitops/apps/values.yaml` and add a third entry under `projects:`:

    ```yaml
      - name: gamma
        displayName: Project Gamma
        description: Genomics pilot (synthetic). Small or medium workspaces.
        image: quay.io/jupyter/minimal-notebook:2026-08-10
        sizes: [small, medium]
        quota:
          cpu: "2"
          memory: 3Gi
          pods: 4
          storage: 5Gi
        sharedStorage: 1Gi
    ```

    Check the chart renders before you push:

    ```bash
    helm template root gitops/apps | grep -A3 "name: project-gamma"
    ```

    Commit, push and nudge Argo CD:

    ```bash
    git add gitops/apps/values.yaml
    git commit -m "Onboard project gamma"
    git push
    tre sync
    kubectl -n argocd get application project-gamma -w
    ```

    In a real TRE this commit would be a **pull request** reviewed by the data governance team: the
    project's approval is on record next to its technical definition.

=== "Without a fork"

    Render the project chart yourself and apply it. This is what Argo CD would do, but nothing
    will keep it in sync afterwards.

    ```bash
    helm template project-gamma gitops/projects/chart \
      --set name=gamma \
      --set displayName="Project Gamma" \
      --set 'sizes={small,medium}' | kubectl apply -f -
    ```

Now look at what appeared:

```bash
kubectl get ns project-gamma --show-labels
kubectl -n project-gamma get resourcequota,limitrange,pvc,rolebinding,cnp
```

You should see **two** CiliumNetworkPolicies: `workspace-baseline` from the chart and
`default-deny`, which Kyverno generated because the namespace is labelled `k8tre.io/type=project`.

## Part B: give someone access

Nobody can use gamma yet: no one is in the `gamma` group.

1. Open the Keycloak console (`/keycloak`, `admin`/`admin`) and switch to realm **tre**.
2. **Groups → Create group** → name `gamma` → **Create**.
3. **Users → researcher1 → Groups → Join Group** → tick `gamma` → **Join**.

As researcher1 in JupyterHub: **log out** (`/jupyter/hub/logout`) and log back in. The spawn page
now offers **Project Alpha** and **Project Gamma**. Start gamma:

```bash
tre workspaces
```

!!! warning "Keycloak dev mode"
    Keycloak changes made in the console disappear if the Keycloak pod restarts (see
    [Keycloak](../components/keycloak.md#dev-mode-caveats)). To make `gamma` permanent, add it to
    `gitops/keycloak/realm-tre.json`.

## Part C: the shortcut that doesn't work

What if someone skips Git and just creates a namespace that *looks* like a project?

```bash
kubectl create namespace rogue
kubectl label namespace rogue k8tre.io/type=project k8tre.io/project=rogue
sleep 5
kubectl -n rogue get cnp
```

Kyverno has already put a `default-deny` policy there. Guardrails apply to namespaces nobody
declared.

Now in Keycloak create group `rogue` and add **researcher4** to it. Log in to JupyterHub as
researcher4: "rogue" is offered (JupyterHub discovers projects from labels). Start it. The spawn
**fails**, and the hub log shows the Kubernetes API answering `403 Forbidden`.

```bash
kubectl -n jupyterhub logs deploy/hub --since=5m | grep -i forbidden | head -3
kubectl auth can-i create pods -n rogue --as system:serviceaccount:jupyterhub:hub
kubectl auth can-i create pods -n project-gamma --as system:serviceaccount:jupyterhub:hub
```

The hub can only create workspaces where a project has **granted** it the right, through the
RoleBinding in the project chart. A label alone isn't enough: a second, independent lock.

Clean up:

```bash
kubectl delete namespace rogue
```

## Part D: retire project gamma

=== "With a fork"

    Remove the gamma entry from `gitops/apps/values.yaml`, commit, push, `tre sync`.

=== "Without a fork"

    ```bash
    helm template project-gamma gitops/projects/chart --set name=gamma | kubectl delete -f -
    ```

Then:

```bash
kubectl get ns project-gamma          # Terminating, then gone
kubectl get pv | grep project-gamma   # the project-shared PV is "Released", not deleted
```

The `tre-project-shared` StorageClass has `reclaimPolicy: Retain`, so the project's shared data
outlives the project until someone makes a deliberate archive-or-destroy decision. Clean it up
when you're done:

```bash
kubectl get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace=="project-gamma")]}{.metadata.name}{"\n"}{end}' \
  | xargs -r kubectl delete pv
```

Also remove the `gamma` group in Keycloak.

## Check your understanding

1. List everything that had to happen for researcher1 to use gamma. Which steps were automated,
   and which were deliberate human decisions?
2. Why is it good that JupyterHub *discovers* projects instead of keeping its own list?
3. What would you add to the project chart for a real TRE? (Ideas: a project-specific data volume
   mounted read-only, an egress allow-list, a cost-centre label, a backup schedule.)
