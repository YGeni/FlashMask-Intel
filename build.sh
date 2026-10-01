#!/bin/sh
# Flash Mask universal (arm64 + x86_64) build script.
#
# Usage:
#   ./build.sh                          Unsigned local build (for testing)
#   ./build.sh --team <TEAMID>          Signed build with your own team
#   ./build.sh --team <TEAMID> --bundle-id com.yourname.flashmask
#   ./build.sh --dmg                    Also produce a DMG installer
#
# Examples:
#   ./build.sh
#   ./build.sh --team AB12CD34EF --bundle-id com.example.flashmask --dmg
set -e

PROJECT='macos/Flash Mask.xcodeproj'
SCHEME='Flash Mask'
CONFIGURATION='Release'
DERIVED='.derivedData/build'
TEAM=''
BUNDLE_ID=''
MAKE_DMG=0

while [ $# -gt 0 ]; do
  case "$1" in
    --team)     TEAM="$2"; shift 2 ;;
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    --dmg)      MAKE_DMG=1; shift ;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
done

OVERRIDES="ONLY_ACTIVE_ARCH=NO"
SIGNED=0
if [ -n "$TEAM" ]; then
  OVERRIDES="$OVERRIDES DEVELOPMENT_TEAM=$TEAM"
  SIGNED=1
  if [ -n "$BUNDLE_ID" ]; then
    OVERRIDES="$OVERRIDES PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID"
  fi
elif [ -n "$BUNDLE_ID" ]; then
  OVERRIDES="$OVERRIDES PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID CODE_SIGNING_ALLOWED=NO"
fi
if [ "$SIGNED" -eq 0 ]; then
  OVERRIDES="$OVERRIDES CODE_SIGNING_ALLOWED=NO"
fi

echo "==> Building universal (arm64 + x86_64) ${CONFIGURATION}..."
set -- xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  $OVERRIDES \
  build

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" "$@"
# Filter noise but keep errors visible.
APP="$DERIVED/Build/Products/$CONFIGURATION/Flash Mask.app"

echo
echo "==> App: $APP"
if codesign -dv "$APP" >/dev/null 2>&1; then
  echo "==> Signing status: SIGNED"
  codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier|Identifier=' || true
else
  echo "==> Signing status: UNSIGNED (local testing only; Gatekeeper will block it on other Macs)"
fi
file "$APP/Contents/MacOS/FlashMask" | sed 's/^==> //' || true

if [ "$MAKE_DMG" -eq 1 ]; then
  DMG_NAME='FlashMask-Universal.dmg'
  echo
  echo "==> Creating $DMG_NAME..."
  rm -rf .dmgroot "$DMG_NAME"
  mkdir -p .dmgroot
  cp -R "$APP" '.dmgroot/Flash Mask.app'
  ln -sfn /Applications .dmgroot/Applications
  hdiutil create -volname 'Flash Mask' -srcfolder .dmgroot -ov -format UDZO "$DMG_NAME" >/dev/null
  echo "==> DMG: $(pwd)/$DMG_NAME"
  if [ "$SIGNED" -eq 1 ]; then
    echo "==> NOTE: for distribution, notarize the app and rebuild the DMG:"
    echo "      ditto -c -k --keepParent '$APP' FlashMask.zip"
    echo "      xcrun notarytool submit FlashMask.zip --keychain-profile <profile> --wait"
    echo "      xcrun stapler staple '$APP'"
    echo "      ./$0 --team $TEAM${BUNDLE_ID:+ --bundle-id $BUNDLE_ID} --dmg"
  fi
fi
