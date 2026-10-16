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
ls -la build/macos/export/MovieCat.pkg
