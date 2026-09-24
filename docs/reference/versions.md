# Versions

| Component | Version | Where it is pinned |
|---|---|---|
| k3s (Kubernetes) | v1.31.5+k3s1 | `.devcontainer/docker-compose.yml` (`K3S_VERSION`), `versions.env` |
| Cilium | 1.16.5 | `.devcontainer/versions.env` |
| Cilium CLI | v0.16.22 | `devcontainer.Dockerfile` |
| Hubble CLI | v1.16.5 | `devcontainer.Dockerfile` |
| Hubble UI | v0.13.3 (overrides Cilium's default; older versions 404 under `/hubble/`) | `.devcontainer/versions.env` |
| Argo CD | v3.0.0 | `versions.env` (server), `devcontainer.Dockerfile` (CLI) |
| Keycloak | 26.0.7 | `gitops/keycloak/deployment.yaml` |
| Zero to JupyterHub chart | 4.0.0 (JupyterHub 5.2.1, KubeSpawner 7.0.0, OAuthenticator 17.1.0) | `gitops/jupyterhub/kustomization.yaml` |
| Notebook image | `quay.io/jupyter/minimal-notebook:2026-08-10` | `gitops/apps/values.yaml`, `gitops/projects/chart/values.yaml`, `gitops/jupyterhub/values.yaml` |
| Kyverno chart | 3.3.4 (Kyverno 1.13.2) | `gitops/apps/values.yaml` |
| Kubescape CLI | v4.0.14 | `devcontainer.Dockerfile` |
| kubectl | v1.31.5 | `devcontainer.Dockerfile` |
| Helm | v3.16.3 | `devcontainer.Dockerfile` |
| Zensical (docs) | latest | `.github/workflows/docs.yml` |

## Upgrading safely

1. Change **one** component at a time on a branch.
2. Keep `kubectl` within one minor version of k3s.
3. Check the component's compatibility matrix (Cilium ↔ Kubernetes, Kyverno ↔ Kubernetes,
   Z2JH ↔ Kubernetes).
4. For the JupyterHub chart, update `tests/requirements.txt` to the versions in the new hub image
   and run `pytest tests`.
5. For Kyverno, rebuild the CLI version in `.github/workflows/validate.yml` and run
   `kyverno test tests/kyverno`.
6. Do a full dry run in a fresh codespace **before** the workshop.
