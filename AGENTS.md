# AGENTS.md: guidance for coding agents in the KID repository

KID (**KARECTL in Docker**) is a *training* environment: a single-node Kubernetes Trusted Research
Environment (TRE), modelled on [K8TRE](https://docs.k8tre.org/latest/), running in a VS Code dev
container (GitHub Codespaces or local). The person you are helping is most likely a **trainee**
working through the labs in `docs/labs/`. They know TREs but are new to Kubernetes.

## How to help a trainee

- **Teach, don't just solve.** For lab steps and "Check your understanding" questions, explain the
  concept, point to the file or command that shows it, and let them run it. Give the full answer
  when they ask for it or are stuck after a hint.
- **Show your evidence.** Prefer running a read-only `kubectl`/`hubble` command and explaining its
  output to answering from memory. Cite repo paths (`gitops/...`) and docs pages (`docs/...`).
- **Connect to TRE concepts.** Relate answers back to isolation, egress control, storage scoping,
  resource limits, guardrails and the Five Safes. `docs/concepts/` has the vocabulary.
- **Keep changes small and reversible**, and say whether a change goes through Git (GitOps) or
  directly into the cluster (`kubectl`), and what that means for drift and audit.
- Task-specific procedures live in **agent skills** under `.agents/skills/` (see below). Load the
  matching skill before doing that kind of task.

## Safety rules

1. **Training data only.** Never put real, personal or sensitive data in this environment, and
   never help move data *out* of a workspace around the controls (that's what the controls are for).
2. **Don't weaken guardrails to make something work.** If a workspace can't reach something, a pod is
   rejected or a quota is hit, explain *why* (usually it's the lesson) before proposing a change.
   Never delete or disable `default-deny`, `workspace-baseline`, `jupyterhub-baseline`, the Kyverno
   policies, Pod Security labels, quotas or RBAC as a "fix" unless the trainee explicitly asks for
   that experiment, and then say how to restore it.
3. **Ask before destructive actions**: deleting namespaces, PVCs/PVs (project data), the Keycloak pod
   (resets users and groups), `git push --force`, `git reset --hard`, or re-bootstrapping.
4. Demo credentials in this repo are public on purpose. Don't "fix" them; never reuse them elsewhere.

## Environment facts

- Commands run in the **dev container terminal**. `kubectl`, `helm`, `cilium`, `hubble`, `argocd`,
  `kubescape` and `docker` are installed; `KUBECONFIG=~/.kube/config` points at the `k3s-server`
  container. `k` is an alias for `kubectl`. If you are running *outside* the dev container (e.g. on
  the host), these tools won't reach the cluster: ask the trainee to run commands in the container.
- `scripts/tre` (on `PATH` as `tre`): `tre info` (URLs, passwords), `tre status` (Argo CD apps,
  unhealthy pods), `tre workspaces`, `tre usage`, `tre hubble` (start the Hubble port-forward, needed
  before `hubble observe`), `tre sync` (make Argo CD re-read Git now), `tre bootstrap`.
- URLs are under one public URL (`tre info`): `/` portal, `/jupyter/`, `/hubble/`, `/argocd/`,
  `/auth/` + `/keycloak` (Keycloak). Codespaces: `https://<name>-80.app.github.dev`; local:
  `http://localhost` (or `TRE_HTTP_PORT`).
- Demo users (password): `researcher1` (researcher) → alpha; `researcher2` → beta; `researcher3` →
  alpha + beta; `researcher4` → no project; `tre-admin` (admin) → JupyterHub admin. Keycloak console
  `admin`/`admin`. Groups are copied into JupyterHub **at login**: log out and in after changes.
- Keycloak runs in dev mode: changes made in its console are **lost when the pod restarts** (the
  realm is re-imported from `gitops/keycloak/realm-tre.json`).

## How the platform is wired

- **GitOps.** `bootstrap.sh` installs Cilium (+ Hubble) and Argo CD, then applies
  `gitops/root-app.yaml` pointing at the trainee's fork and branch. `gitops/apps/` is a Helm chart
  that renders one Argo CD Application per component and per project. Argo CD has `selfHeal` and
  `prune`: **manual edits to Git-managed objects are reverted**; objects created by hand (not in Git)
  are left alone. Changes under `gitops/` only reach the cluster after `git commit && git push`
  (then `tre sync`). Trainees without a fork apply rendered manifests with `kubectl` instead.
- **Projects.** A project is a namespace `project-<name>` labelled `k8tre.io/type=project`,
  `k8tre.io/project=<name>`, rendered by `gitops/projects/chart` from the `projects:` list in
  `gitops/apps/values.yaml`. Members = Keycloak group `<name>`.
- **Workspaces.** JupyterHub (Z2JH 4.0.0) spawns `jupyter-<user>` pods (label
  `component=singleuser-server`) into the chosen project namespace. Project logic:
  `gitops/jupyterhub/files/tre_config.py`. Home PVC `home-<user>` per project, shared PVC
  `project-shared` at `~/shared`.
- **Network.** Cilium policies: `workspace-baseline` (project chart: ingress only from hub/proxy on
  8888; egress only DNS + hub:8081), `default-deny` (generated by Kyverno in every project namespace,
  re-created if deleted), optional `internet-allowlist` (FQDNs, project value `internetAllowlist`),
  and `jupyterhub-baseline` (`gitops/network-policies/`). Policies are additive allow-lists.
- **Guardrails.** Kyverno policies in `gitops/kyverno/` (scoped to project namespaces); Pod Security
  `baseline` enforced (`restricted` warned) via namespace labels; ResourceQuota + LimitRange per project.

## Repository map

| Path | What it is |
|---|---|
| `.devcontainer/` | Dev container, k3s compose file, `bootstrap.sh`, `versions.env` |
| `gitops/apps/values.yaml` | **List of research projects** (+ Kyverno toggle) |
| `gitops/projects/chart/` | Everything one project gets (namespace, quota, limits, PVC, RBAC, netpol) |
| `gitops/jupyterhub/` | Z2JH values, RBAC, `files/tre_config.py` |
| `gitops/keycloak/realm-tre.json` | Users, groups, OIDC client |
| `gitops/kyverno/` | ClusterPolicies + RBAC for generate rules |
| `gitops/network-policies/` | Cilium policy for JupyterHub itself |
| `gitops/platform/` | StorageClasses, Hubble UI ingress |
| `docs/` | Training docs (Zensical); labs in `docs/labs/` |
| `tests/` | Spawner unit tests, JupyterHub e2e harness, Kyverno CLI tests |

## Before you finish a change

Run what applies (CI runs all of them):

```bash
helm template root gitops/apps > /dev/null                  # apps chart renders
helm template p gitops/projects/chart --set name=test > /dev/null
scripts/validate.sh            # shellcheck, helm, kustomize, kubeconform (needs kustomize/kubeconform)
pip install -r tests/requirements.txt && pytest tests       # after touching tre_config.py
kyverno test tests/kyverno     # after touching gitops/kyverno (if the kyverno CLI is installed)
zensical build --clean         # after touching docs/ (pip install zensical)
```

Keep YAML comments explanatory: this repo is read by learners. Match the existing style.

## Agent skills

Detailed procedures are in `.agents/skills/<name>/SKILL.md` (also visible as `.claude/skills` and
`.github/skills`). Use them:

| Skill | Use when the trainee wants to... |
|---|---|
| `kid-lab-guide` | work through a lab, check an answer, understand what a lab step shows |
| `kid-network-policy` | allow/deny traffic, add internet access, read Hubble drops |
| `kid-new-project` | create, change or retire a research project; give users access |
| `kid-kyverno-policy` | write, test or change an admission/generate policy |
| `kid-workspace-config` | change workspace sizes, images, storage, culling or spawner logic |
| `kid-troubleshoot` | fix a broken environment: bootstrap, Argo CD, login, spawns, Hubble |
