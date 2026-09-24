# Kubescape

[Kubescape](https://kubescape.io/) scans a cluster (or YAML files, or Helm charts) against
security **frameworks** such as the NSA/CISA Kubernetes Hardening Guide, MITRE ATT&CK and the CIS
Benchmark. It reports failed **controls** with a risk score and how to fix each one.

KID ships only the **CLI** in the dev container. The in-cluster Kubescape operator gives continuous
scanning and image vulnerability reports but needs 1.5 GB+ of RAM, too much for a laptop demo.

## Commands

```bash
kubescape list frameworks
kubescape scan framework nsa                                   # whole cluster
kubescape scan framework nsa --include-namespaces project-alpha,project-beta
kubescape scan framework mitre --include-namespaces project-alpha
kubescape scan control C-0017 --include-namespaces project-alpha -v   # a single control, verbose
kubescape scan gitops/                                          # scan the YAML/Helm in Git
kubescape scan framework nsa --format html --output /workspace/kubescape-report.html
```

!!! note
    Kubescape downloads the framework definitions from GitHub the first time it runs, so it needs
    internet access from the dev container. That's fine in Codespaces and on most networks.

## Reading results

* **Compliance score**: the percentage of controls passed, weighted by resources.
* **Failed resources**: for each control, which objects fail and why.
* Some failures are **expected and accepted** in KID (for example, workspaces don't use a read-only root
  filesystem because JupyterLab, pip and conda expect to write outside the home directory). A real TRE records
  such decisions as documented exceptions, much as an ISO 27001 statement of applicability does.

See [lab 9](../labs/09-kubescape.md) for a guided walkthrough.
