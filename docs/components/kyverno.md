# Kyverno

[Kyverno](https://kyverno.io/) is a **policy engine** that plugs into the Kubernetes API server as
an admission webhook. Policies are ordinary YAML objects (`ClusterPolicy`), so they live in Git and
are deployed by Argo CD like everything else.

KID installs Kyverno 1.13 (chart 3.3.4) with the admission, background and reports controllers.
The cleanup controller is disabled to save memory. Set `KID_ENABLE_KYVERNO=false` to skip Kyverno
altogether on a small laptop.

## What policies can do

| Type | When | Example in KID |
|---|---|---|
| **validate** (Enforce) | On create/update, **rejects** | `restrict-image-registries` |
| **validate** (Audit) | On create/update + background scans, **reports only** | `disallow-latest-tag` |
| **generate** | When a matching object appears, **creates** another | `generate-project-default-deny` |
| **mutate** | On create/update, **changes** the object | (not used; try it in the challenges) |

## KID's policies (`gitops/kyverno/`)

All are scoped with `namespaceSelector: {matchLabels: {k8tre.io/type: project}}`, so platform
namespaces are unaffected.

| Policy | Mode | Rule |
|---|---|---|
| `restrict-image-registries` | Enforce | Containers must use `quay.io/jupyter/*` |
| `disallow-privileged-workspaces` | Enforce | No `privileged`, `hostNetwork`, `hostPID`, `hostIPC`, `hostPath` |
| `require-project-label` | Enforce | Pod label `k8tre.io/project` must equal the namespace's project |
| `disallow-latest-tag` | **Audit** | Images must have a pinned tag |
| `generate-project-default-deny` | Generate (+ synchronize) | Every project namespace gets a `default-deny` CiliumNetworkPolicy |

`rbac.yaml` grants Kyverno permission to manage `CiliumNetworkPolicy` objects. Kyverno can only
generate what it's allowed to create.

## Kyverno and Pod Security Admission

Project namespaces also carry `pod-security.kubernetes.io/enforce: baseline`. The built-in Pod
Security admission runs **before** webhooks, so a privileged pod is usually rejected by Pod
Security first, with a different message. Two independent layers enforcing the same rule is
deliberate: defence in depth.

## Commands

```bash
kubectl get clusterpolicies                      # short name: cpol
kubectl describe cpol restrict-image-registries
kubectl get policyreports -A                     # short name: polr
kubectl -n project-alpha get polr -o wide
kubectl get updaterequests -A                    # generate-rule bookkeeping
```

## Testing policies offline

The repository has CLI tests in `tests/kyverno/`. CI runs them with the
[Kyverno CLI](https://kyverno.io/docs/kyverno-cli/):

```bash
kyverno test tests/kyverno
```

Testing policies before they reach a cluster is "shift-left" security, and the same idea applies to
any policy change you propose in a TRE.
