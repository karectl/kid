---
name: kid-kyverno-policy
description: Write, change, test or explain Kyverno policies in the KID training TRE - validate (Enforce/Audit), generate and mutate rules scoped to research project namespaces, offline tests with the kyverno CLI, and reading PolicyReports. Use when the user asks about admission control, guardrails, why a pod was rejected, or wants a new policy.
---

# Kyverno in KID

- Kyverno 1.13 (chart 3.3.4), installed by the Argo CD app `kyverno` (`gitops/apps/templates/kyverno.yaml`).
  May be disabled (`KID_ENABLE_KYVERNO=false`): check `kubectl get ns kyverno` first.
- Policies: `gitops/kyverno/*.yaml`, listed in `gitops/kyverno/kustomization.yaml`, synced by the
  Argo CD app `kyverno-policies`.
- Offline tests: `tests/kyverno/` (`kyverno-test.yaml`, `resources.yaml`, `values.yaml`).

| Policy | Mode | Rule |
|---|---|---|
| `restrict-image-registries` | Enforce | images must match `quay.io/jupyter/*` |
| `disallow-privileged-workspaces` | Enforce | no privileged, hostNetwork/PID/IPC, hostPath |
| `require-project-label` | Enforce | pod label `k8tre.io/project` == namespace's (uses an `apiCall` context) |
| `disallow-latest-tag` | Audit | pinned tags only; results in PolicyReports |
| `generate-project-default-deny` | Generate + synchronize | `default-deny` CiliumNetworkPolicy in every project namespace |

## Explaining a rejection

The admission error names each failed policy and rule. If it starts with
`violates PodSecurity "baseline:latest"`, it was **Pod Security Admission** (namespace label
`pod-security.kubernetes.io/enforce: baseline`), which runs before Kyverno's webhook, not Kyverno.
Tell the trainee which layer blocked it and point to the YAML.

## Writing a policy

Conventions in this repo (follow them):
- Kyverno 1.13 syntax: `validate.failureAction: Enforce|Audit` **per rule** (not the deprecated
  `spec.validationFailureAction`); `generate.generateExisting` per rule.
- Scope to projects: `match.any[].resources.namespaceSelector.matchLabels: {k8tre.io/type: project}`
  (for Namespace-kind rules use `selector` instead).
- Annotations `policies.kyverno.io/title|category|severity|description` with a learner-friendly
  description of *why* it matters for a TRE.
- Start new validate rules in **Audit**, look at reports, then switch to Enforce.
- Generate rules creating new kinds need RBAC: extend `gitops/kyverno/rbac.yaml` (ClusterRole with
  label `rbac.kyverno.io/aggregate-to-background-controller: "true"`).
- Add the file to `gitops/kyverno/kustomization.yaml`.

Skeleton:
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: <kebab-name>
  annotations:
    policies.kyverno.io/title: <Title>
    policies.kyverno.io/category: TRE workspaces
    policies.kyverno.io/severity: medium
    policies.kyverno.io/description: >-
      <why this matters in a TRE>
spec:
  background: true
  rules:
    - name: <rule-name>
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaceSelector:
                matchLabels:
                  k8tre.io/type: project
      validate:
        failureAction: Audit
        message: <what to do instead>
        pattern:
          spec:
            containers:
              - <field>: <pattern>
```

## Test before it reaches the cluster

1. Add example resources to `tests/kyverno/resources.yaml` (one that must pass, one that must fail;
   the `workspace` pod models what KubeSpawner creates and must keep passing).
2. Add `results:` entries to `tests/kyverno/kyverno-test.yaml`. For namespaceSelector matching,
   namespace labels come from `tests/kyverno/values.yaml`; apiCall variables are mocked there too.
3. Run `kyverno test tests/kyverno` (CI does this too). If the CLI isn't installed, say so and rely
   on CI.
4. Also run `tests/e2e/run.sh` if the change could affect workspace pods: it checks the pod
   JupyterHub really creates against all policies.

## Apply and observe

GitOps: commit + push + `tre sync`. Then:
```bash
kubectl get cpol                                    # READY must be True
kubectl -n project-alpha get polr -o wide           # audit results
kubectl -n project-alpha run t --image=nginx:1.27 --dry-run=server   # admission check without creating
```
Without a fork: `kubectl apply -f gitops/kyverno/<file>.yaml` (not managed by Argo CD then, unless
the file is already in Git and pushed).
