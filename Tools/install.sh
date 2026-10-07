#!/bin/zsh
# Builds Speak (Release), installs it to /Applications and relaunches it.
# Permissions carry over between installs because the app is always signed with the same certificate.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -project Speak.xcodeproj -scheme Speak -configuration Release \
    -destination "platform=macOS" -derivedDataPath build/DerivedData build -quiet

pkill -x Speak 2>/dev/null && sleep 1 || true
rm -rf /Applications/Speak.app
cp -R build/DerivedData/Build/Products/Release/Speak.app /Applications/
open /Applications/Speak.app
echo "Speak installed to /Applications and launched."
