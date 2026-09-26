---
name: kid-lab-guide
description: Tutor a trainee through the KID (KARECTL in Docker) Kubernetes TRE labs in docs/labs/ - explain what a lab step demonstrates, check their output or answers, give graded hints, and map each lab to the files and commands behind it. Use when the user mentions a lab number, a "check your understanding" question, or asks why they see a particular result while following the training.
---

# KID lab guide

The labs live in `docs/labs/01-orientation.md` … `10-challenges.md`. Read the lab the trainee is on
before answering; quote its step numbers so they can follow along.

## Teaching approach

1. **Find where they are**: which lab and step, which user they are logged in as, what they ran,
   what they saw. Ask if unclear.
2. **Hint ladder** for questions and exercises: (a) point to the concept/doc page, (b) point to the
   exact file or command, (c) give the answer with the reasoning. Move down the ladder when they ask
   or are stuck. Never skip straight to (c) for "Check your understanding" unless asked.
3. **Verify with the cluster** using read-only commands, and explain the output line by line.
4. **Tie it back to the TRE**: what control did they just see, which of the Five Safes it supports,
   and what a production TRE would add (`docs/concepts/architecture.md#what-a-production-tre-adds`).
5. At the end of a lab, offer to clean up anything they created (the lab lists it).

## Lab map

| Lab | Demonstrates | Key files | Key commands |
|---|---|---|---|
| 1 Orientation | Namespaces, labels, ingress, GitOps source | `gitops/apps/`, `gitops/*/ingress.yaml` | `kubectl get ns --show-labels`, `kubectl get ingress -A`, `tre status` |
| 2 Workspaces | Group → project → pod in project namespace | `gitops/jupyterhub/files/tre_config.py`, `gitops/keycloak/realm-tre.json` | `tre workspaces`, `kubectl -n project-alpha describe pod jupyter-researcher1`, `kubectl -n jupyterhub logs deploy/hub \| grep "may use projects"` |
| 3 Isolation | Default deny, identity-based policy, Hubble | `gitops/projects/chart/templates/networkpolicy.yaml`, `gitops/kyverno/generate-default-deny.yaml` | `tre hubble`, `hubble observe --namespace project-alpha --verdict DROPPED`, `kubectl -n project-alpha get cnp` |
| 4 Egress | No internet; FQDN allow-lists; GitOps vs kubectl | `gitops/projects/chart/templates/internet-allowlist.yaml`, `gitops/apps/values.yaml` | `hubble observe --namespace project-alpha --protocol dns`, `cilium-dbg fqdn cache list` |
| 5 Storage | StorageClasses, per-project home, shared PVC, node access | `gitops/platform/storageclasses.yaml`, `shared-storage.yaml`, `resourcequota.yaml` | `kubectl get pvc -A`, `kubectl get pv`, `docker exec` into `k3s-server` |
| 6 Resources | Limits, throttling, OOM, LimitRange, ResourceQuota | `gitops/projects/chart/values.yaml` (`sizeCatalogue`), `limitrange.yaml`, `resourcequota.yaml` | `kubectl top pod -n project-alpha`, `kubectl -n project-beta describe resourcequota` |
| 7 New project | GitOps onboarding, Keycloak groups, RBAC as second lock | `gitops/apps/values.yaml`, `gitops/projects/chart/templates/rbac.yaml` | see skill `kid-new-project` |
| 8 Kyverno | Enforce vs Audit, generate, PSA vs Kyverno | `gitops/kyverno/*.yaml`, `tests/kyverno/` | `kubectl get cpol`, `kubectl -n project-alpha get polr -o wide` |
| 9 Kubescape | Posture scanning and triage | – | `kubescape scan framework nsa --include-namespaces project-alpha,project-beta` |
| 10 Challenges | Open-ended | varies | use the matching skill |

## Expected results (so you can reassure or correct)

- **Lab 2**: researcher1 sees only *Project Alpha* (Small); researcher3 sees both, beta offers
  Small/Medium; researcher4 sees "You are not a member of any research project" and Start is refused.
  Pod `jupyter-<user>` runs as uid 1000 with label `k8tre.io/project=<p>` and env `K8TRE_PROJECT`.
- **Lab 3**: connections from alpha to a beta workspace IP time out; Hubble shows `Policy denied
  DROPPED`. Workspaces in the *same* project also can't reach each other (ingress only from
  hub/proxy). Deleting `default-deny` → Kyverno re-creates it; deleting `workspace-baseline` → Argo
  CD re-creates it.
- **Lab 4**: DNS resolves but TCP to the internet times out. After an FQDN allow-list only the listed
  names work, only in that project.
- **Lab 5**: `~/shared` is shared within a project; `$HOME` is per user *per project*; the
  `local-path` class is refused by quota; a 50Gi claim is refused by the LimitRange (max 5Gi).
- **Lab 6**: CPU is throttled to the limit (~500m for small); memory over the limit kills the
  *kernel* (pod keeps running, RESTARTS stays 0); `toobig` is refused by the LimitRange; two 2Gi
  "hog" pods fill beta's 4Gi quota and the next spawn fails with `exceeded quota`. KubeSpawner reads
  `1G` as 1 GiB.
- **Lab 7**: a hand-labelled namespace gets `default-deny` from Kyverno, JupyterHub offers it, but
  the spawn fails with `403 Forbidden` because there's no hub RoleBinding.
- **Lab 8**: `nginx` in a project → blocked by `restrict-image-registries` and
  `require-project-label`; privileged pod → blocked first by **Pod Security** (built-in admission
  runs before webhooks); `:latest` → allowed but reported (Audit).

## Common trainee mix-ups

- Logged in as the wrong user: each user needs its own browser profile or private window.
- Group changes not visible: log out of JupyterHub (`/jupyter/hub/logout`) and back in.
- `hubble observe` "connection refused": run `tre hubble` first.
- Edited a file under `gitops/` and nothing happened: it must be committed and pushed to the branch
  Argo CD follows (`kubectl -n argocd get application root -o jsonpath='{.spec.source.targetRevision}'`), then `tre sync`.
- Manual `kubectl edit` of a Git-managed object reverted: that's Argo CD `selfHeal`, which is the point.
