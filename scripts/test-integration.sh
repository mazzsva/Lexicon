#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"

destination="${DESTINATION:-platform=iOS Simulator,name=iPhone 18 Pro}"
command=(
    env TEST_RUNNER_FIREBASE_EMULATORS=1
    xcodebuild test
    -scheme Lexicon
    -destination "$destination"
    -only-testing:LexiconTests/BaseSuite/IntegrationSuite
    -collect-test-diagnostics never
    "$@"
)

firebase emulators:exec --project demo-overhead --only auth,firestore "${(j: :)${(q)command[@]}}"
