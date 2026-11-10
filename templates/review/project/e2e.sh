#!/usr/bin/env bash
#
# .review/e2e.sh — the end-to-end tests: the app driven the way its user drives
# it, one platform per call.
#
# THIS FILE BELONGS TO YOUR PROJECT, NOT TO THE SUBMODULE.
# Copied once from CodingStandards/templates/review/project/ into your repo's
# .review/, filled in, and committed by the user: land.sh refuses a run whose
# harness is not the committed one.
#
# Usage:   .review/e2e.sh <platform> <report-dir>
#          platform: android, ios or app — what e2e-gate.sh finds in the tree
# Writes:  JUnit XML of every end-to-end test of that platform into report-dir,
#          which is empty when it starts — this run's results, nowhere else
# Exit:    the exit code of the test command
#
# review.sh runs it through CodingStandards/templates/review/lib/e2e-gate.sh
# after the gates. That script counts the tests in the XML and never trusts the
# exit code alone — a test command with nothing to run exits 0. A platform
# passes only when a test ran on it, none failed, and every test a case of
# qa/test-cases.md names (e2e: `<test>`) passed on each platform that runs it.
# It must leave the working tree as it found it. A script it calls from
# .review/ is named .review/e2e-<name>.sh and committed with it.

set -uo pipefail

PLATFORM="$1"
REPORTS="$2"
mkdir -p "$REPORTS"

# The stub writes no XML, so it reads as "ran no test" and never passes.
echo "TODO: end-to-end tests of $PLATFORM" >&2
exit 1

# Examples (delete the stub above and keep what fits):
#
# Kotlin / KMP (modules composeApp and androidApp, iosApp/{App}.xcodeproj with a
# UI test target {App}UITests). Verify both report paths on the installed AGP
# and Xcode.
#
#   case "$PLATFORM" in
#     android)
#       # A booted device is reused; otherwise one boots, for at most 240 s.
#       if [ "$(adb get-state 2>/dev/null)" != device ]; then
#         emulator -avd "$E2E_AVD" -no-window -no-audio -no-boot-anim >/dev/null 2>&1 &
#         for _ in $(seq 120); do
#           [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
#           sleep 2
#         done
#       fi
#       rm -rf androidApp/build/outputs/androidTest-results
#       ./gradlew --console=plain :androidApp:connectedAndroidTest
#       status=$?
#       find androidApp/build/outputs/androidTest-results/connected -name '*.xml' \
#         -exec cp {} "$REPORTS" \;
#       exit "$status" ;;
#     ios)
#       udid="$(xcrun simctl list devices booted -j | jq -r '[.devices[][] | .udid][0] // empty')"
#       xcodebuild test -project iosApp/{App}.xcodeproj -scheme {App} \
#         -destination "id=$udid" -resultBundlePath "$REPORTS/r.xcresult"
#       status=$?
#       xcrun xcresulttool get test-results tests --path "$REPORTS/r.xcresult" | jq -r '
#         def cases($suite): if .nodeType == "Test Case" then {suite: $suite, name, result}
#           else ((if .nodeType == "Test Suite" then .name else $suite end) as $s
#                 | .children[]? | cases($s)) end;
#         "<testsuite hostname=\"ios\">",
#         ([.testNodes[] | cases("")][]
#          | "<testcase classname=\"\(.suite)\" name=\"\(.name)\">"
#            + (if .result == "Failed" then "<failure/>"
#               elif .result == "Skipped" then "<skipped/>" else "" end)
#            + "</testcase>"),
#         "</testsuite>"' >"$REPORTS/r.xml"
#       exit "$status" ;;
#   esac
#
# Other stacks — one platform, app:
#   pytest tests/e2e --junitxml="$REPORTS/r.xml"
#   gotestsum --junitfile "$REPORTS/r.xml" -- ./e2e/...
#   PLAYWRIGHT_JUNIT_OUTPUT_NAME="$REPORTS/r.xml" npx playwright test --reporter=junit
