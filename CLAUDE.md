# Speak

Local-only Wispr Flow–style dictation for macOS 27. **Read `PLAN.md` first** — it holds the decisions,
architecture and to-do list. Keep it current as work lands, and add anything learned the hard way under Notes.

## Layout
- `Packages/SpeakKit` — `SpeakCore` (pure logic: trigger state machine, polish guard/pipeline, history),
  `SpeakEngines` (Apple SpeechAnalyzer + Foundation Models), `speak-bench` (headless CLI), tests.
- `Speak/` — app target (folder-synced; new files are picked up automatically): event tap, audio capture,
  paste insertion, pill panel, menu, settings.
- `Bench/polish-cases.json` — raw → expected cases for prompt tuning.
- `server/telemetry/` — Cloudflare Worker + D1 that receives the anonymous usage report (`cf` CLI, not Wrangler;
  see its README). The report format lives in `SpeakCore/UsageStats.swift`; tests keep it in step with the README's
  "Usage stats" table and the server's accepted fields, so change all three together.
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
# Shareable build: dry run (local only), then the real thing (asks before contacting Apple, then before publishing)
Tools/release.sh --dry-run
Tools/release.sh --version 0.3 --publish --notes notes.md
Tools/release.sh --version 0.3 --resume --publish --notes notes.md   # after notarization outlasted the 30 min wait
# README screenshots and recordings from scripted scenes (Speak/Demo/DemoScene.swift) → docs/
Tools/demo.sh terminal   # GIF + MP4; also: card, menu (PNG)
# Sparkle update test: old + new dry-run builds, throwaway key, appcast served on localhost
Tools/update-test.sh
# Usage stats summary from the live database (read-only; needs cf signed in)
Tools/stats.sh [days]
# Render setup/usage stats/Settings views to PNGs offscreen and quit (Debug build; no windows, mic or key tap)
build/DerivedData/Build/Products/Debug/Speak.app/Contents/MacOS/Speak -snapshot /tmp/speak-snapshot
```

## Rules
- The Mac is usually in use while you work: don't launch Speak.app, post keyboard events, or open windows unless
  asked.
- Signing uses the "Apple Development" identity (team V4TSTMTS4F) so TCC permissions survive rebuilds.
- Never run `Tools/release.sh` without `--dry-run` unless asked: it contacts Apple (Developer ID, notarization).
- `main` is protected: never push to it. Branch, push, open a PR (`gh pr create`); merge only when asked.

## Releasing
1. Release-prep PR: bump `MARKETING_VERSION` in the project if needed, update `PLAN.md`. Merge it.
2. `git switch main && git pull`, then `Tools/release.sh --dry-run`.
3. Write release notes to a file outside the repo (or skip `--notes` for GitHub's generated ones), then
   `Tools/release.sh --version X.Y --publish --notes FILE`. It refuses to run unless on `main`, clean and level with
   `origin/main`, and unless the build number (commit count) is higher than the newest in `site/appcast.xml`.
4. It then creates the GitHub release `vX.Y` on the built commit with the zip and any deltas, checks the download,
   and opens and merges a PR with the new `site/appcast.xml`; that merge deploys the feed. Order matters: the feed
   must never go live before its download exists.
5. `build/updates/` keeps every released zip so Sparkle can make delta updates; it exists only on this Mac.
- Sparkle updates are on only when a build gets `SPEAK_FEED_URL` / `SPEAK_UPDATE_KEY` (from `release.sh`). Keep Xcode
  and `install.sh` builds without them, so a dev build never updates itself to a release. The private EdDSA key
  lives only in the maintainer's Keychain; never print, export or commit it.
- Usage stats are sent only by release builds (`release.sh` sets `SPEAK_TELEMETRY_URL`, like the Sparkle feed) and
  only after the choice has been shown. Never add a field without adding it to the README table, and never send
  text, app names or an identifier.
- Engines stay behind `Transcriber` / `TextPolisher` protocols; don't add cloud code until planned.
- Check SDK `.swiftinterface` files for macOS 26/27 APIs rather than guessing.
