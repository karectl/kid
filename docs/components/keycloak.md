# Keycloak

[Keycloak](https://www.keycloak.org/) is the **identity provider**. JupyterHub delegates login to
it using OpenID Connect (OIDC), and it decides which **groups** a user is in. In KID, group
membership is how project membership works.

## Realm `tre`

Imported at start-up from `gitops/keycloak/realm-tre.json`:

* **Client `jupyterhub`**: confidential OIDC client with a `groups` protocol mapper
  (`oidc-group-membership-mapper`, `full.path: false`), so tokens and the userinfo endpoint
  carry `"groups": ["alpha", "beta"]`.
* **Groups**: `alpha`, `beta` (one per project) and `tre-admins`.
* **Users**: `researcher1`–`researcher4`, `tre-admin`. See [First steps](../getting-started/first-steps.md#the-demo-accounts).

## Consoles

* Admin console: **`/keycloak`** (redirects to `/auth/admin/master/console/`), login `admin`/`admin`.
  Switch to the **tre** realm with the realm selector at the top left.
* Account console for a user: `/auth/realms/tre/account/`.

## Adding a user to a project

1. Admin console → realm **tre** → **Users** → pick the user → **Groups** → **Join Group** → pick
   the project group.
2. The user must **log out of JupyterHub and back in** (groups are synced at login).
   Use **File → Log Out** in JupyterLab, or visit `/jupyter/hub/logout`.

## Dev mode caveats

Keycloak runs with `start-dev`: an embedded H2 database inside the container and no TLS.

!!! warning "Changes made in the admin console don't survive a Keycloak restart"
    When the Keycloak pod restarts, the database is recreated and the realm is re-imported from
    Git. That is handy for training (you can always get back to a clean state with
    `kubectl -n keycloak rollout restart deploy/keycloak`), but a real TRE uses an external
    PostgreSQL database and manages realms declaratively or through an operator.

## How JupyterHub uses it

```yaml
# gitops/jupyterhub/values.yaml (abridged)
GenericOAuthenticator:
  username_claim: preferred_username
  manage_groups: true
  auth_state_groups_key: oauth_user.groups
  admin_groups: [tre-admins]
```

The browser is sent to the **public** URL (`$PUBLIC_URL/auth/...`). The hub exchanges the code for
a token and fetches userinfo over the **cluster-internal** Service
(`keycloak.keycloak.svc.cluster.local`), which the hub's network policy allows on port 8080.
