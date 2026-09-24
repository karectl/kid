#!/usr/bin/env bash
# Static checks for everything Argo CD would deploy. Runs in CI
# (.github/workflows/validate.yml) and locally if helm, kustomize,
# kubeconform and python3 (with PyYAML) are on the PATH.
#
#   scripts/validate.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
VALUES="$(mktemp -d)"
trap 'rm -rf "${OUT}" "${VALUES}"' EXIT
cd "${ROOT}"

step() { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }

step "Shell scripts"
if command -v shellcheck >/dev/null; then
  shellcheck -S warning .devcontainer/bootstrap.sh scripts/tre scripts/validate.sh tests/e2e/run.sh
else
  echo "shellcheck not installed - skipped"
fi

step "JSON"
python3 -m json.tool .devcontainer/devcontainer.json >/dev/null
python3 -m json.tool gitops/keycloak/realm-tre.json >/dev/null
echo ok

step "Helm charts"
helm lint gitops/apps gitops/projects/chart
helm template root gitops/apps \
  --set repoURL=https://github.com/example/kid.git --set revision=main \
  > "${OUT}/apps.yaml"

# Render the project chart once per project, with the values Argo CD would pass.
python3 - "${OUT}" "${VALUES}" <<'PY'
import sys, yaml
out, values = sys.argv[1], sys.argv[2]
for doc in yaml.safe_load_all(open(f"{out}/apps.yaml")):
    if doc and doc["metadata"]["name"].startswith("project-"):
        vals = doc["spec"]["source"]["helm"]["valuesObject"]
        yaml.safe_dump(vals, open(f"{values}/{doc['metadata']['name']}.yaml", "w"))
PY
for values in "${VALUES}"/project-*.yaml; do
  name="$(basename "${values}" .yaml)"
  helm template "${name}" gitops/projects/chart -f "${values}" > "${OUT}/${name}.yaml"
  echo "rendered ${name}"
done
# Also exercise the optional internet allow-list template.
helm template allowlist gitops/projects/chart --set name=test \
  --set 'internetAllowlist={pypi.org,*.pythonhosted.org}' > "${OUT}/project-allowlist.yaml"

step "Kustomize"
for dir in platform keycloak portal kyverno jupyterhub; do
  kustomize build --enable-helm "gitops/${dir}" > "${OUT}/kustomize-${dir}.yaml"
  echo "built gitops/${dir}"
done
cp gitops/network-policies/*.yaml "${OUT}/"

step "Root app template"
KID_GITOPS_REPO=https://github.com/example/kid.git KID_GITOPS_REVISION=main KID_ENABLE_KYVERNO=true \
  envsubst '${KID_GITOPS_REPO} ${KID_GITOPS_REVISION} ${KID_ENABLE_KYVERNO}' \
  < gitops/root-app.yaml > "${OUT}/root-app.yaml"
grep -q '\${' "${OUT}/root-app.yaml" && { echo "unsubstituted variable in root-app.yaml"; exit 1; }
echo ok

step "Schemas (kubeconform)"
kubeconform -strict -summary -kubernetes-version 1.31.5 \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  "${OUT}"/*.yaml
