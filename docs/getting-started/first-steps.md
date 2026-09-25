# First steps

All commands in these docs run in the **dev container terminal** (VS Code → Terminal → New
Terminal) unless they say otherwise.

## Check that everything is up

```bash
tre status
```

You're ready when every application is `Synced` and `Healthy` and no pods are listed as unhealthy:

```text
Argo CD applications
NAME               SYNC     HEALTH    REVISION
jupyterhub         Synced   Healthy   3f1c...
keycloak           Synced   Healthy   3f1c...
kyverno            Synced   Healthy   3.3.4
kyverno-policies   Synced   Healthy   3f1c...
network-policies   Synced   Healthy   3f1c...
platform           Synced   Healthy   3f1c...
portal             Synced   Healthy   3f1c...
project-alpha      Synced   Healthy   3f1c...
project-beta       Synced   Healthy   3f1c...
root               Synced   Healthy   3f1c...

Pods that are not Running/Completed
  none - all good
```

It is normal for some applications to show `Progressing`, `OutOfSync` or `Missing` for the first
few minutes. Kyverno policies, for example, can't be created until Kyverno has installed its
CRDs, so Argo CD retries them.

## Find your URLs and passwords

```bash
tre info
```

```text
KID - KARECTL in Docker
  Portal      https://<name>-80.app.github.dev/
  JupyterHub  https://<name>-80.app.github.dev/jupyter/   researcher1 / researcher  (project alpha)
  ...
```

Open the **Portal**: it links to everything else and lists the demo accounts.

## The `tre` helper

| Command | What it does |
|---|---|
| `tre info` | URLs and demo credentials |
| `tre status` | Argo CD applications and unhealthy pods |
| `tre workspaces` | Running notebook servers, their project and limits |
| `tre usage` | CPU/memory of the node and the busiest pods |
| `tre hubble` | Port-forward Hubble so `hubble observe` works |
| `tre sync` | Make Argo CD re-read Git now |
| `tre bootstrap` | Re-run the bootstrap script |

It's a short bash script (`scripts/tre`) that runs `kubectl` for you. Read it to see how.

## The demo accounts

| User | Password | Keycloak groups | What they can do |
|---|---|---|---|
| `researcher1` | `researcher` | `alpha` | Launch workspaces in **project-alpha** |
| `researcher2` | `researcher` | `beta` | Launch workspaces in **project-beta** |
| `researcher3` | `researcher` | `alpha`, `beta` | Choose either project |
| `researcher4` | `researcher` | – | Log in, but launch nothing |
| `tre-admin` | `admin` | `tre-admins` | JupyterHub admin panel |

Keycloak admin console: `admin` / `admin`. Argo CD: `admin` / the password printed by `tre info`.

!!! tip "Several users at once"
    Use a private/incognito window, or another browser profile, for each extra user. Cookies
    are per browser profile.

You're ready for the [labs](../labs/index.md).
