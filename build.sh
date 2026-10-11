#!/bin/bash
# Compile Tiroflan, assemble l'app (Tiroflan.app) et l'installe dans /Applications.
#
# Exemple d'appel :
#   ./build.sh            # compile, installe et relance
#   ./build.sh --no-install   # compile seulement (build/Tiroflan.app)
set -euo pipefail
cd "$(dirname "$0")"

# Compilation directe avec swiftc (le SwiftPM des Command Line Tools de ce Mac est cassé).
mkdir -p .build
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 -sdk "$(xcrun --show-sdk-path)" \
  -module-name Tiroflan Sources/Tiroflan/*.swift Sources/Tiroflan/Views/*.swift -o .build/Tiroflan

APP="build/Tiroflan.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
cp .build/Tiroflan "$APP/Contents/MacOS/Tiroflan"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Fonts/*.ttf Resources/Fonts/OFL.txt "$APP/Contents/Resources/Fonts/"
# Icône (le flan) : régénérer avec Resources/Icon/make_icon.swift si les SVG changent.
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Signature : certificat « Tiroflan Local Signing » s'il existe (créé dans Trousseaux d'accès),
# identité stable donc macOS garde l'accès à l'agenda d'une version à l'autre.
# Sinon signature « ad hoc » : macOS redemandera l'accès après chaque compilation.
if security find-identity -p codesigning 2>/dev/null | grep -q "Tiroflan Local Signing"; then
  codesign --force --sign "Tiroflan Local Signing" "$APP"
else
  echo "Certificat « Tiroflan Local Signing » absent : signature ad hoc."
  codesign --force --sign - "$APP"
fi
echo "App assemblée : $APP"

if [[ "${1:-}" == "--no-install" ]]; then exit 0; fi

# On ferme l'ancienne version proprement (les données sont dans ~/Library/Application Support/Tiroflan).
osascript -e 'quit app id "com.theodavid.tiroflan"' 2>/dev/null || true
sleep 1
pkill -x Tiroflan 2>/dev/null || true
rm -rf "/Applications/Tiroflan.app"
cp -R "$APP" /Applications/
open "/Applications/Tiroflan.app"
echo "Installée et lancée : /Applications/Tiroflan.app"
