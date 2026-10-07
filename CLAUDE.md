# Speak

Local-only Wispr Flow–style dictation for macOS 27. **Read `PLAN.md` first** — it holds the decisions,
architecture and progress checklist. Tick items and add dated log entries there as work lands.

## Layout
- `Packages/SpeakKit` — `SpeakCore` (pure logic: trigger state machine, polish guard/pipeline, history),
  `SpeakEngines` (Apple SpeechAnalyzer + Foundation Models), `speak-bench` (headless CLI), tests.
- `Speak/` — app target (folder-synced; new files are picked up automatically): event tap, audio capture,
  paste insertion, pill panel, menu, settings.
- `Bench/polish-cases.json` — raw → expected cases for prompt tuning.

## Commands
```sh
# Unit tests (headless)
cd Packages/SpeakKit && swift test
# Engine checks without launching the app (`say -o` writes audio silently)
swift run speak-bench status
swift run speak-bench transcribe --realtime /path/to/clip.aiff
swift run speak-bench cases ../../Bench/polish-cases.json
# App build
xcodebuild -project Speak.xcodeproj -scheme Speak -derivedDataPath build/DerivedData build
```

## Rules
- The user works on this Mac: don't launch Speak.app, post keyboard events, or open windows unless asked.
- Signing uses the "Apple Development" identity (team V4TSTMTS4F) so TCC permissions survive rebuilds.
- Engines stay behind `Transcriber` / `TextPolisher` protocols; don't add cloud code until planned.
- Check SDK `.swiftinterface` files for macOS 26/27 APIs rather than guessing.
