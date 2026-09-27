---
name: kid-network-policy
description: Create, change, explain or debug Cilium network policies in the KID training TRE - allow a project internet access to specific domains, allow or block traffic between workspaces, projects and services, write L7 HTTP rules, and use Hubble to find dropped flows. Use for any request about connectivity, egress, firewall rules, CiliumNetworkPolicy, toFQDNs or Hubble.
---

# Network policy in KID

## What exists (read these first)

| Policy | Namespace | Source | Selects | Allows |
|---|---|---|---|---|
| `workspace-baseline` | each `project-*` | `gitops/projects/chart/templates/networkpolicy.yaml` | `component: singleuser-server` | ingress from hub/proxy on 8888; egress to kube-dns (with L7 DNS rule) and hub:8081 |
| `default-deny` | each `project-*` | Kyverno `gitops/kyverno/generate-default-deny.yaml` (synchronize) | every pod | nothing (`ingress: [{}]`, `egress: [{}]`) |
| `internet-allowlist` | projects with `internetAllowlist` | `gitops/projects/chart/templates/internet-allowlist.yaml` | workspaces | HTTPS (443) to listed FQDNs |
| `jupyterhub-baseline` | `jupyterhub` | `gitops/network-policies/jupyterhub.yaml` | every pod | DNS, API server, Keycloak:8080, workspaces:8888; ingress from Traefik:8000 and workspaces:8081 |

Rules of thumb:
- Once any policy selects a pod in a direction, everything else in that direction is dropped.
- Policies are **additive**: you widen access by adding a policy; you cannot "deny" with a second
  allow-policy. Don't delete `default-deny` or `workspace-baseline` to open traffic.
- Selectors use labels. Namespace: `k8s:io.kubernetes.pod.namespace: <ns>`. Namespace labels:
  `k8s:io.cilium.k8s.namespace.labels.k8tre.io/type: project`.
- `toFQDNs` works only because the workspace DNS rule has `rules: dns: [{matchPattern: "*"}]`
  (Cilium's DNS proxy learns name → IP). Keep that rule.
- HTTPS can only be filtered by name/port, not by URL path (no TLS termination). L7 `http` rules
  only work for plain HTTP.

## Procedure: give a project internet access to specific sites

Prefer the **GitOps** way (auditable):

1. In `gitops/apps/values.yaml`, under the project, add:
   ```yaml
       internetAllowlist:
         - pypi.org
         - files.pythonhosted.org
   ```
   Entries containing `*` become `matchPattern`, others `matchName`. Prefer exact names.
2. Render to check: `helm template root gitops/apps | grep -A12 "name: project-alpha"` and
   render the project chart with those values if needed.
3. `git commit`, `git push`, `tre sync`; confirm with `kubectl -n project-alpha get cnp internet-allowlist -o yaml`.

**No fork** (or quick experiment): render just that template and apply it:
```bash
helm template project-alpha gitops/projects/chart --set name=alpha \
  --set 'internetAllowlist={pypi.org,files.pythonhosted.org}' \
  -s templates/internet-allowlist.yaml | kubectl apply -f -
```
Say that Argo CD doesn't manage it (an undocumented exception), and how to remove it.

Discuss the risk: PyPI/CRAN allow arbitrary uploads; real TREs use curated mirrors/proxies.

## Procedure: other traffic

Write a new `CiliumNetworkPolicy` rather than editing the baselines. Template:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: <what-it-allows>
  namespace: project-<p>
spec:
  description: <why, in one sentence>
  endpointSelector:
    matchLabels:
      component: singleuser-server
  egress:            # or ingress with fromEndpoints
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: <ns>
            <label>: <value>
      toPorts:
        - ports:
            - port: "<port>"
              protocol: TCP
```

- Same-project workspace ↔ workspace: needs **both** an egress rule (to `component:
  singleuser-server`) and an ingress rule (from it) in that namespace. Discuss whether that's wise.
- New traffic to/from JupyterHub also needs `gitops/network-policies/jupyterhub.yaml` changed.
- To make a policy part of every project, add it to `gitops/projects/chart/templates/`.

Validate YAML before applying: `kubectl apply --dry-run=server -f file.yaml`.

## Verify with Hubble

```bash
tre hubble                                          # once per session (port-forward)
hubble observe --namespace project-alpha --verdict DROPPED --last 50
hubble observe --namespace project-alpha --protocol dns --last 20
hubble observe --from-pod project-alpha/jupyter-researcher1 --follow
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg endpoint list
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg fqdn cache list
```

Test from inside a workspace (JupyterLab notebook):
```python
import socket; socket.create_connection(("pypi.org", 443), timeout=5)
```
A timeout means dropped by policy; a DNS error means the name didn't resolve.

Hubble UI: `/hubble/`, pick the namespace; red edges are drops.
