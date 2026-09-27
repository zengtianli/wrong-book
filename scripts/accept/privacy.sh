#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# Existing fixtures intercept every HTTP request and use only synthetic .invalid
# cookies. Their library/archive stand-ins never read the user's real cache.
# The additional persistence seam prevents even standard UserDefaults access.
accept_swift privacy-import Sources/Api.swift Sources/AccountDeletion.swift \
  Sources/PaperRequestSession.swift Tests/PrivacyAcceptance.swift \
  Tests/PaperSessionRegression.swift
accept_swift privacy-identity Sources/Api.swift Sources/AccountDeletion.swift \
  Sources/PaperRequestSession.swift Sources/Session.swift \
  Tests/PrivacyAcceptance.swift Tests/SessionIdentityRegression.swift

accept_scope 'Privacy: bound import cookies; old scope/login/endpoint rejected before transport; stale account/deletion responses rejected; guest refresh sends no request; auth operations serialize. Preferences are in-memory; library storage is a test stand-in. Physical-device permissions, live deletion, server retention and AI consent UI are outside this check.'
