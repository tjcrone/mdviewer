#!/bin/bash
# Build MDViewer.app. Usage:
#   ./build.sh            build into build/MDViewer.app
#   ./build.sh install    build and copy to /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP=build/MDViewer.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O Sources/main.swift -o "$APP/Contents/MacOS/MDViewer"

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/* "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign - "$APP"

echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    rm -rf /Applications/MDViewer.app
    cp -R "$APP" /Applications/
    # Tell LaunchServices about it right away.
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f /Applications/MDViewer.app
    echo "Installed to /Applications/MDViewer.app"
fi
