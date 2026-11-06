# Speak — Plan

A small, local-only, Wispr Flow–style dictation app for macOS. Hold **fn** (or double-tap for hands-free),
talk, release, and polished text is pasted into whatever field has focus. English only for now.

## Decisions

| Area | Decision | Why |
|---|---|---|
| Platform | macOS 27, Xcode 27, Swift 6 (strict concurrency), SwiftUI + AppKit where needed | Native, minimal |
| App type | Menu bar only (`LSUIElement`), not sandboxed | Event taps and synthetic keystrokes don't work in the sandbox |
| Project | Plain Xcode project with folder-synced groups + local `SpeakKit` package | No extra tooling; core logic testable with `swift test` |
| Signing | "Apple Development" identity for local builds; Developer ID + notarization for releases (`Tools/release.sh`) | TCC permissions survive rebuilds |
| Speech → text | Apple `SpeechAnalyzer` / `SpeechTranscriber` | Built in, streams while you talk, no dependencies |
| Polish | Apple Foundation Models, plain-text output with worked examples, polished in pieces while speaking | On-device; guided generation was too slow on M1 |
| Fallback | Paste the raw transcript if polish errors, refuses, times out or drops content | Never lose what was said |
| Insertion | Clipboard paste (⌘V via `CGEvent`); the dictation stays on the clipboard (no restore); pastes ≥ 1 s apart; a space is added after each paste | Works everywhere incl. Electron, browsers, terminals; a paste that didn't land is one ⌘V away |
| Pill UI | One glass shape that grows into a live-text card; bottom-centre by default, draggable, position remembered | Minimal, out of the way |
| Distribution | Direct download (GitHub Releases), MIT licence; Homebrew later | The App Store sandbox blocks the event tap and paste |
| Updates | Sparkle 2 (SwiftPM), on only in `release.sh` builds; appcast published from `site/appcast.xml`, which `release.sh --publish` updates through a PR after the GitHub release is up | Local builds must never be replaced by a release (different certificate resets permissions) |
| Cloud | Not now. Engines sit behind `Transcriber` / `TextPolisher` protocols | Local-first |
| Usage stats | One anonymous report a day (counts only, no ID), on by default but only after the choice has been shown (setup, or once after updating); release builds only; Cloudflare Worker + D1 at `speak-telemetry.stoupe.dev`, no IPs stored, logging off, 13-month retention | See how much Speak is used without giving up the privacy promise; the README lists every field and why |

## Architecture

```
Speak.app
├─ HotkeyMonitor        CGEventTap on flagsChanged → trigger key down/up
├─ TriggerStateMachine  idle → holding → (short tap → wait for 2nd tap → handsFree) → finishing
├─ AudioRecorder        AVAudioEngine → 16 kHz mono buffers + level meter
├─ Transcriber          protocol; AppleSpeechTranscriber
├─ TextPolisher         protocol; FoundationModelsPolisher, PassthroughPolisher
├─ IncrementalPolish    polishes finished sentences while you talk, the rest on release
├─ ContextProvider      frontmost app → style hint (chat / email / code / default)
├─ TextInserter         clipboard set → ⌘V (dictation stays on the clipboard)
├─ DictationController  @Observable @MainActor coordinator
├─ History              JSON file in Application Support, last 100 items (text only, no audio)
├─ Updater              Sparkle, only when the build has a feed URL
├─ Telemetry            anonymous daily usage report (counts in SpeakCore/UsageStats), only when the build has an endpoint
└─ UI                   PillPanel (NSPanel + SwiftUI glass), MenuBarExtra (status, recent items to copy), Settings, Setup
```

## To do

- [ ] Hands-on test of the pill card: animation feel, hold vs double-tap, click-through around the card,
      card opening downwards at the top of the screen
- [ ] Check the event tap in fullscreen apps and after sleep/wake
- [ ] Measure `mic live … after key down` in the log (built-in mic vs AirPods); if it's slow, find which step is
      slow before trying fixes
- [ ] Check paste in Safari, Slack, VS Code and Terminal
- [ ] Maybe: restore the previous clipboard again once a paste can be confirmed — watch the focused field via
      Accessibility for the text landing (Chromium/Electron need `AXManualAccessibility`), with the restore decision
      as a pure, tested state machine in `SpeakCore`; with no confirmation, keep the dictation on the clipboard
- [ ] Paragraph breaks across pieces: a layout pass that returns only break positions (words can't change)
- [ ] Maybe: Settings toggle to hide the live text (screen sharing)
- [x] Run `Tools/update-test.sh`: 0.0.1 → 0.0.2 from the menu, relaunched, permissions kept, Settings fits
- [x] Sparkle signing key made (private key in the Keychain, backed up) and `FEED_URL` / `UPDATE_KEY` /
      `DOWNLOADS_URL` filled in `Tools/release.sh`
- [x] First release: 0.1 (build 25) notarized, on GitHub Releases, feed live at `stoupe.github.io/speak/appcast.xml`
- [x] Anonymous usage stats: app, opt-in screens, README table (kept in step by a test), Worker + D1 deployed,
      `Tools/stats.sh`
- [ ] Turn on GitHub Sponsors (the site's Sponsor link and `.github/FUNDING.yml` already point
      at `Stoupe`; the star count in `site/stars.js` stays hidden until the repo has `MIN_STARS`)
- [ ] Landing page (`site/`): self-host the fonts (GitHub links are in; they assume `Stoupe/speak` is public)
- [ ] Later: Homebrew cask, command mode (select text, speak an edit), snippets

## Notes

Things learned the hard way, on an M1 with 8 GB:

- macOS 27 drops synthetic key events created without a `CGEventSource`.
- After a quick fn tap macOS sends a synthetic Globe keyDown (keycode 179); it must not count as "another key".
- Timestamp events on the tap thread: main-thread stalls made quick taps look like holds.
- Don't time the "start talking" cue. A 150 ms delay meant to hide quick taps hid nothing (a short tap stays
  alive through the 300 ms double-tap window), and Tink could play before the mic was capturing. Now the pill
  shows on key-down, `AVAudioEngine.start()` runs on its own queue, and the first audio buffer fades the
  waveform from red to normal and plays Tink.
- Touching `AVAudioEngine().inputNode` (even without starting it) makes macOS show the microphone prompt when
  access is undecided. The launch warm-up waits for permission, so the setup window explains first.
- Foundation Models: guided generation took ~3 s per sentence, plain text with worked examples 0.4–0.9 s.
  Calls can fail with `ModelManagerError 1013` under memory pressure, so the raw-text fallback matters.
- `SpeechTranscriber` finalizes in bursts 4–9 s apart. `SpeechAnalyzer.finalize(through:)` forces it earlier
  but garbles the transcript; `DictationTranscriber`'s frequent finalization uses an older, less accurate model.
- Smart spacing via Accessibility was dropped: Electron apps and terminals don't expose the text, and it
  wouldn't work in a sandboxed build.
- 2026-10-12 — Real use after the change above (21 dictations): most waits 0.6–2.7 s, but 5 final calls hit the
  2 s + 10 ms/char limit and pasted raw after 2.5–4.7 s. Polish time limit raised to 3 s + 15 ms/char (max 8 s);
  pieces polished while talking get double that.
- App icon: `swift Tools/make-icons.swift` writes `Speak/AppIcon.icon` (Icon Composer, layered glass) and renders
  it with Xcode's `ictool` (inside Icon Composer.app) for the fallback PNGs and previews, so it can be checked
  headlessly in every appearance. In dark mode the system recolours white/near-white layers with the background
  colour unless the layer has a dark `fill-specializations` entry.
- Site wordmark (`site/wordmark.js`): WebKit ignores a `clip-path` on `<text>` when the clip region doesn't overlap
  the text, and draws the whole word; clip a `<g>` around the text instead. `hidden` doesn't hide an `<svg>`
  without a CSS rule. Offscreen WKWebView snapshots don't advance animations, so check motion by seeking them.
- Notarization: the account's first submission took ~1.5 days ("In Progress" the whole time); `release.sh`'s
  30 min wait times out; once `notarytool info` says Accepted, finish with `release.sh --resume` (it reuses the
  recorded build, commit and submission). `notarytool` can't read its
  Keychain profile while the screen is locked. The first `generate_appcast` with the real key waits on a
  Keychain Allow dialog.
- Clipboard restore after pasting was removed (2026-11-05): it sometimes pasted the *old* clipboard. With the text
  provided lazily (`NSPasteboardItemDataProvider`), macOS asks once, on the first read by anyone (Universal
  Clipboard, clipboard managers), then serves its copy, so "read" never meant "the target app read it". Writing,
  arming and posting ⌘V in one main-thread pass also meant every early read counted. Slow apps (often right after
  polish, when the Mac is busy) handled ⌘V after the 500 ms / 1.5 s restore and pasted the old contents.
- Releases (2026-11-05): `main` takes changes only through PRs. `release.sh --publish` does the GitHub release,
  the download check and the appcast PR in that order. The build number stays the commit count on `main`: it only
  grows, whatever the merge style, since force pushes are blocked; the script also refuses a build that isn't higher
  than the newest `sparkle:version` in the appcast.
- Usage stats server (2026-11-06): `npm i -g cf` gave 0.15.0 the day before 1.0 betas became `latest`; the 1.0 betas
  have `cf init` and `cloudflare.config.ts`, so check `cf --version`. Cron triggers fail to deploy until the account
  has a workers.dev subdomain, even with `workersDev: false`, so old reports are deleted on each insert instead.
  `cf`/Wrangler drop `.wrangler/cache/cf.json` in whatever folder they run in, holding the request's location (city,
  postcode): it's gitignored. The Settings form has a fixed height (it doesn't scroll); the usage stats section's
  110 pt was measured by rendering with the Debug-only `-snapshot` (see `Speak/Demo/Snapshot.swift`).
