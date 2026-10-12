#!/bin/bash
# Builds DotWiz.app into ./build. Usage: ./build-app.sh [--install]
#   --install  also copies the app to /Applications
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/DotWiz"

APP="build/DotWiz.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DotWiz"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

# Register with Launch Services so Finder offers DotWiz for .dot/.gv files.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" || true

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/DotWiz.app
    cp -R "$APP" /Applications/
    echo "Installed /Applications/DotWiz.app"
else
    echo "Built $APP"
fi
