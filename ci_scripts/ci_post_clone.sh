#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
fi
bash sync-lessons.sh
xcodegen generate --spec project.yml
