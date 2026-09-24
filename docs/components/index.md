# Components

| Component | Role in the TRE | Namespace | Deployed by | Page |
|---|---|---|---|---|
| **Cilium + Hubble** | Pod networking, network policy, flow visibility | `kube-system` | `bootstrap.sh` | [Cilium & Hubble](cilium-hubble.md) |
| **JupyterHub** | Workspace orchestration | `jupyterhub`, `project-*` | Argo CD | [JupyterHub](jupyterhub.md) |
| **Keycloak** | Identity provider (OIDC), project groups | `keycloak` | Argo CD | [Keycloak](keycloak.md) |
| **Storage** | StorageClasses, home and project volumes | cluster, `project-*` | Argo CD | [Storage](storage.md) |
| **Argo CD** | GitOps: deploys everything from Git | `argocd` | `bootstrap.sh` | [Argo CD](argocd.md) |
| **Kyverno** | Admission policy and generated guardrails | `kyverno` | Argo CD | [Kyverno](kyverno.md) |
| **Kubescape** | Security posture scanning | CLI in the dev container | Dockerfile | [Kubescape](kubescape.md) |
| **Traefik** | HTTP ingress (bundled with k3s) | `kube-system` | k3s | – |
| **Portal** | Landing page | `portal` | Argo CD | – |
