# Resource budget

KID targets **16 GB laptops** with Docker allowed **8–10 GB**, and 4-core / 16 GB Codespaces.

## Where the memory goes

| Component | Requests (reserved) | Typical use |
|---|---|---|
| k3s (API server, etcd-less SQLite, controller, scheduler, kubelet, containerd) | – | 500–700 MB |
| CoreDNS, Traefik, local-path, metrics-server | ~200 MB | 150–250 MB |
| Cilium agent, operator, envoy, Hubble relay/UI | ~300 MB | 350–500 MB |
| Argo CD (server, repo-server, controller, redis) | – | 350–500 MB |
| Keycloak (heap capped at 512 MB) | 512 MB | 450–650 MB |
| JupyterHub hub + proxy | 320 MB | 150–250 MB |
| Kyverno (admission, background, reports) | ~200 MB | 200–350 MB |
| Portal | – | < 10 MB |
| **Platform** | | **≈ 2.5–3.5 GB** |
| Workspace, small | 256 MB | 150–400 MB idle, ≤ 1 GiB |
| Workspace, medium | 512 MB | ≤ 2 GiB |

Measure yourself:

```bash
tre usage
docker stats --no-stream
```

## On a tight machine

1. Run **one or two** workspaces at a time; stop them when you finish a lab.
2. Bootstrap with **`KID_ENABLE_KYVERNO=false`** (skip lab 8).
3. Close other heavy apps (browsers with many tabs, IDEs, Slack/Teams).
4. Docker Desktop: turn off Kubernetes in Docker Desktop itself if it's enabled (it's a second
   cluster!) and any unused extensions.
5. Lower the idle cull time in `gitops/jupyterhub/values.yaml`.

## Disk

Images: ~2.5 GB in the k3s container (Cilium, Keycloak, Jupyter, Argo CD, Kyverno) plus ~1.5 GB for
the dev container image. Allow 20 GB free.
