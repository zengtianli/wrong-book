#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

accept_scope 'Local lesson file → production question index → stable review identifiers; production import subject options.'
accept_swift functionality Sources/QuestionIndex.swift Tests/FunctionalityAcceptance.swift
accept_swift import-subjects Sources/ImportSubjectOptions.swift Tests/ImportSubjectRegression.swift
