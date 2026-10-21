#!/usr/bin/env bash
set -euo pipefail
CAPSULE_ROOT="$(cd "$(dirname "$0")" && pwd)"
CHECKOUT_ROOT="${1:?Pass the prepared NOOP checkout}"
cd "$CHECKOUT_ROOT"
command -v xcodebuild >/dev/null || { echo 'Xcode on macOS is required.' >&2; exit 2; }
xcodegen generate --spec project.personal.generated.yml
xcodebuild -project Strand.xcodeproj -scheme NOOPiOS -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/personal-device \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
APP_PATH="build/personal-device/Build/Products/Release-iphoneos/NOOP Staging.app"
test -d "$APP_PATH"
# Follow upstream's SideStore packaging; retain the widget/Live Activity extension.
rm -rf "$APP_PATH/Watch"
python3 "$CAPSULE_ROOT/package.py" --checkout "$PWD" --prepare "$APP_PATH"
Tools/prepare-ios-sideload-app.sh "$APP_PATH"
python3 "$CAPSULE_ROOT/package.py" --checkout "$PWD" --package "$APP_PATH"
