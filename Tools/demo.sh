#!/bin/zsh
# Captures a scripted demo scene for the README (scenes: Speak/Demo/DemoScene.swift) into docs/.
#
#   Tools/demo.sh card       # docs/card.png
#   Tools/demo.sh menu       # docs/menu.png
#   Tools/demo.sh terminal   # docs/terminal.gif (for the README) + docs/terminal.mp4 (sharper; GitHub only plays
#                            # video uploaded through its web editor, so drag this into the README there)
#
# Builds the Debug app and runs it with -demo <scene> in place of the installed Speak, which is quit first and
# relaunched afterwards. The scene draws its own backdrop; only that area of the screen is captured. Needs Screen
# Recording permission for the terminal, Accessibility too for the menu scene (to click the menu bar icon), and
# ffmpeg for recordings.
set -euo pipefail
cd "$(dirname "$0")/.."

SCENE=${1:?usage: Tools/demo.sh <scene>}
OUT=docs
DIR=/tmp/speak-demo  # shared with DemoCapture
APP=build/DerivedData/Build/Products/Debug/Speak.app

xcodebuild -project Speak.xcodeproj -scheme Speak -configuration Debug \
    -destination "platform=macOS" -derivedDataPath build/DerivedData build -quiet

WAS_RUNNING=false
pgrep -xq Speak && WAS_RUNNING=true
pkill -x Speak 2>/dev/null && sleep 1 || true

cleanup() {
    pkill -f "$APP/Contents/MacOS/Speak" 2>/dev/null || true
    if $WAS_RUNNING; then sleep 1; open /Applications/Speak.app; fi
}
trap cleanup EXIT

# Waits for a file from the app, up to $2 seconds (default 15).
await() {
    for _ in {1..$(( ${2:-15} * 10 ))}; do [[ -f "$1" ]] && return; sleep 0.1; done
    echo "Timed out waiting for $1" >&2
    return 1
}

rm -rf "$DIR" && mkdir -p "$DIR" "$OUT"
open -n "$APP" --args -demo "$SCENE"
await "$DIR/info" || { echo "Is '$SCENE' a scene in Speak/Demo/DemoScene.swift?" >&2; exit 1; }
source "$DIR/info"
sleep 1  # let the backdrop and pill draw

case "$capture" in
    still)
        touch "$DIR/start"
        sleep 1.5
        screencapture -x -R"$region" "$OUT/$SCENE.png"
        echo "Wrote $OUT/$SCENE.png"
        ;;
    menu)
        touch "$DIR/start"
        sleep 0.5
        osascript -e 'tell application "System Events" to tell (first process whose unix id is '"$(pgrep -nf "$APP/Contents/MacOS/Speak")"') to click menu bar item 1 of menu bar 2' >/dev/null &
        await "$DIR/menu"
        source "$DIR/menu"
        screencapture -x -R"$region" "$OUT/$SCENE.png"
        osascript -e 'tell application "System Events" to key code 53'  # Esc closes the menu
        echo "Wrote $OUT/$SCENE.png"
        ;;
    video)
        # Start recording, give it a moment to get going, then play the scene; Ctrl-C ends the recording.
        screencapture -x -v -R"$region" "$DIR/raw.mov" &
        RECORDER=$!
        sleep 1
        touch "$DIR/start"
        await "$DIR/done" 120
        sleep 0.5
        kill -INT $RECORDER
        wait $RECORDER
        # Full (Retina) resolution: the site shows it at around 860 points wide.
        ffmpeg -loglevel error -y -i "$DIR/raw.mov" -vf "fps=30,scale=trunc(iw/2)*2:trunc(ih/2)*2" \
            -c:v libx264 -pix_fmt yuv420p -crf 23 -movflags +faststart "$OUT/$SCENE.mp4"
        ffmpeg -loglevel error -y -i "$DIR/raw.mov" -vf \
            "fps=20,scale=860:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
            "$OUT/$SCENE.gif"
        echo "Wrote $OUT/$SCENE.gif ($(du -h "$OUT/$SCENE.gif" | cut -f1)) and $OUT/$SCENE.mp4 ($(du -h "$OUT/$SCENE.mp4" | cut -f1))"
        ;;
esac

# Captures are at the display's scale. The scene is drawn on the built-in (Retina) display, but the menu opens on
# whichever display has the active window.
if [[ "$capture" != video ]]; then
    width=${${region#*,*,}%%,*}  # region is x,y,width,height
    pixels=$(sips -g pixelWidth "$OUT/$SCENE.png" | awk '/pixelWidth/ {print $2}')
    (( pixels > width )) || echo "Warning: captured at 1x. Click a window on the built-in display and run again." >&2
fi
