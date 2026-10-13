#!/bin/zsh
# Builds a shareable, notarized Speak.zip.
#
#   Tools/release.sh --dry-run [--version 0.3] [--build 7] [--feed URL --update-key KEY]
#       Archive + export signed with your local Apple Development certificate, then run the same checks
#       notarization cares about. Nothing is sent to Apple and no certificates are created.
#       --feed/--update-key turn on Sparkle updates in the build (Tools/update-test.sh uses this).
#
#   Tools/release.sh [--version 0.3] [--notary-profile speak-notary]
#       The real thing: Developer ID signing (Xcode may create a cloud-managed Developer ID certificate on
#       first use), notarization, stapling, the final zip and the Sparkle appcast. Asks before contacting Apple.
#       Nothing is uploaded: it prints the publishing steps at the end.
#
# One-time setup for real releases: store notarization credentials in your Keychain, e.g.
#   xcrun notarytool store-credentials speak-notary --apple-id you@example.com --team-id V4TSTMTS4F
# (prompts for an app-specific password from account.apple.com; the script only uses the profile name).

set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="V4TSTMTS4F"
DRY_RUN=false
VERSION=""
BUILD=""
NOTARY_PROFILE="speak-notary"

# Sparkle updates. Real releases refuse to run until all three are set, and builds without them never check for
# updates (see Speak/App/Updater.swift). Every release keeps its feed URL forever, so it must keep working: a
# custom domain added to GitHub Pages later redirects from the github.io address.
FEED_URL="https://stoupe.github.io/speak/appcast.xml"         # published from site/appcast.xml
UPDATE_KEY="PFlseSBc4KrnvY+QuYNdbd5iJ2MMhkNQBJR2VPyM57I="     # public EdDSA key: generate_keys -p (private key: Keychain, backup in 1Password)
DOWNLOADS_URL="https://github.com/Stoupe/speak/releases/download"  # the release tag is appended

while (( $# )); do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --version) VERSION="$2"; shift ;;
        --build) BUILD="$2"; shift ;;
        --feed) FEED_URL="$2"; shift ;;
        --update-key) UPDATE_KEY="$2"; shift ;;
        --notary-profile) NOTARY_PROFILE="$2"; shift ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

step() { print -P "\n%B==> $1%b"; }
fail() { print -P "%F{red}✗ $1%f" >&2; exit 1; }
ok() { print -P "%F{green}✓%f $1"; }

# Version: given, or the project's MARKETING_VERSION. Build number: commit count, so it always increases.
if [[ -z "$VERSION" ]]; then
    VERSION=$(xcodebuild -project Speak.xcodeproj -target Speak -configuration Release -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ MARKETING_VERSION / { print $2; exit }')
fi
[[ -n "$BUILD" ]] || BUILD=$(git rev-list --count HEAD)
OUT="build/release/Speak-$VERSION-$BUILD"

if [[ -n "$(git status --porcelain)" ]]; then
    $DRY_RUN || fail "Uncommitted changes. Commit first so the release matches a known commit."
    print -P "%F{yellow}!%f Uncommitted changes (fine for a dry run)."
fi

if $DRY_RUN; then
    print "Dry run: Speak $VERSION ($BUILD). Nothing will be sent to Apple."
else
    [[ -n "$FEED_URL" && -n "$UPDATE_KEY" && -n "$DOWNLOADS_URL" ]] \
        || fail "Updates aren't set up: fill in FEED_URL, UPDATE_KEY and DOWNLOADS_URL at the top of this script."
    print "Release: Speak $VERSION ($BUILD)."
    print "This will contact Apple to sign with Developer ID (creating a certificate on first use) and to notarize."
    read -q "REPLY?Continue? [y/N] " || { print; exit 1; }
    print
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || fail "No notarization credentials named '$NOTARY_PROFILE'. See the setup note at the top of this script."
fi

rm -rf "$OUT"
mkdir -p "$OUT"

step "Archiving"
xcodebuild archive \
    -project Speak.xcodeproj -scheme Speak -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$OUT/Speak.xcarchive" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
    SPEAK_FEED_URL="$FEED_URL" SPEAK_UPDATE_KEY="$UPDATE_KEY" \
    -quiet
ok "Archived to $OUT/Speak.xcarchive"

step "Exporting"
EXPORT_OPTIONS="$OUT/ExportOptions.plist"
if $DRY_RUN; then
    # Same pipeline, but signed with the local development certificate: no network, no new certificates.
    cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>method</key><string>debugging</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Apple Development</string>
    <key>teamID</key><string>$TEAM_ID</string>
</dict></plist>
EOF
    xcodebuild -exportArchive -archivePath "$OUT/Speak.xcarchive" -exportPath "$OUT/export" \
        -exportOptionsPlist "$EXPORT_OPTIONS" -quiet
else
    cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>automatic</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>destination</key><string>export</string>
</dict></plist>
EOF
    xcodebuild -exportArchive -archivePath "$OUT/Speak.xcarchive" -exportPath "$OUT/export" \
        -exportOptionsPlist "$EXPORT_OPTIONS" -allowProvisioningUpdates -quiet
fi
APP="$OUT/export/Speak.app"
[[ -d "$APP" ]] || fail "Export didn't produce Speak.app"
ok "Exported $APP"

step "Checking the signature"
codesign --verify --deep --strict "$APP" || fail "Signature doesn't verify"
ok "Signature verifies (deep, strict)"
SIGNATURE=$(codesign -dvv "$APP" 2>&1)
ENTITLEMENTS=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)
[[ "$SIGNATURE" == *"flags=0x10000(runtime)"* ]] || fail "Hardened Runtime is off (required for notarization)"
ok "Hardened Runtime on"
[[ "$ENTITLEMENTS" == *"com.apple.security.device.audio-input"* ]] || fail "Missing the microphone entitlement"
ok "Microphone entitlement present"
INFO="$APP/Contents/Info.plist"
[[ "$(plutil -extract SUFeedURL raw -o - "$INFO")" == "$FEED_URL" ]] || fail "SUFeedURL doesn't match FEED_URL"
[[ "$(plutil -extract SUPublicEDKey raw -o - "$INFO")" == "$UPDATE_KEY" ]] || fail "SUPublicEDKey doesn't match UPDATE_KEY"
if [[ -n "$FEED_URL" ]]; then ok "Updates on: $FEED_URL"; else print -P "%F{yellow}!%f Updates off (no feed URL)"; fi
[[ "$SIGNATURE" == *"Timestamp="* ]] || print -P "%F{yellow}!%f No secure timestamp (expected for a dry run; Developer ID export adds one)"
if $DRY_RUN; then
    [[ "$ENTITLEMENTS" == *"get-task-allow"* ]] && print -P "%F{yellow}!%f Debug entitlement present (expected for a dry run; Developer ID export removes it)"
    print "$SIGNATURE" | grep -E -m2 "^(Authority=Apple Development|TeamIdentifier)" | sed 's/^/  /'
    step "Dry run complete"
    print "Everything up to Developer ID signing works. For the real release:"
    print "  1. One time: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <your Apple ID> --team-id $TEAM_ID"
    print "  2. Tools/release.sh --version $VERSION"
    exit 0
fi

[[ "$SIGNATURE" == *"Authority=Developer ID Application"* ]] || fail "Not signed with Developer ID"
ok "Signed with Developer ID"
[[ "$ENTITLEMENTS" != *"get-task-allow"* ]] || fail "Debug entitlement still present (notarization would reject it)"
ok "No debug entitlement"

step "Notarizing (usually a few minutes)"
SUBMISSION="$OUT/Speak-notarize.zip"
ditto -c -k --keepParent "$APP" "$SUBMISSION"
RESULT="$OUT/notary-result.json"
xcrun notarytool submit "$SUBMISSION" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m \
    --output-format json > "$RESULT" || true
STATUS=$(plutil -extract status raw -o - "$RESULT" 2>/dev/null || echo "unknown")
SUBMISSION_ID=$(plutil -extract id raw -o - "$RESULT" 2>/dev/null || echo "")
if [[ "$STATUS" != "Accepted" ]]; then
    [[ -n "$SUBMISSION_ID" ]] && xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" "$OUT/notary-log.json" || true
    fail "Notarization status: $STATUS. Details: $OUT/notary-log.json"
fi
ok "Notarized (submission $SUBMISSION_ID)"

step "Stapling"
xcrun stapler staple "$APP"
GATEKEEPER=$(spctl --assess --type execute --verbose "$APP" 2>&1) || fail "Gatekeeper rejects the app: $GATEKEEPER"
[[ "$GATEKEEPER" == *"Notarized Developer ID"* ]] || fail "Gatekeeper doesn't see it as notarized: $GATEKEEPER"
ok "Gatekeeper accepts it as Notarized Developer ID"

step "Packaging"
ZIP="$OUT/Speak-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
ok "Ready to share: $ZIP"

# Every release's zip is kept in build/updates so generate_appcast can build delta updates against them. It reuses
# the appcast in that folder, adding the new version; site/appcast.xml is the published copy.
step "Updating the appcast"
UPDATES="build/updates"
TAG="v$VERSION"
mkdir -p "$UPDATES"
cp "$ZIP" "$UPDATES/"
[[ -f "$UPDATES/appcast.xml" ]] || [[ ! -f site/appcast.xml ]] || cp site/appcast.xml "$UPDATES/appcast.xml"
SPARKLE_BIN="build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
[[ -x "$SPARKLE_BIN/generate_appcast" ]] \
    || xcodebuild -resolvePackageDependencies -project Speak.xcodeproj -scheme Speak -derivedDataPath build/DerivedData -quiet
"$SPARKLE_BIN/generate_appcast" --download-url-prefix "$DOWNLOADS_URL/$TAG/" "$UPDATES" \
    || fail "generate_appcast failed (it signs with the private key in your Keychain)"
cp "$UPDATES/appcast.xml" site/appcast.xml
ok "site/appcast.xml now lists $VERSION ($BUILD)"

step "Publish (in this order)"
print "  1. Create a GitHub release tagged $TAG and upload $UPDATES/Speak-$VERSION.zip"
print "     and any new .delta files generate_appcast made there (the appcast points at them under the same tag)."
print "  2. Check the download link works: $DOWNLOADS_URL/$TAG/Speak-$VERSION.zip"
print "  3. Commit and push site/appcast.xml. Installed copies see the update once the site is live."
