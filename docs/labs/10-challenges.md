# Lab 10: Challenges

Open-ended exercises for fast finishers, or for a second session. Each one names the files you'll
probably touch. Some need a fork (GitOps); all can be done with `kubectl` if not.

## Networking

1. **Same-project collaboration.** Allow workspaces *in the same project* to reach each other on
   port 8888, but not across projects. Hint: a CiliumNetworkPolicy with `fromEndpoints` matching
   `component: singleuser-server` (namespace defaults to the policy's own). Test with Hubble.
   *Discuss:* is this a good idea in a TRE?
2. **Watch a login.** With `hubble observe --namespace jupyterhub --follow`, log in as a user and
   identify every flow: hub→Keycloak, proxy→workspace, workspace→hub.
3. **L7 rules.** Write a policy allowing workspaces in alpha only `GET` requests to
   `http://example.com/` (plain HTTP). Hint: `toFQDNs` + `toPorts.rules.http`. Why can't you do the
   same for HTTPS?
4. **Break it and fix it.** Remove the `ingress` Traefik rule from
   `gitops/network-policies/jupyterhub.yaml` (fork) or `kubectl edit` a copy. What breaks? Find the
   drops in Hubble, then restore it.

## Workspaces

5. **Per-project images.** Make project beta use `quay.io/jupyter/scipy-notebook:2026-08-10`
   (`gitops/apps/values.yaml`). Why does Kyverno allow it? What would you need to change to use
   `ghcr.io/...` images?
6. **Faster culling.** Stop idle servers after 10 minutes (`gitops/jupyterhub/values.yaml`,
   `cull.timeout`). Why is idle culling a security control and not just a cost one?
7. **Read-only reference data.** Add a `project-data` PVC to the project chart, mount it read-only
   at `~/data` for all workspaces (`singleuser.storage.extraVolumeMounts` with `readOnly: true`),
   and discuss how data would get *into* it in a real TRE (the airlock).
8. **Hardening.** Add `seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation: false` and
   `capabilities: {drop: [ALL]}` to workspaces
   (`singleuser.extraPodConfig` / `singleuser.extraContainerConfig` in the JupyterHub values).
   Then switch the namespace label to `pod-security.kubernetes.io/enforce: restricted` in the
   project chart. Do workspaces still start? Re-run Kubescape: did the score change?

## Policy

9. **Mutate.** Write a Kyverno `mutate` policy that copies a `k8tre.io/cost-centre` annotation from
   the namespace onto every pod as a label. Add the annotation to the project chart.
10. **Protect sessions.** Write a Kyverno policy that blocks `kubectl exec` into workspace pods
    (match `PodExecOptions` / operation `CONNECT`). What should happen when an administrator really
    needs to help a user? (Think: break-glass with approval and audit.)
11. **Test first.** Add cases for your new policies to `tests/kyverno/` and run
    `kyverno test tests/kyverno` (CI runs it too).

## Platform

12. **Lean mode.** Re-bootstrap with `KID_ENABLE_KYVERNO=false` and compare `tre usage`. What
    protections did you lose? Which remain (Pod Security, quotas, network policy)?
13. **Drift.** `kubectl edit` the `project-quota` in alpha to double it. How long does it last?
    Where would you see that it happened? (Argo CD UI → project-alpha → History and events.)
14. **Read K8TRE.** Compare `gitops/jupyterhub/files/tre_config.py` with K8TRE's JupyterHub
    configuration in the [k8tre repository](https://github.com/k8tre/k8tre/tree/main/apps/jupyterhub).
    What does K8TRE do differently (hint: the cr8tor backend, Guacamole, Kerberos) and why?
