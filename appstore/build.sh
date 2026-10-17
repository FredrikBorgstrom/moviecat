#!/bin/bash
# Builds, signs and exports the Mac App Store package to build/macos/export/MovieCat.pkg.
# Bump "version:" in pubspec.yaml (the +N build number must increase) before each upload.
set -euo pipefail
cd "$(dirname "$0")/.."
CFG=appstore/asc.local.json
KEY_ID=$(python3 -c "import json;print(json.load(open('$CFG'))['keyId'])")
ISSUER=$(python3 -c "import json;print(json.load(open('$CFG'))['issuerId'])")
KEY=$(python3 -c "import json,os;print(os.path.expanduser(json.load(open('$CFG'))['keyPath']))")

flutter build macos --release --config-only
rm -rf build/macos/MovieCat.xcarchive build/macos/export
xcodebuild archive -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release \
  -archivePath build/macos/MovieCat.xcarchive -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER" \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=F3C7B92SZG CODE_SIGN_IDENTITY="Apple Development" \
  | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)"
# Signed for distribution with the "MovieCat Mac App Store" provisioning profile.
xcodebuild -exportArchive -archivePath build/macos/MovieCat.xcarchive -exportPath build/macos/export \
  -exportOptionsPlist macos/ExportOptions.plist | grep -E "error|EXPORT (SUCCEEDED|FAILED)"

# Xcode's export leaves Swift-package resource bundles (file_selector, url_launcher)
# signed with the development certificate, which App Store processing rejects
# (error 90284). Re-sign them for distribution, re-seal the app, rebuild the pkg.
DIST="Apple Distribution: AB Cx3 (F3C7B92SZG)"
INSTALLER="3rd Party Mac Developer Installer: AB Cx3 (F3C7B92SZG)"
WORK=build/macos/resign
rm -rf "$WORK" && pkgutil --expand-full build/macos/export/MovieCat.pkg "$WORK"
APP="$WORK/com.abcx3.moviecat.pkg/Payload/MovieCat.app"
codesign -d --entitlements "$WORK/entitlements.plist" --xml "$APP"
for item in "$APP"/Contents/Resources/*.bundle; do
  codesign --force --sign "$DIST" --timestamp=none "$item"
done
codesign --force --sign "$DIST" --entitlements "$WORK/entitlements.plist" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
productbuild --component "$APP" /Applications --sign "$INSTALLER" build/macos/export/MovieCat.pkg
rm -rf "$WORK"
ls -la build/macos/export/MovieCat.pkg
