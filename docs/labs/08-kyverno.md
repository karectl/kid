# Lab 8: Guardrails with Kyverno

**Objectives**: get rejected by admission policy, tell Kyverno's rejections apart from Pod
Security's, read policy reports, and understand Enforce vs Audit and generate rules.

!!! note
    Skip this lab if you bootstrapped with `KID_ENABLE_KYVERNO=false`.

## 1. What policies are there?

```bash
kubectl get clusterpolicies
kubectl describe cpol restrict-image-registries | sed -n '1,40p'
```

All should be `READY: True`. Read the YAML in `gitops/kyverno/`: every rule matches only
namespaces labelled `k8tre.io/type=project`.

## 2. Bring your own software

A researcher (or a compromised account) tries to run an arbitrary image in a project:

```bash
kubectl -n project-alpha run evil --image=nginx:1.27
```

```text
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:

resource Pod/project-alpha/evil was blocked due to the following policies

require-project-label:
  project-label-matches-namespace: 'validation error: Pods in project-alpha must carry
    the label k8tre.io/project=alpha. ...'
restrict-image-registries:
  approved-registry-only: 'validation error: Image nginx:1.27 is not from an approved
    registry. Project workspaces may only use quay.io/jupyter/* images. ...'
```

Two policies failed. Fix one at a time and watch the list shrink:

```bash
kubectl -n project-alpha run evil --image=nginx:1.27 --labels=k8tre.io/project=alpha
kubectl -n project-alpha run evil --image=quay.io/jupyter/minimal-notebook:2026-08-10 --labels=k8tre.io/project=beta
```

The last one is an approved image, but **mislabelled** as project beta. Labels feed network policy
and audit, so lying about them is blocked.

## 3. Privileged containers: two layers

```bash
kubectl -n project-alpha run priv --restart=Never \
  --image=quay.io/jupyter/minimal-notebook:2026-08-10 --labels=k8tre.io/project=alpha \
  --overrides='{"spec":{"containers":[{"name":"priv","image":"quay.io/jupyter/minimal-notebook:2026-08-10","securityContext":{"privileged":true}}]}}'
```

```text
Error from server (Forbidden): pods "priv" is forbidden: violates PodSecurity "baseline:latest":
privileged (container "priv" must not set securityContext.privileged=true)
```

This rejection came from **Pod Security Admission**, built into Kubernetes and switched on by the
namespace label `pod-security.kubernetes.io/enforce: baseline`. It runs before Kyverno's webhook.
The Kyverno policy `disallow-privileged-workspaces` would have blocked it too; the offline tests
(`tests/kyverno/`) show that. Two independent layers for the most dangerous setting is deliberate.

## 4. Audit is not Enforce

```bash
kubectl -n project-alpha run floating --restart=Never \
  --image=quay.io/jupyter/minimal-notebook:latest --labels=k8tre.io/project=alpha \
  --command -- sleep 600
```

It is **allowed**: `disallow-latest-tag` is in `Audit` mode. The result goes into a
**PolicyReport**:

```bash
sleep 15
kubectl -n project-alpha get policyreports -o wide
kubectl -n project-alpha get policyreports -o yaml | grep -B2 -A10 "policy: disallow-latest-tag" | grep -E "result|message|name:" | head
```

Audit mode is how you roll out a new rule safely: measure how much would break, fix it, then switch
to Enforce.

```bash
kubectl -n project-alpha delete pod floating
```

## 5. Outside projects, nothing applies

```bash
kubectl -n default run nginx --image=nginx:1.27
kubectl -n default delete pod nginx
```

Allowed, because the policies are scoped to project namespaces. **Discuss**: is that the right
scope for a TRE? What would you enforce cluster-wide?

## 6. Generate rules

You met `generate-project-default-deny` in labs 3 and 7. Look at Kyverno's bookkeeping:

```bash
kubectl get cpol generate-project-default-deny -o yaml | grep -A12 "generate:"
kubectl get cnp -A -l app.kubernetes.io/managed-by=kyverno
```

## 7. Policies are code: test them

Read `tests/kyverno/kyverno-test.yaml`. It feeds example pods (a real workspace, `evil`,
`privileged`...) through the policies and checks each result. CI runs it on every push, so a policy
change that would block real workspaces fails **before** it reaches a cluster.

## Check your understanding

1. Why block by **registry** rather than by image name?
2. What would happen to running workspaces if you tightened a policy in Enforce mode? (Hint:
   admission only checks *new* requests; background scans report on existing ones.)
3. Kyverno runs as a webhook with `failurePolicy: Fail` for these policies. What happens to
   workspace launches if Kyverno is down? Is that the right trade-off for a TRE?
