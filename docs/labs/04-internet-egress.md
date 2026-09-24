# Lab 4: Internet egress

**Objectives**: confirm workspaces have no internet access, see *what* they tried to reach,
and grant narrowly scoped access by DNS name, first by hand and then the GitOps way.

## 1. No internet

As **researcher1** (project-alpha), in a notebook:

```python
import urllib.request
for url in ["https://pypi.org/simple/", "https://github.com", "http://example.com"]:
    try:
        urllib.request.urlopen(url, timeout=5)
        print("REACHED", url)
    except Exception as e:
        print("blocked", url, "-", e)
```

And from a JupyterLab terminal:

```bash
pip install --timeout 5 --retries 0 cowsay
```

Everything times out.

## 2. But DNS works

```python
import socket
print(socket.gethostbyname("pypi.org"))
```

Name lookups are allowed (workspaces need DNS to find the hub), so the name resolves even though
the connection is then dropped. **Discuss**: could a determined user leak data through DNS
queries alone? What would a production TRE do about it? (Hints: restrict `matchPattern`, log
queries, use an internal resolver.)

## 3. See what was attempted

```bash
hubble observe --namespace project-alpha --protocol dns --last 20
hubble observe --namespace project-alpha --verdict DROPPED --last 20
```

The DNS lines show the **names** looked up (`pypi.org`, `github.com`...). The dropped lines show
the connections to their IPs on port 443/80, with destination identity `world`. This is the audit
trail you'd want in a TRE.

## 4. Allow PyPI for project alpha only, by hand

Create `/workspace/allow-pypi.yaml` in the dev container:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-pypi
  namespace: project-alpha
spec:
  description: Lab 4 - workspaces in alpha may install packages from PyPI.
  endpointSelector:
    matchLabels:
      component: singleuser-server
  egress:
    - toFQDNs:
        - matchName: pypi.org
        - matchName: files.pythonhosted.org
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
```

```bash
kubectl apply -f /workspace/allow-pypi.yaml
```

Back in researcher1's terminal:

```bash
pip install --timeout 10 cowsay && python -c "import cowsay; cowsay.cow('Hello from project alpha')"
```

It works. Re-run the notebook cell from step 1: PyPI is reachable, GitHub and example.com are not.

Check that **project-beta** is still offline: as researcher2, run the same `pip install`.

```bash
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg fqdn cache list | grep -E "pypi|pythonhosted"
```

Cilium learned the IPs behind the allowed names from the DNS answers.

!!! note "Why Argo CD leaves it alone"
    `allow-pypi` isn't in Git, so Argo CD doesn't manage it and won't prune it. That is exactly the
    kind of **undocumented firewall exception** GitOps is meant to prevent. Delete it now:
    `kubectl delete -f /workspace/allow-pypi.yaml`.

## 5. Do it properly: through Git

The project chart has an `internetAllowlist` setting that renders an equivalent policy
(`gitops/projects/chart/templates/internet-allowlist.yaml`).

=== "With a fork"

    Edit `gitops/apps/values.yaml` and add to the **alpha** project:

    ```yaml
      - name: alpha
        ...
        internetAllowlist:
          - pypi.org
          - files.pythonhosted.org
    ```

    ```bash
    git add gitops/apps/values.yaml
    git commit -m "alpha: allow PyPI"
    git push
    tre sync
    kubectl -n project-alpha get cnp -w
    ```

    `internet-allowlist` appears within a minute. The commit is your change record: who asked, who
    approved and when.

=== "Without a fork"

    Render just that template from the chart locally and apply it (this is what Argo CD does for
    you):

    ```bash
    helm template project-alpha gitops/projects/chart \
      --set name=alpha \
      --set 'internetAllowlist={pypi.org,files.pythonhosted.org}' \
      -s templates/internet-allowlist.yaml | kubectl apply -f -
    ```

Test `pip install` again as researcher1.

## 6. Clean up

Remove the `internetAllowlist` lines (commit and push), or
`kubectl -n project-alpha delete cnp internet-allowlist`.

## What just happened

* Egress was denied because `workspace-baseline` only allows DNS and the hub.
* `toFQDNs` makes Cilium watch DNS answers (through the DNS proxy set up by the `dns` rule) and
  allow traffic only to the IPs those names resolved to.
* Policies are additive, so adding a policy **widened** access for the selected pods only.

## Check your understanding

1. Why is allowing `*.pythonhosted.org` riskier than listing the exact name?
2. PyPI lets anyone upload packages. Is allowing it compatible with "safe settings"? What do real
   TREs do instead? (Package mirrors or proxies with allow-lists, e.g. Nexus or Artifactory.)
3. Cilium can also filter **HTTP paths and methods** (L7), but not for HTTPS without terminating TLS.
   Why?
