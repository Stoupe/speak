# Speak

Local-only Wispr Flow–style dictation for macOS 27. **Read `PLAN.md` first** — it holds the decisions,
architecture and to-do list. Keep it current as work lands, and add anything learned the hard way under Notes.

## Layout
- `Packages/SpeakKit` — `SpeakCore` (pure logic: trigger state machine, polish guard/pipeline, history),
  `SpeakEngines` (Apple SpeechAnalyzer + Foundation Models), `speak-bench` (headless CLI), tests.
- `Speak/` — app target (folder-synced; new files are picked up automatically): event tap, audio capture,
  paste insertion, pill panel, menu, settings.
- `Bench/polish-cases.json` — raw → expected cases for prompt tuning.
- `Speak/Demo/` — Debug-only scripted scenes for README captures: mock backdrops (terminal, email) and a
  player that drives the real pill. Captured by `Tools/demo.sh`.
- `site/` — landing page: plain HTML + CSS (+ `demo.js` for the hero demo, `waves.js` for the headline waveforms,
  `wordmark.js` for the header wordmark, `stars.js` for the live GitHub star count), no build step. Separate from the app; nothing in Xcode or SwiftPM reads it. Never put web files in `Speak/` (that folder is bundled into the app).

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
# Install the Release build to /Applications and relaunch (--fresh: wipe settings, history + permissions to see onboarding)
Tools/install.sh
Tools/install.sh --fresh
# Shareable build: dry run (local only), then the real thing (asks before contacting Apple)
Tools/release.sh --dry-run
Tools/release.sh --version 0.3
# README screenshots and recordings from scripted scenes (Speak/Demo/DemoScene.swift) → docs/
Tools/demo.sh terminal   # GIF + MP4; also: card, menu (PNG)
# Sparkle update test: old + new dry-run builds, throwaway key, appcast served on localhost
Tools/update-test.sh
```

## Rules
- The Mac is usually in use while you work: don't launch Speak.app, post keyboard events, or open windows unless
  asked.
- Signing uses the "Apple Development" identity (team V4TSTMTS4F) so TCC permissions survive rebuilds.
- Never run `Tools/release.sh` without `--dry-run` unless asked: it contacts Apple (Developer ID, notarization).
- Sparkle updates are on only when a build gets `SPEAK_FEED_URL` / `SPEAK_UPDATE_KEY` (from `release.sh`). Keep Xcode
  and `install.sh` builds without them, so a dev build never updates itself to a release. The private EdDSA key
  lives only in the maintainer's Keychain; never print, export or commit it.
- Engines stay behind `Transcriber` / `TextPolisher` protocols; don't add cloud code until planned.
- Check SDK `.swiftinterface` files for macOS 26/27 APIs rather than guessing.
