#!/bin/sh
# Sign and open Phantom.app (required after every build due to Sparkle Team ID mismatch).
# Strip xattrs first to prevent codesign failures on subsequent runs.
APP="$(dirname "$0")/build/Release/Phantom.app"
xattr -cr "$APP" 2>/dev/null
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"

xattr -cr "$APP"
codesign --force --sign - "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign - "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign - "$SPARKLE/Versions/B/Autoupdate"
codesign --force --sign - "$SPARKLE/Versions/B/Sparkle"
codesign --force --sign - "$SPARKLE"
codesign --force --sign - "$APP"
open "$APP"
