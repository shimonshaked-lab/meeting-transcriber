#!/usr/bin/env bash
# Builds and runs the app's unit tests on macOS and on iPhone + iPad simulators.
# Continues through all platforms and fails at the end if any failed.
set -uo pipefail
mkdir -p results

sim() {
  xcrun simctl list devices available -j | jq -r --arg p "^$1" \
    '[.devices | to_entries[] | select(.key | test("iOS")) | .value[] | select(.name | test($p))] | last | .udid'
}

overall=0
host_major=$(sw_vers -productVersion | cut -d. -f1)
for platform in ${PLATFORMS:-macOS iPhone iPad}; do
  action=test
  if [ "$platform" = macOS ]; then
    dest="platform=macOS"
    # The app targets macOS 26; on an older runner we can compile but not run the tests.
    if [ "$host_major" -lt 26 ]; then
      action=build-for-testing
      echo "::warning::Runner is macOS $(sw_vers -productVersion): compiling the Mac app and tests only, not running them."
    fi
  else
    udid=$(sim "$platform")
    if [ -z "$udid" ] || [ "$udid" = null ]; then echo "::error::No $platform simulator found"; overall=1; continue; fi
    dest="id=$udid"
  fi
  echo "::group::$platform ($dest)"
  status=0
  xcodebuild "$action" \
    -project MeetingTranscriber.xcodeproj \
    -scheme MeetingTranscriber \
    -destination "$dest" \
    $( [ "$action" = test ] && echo -resultBundlePath "results/$platform.xcresult" ) \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    < /dev/null > "results/$platform.log" 2>&1 || status=$?
  echo "xcodebuild exit status for $platform: $status"
  grep -v "CoreData: error" "results/$platform.log" \
    | grep -E "error:|Test Case .*(passed|failed)|Executed|\*\* |XCTAssert" || true
  echo "--- last 25 lines ---"
  grep -v "CoreData: error" "results/$platform.log" | tail -n 25 || true
  echo "::endgroup::"
  if [ "$status" -ne 0 ]; then
    echo "::error::$platform failed (exit $status)"
    grep -v "CoreData: error" "results/$platform.log" | grep -E "error:" | sort -u | head -40 | sed 's/^/::error::/' || true
    overall=1
  else
    echo "✅ $platform passed ($action)"
  fi
done
exit "$overall"
