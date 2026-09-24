"""End-to-end: real JupyterHub (Z2JH config + repo values + tre_config.py)
behind a real configurable-http-proxy, mock Keycloak, fake Kubernetes API."""
import json, os, pathlib, re, time, urllib.parse
import pytest, requests

# Only meaningful with the hub, proxy and fakes running: use tests/e2e/run.sh.
pytestmark = pytest.mark.skipif(os.environ.get("KID_E2E") != "1", reason="run via tests/e2e/run.sh")

BASE = "http://127.0.0.1:8000"
PUBLIC = "http://127.0.0.1:8000"
W = pathlib.Path(__file__).resolve().parent / ".work"
REC = W / "recorded"
NO_PROXY = {"http": None, "https": None}


def login(user):
    s = requests.Session()
    s.trust_env = False
    r = s.get(f"{BASE}/jupyter/hub/oauth_login", allow_redirects=False)
    assert r.status_code == 302, r.text
    loc = r.headers["Location"]
    assert loc.startswith(f"{PUBLIC}/auth/realms/tre/protocol/openid-connect/auth?"), loc
    q = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(loc).query))
    assert q["client_id"] == "jupyterhub"
    assert q["redirect_uri"] == f"{PUBLIC}/jupyter/hub/oauth_callback"
    assert set(q["scope"].split()) == {"openid", "profile", "email"}
    # Play Keycloak: send the browser back with a code (our mock uses code = username).
    r = s.get(q["redirect_uri"], params={"code": user, "state": q["state"]}, allow_redirects=False)
    assert r.status_code == 302, (r.status_code, r.text[:500])
    return s


def xsrf(s, html):
    m = re.search(r'name="_xsrf" value="([^"]+)"', html)
    return m.group(1) if m else s.cookies.get("_xsrf")


def recorded(kind, ns, name):
    p = REC / f"{kind}-{ns}-{name}.json"
    return json.loads(p.read_text()) if p.exists() else None


def wait_for(fn, timeout=30):
    end = time.time() + timeout
    while time.time() < end:
        v = fn()
        if v:
            return v
        time.sleep(0.5)
    return None


def test_login_redirects_to_public_keycloak_url():
    login("researcher1")


def test_spawn_form_shows_only_member_projects():
    html = login("researcher1").get(f"{BASE}/jupyter/hub/spawn").text
    assert "Project Alpha" in html and "Project Beta" not in html
    html = login("researcher3").get(f"{BASE}/jupyter/hub/spawn").text
    assert "Project Alpha" in html and "Project Beta" in html
    assert "Medium - 1 CPU, 2 GB RAM" in html  # beta offers medium


def test_spawn_creates_workspace_in_project_namespace():
    s = login("researcher3")
    html = s.get(f"{BASE}/jupyter/hub/spawn").text
    r = s.post(f"{BASE}/jupyter/hub/spawn", allow_redirects=False,
               data={"_xsrf": xsrf(s, html), "profile": "beta",
                     "profile-option-beta--size": "medium"})
    assert r.status_code in (302, 200), (r.status_code, r.text[:300])
    pod = wait_for(lambda: recorded("Pod", "project-beta", "jupyter-researcher3"))
    pvc = recorded("PersistentVolumeClaim", "project-beta", "home-researcher3")
    assert pod, "no pod created in project-beta"
    assert pvc and pvc["spec"]["storageClassName"] == "tre-user-home"
    assert pvc["spec"]["resources"]["requests"]["storage"] == "1Gi"
    c = pod["spec"]["containers"][0]
    assert c["image"] == "quay.io/jupyter/minimal-notebook:2026-08-10"
    # KubeSpawner sends quantities as JSON numbers; the API server accepts them
    assert float(c["resources"]["limits"]["cpu"]) == 1.0
    assert int(c["resources"]["limits"]["memory"]) == 2 * 1024**3
    assert pod["metadata"]["labels"]["k8tre.io/project"] == "beta"
    assert pod["metadata"]["labels"]["component"] == "singleuser-server"
    env = {e["name"]: e.get("value") for e in c["env"]}
    assert env["K8TRE_PROJECT"] == "beta"
    vols = {v["name"]: v for v in pod["spec"]["volumes"]}
    assert vols["project-shared"]["persistentVolumeClaim"]["claimName"] == "project-shared"
    claims = [v["persistentVolumeClaim"]["claimName"] for v in pod["spec"]["volumes"] if "persistentVolumeClaim" in v]
    assert "home-researcher3" in claims
    mounts = {m["mountPath"] for m in c["volumeMounts"]}
    assert {"/home/jovyan", "/home/jovyan/shared"} <= mounts
    assert not pod["spec"].get("initContainers"), "no privileged block-cloud-metadata init container expected"


def test_forged_project_is_rejected():
    s = login("researcher1")
    html = s.get(f"{BASE}/jupyter/hub/spawn").text
    s.post(f"{BASE}/jupyter/hub/spawn", allow_redirects=False,
           data={"_xsrf": xsrf(s, html), "profile": "beta"})
    time.sleep(3)
    assert recorded("Pod", "project-beta", "jupyter-researcher1") is None
    log = (W / "hub.out").read_text()
    assert "No such profile: beta" in log


def test_user_without_project_cannot_spawn():
    s = login("researcher4")
    html = s.get(f"{BASE}/jupyter/hub/spawn").text
    assert "You are not a member of any research project" in html
    # Pressing Start anyway (or calling the API) is refused by pre_spawn_hook
    s.post(f"{BASE}/jupyter/hub/spawn", data={"_xsrf": xsrf(s, html)})
    assert wait_for(lambda: "researcher4 is not a member of any research project"
                    in (W / "hub.out").read_text(), 15)
    assert not list(REC.glob("Pod-*-jupyter-researcher4.json"))
    assert not list(REC.glob("PersistentVolumeClaim-*-home-researcher4.json"))


def test_admin_group_maps_to_jupyterhub_admin():
    assert login("tre-admin").get(f"{BASE}/jupyter/hub/admin").status_code == 200
    assert login("researcher1").get(f"{BASE}/jupyter/hub/admin").status_code == 403


def test_rogue_namespace_without_rolebinding_cannot_host_workspaces():
    s = login("researcher5")
    html = s.get(f"{BASE}/jupyter/hub/spawn").text
    assert "rogue" in html  # discovered from labels alone
    s.post(f"{BASE}/jupyter/hub/spawn", data={"_xsrf": xsrf(s, html), "profile": "rogue"})
    assert wait_for(lambda: "Forbidden" in (W / "hub.out").read_text().split("researcher5", 1)[-1], 30)
    assert not list(REC.glob("Pod-rogue-*.json"))
