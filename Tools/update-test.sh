#!/bin/zsh
# Tests Sparkle updates end to end without contacting Apple or the internet: builds an "old" and a "new" Speak
# (dry-run builds, signed with your Apple Development certificate, so permissions carry over), signs the new one
# with a throwaway key (a file in build/update-test, not your Keychain or the real release key) and serves an
# appcast on localhost. Then you update the old app from its menu.
#
#   Tools/update-test.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PORT=8789
FEED="http://127.0.0.1:$PORT/appcast.xml"
DIR="build/update-test"
SPARKLE_BIN="build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"

step() { print -P "\n%B==> $1%b"; }

rm -rf "$DIR"
mkdir -p "$DIR/feed"

step "Making a throwaway signing key"
# Sparkle's private key file is the base64 Ed25519 seed; the public key is the base64 raw public key.
cat > "$DIR/keygen.swift" <<'EOF'
import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
try! key.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
print(key.publicKey.rawRepresentation.base64EncodedString())
EOF
PUBLIC_KEY=$(swift "$DIR/keygen.swift" "$DIR/private-key")
print "Public key: $PUBLIC_KEY"

build() {
    Tools/release.sh --dry-run --version "$1" --build "$2" --feed "$FEED" --update-key "$PUBLIC_KEY"
}

step "Building the old version (0.0.1)"
build 0.0.1 1
ditto build/release/Speak-0.0.1-1/export/Speak.app "$DIR/Speak.app"

step "Building the new version (0.0.2)"
build 0.0.2 2
ditto -c -k --keepParent build/release/Speak-0.0.2-2/export/Speak.app "$DIR/feed/Speak-0.0.2.zip"

step "Writing the appcast"
[[ -x "$SPARKLE_BIN/generate_appcast" ]] \
    || xcodebuild -resolvePackageDependencies -project Speak.xcodeproj -scheme Speak -derivedDataPath build/DerivedData -quiet
"$SPARKLE_BIN/generate_appcast" --ed-key-file "$DIR/private-key" --download-url-prefix "http://127.0.0.1:$PORT/" "$DIR/feed"

step "Ready"
print "  1. Quit Speak if it's running."
print "  2. open $DIR/Speak.app   (version 0.0.1; it may ask about checking automatically, either answer is fine)"
print "  3. Menu bar → Check for Updates… → install 0.0.2. It should relaunch by itself."
print "  4. Menu bar → About Speak should say 0.0.2. Dictate once to check permissions survived."
print "  5. Quit it, press Ctrl-C here, and reopen /Applications/Speak.app."
print "Logs: Console.app, search for Sparkle."
step "Serving $FEED (Ctrl-C to stop)"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$DIR/feed"
