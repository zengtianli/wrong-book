#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch="$(mktemp -d /tmp/wrongbook-sop.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
xcrun --sdk macosx swiftc Sources/ImportSubjectOptions.swift Tests/ImportSubjectRegression.swift -o "$scratch/subject"
"$scratch/subject"
xcrun --sdk macosx swiftc Sources/Api.swift Sources/AccountDeletion.swift \
  Sources/PaperRequestSession.swift Tests/PaperSessionRegression.swift -o "$scratch/paper"
"$scratch/paper"
xcrun --sdk macosx swiftc -target "$(uname -m)-apple-macos15.0" \
  Sources/Api.swift Sources/AccountDeletion.swift Sources/PaperRequestSession.swift \
  Sources/Session.swift Tests/SessionIdentityRegression.swift -o "$scratch/identity"
"$scratch/identity"
