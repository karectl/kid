"""Tests for gitops/jupyterhub/files/tre_config.py.

They load the config file the same way the hub does, then drive the real
KubeSpawner profile logic against a fake Kubernetes API.

    pip install -r tests/requirements.txt && pytest tests
"""

import asyncio
import functools
import json
import os
import tempfile
import types
from pathlib import Path

# KubeSpawner loads a kubeconfig when it starts, and kubernetes_asyncio reads
# $KUBECONFIG at import time, so give it a harmless one before importing.
_KUBECONFIG = Path(tempfile.mkdtemp()) / "kubeconfig"
_KUBECONFIG.write_text(
    "apiVersion: v1\nkind: Config\ncurrent-context: x\n"
    "clusters: [{name: x, cluster: {server: 'https://127.0.0.1:1'}}]\n"
    "contexts: [{name: x, context: {cluster: x, user: x}}]\n"
    "users: [{name: x, user: {token: t}}]\n"
)
os.environ["KUBECONFIG"] = str(_KUBECONFIG)

import pytest  # noqa: E402
from kubespawner import KubeSpawner  # noqa: E402
from tornado import web  # noqa: E402
from traitlets.config import Config  # noqa: E402

CONFIG_FILE = Path(__file__).parents[1] / "gitops/jupyterhub/files/tre_config.py"

SIZES = [
    {"slug": "small", "displayName": "Small", "cpuGuarantee": 0.1, "cpuLimit": 0.5,
     "memGuarantee": "256M", "memLimit": "1G"},
    {"slug": "medium", "displayName": "Medium", "cpuGuarantee": 0.25, "cpuLimit": 1,
     "memGuarantee": "512M", "memLimit": "2G"},
]


@pytest.fixture
def config():
    c = Config()
    exec(CONFIG_FILE.read_text(), {"c": c})
    return c


def namespace(name, project, phase="Active", sizes=SIZES):
    return types.SimpleNamespace(
        status=types.SimpleNamespace(phase=phase),
        metadata=types.SimpleNamespace(
            name=name,
            labels={"k8tre.io/type": "project", "k8tre.io/project": project},
            annotations={
                "k8tre.io/display-name": f"Project {project.title()}",
                "k8tre.io/image": "quay.io/jupyter/minimal-notebook:test",
                "k8tre.io/sizes": json.dumps(sizes),
            },
        ),
    )


class FakeCoreV1Api:
    async def list_namespace(self, label_selector, _request_timeout):
        assert label_selector == "k8tre.io/type=project"
        return types.SimpleNamespace(items=[
            namespace("project-beta", "beta"),
            namespace("project-alpha", "alpha", sizes=SIZES[:1]),
            namespace("project-old", "old", phase="Terminating"),
        ])


def spawner(config, groups, user_options=None):
    s = KubeSpawner(_mock=True, config=config)
    s.user.name = "researcher1"
    s.user.groups = [types.SimpleNamespace(name=g) for g in groups]
    s.api = FakeCoreV1Api()
    s.user_options = user_options or {}
    return s


def run_async(test):
    """KubeSpawner needs a running event loop, so run each test inside one."""
    @functools.wraps(test)
    def wrapper(*args, **kwargs):
        return asyncio.run(test(*args, **kwargs))
    return wrapper


@run_async
async def test_only_member_projects_are_offered(config):
    s = spawner(config, ["alpha"])
    profiles = await s.profile_list(s)
    assert [p["slug"] for p in profiles] == ["alpha"]


@run_async
async def test_terminating_projects_are_hidden(config):
    s = spawner(config, ["alpha", "beta", "old"])
    profiles = await s.profile_list(s)
    assert [p["slug"] for p in profiles] == ["alpha", "beta"]


@run_async
async def test_profile_sets_namespace_image_and_size(config):
    s = spawner(config, ["beta"], {"profile": "beta", "size": "medium"})
    await s.load_user_options()
    assert s.namespace == "project-beta"
    assert s.image == "quay.io/jupyter/minimal-notebook:test"
    assert s.cpu_limit == 1.0
    assert s.mem_limit == 2 * 1024**3
    assert s.extra_labels["k8tre.io/project"] == "beta"
    assert s.environment["K8TRE_PROJECT"] == "beta"


@run_async
async def test_default_is_first_project_and_first_size(config):
    s = spawner(config, ["alpha", "beta"])
    await s.load_user_options()
    assert s.namespace == "project-alpha"
    assert s.cpu_limit == 0.5


@run_async
async def test_cannot_request_a_project_you_are_not_in(config):
    s = spawner(config, ["alpha"], {"profile": "beta"})
    with pytest.raises(ValueError, match="No such profile"):
        await s.load_user_options()


@run_async
async def test_cannot_request_a_size_the_project_does_not_offer(config):
    s = spawner(config, ["alpha"], {"profile": "alpha", "size": "medium"})
    # KubeSpawner rejects the unknown choice (the exact exception varies).
    with pytest.raises((ValueError, KeyError)):
        await s.load_user_options()


@run_async
async def test_users_without_a_project_cannot_spawn(config):
    s = spawner(config, ["unrelated"])
    with pytest.raises(web.HTTPError) as err:
        await s.pre_spawn_hook(s)
    assert err.value.status_code == 403


@run_async
async def test_spawn_form_lists_only_member_projects(config):
    s = spawner(config, ["alpha"])
    form = await s._render_options_form_dynamically(s)
    assert "Project Alpha" in form
    assert "Project Beta" not in form


def test_workspaces_reach_hub_by_fqdn(config):
    assert config.JupyterHub.hub_connect_url == "http://hub.jupyterhub.svc.cluster.local:8081"
