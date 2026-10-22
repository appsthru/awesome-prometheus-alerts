#!/bin/bash
# Installs what .claude/scripts/check_rules.py needs to validate _data/rules.yml with promtool,
# mirroring .github/workflows/test.yml: python-liquid (renders dist/template.yml) and promtool.
# Best effort: a failed install only prints a warning and never blocks the session.
set -uo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

PROM_VERSION="3.15.1"
# Go module version of the same Prometheus release (v3.X.Y is published as v0.3XX.Y).
PROM_MODULE_VERSION="v0.315.1"
PYTHON_LIQUID_VERSION="2.3.5"
BIN_DIR="/usr/local/bin"
# Upper bound for the from-source fallback, so a slow or broken build cannot hold the session.
BUILD_TIMEOUT="300"

install_python_deps() {
  python3 -c "import liquid, yaml, sys; sys.exit(liquid.__version__ != '${PYTHON_LIQUID_VERSION}')" 2>/dev/null && return 0
  pip3 install --quiet --root-user-action=ignore "python-liquid==${PYTHON_LIQUID_VERSION}" pyyaml ||
    pip3 install --quiet --root-user-action=ignore --break-system-packages "python-liquid==${PYTHON_LIQUID_VERSION}" pyyaml
}

install_promtool() {
  promtool --version 2>/dev/null | grep -q "version ${PROM_VERSION}" && return 0
  local tmp url src
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN
  url="https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
  if curl -fsSL --retry 2 --max-time 60 -o "${tmp}/prometheus.tar.gz" "${url}"; then
    tar -xzf "${tmp}/prometheus.tar.gz" -C "${tmp}" --strip-components=1 "prometheus-${PROM_VERSION}.linux-amd64/promtool" &&
      install -m 0755 "${tmp}/promtool" "${BIN_DIR}/promtool"
    return
  fi
  # github.com is not in every environment's network allowlist; build from the Go module proxy instead (~3-4 min).
  echo "promtool release download failed, building ${PROM_MODULE_VERSION} from source" >&2
  command -v go >/dev/null || return 1
  src="$(go mod download -json "github.com/prometheus/prometheus@${PROM_MODULE_VERSION}" | jq -r .Dir)" || return 1
  (cd "${src}" && GOWORK=off GOFLAGS=-mod=mod timeout "${BUILD_TIMEOUT}" go build \
    -ldflags "-X github.com/prometheus/common/version.Version=${PROM_VERSION}" \
    -o "${BIN_DIR}/promtool" ./cmd/promtool)
}

install_python_deps || echo "WARNING: python-liquid not installed; check_rules.py cannot render the rules." >&2
if install_promtool; then
  promtool --version | head -1
else
  echo "WARNING: promtool not installed; check_rules.py will skip the promtool step." >&2
fi
exit 0
