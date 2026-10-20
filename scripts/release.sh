#!/bin/bash
# Builds MenuRaid, signs it with your Developer ID certificate, notarizes it with Apple and packages a .dmg.
#
#   scripts/release.sh                   full release: build, sign, notarize, staple, package
#   scripts/release.sh --skip-notarize   build, sign and verify only (needs no Apple credentials)
#
# One-time setup for notarizing (the password is an app-specific one from appleid.apple.com):
#   xcrun notarytool store-credentials MenuRaid-notary --apple-id YOUR_APPLE_ID --team-id DM7437997T
#
# Output goes to build/release/ (git-ignored). Set NOTARY_PROFILE to use a different stored profile.
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="MenuRaid.xcodeproj"
SCHEME="MenuRaid"
TEAM_ID="DM7437997T"
PROFILE="${NOTARY_PROFILE:-MenuRaid-notary}"
OUT="build/release"
SKIP_NOTARIZE=0
[[ "${1:-}" == "--skip-notarize" ]] && SKIP_NOTARIZE=1

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'error: %s\n' "$1" >&2; exit 1; }

IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
[[ -n "$IDENTITY" ]] || fail "No 'Developer ID Application' certificate in your keychain. Create one in Xcode > Settings > Apple Accounts > Manage Certificates."

if [[ $SKIP_NOTARIZE -eq 0 ]]; then
    xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
        || fail "No stored notarization profile '$PROFILE'. Run: xcrun notarytool store-credentials $PROFILE --apple-id YOUR_APPLE_ID --team-id $TEAM_ID  (or use --skip-notarize)"
fi

VERSION=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '$1 ~ /MARKETING_VERSION$/ {print $2; exit}')
[[ -n "$VERSION" ]] || fail "Couldn't read MARKETING_VERSION."
echo "MenuRaid $VERSION, signing as: $IDENTITY"

rm -rf "$OUT"
mkdir -p "$OUT"

cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF

step "Archiving (Release)"
xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$OUT/MenuRaid.xcarchive" -quiet

step "Exporting with Developer ID signing"
xcodebuild -exportArchive -archivePath "$OUT/MenuRaid.xcarchive" \
    -exportPath "$OUT/export" -exportOptionsPlist "$OUT/ExportOptions.plist" -quiet
APP="$OUT/export/MenuRaid.app"
[[ -d "$APP" ]] || fail "Export produced no app."

step "Verifying the signature"
codesign --verify --deep --strict --verbose=2 "$APP"
DETAILS=$(codesign -dvv "$APP" 2>&1)
grep -q "Authority=Developer ID Application" <<<"$DETAILS" || fail "App isn't signed with a Developer ID Application certificate."
grep -Eq "flags=0x[0-9a-f]+\(.*runtime" <<<"$DETAILS" || fail "Hardened Runtime is off; Apple would reject notarization."
echo "Signed with Developer ID, Hardened Runtime on."
echo "Entitlements:"; codesign -d --entitlements - "$APP" 2>/dev/null | sed 's/^/    /'

# These must not ship: the debug tool and sample data are #if DEBUG only.
if strings "$APP/Contents/MacOS/MenuRaid" | grep -q "TestQueryView"; then fail "Debug code found in the release binary."; fi

DMG="$OUT/MenuRaid-$VERSION.dmg"

if [[ $SKIP_NOTARIZE -eq 1 ]]; then
    step "Skipping notarization (--skip-notarize)"
    echo "Built and signed: $APP"
    exit 0
fi

step "Notarizing the app (this can take a few minutes)"
ditto -c -k --keepParent "$APP" "$OUT/MenuRaid.zip"
xcrun notarytool submit "$OUT/MenuRaid.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

step "Packaging $DMG"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "MenuRaid $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --sign "$IDENTITY" --timestamp "$DMG"

step "Notarizing the disk image"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

step "Final checks"
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
xcrun stapler validate "$DMG"

step "Done"
echo "$DMG"
shasum -a 256 "$DMG"
echo
echo "Next: git tag v$VERSION && git push origin v$VERSION, then attach the .dmg to a GitHub release for that tag."
