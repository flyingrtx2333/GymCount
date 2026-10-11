#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
release_version="${GYMCOUNT_RELEASE_VERSION:-1.1.3}"
release_build="${GYMCOUNT_RELEASE_BUILD:-26}"
release_dir="$PWD/build/TestFlight-$release_version-$release_build"
mkdir -p "$release_dir"
case "${1:-archive}" in
  archive)
    rtk proxy xcodebuild archive -project GymCountSync.xcodeproj -scheme 'GymCount Capture' \
      -configuration Release -destination 'generic/platform=iOS' \
      -archivePath "$release_dir/GymCount.xcarchive" -allowProvisioningUpdates \
      > "$release_dir/archive.log" 2>&1
    ;;
  export)
    rtk proxy xcodebuild -exportArchive -archivePath "$release_dir/GymCount.xcarchive" \
      -exportPath "$release_dir/export" -exportOptionsPlist "$release_dir/ExportOptions.plist" \
      -allowProvisioningUpdates > "$release_dir/export.log" 2>&1
    ;;
  upload)
    source "$HOME/.appstoreconnect/assettimemachine.env"
    rtk proxy xcrun altool --upload-app --type ios --file "$release_dir/export/GymCount.ipa" \
      --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" > "$release_dir/upload.log" 2>&1
    ;;
  status)
    source "$HOME/.appstoreconnect/assettimemachine.env"
    rtk proxy xcrun altool --build-status --delivery-id "$2" \
      --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
    ;;
  *) exit 2 ;;
esac
