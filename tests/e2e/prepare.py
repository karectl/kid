"""Materialise the JupyterHub hub exactly as Argo CD would deploy it, so a real
JupyterHub process can run it outside Kubernetes.

  * `kustomize build --enable-helm gitops/jupyterhub` (Z2JH chart + our values)
  * the hub ConfigMap/Secret files the pod would mount (jupyterhub_config.py,
    z2jh.py, values.yaml, generated secrets)
  * tre_config.py from the generated ConfigMap
  * the project Namespaces rendered from gitops/apps + gitops/projects/chart,
    served later by the fake Kubernetes API

Requires kustomize and helm on PATH. Output goes to tests/e2e/.work/.
"""
import base64
import json
import os
import pathlib
import shutil
import subprocess

import yaml

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
W = HERE / ".work"


def main():
    if W.exists():
        shutil.rmtree(W)
    W.mkdir()

    render = subprocess.check_output(
        ["kustomize", "build", "--enable-helm", str(REPO / "gitops/jupyterhub")], text=True
    )
    # kustomize downloads the chart next to the kustomization; don't leave it there
    shutil.rmtree(REPO / "gitops/jupyterhub/charts", ignore_errors=True)
    (W / "render.yaml").write_text(render)
    docs = [d for d in yaml.safe_load_all(render) if d]

    def get(kind, prefix):
        return next(d for d in docs if d["kind"] == kind and d["metadata"]["name"].startswith(prefix))

    etc = W / "etc"
    (etc / "config").mkdir(parents=True)
    (etc / "secret").mkdir()
    hub_cm = get("ConfigMap", "hub")["data"]
    for k, v in hub_cm.items():
        (etc / "config" / k).write_text(v)

    tre = W / "tre"
    tre.mkdir()
    for k, v in get("ConfigMap", "jupyterhub-tre-config-")["data"].items():
        (tre / k).write_text(v)

    secret = {k: base64.b64decode(v).decode() for k, v in get("Secret", "hub")["data"].items()}
    values = yaml.safe_load(secret["values.yaml"])
    extra = values["hub"]["extraConfig"]
    for k, v in extra.items():
        extra[k] = v.replace("/etc/jupyterhub/tre/", f"{tre}/")
    # Test-only overrides: there is no cluster DNS, Keycloak or database here.
    extra["99-e2e-harness"] = f"""
c.JupyterHub.hub_connect_url = "http://127.0.0.1:8081"
c.ConfigurableHTTPProxy.api_url = "http://127.0.0.1:8001"
c.GenericOAuthenticator.token_url = "http://127.0.0.1:9000/token"
c.GenericOAuthenticator.userdata_url = "http://127.0.0.1:9000/userinfo"
c.KubeSpawner.start_timeout = 20
c.JupyterHub.db_url = "sqlite:///{W}/jupyterhub.sqlite"
"""
    secret["values.yaml"] = yaml.safe_dump(values)
    for k, v in secret.items():
        (etc / "secret" / k).write_text(v)

    for f in ("jupyterhub_config.py", "z2jh.py"):
        (W / f).write_text(hub_cm[f].replace("/usr/local/etc/jupyterhub", str(etc)))

    env = {"PUBLIC_URL": "http://127.0.0.1:8000", "HUB_SERVICE_PORT": "8081",
           "PROXY_API_SERVICE_PORT": "8001", "PROXY_PUBLIC_SERVICE_PORT": "80",
           "POD_NAMESPACE": "jupyterhub", "HELM_RELEASE_NAME": "jupyterhub",
           "CONFIGPROXY_AUTH_TOKEN": secret["hub.config.ConfigurableHTTPProxy.auth_token"],
           "KUBECONFIG": str(W / "kubeconfig")}
    (W / "hub.env").write_text("".join(f"export {k}={json.dumps(v)}\n" for k, v in env.items()))

    (W / "kubeconfig").write_text(
        "apiVersion: v1\nkind: Config\ncurrent-context: fake\n"
        "clusters: [{name: fake, cluster: {server: 'http://127.0.0.1:6443'}}]\n"
        "contexts: [{name: fake, context: {cluster: fake, user: fake}}]\n"
        "users: [{name: fake, user: {token: fake}}]\n"
    )

    apps = subprocess.check_output(["helm", "template", "root", str(REPO / "gitops/apps")], text=True)
    namespaces = []
    for d in yaml.safe_load_all(apps):
        if d and d["metadata"]["name"].startswith("project-"):
            vf = W / f"{d['metadata']['name']}.values.yaml"
            vf.write_text(yaml.safe_dump(d["spec"]["source"]["helm"]["valuesObject"]))
            out = subprocess.check_output(
                ["helm", "template", d["metadata"]["name"], str(REPO / "gitops/projects/chart"), "-f", str(vf)],
                text=True)
            namespaces += [x for x in yaml.safe_load_all(out) if x and x["kind"] == "Namespace"]
    for n in namespaces:
        n["status"] = {"phase": "Active"}
    (W / "namespaces.json").write_text(json.dumps(namespaces))
    print("prepared", W, [n["metadata"]["name"] for n in namespaces])


if __name__ == "__main__":
    main()
