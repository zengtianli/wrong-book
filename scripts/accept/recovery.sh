#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

accept_scope 'Recovery: production catalog retry/cancellation, subscription error recovery and stale-response isolation, HTTP error decoding. Injected local faults; no StoreKit transactions or device end-to-end claim.'
accept_swift recovery \
  Sources/Api.swift Sources/AccountDeletion.swift Sources/PaperRequestSession.swift \
  Sources/SubscriptionCatalog.swift Sources/AISubscription.swift Tests/RecoveryAcceptance.swift
accept_swift recovery-http \
  Sources/Api.swift Sources/AccountDeletion.swift Sources/PaperRequestSession.swift \
  Tests/ApiRegression.swift
