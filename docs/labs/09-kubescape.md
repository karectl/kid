# Lab 9: Posture with Kubescape

**Objectives**: scan the cluster and the Git repository against published hardening frameworks,
and practise **triage**: deciding what to fix, what to accept and why.

## 1. Scan the projects

```bash
kubescape list frameworks
kubescape scan framework nsa --include-namespaces project-alpha,project-beta
```

The first run downloads the framework definitions. You get a table of **controls** (checks), each
with a severity, the number of failed resources, and a **compliance score** at the end.

## 2. Compare with the whole cluster

```bash
kubescape scan framework nsa
```

The score drops. Platform components in `kube-system` (Cilium, for one) *need* privileges, host
networking and so on. That's expected and doesn't make them wrong, but it shows why platform
namespaces need their own tight access control and review.

## 3. Drill into a control

Pick a failed control from step 1 and look at the detail, for example:

```bash
kubescape scan framework nsa --include-namespaces project-alpha -v 2>&1 | less -R
```

For each failed resource Kubescape explains what failed and how to fix it.

## 4. Scan Git before it reaches the cluster

```bash
kubescape scan gitops/projects/chart
kubescape scan gitops/network-policies gitops/kyverno
```

Scanning manifests and charts in CI catches problems at review time, before they are deployed.

## 5. Triage

As a group, fill in a table like this for **three** failed controls:

| Control | Affected resources | Risk in *this* TRE | Decision | Justification / action |
|---|---|---|---|---|
| e.g. Immutable container filesystem | workspace pods | Low–medium: users can modify files outside `$HOME` inside their own container | **Accept** | JupyterLab/pip/conda need writable paths; container is ephemeral; network egress is denied |
| ... | | | Fix / Accept / N/A | |

Decisions that are **accepted** should be recorded (a risk register, or a `PolicyException`/scan
exception file in Git) so the next scan, and the next auditor, knows they were deliberate.

## 6. A report to share

```bash
kubescape scan framework nsa --include-namespaces project-alpha,project-beta \
  --format html --output /workspace/kubescape-report.html
```

Open `kubescape-report.html` from the VS Code explorer (right-click → **Open with Live Preview**,
or download it).

!!! warning
    Don't commit scan reports of real systems to public repositories. They are a map for
    attackers.

## Check your understanding

1. What is the difference between what **Kyverno** does and what **Kubescape** does?
2. Some findings can be fixed in the project chart (e.g. setting `seccompProfile: RuntimeDefault`
   on workspaces). Where exactly would you add that? (Hint: `singleuser.extraPodConfig` or
   KubeSpawner's `container_security_context`.)
3. How often should a TRE be scanned, and who should see the results?
