# KID: project-aware workspaces for JupyterHub.
#
# Loaded by the hub via hub.extraConfig (see ../values.yaml), so `c` is the
# JupyterHub config object.
#
# How it works
# ------------
# 1. A *project* is a Kubernetes namespace labelled  k8tre.io/type=project.
#    Its annotations describe it (display name, image, workspace sizes). They
#    are written by the project Helm chart: gitops/projects/chart.
# 2. A user may use a project if they are in the Keycloak group of the same
#    name. OAuthenticator copies Keycloak groups into JupyterHub groups at login
#    (manage_groups = True).
# 3. When the user opens the spawn page, `project_profiles` lists the projects
#    they are a member of. Each profile tells KubeSpawner which namespace, image
#    and CPU/memory limits to use.
# 4. KubeSpawner calls `project_profiles` *again* when the server starts and
#    rejects any profile not in the list, so users can't start a workspace in
#    a project they don't belong to by crafting an API request.
#
# Nothing here is cached: add a namespace or change a user's groups and the
# next spawn picks it up without restarting the hub.

import json
import os

from tornado import web

PROJECT_SELECTOR = "k8tre.io/type=project"
HUB_NAMESPACE = os.environ.get("POD_NAMESPACE", "jupyterhub")


async def list_projects(spawner):
    """Return the research projects that exist in the cluster."""
    namespaces = await spawner.api.list_namespace(
        label_selector=PROJECT_SELECTOR,
        _request_timeout=spawner.k8s_api_request_timeout,
    )
    projects = []
    for ns in namespaces.items:
        if ns.status and ns.status.phase != "Active":
            continue  # being deleted
        labels = ns.metadata.labels or {}
        notes = ns.metadata.annotations or {}
        name = labels.get("k8tre.io/project")
        if not name:
            continue
        projects.append(
            {
                "name": name,
                "namespace": ns.metadata.name,
                "display_name": notes.get("k8tre.io/display-name", name),
                "description": notes.get("k8tre.io/description", ""),
                "image": notes.get("k8tre.io/image"),
                "sizes": json.loads(notes.get("k8tre.io/sizes") or "[]"),
            }
        )
    return sorted(projects, key=lambda p: p["name"])


def user_groups(spawner):
    return {group.name for group in spawner.user.groups}


def size_choices(sizes):
    """Turn the project's size list into KubeSpawner profile_options choices."""
    choices = {}
    for i, size in enumerate(sizes):
        choices[size["slug"]] = {
            "display_name": size.get("displayName", size["slug"]),
            "default": i == 0,
            "kubespawner_override": {
                "cpu_guarantee": float(size["cpuGuarantee"]),
                "cpu_limit": float(size["cpuLimit"]),
                "mem_guarantee": str(size["memGuarantee"]),
                "mem_limit": str(size["memLimit"]),
            },
        }
    return choices


async def project_profiles(spawner):
    """KubeSpawner profile_list: one profile per project the user belongs to."""
    groups = user_groups(spawner)
    profiles = []
    for project in await list_projects(spawner):
        if project["name"] not in groups:
            continue
        override = {
            # The key line: the workspace pod, its home PVC and its events
            # all live in the project's namespace.
            "namespace": project["namespace"],
            "extra_labels": {"k8tre.io/project": project["name"]},
            "environment": {"K8TRE_PROJECT": project["name"]},
        }
        if project["image"]:
            override["image"] = project["image"]
        profile = {
            "slug": project["name"],
            "display_name": project["display_name"],
            "description": project["description"],
            "kubespawner_override": override,
        }
        if project["sizes"]:
            profile["profile_options"] = {
                "size": {
                    "display_name": "Workspace size",
                    "choices": size_choices(project["sizes"]),
                }
            }
        profiles.append(profile)
    spawner.log.info(
        "User %s (groups %s) may use projects %s",
        spawner.user.name,
        sorted(groups),
        [p["slug"] for p in profiles],
    )
    return profiles


async def require_a_project(spawner):
    """pre_spawn_hook: refuse to start outside a project.

    Without this, a user with no project groups would fall back to the default
    namespace (the hub's own), which is exactly what a TRE must not allow.
    """
    profiles = await project_profiles(spawner)
    if not profiles:
        raise web.HTTPError(
            403,
            f"{spawner.user.name} is not a member of any research project. "
            "Ask a TRE administrator to add you to a project group in Keycloak.",
        )


NO_PROJECT_MESSAGE = (
    '<div class="alert alert-warning" role="alert">'
    "<strong>You are not a member of any research project.</strong> "
    "Ask a TRE administrator to add you to a project group in Keycloak, "
    "then log out and back in."
    "</div>"
)


async def spawn_form(spawner):
    """The spawn page: the project/size picker, or an explanation if the user
    has no projects (KubeSpawner would otherwise show an empty form)."""
    profiles = await project_profiles(spawner)
    if not profiles:
        return NO_PROJECT_MESSAGE
    return spawner._render_options_form(profiles)


c.KubeSpawner.profile_list = project_profiles
c.KubeSpawner.options_form = spawn_form
c.KubeSpawner.pre_spawn_hook = require_a_project

# Workspaces run in other namespaces, so they must reach the hub by its
# fully-qualified service name, not the short name "hub".
c.JupyterHub.hub_connect_url = f"http://hub.{HUB_NAMESPACE}.svc.cluster.local:8081"

# One workspace per user at a time keeps the demo within laptop memory.
c.JupyterHub.allow_named_servers = False
# Don't let users override spawner settings from their home directory.
c.Spawner.disable_user_config = True
c.Spawner.http_timeout = 120
