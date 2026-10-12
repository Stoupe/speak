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
| Insertion | Clipboard paste (⌘V via `CGEvent`), old clipboard restored once the app has read it, marked transient; a space is added after each paste | Works everywhere incl. Electron, browsers, terminals |
| Pill UI | One glass shape that grows into a live-text card; bottom-centre by default, draggable, position remembered | Minimal, out of the way |
| Distribution | Direct download (GitHub Releases), MIT licence; Sparkle and Homebrew later | The App Store sandbox blocks the event tap and paste |
| Cloud | Not now. Engines sit behind `Transcriber` / `TextPolisher` protocols | Local-first |

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
├─ TextInserter         clipboard save → set → ⌘V → restore
├─ DictationController  @Observable @MainActor coordinator
├─ History              JSON file in Application Support, last 100 items (text only, no audio)
└─ UI                   PillPanel (NSPanel + SwiftUI glass), MenuBarExtra, Settings, Setup
```

## To do

- [ ] Hands-on test of the pill card: animation feel, hold vs double-tap, click-through around the card,
      card opening downwards at the top of the screen
- [ ] Check the event tap in fullscreen apps and after sleep/wake
- [ ] Check paste in Safari, Slack, VS Code and Terminal
- [ ] Paragraph breaks across pieces: a layout pass that returns only break positions (words can't change)
- [ ] Maybe: Settings toggle to hide the live text (screen sharing)
- [ ] First release: Developer ID signing + notarization via `Tools/release.sh`, then a GitHub Release
- [ ] Landing page (`site/`): real download and GitHub links, self-host the fonts
- [ ] Later: Sparkle updates, Homebrew cask, command mode (select text, speak an edit), snippets

## Notes

Things learned the hard way, on an M1 with 8 GB:

- macOS 27 drops synthetic key events created without a `CGEventSource`.
- After a quick fn tap macOS sends a synthetic Globe keyDown (keycode 179); it must not count as "another key".
- Timestamp events on the tap thread: main-thread stalls made quick taps look like holds.
- Foundation Models: guided generation took ~3 s per sentence, plain text with worked examples 0.4–0.9 s.
  Calls can fail with `ModelManagerError 1013` under memory pressure, so the raw-text fallback matters.
- `SpeechTranscriber` finalizes in bursts 4–9 s apart. `SpeechAnalyzer.finalize(through:)` forces it earlier
  but garbles the transcript; `DictationTranscriber`'s frequent finalization uses an older, less accurate model.
- Smart spacing via Accessibility was dropped: Electron apps and terminals don't expose the text, and it
  wouldn't work in a sandboxed build.
