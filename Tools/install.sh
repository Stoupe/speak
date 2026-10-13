#!/bin/zsh
# Builds Speak (Release), installs it to /Applications and relaunches it.
# Permissions carry over between installs because the app is always signed with the same certificate.
#
#   Tools/install.sh           # normal install
#   Tools/install.sh --fresh   # start as a new user would: deletes Speak's settings (including the dictionary),
#                              # history and Microphone, Accessibility and Input Monitoring permissions, so it opens
#                              # with the setup window (the system Globe-key setting isn't touched)
set -euo pipefail
cd "$(dirname "$0")/.."

FRESH=false
for arg in "$@"; do
    case "$arg" in
        --fresh) FRESH=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

xcodebuild -project Speak.xcodeproj -scheme Speak -configuration Release \
    -destination "platform=macOS" -derivedDataPath build/DerivedData build -quiet

pkill -x Speak 2>/dev/null && sleep 1 || true

if $FRESH; then
    BUNDLE_ID=dev.stoupe.Speak
    defaults delete "$BUNDLE_ID" 2>/dev/null || true
    rm -rf ~/Library/Application\ Support/Speak
    for service in Microphone Accessibility ListenEvent; do
        tccutil reset "$service" "$BUNDLE_ID" >/dev/null
    done
    echo "Reset settings, history and permissions: Speak will start with the setup window."
fi

rm -rf /Applications/Speak.app
cp -R build/DerivedData/Build/Products/Release/Speak.app /Applications/
open /Applications/Speak.app
echo "Speak installed to /Applications and launched."
