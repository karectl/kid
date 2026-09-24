# Run it locally with VS Code Dev Containers

## 1. Give Docker enough memory

=== "Docker Desktop (macOS / Windows)"

    **Settings → Resources**: set **Memory to at least 8 GB** (10 GB recommended), **CPUs to 4**
    and **Disk to at least 40 GB**. Apply & restart.

    On Windows use the WSL 2 backend and clone the repository **inside** the WSL filesystem
    (e.g. `~/src/kid`), not under `C:\`. It is much faster.

=== "Linux (Docker Engine)"

    Nothing to configure; containers can use all host memory. Make sure your user can run
    `docker ps` without `sudo`.

!!! info "Apple Silicon"
    The dev container downloads the arm64 build of every tool, and all container images used by
    the TRE are multi-architecture, so M1–M4 Macs work natively.

## 2. Get the code

```bash
# with a fork (recommended - enables the GitOps labs)
git clone https://github.com/<you>/kid.git
# or read-only
git clone https://github.com/karectl/kid.git
cd kid
code .
```

## 3. Open in the container

VS Code asks *"Reopen in Container?"*. Click it (or run **Dev Containers: Reopen in Container**
from the command palette). The first build downloads ~1.5 GB and takes 5–10 minutes.

## 4. Open the TRE

The `k3s-server` container publishes port 80 on your machine, so the TRE is at
**<http://localhost/>**.

!!! question "Port 80 already in use?"
    Set `TRE_HTTP_PORT` on your machine **before** opening the container, e.g.

    ```bash
    export TRE_HTTP_PORT=8080
    code .
    ```

    The TRE will then be at `http://localhost:8080/`. If the container was already created,
    run **Dev Containers: Rebuild Container** after setting the variable.

## Options

All of these are read from your machine's environment when the container is created:

| Variable | Default | Purpose |
|---|---|---|
| `TRE_HTTP_PORT` | `80` | Host port for the TRE |
| `KID_ENABLE_KYVERNO` | `true` | Set `false` on tight-memory laptops to skip Kyverno (~300 MB) |
| `KID_GITOPS_REPO` | your `origin` remote | Git repository Argo CD follows |
| `KID_GITOPS_REVISION` | current branch | Branch, tag or commit Argo CD follows |

!!! warning "Push before you bootstrap"
    Argo CD reads from **GitHub**. If you create a new local branch, push it before running the
    bootstrap, or Argo CD will fail with *"unable to resolve revision"*. The bootstrap prints a
    warning if the branch is missing on the remote.

Next: [First steps](first-steps.md).
