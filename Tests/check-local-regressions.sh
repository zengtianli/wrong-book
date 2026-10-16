#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 Tests/demo_fixture_test.py
python3 Tests/media_record_test.py
"$HOME/Dev/.venv/bin/python" -m pytest -n auto -q Tests/account_native_test.py
scratch="$(mktemp -d /tmp/wrongbook-sop.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
xcrun --sdk macosx swiftc Sources/ImportSubjectOptions.swift Tests/ImportSubjectRegression.swift -o "$scratch/subject"
"$scratch/subject"
xcrun --sdk macosx swiftc Shared/RemoteUI.swift Sources/Api.swift Sources/AccountDeletion.swift \
  Sources/PaperRequestSession.swift Tests/PaperSessionRegression.swift -o "$scratch/paper"
"$scratch/paper"
xcrun --sdk macosx swiftc -target "$(uname -m)-apple-macos15.0" \
  Shared/RemoteUI.swift Sources/Api.swift Sources/AccountDeletion.swift Sources/PaperRequestSession.swift \
  Sources/Session.swift Tests/SessionIdentityRegression.swift -o "$scratch/identity"
"$scratch/identity"
xcrun --sdk macosx swiftc Shared/RemoteUI.swift Sources/Api.swift Sources/AccountDeletion.swift \
  Sources/PaperRequestSession.swift Tests/AccountRegression.swift -o "$scratch/account"
"$scratch/account"
