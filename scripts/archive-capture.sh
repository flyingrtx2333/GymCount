#!/bin/zsh
set -e
cd "${0:A:h:h}"
xcodebuild -project GymCountCapture.xcodeproj -scheme 'GymCount Capture' \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /tmp/GymCountCapture-Companion-TestFlight.xcarchive \
  -allowProvisioningUpdates \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=GYMCOUNT_CAPTURE archive
