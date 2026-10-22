#!/bin/bash
# Installs what .claude/scripts/check-rules.rb needs to validate _data/rules.yml with promtool,
# mirroring .github/workflows/test.yml: the liquid gem (renders dist/template.yml) and promtool.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

PROM_VERSION="3.15.1"
# Go module version of the same Prometheus release (v3.X.Y is published as v0.3XX.Y).
PROM_MODULE_VERSION="v0.315.1"
LIQUID_VERSION="5.5.1"
BIN_DIR="/usr/local/bin"

if ! ruby -e "gem 'liquid', '${LIQUID_VERSION}'" 2>/dev/null; then
  gem install liquid -v "${LIQUID_VERSION}" --no-document
fi

if ! promtool --version 2>/dev/null | grep -q "version ${PROM_VERSION}"; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT
  url="https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
  if curl -fsSL --retry 2 -o "${tmp}/prometheus.tar.gz" "${url}"; then
    tar -xzf "${tmp}/prometheus.tar.gz" -C "${tmp}" --strip-components=1 "prometheus-${PROM_VERSION}.linux-amd64/promtool"
    install -m 0755 "${tmp}/promtool" "${BIN_DIR}/promtool"
  else
    # github.com is not in every environment's network allowlist; build from the Go module proxy instead (~3-4 min).
    echo "promtool release download failed, building ${PROM_MODULE_VERSION} from source" >&2
    src="$(go mod download -json "github.com/prometheus/prometheus@${PROM_MODULE_VERSION}" | jq -r .Dir)"
    (cd "${src}" && GOWORK=off GOFLAGS=-mod=mod go build \
      -ldflags "-X github.com/prometheus/common/version.Version=${PROM_VERSION}" \
      -o "${BIN_DIR}/promtool" ./cmd/promtool)
  fi
fi

promtool --version | head -1
