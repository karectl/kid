# Repository layout

```text
.
├── .devcontainer/
│   ├── devcontainer.json          # VS Code / Codespaces definition, forwarded port 80
│   ├── docker-compose.yml         # two containers: devcontainer + k3s-server
│   ├── devcontainer.Dockerfile    # CLIs: kubectl, helm, cilium, hubble, argocd, kubescape
│   ├── bootstrap.sh               # Cilium, Argo CD, PUBLIC_URL, root app
│   └── versions.env               # pinned versions used by bootstrap.sh
├── gitops/                        # everything Argo CD deploys
│   ├── root-app.yaml              # template for the app of apps (filled in by bootstrap.sh)
│   ├── apps/                      # Helm chart -> one Argo CD Application per component/project
│   │   └── values.yaml            #   <- the list of research projects lives here
│   ├── platform/                  # StorageClasses, Hubble UI ingress
│   ├── keycloak/                  # Keycloak Deployment + realm (users, groups, client)
│   ├── jupyterhub/                # Z2JH chart values, RBAC, ingress
│   │   └── files/tre_config.py    #   <- project-aware spawning logic
│   ├── network-policies/          # CiliumNetworkPolicy for JupyterHub itself
│   ├── kyverno/                   # ClusterPolicies + RBAC for generate
│   ├── projects/chart/            # Helm chart: everything one project needs
│   └── portal/                    # landing page
├── scripts/
│   ├── tre                        # helper CLI (tre info, status, hubble...)
│   └── validate.sh                # static checks run by CI (helm, kustomize, kubeconform)
├── tests/
│   ├── test_tre_config.py         # pytest: spawner logic against real KubeSpawner
│   └── kyverno/                   # kyverno CLI tests for the policies
├── docs/                          # this site (Zensical)
├── zensical.toml                  # site configuration
└── .github/workflows/
    ├── docs.yml                   # build + publish docs to GitHub Pages
    └── validate.yml               # lint, render and test everything
```

## Where to change things

| I want to... | Edit |
|---|---|
| Add/remove a research project | `gitops/apps/values.yaml` (+ Keycloak group) |
| Change what every project gets | `gitops/projects/chart/templates/` |
| Change workspace sizes | `gitops/projects/chart/values.yaml` → `sizeCatalogue` |
| Allow a project some internet | `internetAllowlist` for that project in `gitops/apps/values.yaml` |
| Change how JupyterHub picks projects | `gitops/jupyterhub/files/tre_config.py` (and its tests) |
| Change login / groups / users | `gitops/keycloak/realm-tre.json` |
| Add or change a guardrail | `gitops/kyverno/` (and `tests/kyverno/`) |
| Change a tool version | `.devcontainer/` files; see [Versions](versions.md) |
