#!/usr/bin/env bash
# Bootstraps the KID (K8TRE in Docker) training cluster.
#
# Runs once when the dev container is created (postCreateCommand) and is safe
# to re-run by hand:  bash .devcontainer/bootstrap.sh
#
# Order of operations
#   1. kubeconfig for the k3s-server container
#   2. Cilium (CNI + network policy) with Hubble (flow observability)
#   3. Argo CD (GitOps engine), trimmed to save memory
#   4. Public URL detection (Codespaces vs. local) -> cluster-domain ConfigMaps
#   5. Git repo/branch detection -> Argo CD root "app of apps"
#   Everything else (Keycloak, JupyterHub, Kyverno, projects, policies) is
#   deployed by Argo CD from the gitops/ folder of *this* repository.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
source "${HERE}/versions.env"

say()  { printf '\n\033[1;34m=== %s ===\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }

# ---------------------------------------------------------------------------
say "Connecting to the k3s API server"
mkdir -p "${HOME}/.kube"
until [ -f /kubeconfig/kubeconfig.yaml ]; do sleep 2; done
sed 's|127\.0\.0\.1|k3s-server|g' /kubeconfig/kubeconfig.yaml > "${HOME}/.kube/config"
chmod 600 "${HOME}/.kube/config"
export KUBECONFIG="${HOME}/.kube/config"
grep -q 'KUBECONFIG=' "${HOME}/.bashrc" 2>/dev/null \
  || echo "export KUBECONFIG=${HOME}/.kube/config" >> "${HOME}/.bashrc"

until kubectl version >/dev/null 2>&1; do sleep 2; done
kubectl get nodes

# ---------------------------------------------------------------------------
say "Installing Cilium ${CILIUM_VERSION} with Hubble"
CILIUM_FLAGS=(
  --version "${CILIUM_VERSION}"
  --set operator.replicas=1
  --set kubeProxyReplacement=false
  --set ipam.operator.clusterPoolIPv4PodCIDRList='{10.42.0.0/16}'
  # Hubble: flow logs (relay) + web UI served under /hubble/ by Traefik
  --set hubble.enabled=true
  --set hubble.relay.enabled=true
  --set hubble.ui.enabled=true
  --set hubble.ui.baseUrl=/hubble/
)
if ! kubectl -n kube-system get daemonset cilium >/dev/null 2>&1; then
  cilium install "${CILIUM_FLAGS[@]}"
elif ! kubectl -n kube-system get deploy hubble-relay >/dev/null 2>&1; then
  # Cluster created by an older version of this script: add Hubble in place.
  cilium upgrade "${CILIUM_FLAGS[@]}"
fi

say "Waiting for Cilium"
cilium status --wait --wait-duration 5m
kubectl wait --for=condition=Ready node --all --timeout=300s

say "Waiting for Traefik (k3s bundled ingress controller)"
until kubectl -n kube-system get deploy/traefik >/dev/null 2>&1; do sleep 2; done
kubectl -n kube-system rollout status deploy/traefik --timeout=300s

# ---------------------------------------------------------------------------
say "Installing Argo CD ${ARGOCD_VERSION}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd apply --server-side --force-conflicts -f \
  "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

# Serve the UI under /argocd over plain HTTP (TLS terminates at the Codespaces
# proxy), let Kustomize inflate Helm charts, and poll Git every 60s so lab
# changes show up quickly.
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge -p \
  '{"data":{"server.insecure":"true","server.rootpath":"/argocd"}}'
kubectl -n argocd patch configmap argocd-cm --type merge -p \
  '{"data":{"kustomize.buildOptions":"--enable-helm","timeout.reconciliation":"60s"}}'

# Components the demo does not use: scale to zero to save ~150 MB of RAM.
for d in argocd-dex-server argocd-notifications-controller argocd-applicationset-controller; do
  kubectl -n argocd scale deploy "${d}" --replicas=0 >/dev/null 2>&1 || true
done

kubectl -n argocd rollout restart deploy argocd-server argocd-repo-server
kubectl -n argocd rollout status deploy argocd-server --timeout=300s
kubectl -n argocd rollout status deploy argocd-repo-server --timeout=300s

kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd
  namespace: argocd
spec:
  ingressClassName: traefik
  rules:
    - http:
        paths:
          - path: /argocd
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
EOF

# ---------------------------------------------------------------------------
say "Working out the public URL"
# Codespaces publishes forwarded ports on https://<codespace>-<port>.<domain>.
# Locally the k3s container publishes port ${TRE_HTTP_PORT:-80} on localhost.
if [ -z "${PUBLIC_URL:-}" ]; then
  if [ -n "${CODESPACE_NAME:-}" ] && [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; then
    PUBLIC_URL="https://${CODESPACE_NAME}-80.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
  elif [ "${TRE_HTTP_PORT:-80}" = "80" ]; then
    PUBLIC_URL="http://localhost"
  else
    PUBLIC_URL="http://localhost:${TRE_HTTP_PORT}"
  fi
fi
PUBLIC_URL="${PUBLIC_URL%/}"
DOMAIN="${PUBLIC_URL#*://}"

for ns in keycloak jupyterhub; do
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "${ns}" create configmap cluster-domain \
    --from-literal=DOMAIN="${DOMAIN}" \
    --from-literal=PUBLIC_URL="${PUBLIC_URL}" \
    --dry-run=client -o yaml | kubectl apply -f -
done
echo "PUBLIC_URL=${PUBLIC_URL}"

# ---------------------------------------------------------------------------
say "Working out which Git repository Argo CD should follow"
git config --global --add safe.directory "${ROOT}" 2>/dev/null || true

if [ -z "${KID_GITOPS_REPO:-}" ]; then
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    KID_GITOPS_REPO="https://github.com/${GITHUB_REPOSITORY}.git"
  else
    KID_GITOPS_REPO="$(git -C "${ROOT}" remote get-url origin 2>/dev/null || true)"
    # git@github.com:owner/repo.git -> https://github.com/owner/repo.git
    KID_GITOPS_REPO="$(echo "${KID_GITOPS_REPO}" | sed -E 's#^git@([^:]+):#https://\1/#')"
    KID_GITOPS_REPO="${KID_GITOPS_REPO:-https://github.com/karectl/kid.git}"
  fi
fi
case "${KID_GITOPS_REPO}" in *.git) ;; *) KID_GITOPS_REPO="${KID_GITOPS_REPO}.git" ;; esac

if [ -z "${KID_GITOPS_REVISION:-}" ]; then
  KID_GITOPS_REVISION="$(git -C "${ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
  [ "${KID_GITOPS_REVISION}" = "HEAD" ] && KID_GITOPS_REVISION="$(git -C "${ROOT}" rev-parse HEAD)"
fi

if ! git ls-remote --exit-code "${KID_GITOPS_REPO}" "${KID_GITOPS_REVISION}" >/dev/null 2>&1 \
   && ! git ls-remote "${KID_GITOPS_REPO}" 2>/dev/null | grep -q "^${KID_GITOPS_REVISION}"; then
  warn "'${KID_GITOPS_REVISION}' was not found in ${KID_GITOPS_REPO}."
  warn "Argo CD reads from GitHub, not from your disk: push the branch, or set"
  warn "KID_GITOPS_REPO / KID_GITOPS_REVISION and re-run this script."
fi

export KID_GITOPS_REPO KID_GITOPS_REVISION
export KID_ENABLE_KYVERNO="${KID_ENABLE_KYVERNO:-true}"
echo "repo:     ${KID_GITOPS_REPO}"
echo "revision: ${KID_GITOPS_REVISION}"
echo "kyverno:  ${KID_ENABLE_KYVERNO}"

say "Applying the Argo CD root application"
envsubst '${KID_GITOPS_REPO} ${KID_GITOPS_REVISION} ${KID_ENABLE_KYVERNO}' \
  < "${ROOT}/gitops/root-app.yaml" | kubectl apply -f -

# ---------------------------------------------------------------------------
if [ -S /var/run/docker.sock ]; then
  SOCK_GID="$(stat -c '%g' /var/run/docker.sock)"
  if ! getent group "${SOCK_GID}" >/dev/null 2>&1; then
    if getent group docker >/dev/null 2>&1; then
      sudo groupmod -g "${SOCK_GID}" docker
    else
      sudo groupadd -g "${SOCK_GID}" docker
    fi
  fi
  GROUP_NAME="$(getent group "${SOCK_GID}" | cut -d: -f1)"
  if ! id -nG "$(id -un)" | tr ' ' '\n' | grep -qx "${GROUP_NAME}"; then
    sudo usermod -aG "${GROUP_NAME}" "$(id -un)"
  fi
  echo "$(id -un) is in group ${GROUP_NAME} (gid ${SOCK_GID}) for docker.sock access"
else
  warn "/var/run/docker.sock not present - 'docker exec' into k3s-server will not work"
fi

say "Bootstrap complete - Argo CD is now deploying the TRE (allow 5-10 minutes)"
"${ROOT}/scripts/tre" info || true
echo
echo "Run 'tre status' to watch progress."
