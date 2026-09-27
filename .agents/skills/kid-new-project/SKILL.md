---
name: kid-new-project
description: Create, modify or retire a research project in the KID training TRE (a project-<name> namespace with quota, limits, shared storage, RBAC and network policy), change a project's workspace sizes, image, quota or internet allow-list, and give or remove users' access through Keycloak groups. Use when the user wants a new project, to onboard or offboard someone, or to change project settings.
---

# Research projects in KID

A project is **declared in Git** and **joined through Keycloak**:

- `gitops/apps/values.yaml` → `projects:` list → one Argo CD Application `project-<name>` →
  renders `gitops/projects/chart` into namespace `project-<name>`.
- Keycloak group `<name>` (realm `tre`) → JupyterHub group → the project appears on the spawn page.
- JupyterHub discovers projects from namespace labels; no hub restart is needed.

## Project fields (see `gitops/projects/chart/values.yaml` for defaults)

```yaml
  - name: gamma                 # DNS-safe, short; namespace becomes project-gamma, Keycloak group "gamma"
    displayName: Project Gamma
    description: Genomics pilot (synthetic). Small or medium workspaces.
    image: quay.io/jupyter/minimal-notebook:2026-08-10   # must match Kyverno: quay.io/jupyter/*, pinned tag
    sizes: [small, medium]      # keys of sizeCatalogue (small = 0.5 CPU/1G, medium = 1 CPU/2G)
    quota: {cpu: "2", memory: 3Gi, pods: 4, storage: 5Gi}
    sharedStorage: 1Gi          # project-shared PVC, mounted at ~/shared
    internetAllowlist: []       # optional FQDNs (see skill kid-network-policy)
```

Constraints to check before committing:
- Every size's CPU/memory limit must fit the LimitRange `max` (1 CPU / 2Gi in
  `templates/limitrange.yaml`) and at least one workspace must fit the quota.
- Images outside `quay.io/jupyter/*` are rejected by Kyverno (`gitops/kyverno/restrict-image-registries.yaml`).
- `name` must be unique and must not collide with existing Keycloak groups (`tre-admins`).

## Create a project

**With a fork (GitOps)**
1. Append the entry to `projects:` in `gitops/apps/values.yaml`.
2. Check it renders: `helm template root gitops/apps | grep -A3 "name: project-gamma"`.
3. `git add gitops/apps/values.yaml && git commit -m "Onboard project gamma" && git push`, then `tre sync`.
4. Watch: `kubectl -n argocd get application project-gamma -w` until Synced/Healthy.
5. Verify: `kubectl -n project-gamma get resourcequota,limitrange,pvc,rolebinding,cnp`
   (expect `workspace-baseline` **and** Kyverno's `default-deny`).

**Without a fork**
```bash
helm template project-gamma gitops/projects/chart \
  --set name=gamma --set displayName="Project Gamma" --set 'sizes={small,medium}' | kubectl apply -f -
```
Nothing keeps it in sync; mention that.

## Give users access

Keycloak console (`/keycloak`, `admin`/`admin`) → realm **tre** → **Groups → Create group** `gamma`
→ **Users → <user> → Groups → Join Group**. The user must log out of JupyterHub
(`/jupyter/hub/logout`) and back in.

Console changes are lost when the Keycloak pod restarts. To make them permanent, edit
`gitops/keycloak/realm-tre.json`: add `{"name": "gamma"}` to `groups` and `"/gamma"` to the user's
`groups`, commit, push, then `kubectl -n keycloak rollout restart deploy/keycloak` (this resets
all console changes to what's in Git).

## Change a project

Edit its entry in `gitops/apps/values.yaml` and push. Notes:
- Quota/limit changes apply to *new* pods; running workspaces keep their limits until restarted.
- Changing `image` or `sizes` updates namespace annotations; users see it on their next spawn.
- Editing the ResourceQuota with `kubectl` is reverted by Argo CD (selfHeal): use Git.

## Retire a project (destructive: confirm with the trainee first)

Remove the entry (fork) or `helm template ... | kubectl delete -f -` (no fork). The namespace and
home PVCs go; the `project-shared` PV is **Retained** (`Released` status) because of the
`tre-project-shared` StorageClass. List and, only if asked, delete them:
```bash
kubectl get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace=="project-gamma")]}{.metadata.name}{"\n"}{end}'
```
Also remove the Keycloak group.

## Why a hand-made namespace isn't enough

`kubectl create ns x` + project labels → Kyverno adds `default-deny`, JupyterHub lists it, but
spawns fail with `403 Forbidden` because the hub only has rights where the project chart's
RoleBinding (`templates/rbac.yaml`) grants them. That is lab 7 part C.
