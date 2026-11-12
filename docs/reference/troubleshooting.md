# Troubleshooting

Start with `tre status`. It shows Argo CD application health and any pod that isn't running.

## Bootstrap

??? question "The bootstrap failed or I closed the terminal"
    The log is in `/tmp/kid-bootstrap.log`. The script is idempotent, so re-run it with `tre bootstrap`.

??? question "`cilium status` never becomes OK"
    Usually memory or a restarted k3s container. Check `docker stats --no-stream` and
    `kubectl -n kube-system get pods -l k8s-app=cilium`. On Docker Desktop give Docker at least 8 GB.
    As a last resort: **Dev Containers: Rebuild Container** (the cluster volume survives). To start
    completely from scratch, stop the dev container, then on the host delete the containers and the
    `k3s-server` / `k8s-config` volumes (`docker volume ls | grep -E "k3s-server|k8s-config"`, then
    `docker volume rm ...`) and reopen the folder in the container. In Codespaces, just create a new
    codespace.

??? question "Argo CD: `unable to resolve 'my-branch' to a commit SHA`"
    Argo CD reads from GitHub. Push your branch (`git push -u origin HEAD`) and run `tre sync`. If
    you cloned without forking, bootstrap on `main` or set `KID_GITOPS_REVISION=main`.

??? question "Argo CD: `authentication required` / repository not accessible"
    Your fork is private. Make it public, or add credentials:
    `argocd login --core && argocd repo add https://github.com/<you>/kid.git --username <you> --password <PAT>`
    (with `kubectl config set-context --current --namespace=argocd` first).

??? question "Argo CD: `lookup github.com on 10.43.0.10:53: server misbehaving`"
    The cluster can't resolve names on the internet. CoreDNS (`10.43.0.10`) forwards external
    lookups to an upstream DNS server, and your network is blocking it. Many corporate, university,
    NHS and VPN networks only allow DNS to their own resolvers. Confirm it:
    `kubectl -n kube-system logs -l k8s-app=kube-dns | grep timeout` shows
    `read udp ...->8.8.8.8:53: i/o timeout`.

    The k3s container normally picks up the DNS servers Docker uses (see
    `.devcontainer/k3s-entrypoint.sh`). If it still fails, set `KID_UPSTREAM_DNS` to a resolver
    your network allows (on the host, or in `.devcontainer/.env`), for example
    `KID_UPSTREAM_DNS=192.168.65.7` on Docker Desktop, then **Dev Containers: Rebuild Container**
    (the cluster volume survives). Check with
    `kubectl run dnstest --rm -it --restart=Never --image=busybox:1.36 -- nslookup github.com`.

## Applications

??? question "`kyverno-policies` is Degraded / `no matches for kind ClusterPolicy`"
    Kyverno's CRDs weren't installed yet when Argo CD first tried. It retries automatically. Wait a
    few minutes or run `tre sync`.

??? question "`jupyterhub` stays Progressing"
    `kubectl -n jupyterhub get pods`. If the hub is in `CrashLoopBackOff`, read
    `kubectl -n jupyterhub logs deploy/hub`. A Python error there usually means a typo in
    `tre_config.py` or `values.yaml`; run `pytest tests` before pushing.

??? question "Keycloak takes ages / restarts"
    It needs ~60–90 s to start and ~600 MB of RAM. `kubectl -n keycloak logs deploy/keycloak`. If it
    is OOMKilled, raise its memory limit in `gitops/keycloak/deployment.yaml`.

## Logging in

??? question "Keycloak says *Invalid parameter: redirect_uri* or I'm redirected to the wrong host"
    The public URL is wrong. Check it with
    `kubectl -n jupyterhub get cm cluster-domain -o yaml`. If you changed `TRE_HTTP_PORT` or moved
    the codespace, re-run `tre bootstrap`, then
    `kubectl -n keycloak rollout restart deploy/keycloak` and
    `kubectl -n jupyterhub rollout restart deploy/hub`.

??? question "Codespaces: *401* or GitHub login page when opening the TRE"
    Port 80 is private and needs your GitHub session. Open it from the **Ports** tab in the same
    browser where you are logged in to GitHub.

??? question "I only see one project / groups didn't update"
    Groups are copied at **login**. Log out (`/jupyter/hub/logout`) and back in.

## Workspaces

??? question "*You are not a member of any research project*"
    Working as designed (researcher4, tre-admin). Add the user to a project group in Keycloak.

??? question "Spawn times out / pod `Pending`"
    `kubectl -n project-<p> describe pod jupyter-<user>`. Look at **Events**:

    * `Insufficient memory`: the node is full; stop other workspaces.
    * `exceeded quota`: the project quota is full (lab 6).
    * Image pull still running: the first pull of the notebook image takes a minute or two.

??? question "The workspace starts, then the browser shows *503* or keeps spinning"
    The proxy can't reach the pod, or the pod can't reach the hub. Check network drops:
    `hubble observe --namespace project-<p> --verdict DROPPED` and `--namespace jupyterhub`.

??? question "`hubble observe` says *connection refused*"
    Run `tre hubble` first (it starts the port-forward). If it was running before a restart,
    `pkill -f "hubble port-forward"` and run `tre hubble` again.

## Resources

??? question "My laptop is struggling"
    See [Resource budget](resource-budget.md): stop idle workspaces, disable Kyverno, close other
    apps and browser tabs.
