#!/usr/bin/env bash
# End-to-end test of the JupyterHub layer without a Kubernetes cluster.
#
# Runs the real hub (Z2JH 4.0.0 config + gitops/jupyterhub values +
# tre_config.py) behind the real configurable-http-proxy, with a mock Keycloak
# and a fake Kubernetes API that records what KubeSpawner creates. The
# recorded Pod/PVC are then checked against kubeconform and the Kyverno
# policies (plus Pod Security "baseline").
#
# Needs: python deps from tests/requirements.txt (+ pycurl), kustomize, helm,
# node/npm (configurable-http-proxy), and optionally kubeconform + kyverno.
#   tests/e2e/run.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
W="${HERE}/.work"
PY="${PYTHON:-python3}"

python_bin="$(command -v "${PY}")"
"${PY}" "${HERE}/prepare.py"

CHP="$(command -v configurable-http-proxy || true)"
if [ -z "${CHP}" ]; then
  npm install --silent --prefix "${W}/chp" configurable-http-proxy@4 >/dev/null
  CHP="${W}/chp/node_modules/.bin/configurable-http-proxy"
fi

pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

cd "${W}"
"${python_bin}" "${HERE}/fakes.py" > "${W}/fakes.out" 2>&1 & pids+=($!)
# shellcheck disable=SC1091
source "${W}/hub.env"
"${CHP}" --ip=127.0.0.1 --api-ip=127.0.0.1 --api-port=8001 --port=8000 \
  --default-target=http://127.0.0.1:8081 --error-target=http://127.0.0.1:8081/hub/error \
  > "${W}/chp.out" 2>&1 & pids+=($!)
# The hub starts the idle culler with "python3"; make sure it's ours.
PATH="$(dirname "${python_bin}"):${PATH}" "${python_bin}" -m jupyterhub \
  --config "${W}/jupyterhub_config.py" > "${W}/hub.out" 2>&1 & pids+=($!)

for _ in $(seq 60); do
  curl -sf --noproxy '*' http://127.0.0.1:8000/jupyter/hub/health >/dev/null && break
  sleep 1
done
curl -sf --noproxy '*' http://127.0.0.1:8000/jupyter/hub/health >/dev/null \
  || { echo "hub did not start"; tail -50 "${W}/hub.out"; exit 1; }

status=0
KID_E2E=1 "${PY}" -m pytest -v -p no:cacheprovider "${HERE}/test_e2e.py" || status=$?

# Check what KubeSpawner actually asked Kubernetes to create.
"${PY}" - "${W}" <<'PY'
import glob, json, sys, yaml
w = sys.argv[1]
objs = []
for f in glob.glob(f"{w}/recorded/*.json"):
    d = json.load(open(f))
    d["metadata"]["namespace"] = "project-" + f.split("-project-")[1].split("-")[0]
    objs.append(d)
yaml.safe_dump_all(objs, open(f"{w}/spawned.yaml", "w"))
print(f"recorded {len(objs)} objects from KubeSpawner")
PY
if command -v kubeconform >/dev/null; then
  kubeconform -strict -summary -kubernetes-version 1.31.5 "${W}/spawned.yaml" || status=1
fi
if command -v kyverno >/dev/null; then
  out="$(kyverno apply "${REPO}"/gitops/kyverno/{restrict-image-registries,disallow-privileged,require-project-label,disallow-latest-tag}.yaml \
      "${HERE}/pss-baseline.yaml" --resource "${W}/spawned.yaml" --values-file "${HERE}/kyverno-values.yaml" 2>&1)"
  echo "${out}" | tail -3
  echo "${out}" | grep -q "fail: 0, warn: 0, error: 0" || { echo "spawned workspace violates policy"; status=1; }
fi

[ "${status}" -eq 0 ] && echo "E2E PASSED" || { echo "E2E FAILED"; tail -40 "${W}/hub.out"; }
exit "${status}"
