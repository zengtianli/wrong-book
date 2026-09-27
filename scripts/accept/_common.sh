#!/bin/bash
# Shared, non-interactive acceptance runner. Never launches the GUI or contacts a service.
set -euo pipefail
ACCEPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ACCEPT_ROOT"
ACCEPT_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/wrongbook-accept.XXXXXX")"
trap 'rm -rf "$ACCEPT_SCRATCH"' EXIT

accept_swift() {
  local name="$1"
  shift
  xcrun --sdk macosx swiftc -target "$(uname -m)-apple-macos15.0" \
    "$@" -o "$ACCEPT_SCRATCH/$name"
  "$ACCEPT_SCRATCH/$name"
}

accept_scope() {
  printf '%s\n' "Scope: $*" \
    'Production Swift code in an isolated local harness; no device UI, live AI, account or purchase validation.'
}
