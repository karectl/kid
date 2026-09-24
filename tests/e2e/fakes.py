"""Fake Kubernetes API (records what KubeSpawner creates) + mock Keycloak
token/userinfo endpoints."""
import json, pathlib, sys, threading, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

W = pathlib.Path(__file__).resolve().parent / ".work"
NAMESPACES = json.loads((W / "namespaces.json").read_text())
# Lab 7 part C: a namespace labelled by hand, with no hub RoleBinding.
NAMESPACES.append({"apiVersion": "v1", "kind": "Namespace", "status": {"phase": "Active"},
                   "metadata": {"name": "rogue", "labels": {"k8tre.io/type": "project", "k8tre.io/project": "rogue"}}})
FORBIDDEN = {"kind": "Status", "apiVersion": "v1", "status": "Failure", "reason": "Forbidden", "code": 403,
             "message": 'pods is forbidden: User "system:serviceaccount:jupyterhub:hub" cannot list resource "pods" in namespace "rogue"'}
REC = W / "recorded"
REC.mkdir(exist_ok=True)
USERS = {
    "researcher1": ["alpha"],
    "researcher2": ["beta"],
    "researcher3": ["alpha", "beta"],
    "researcher4": [],
    "tre-admin": ["tre-admins"],
    "researcher5": ["rogue"],
}
LOG = open(W / "fake-k8s.log", "a", buffering=1)


def match_selector(labels, selector):
    for part in filter(None, (selector or "").split(",")):
        k, _, v = part.partition("=")
        if labels.get(k) != v:
            return False
    return True


class K8s(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = dict(urllib.parse.parse_qsl(u.query))
        LOG.write(f"GET {self.path}\n")
        parts = u.path.strip("/").split("/")
        if "/namespaces/rogue/" in u.path:
            return self.send(403, FORBIDDEN)
        if u.path == "/api/v1/namespaces":
            items = [n for n in NAMESPACES if match_selector(n["metadata"]["labels"], q.get("labelSelector"))]
            return self.send(200, {"kind": "NamespaceList", "apiVersion": "v1",
                                   "metadata": {"resourceVersion": "1"}, "items": items})
        if q.get("watch") in ("true", "1"):
            # hold the watch open briefly, then end it with no events
            time.sleep(min(float(q.get("timeoutSeconds", 5)), 5))
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if parts[-1] in ("pods", "events"):
            return self.send(200, {"kind": "List", "apiVersion": "v1", "metadata": {"resourceVersion": "1"}, "items": []})
        # individual objects (PVC existence checks, pods) -> not found
        return self.send(404, {"kind": "Status", "apiVersion": "v1", "status": "Failure", "reason": "NotFound", "code": 404})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        LOG.write(f"POST {self.path}\n")
        if "/namespaces/rogue/" in self.path:
            return self.send(403, FORBIDDEN)
        ns = self.path.split("/")[4]
        kind = body["kind"]
        (REC / f"{kind}-{ns}-{body['metadata']['name']}.json").write_text(json.dumps(body, indent=1))
        body.setdefault("metadata", {})["namespace"] = ns
        return self.send(201, body)

    def do_DELETE(self):
        LOG.write(f"DELETE {self.path}\n")
        return self.send(200, {"kind": "Status", "apiVersion": "v1", "status": "Success"})

    do_PATCH = do_POST


class OAuth(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):  # token endpoint: the "code" is the username
        form = dict(urllib.parse.parse_qsl(self.rfile.read(int(self.headers["Content-Length"])).decode()))
        return self.send(200, {"access_token": "tok-" + form["code"], "token_type": "Bearer",
                               "id_token": "", "scope": "openid profile email"})

    def do_GET(self):  # userinfo
        user = self.headers.get("Authorization", "").split("tok-")[-1]
        return self.send(200, {"sub": user, "preferred_username": user, "groups": USERS[user]})


if __name__ == "__main__":
    k = ThreadingHTTPServer(("127.0.0.1", 6443), K8s)
    o = ThreadingHTTPServer(("127.0.0.1", 9000), OAuth)
    threading.Thread(target=o.serve_forever, daemon=True).start()
    print("fakes up", flush=True)
    k.serve_forever()
