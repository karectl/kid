# Facilitator guide

## Audience and outcomes

Junior research software engineers who already work with TREs, possibly VM-based, but are new to
Kubernetes. By the end they should be able to explain, and **demonstrate on their own cluster**,
how a Kubernetes TRE provides per-project workspaces, isolation, egress control, storage
scoping, resource limits, admission guardrails and posture assessment.

## Suggested agenda (full day)

| Time | Session | Material |
|---|---|---|
| 09:30 | Welcome; start codespaces **first thing** (they take ~15 min) | [Getting started](../getting-started/index.md) |
| 09:45 | Talk: TREs on Kubernetes, K8TRE, the Five Safes mapping | [TREs on Kubernetes](../concepts/tre-on-kubernetes.md) |
| 10:15 | Talk: Kubernetes primer (short, just what's needed) | [Primer](../concepts/kubernetes-primer.md) |
| 10:45 | Lab 1: Orientation | |
| 11:05 | *Break* | |
| 11:20 | Lab 2: Workspaces on demand | [Life of a workspace](../concepts/workspace-lifecycle.md) |
| 11:50 | Lab 3: Project isolation + Hubble | |
| 12:20 | *Lunch* | |
| 13:15 | Lab 4: Internet egress | |
| 13:45 | Lab 5: Storage | |
| 14:10 | Lab 6: CPU and memory | |
| 14:35 | *Break* | |
| 14:50 | Lab 7: A new project (GitOps) | |
| 15:20 | Lab 8: Kyverno | |
| 15:45 | Lab 9: Kubescape + triage discussion | |
| 16:10 | Wrap-up: what a production TRE adds; Q&A | [Architecture](../concepts/architecture.md#what-a-production-tre-adds) |

For a **half day**, do labs 1, 2, 3, 4 and 7 and demo 8 and 9 from the front.

## Before the workshop

- [ ] **Dry run** in a fresh codespace from the exact branch trainees will use. Time the bootstrap.
- [ ] Walk through every lab and note anything that changed in upstream images or charts.
- [ ] Check the pinned images still exist (`quay.io/jupyter/minimal-notebook:2026-08-10` etc.).
- [ ] Confirm the repository is **public** (forks inherit visibility; Argo CD needs to read them).
- [ ] Tell trainees to create a GitHub account in advance, and check their Codespaces allowance
      (organisation-owned codespaces may need an owner to enable billing).
- [ ] For local users: send the [local guide](../getting-started/local.md) a week ahead and ask
      them to build the container once at home (downloads ~4 GB in total).
- [ ] Optional: enable **Codespaces prebuilds** on the repository so the dev container image is
      ready; the cluster bootstrap still runs at creation.
- [ ] Publish the docs (the **Docs** workflow does it on every push to `main`) and share the URL.

## Running the room

* **Pairs work well**: one driver, one navigator, swap each lab.
* Many trainees will have several browser sessions going at once (researcher1, researcher2,
  researcher3). Suggest a **different browser profile per user**, colour-coded.
* The "check your understanding" questions make good whole-room discussions at the end of each lab.
* Lab 5 step 4 (reading data from the node) and lab 7 part C (the rogue namespace) usually get the
  strongest reactions. Leave time for them.

## Resetting a trainee's environment

| Problem | Fix |
|---|---|
| A project is in a mess | `kubectl delete ns project-alpha`, then `tre sync`. Argo CD recreates it (data is lost, retained PVs stay `Released`) |
| Keycloak changes need undoing | `kubectl -n keycloak rollout restart deploy/keycloak` (re-imports the realm) |
| JupyterHub state is odd | `kubectl -n jupyterhub rollout restart deploy/hub` |
| A bad commit on their fork | `git revert <sha> && git push && tre sync` |
| Everything | New codespace (Codespaces) or delete volumes and rebuild (local) |

## Known limitations

* Everything runs on **one node**: no scheduling, affinity or multi-node storage.
* No TLS inside the cluster; Codespaces provides HTTPS at the edge.
* Hubble UI and the Argo CD admin account are for demonstration, not good practice.
* Tests run in CI, but the full cluster needs privileged Docker and is **not** exercised end-to-end in
  CI. The dry run is essential.

## Implementation notes

The design rationale, component budget and decisions are in the
[implementation plan](implementation-plan.md).
