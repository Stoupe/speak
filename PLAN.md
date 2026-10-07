# Speak — Plan

A tiny, local-only, Wispr Flow–style dictation app for macOS. Hold **Fn** (or double-tap Fn for
hands-free), talk, release, and polished text is pasted into whatever field has focus.

Personal tool: no onboarding, no accounts, no distribution. English only.

## Decisions

| Area | Decision | Why |
|---|---|---|
| Platform | macOS 27, Xcode 27, Swift 6 (strict concurrency), SwiftUI + AppKit where needed | Native, minimal |
| App type | Menu bar only (`LSUIElement`), not sandboxed | Event taps and synthetic keystrokes don't work in the sandbox |
| Project | Plain Xcode project with buildable (folder-synced) groups + local `SpeakKit` package | No extra tooling; core logic testable with `swift test` |
| Signing | Existing "Apple Development" identity | Accessibility/Input Monitoring permission survives rebuilds |
| Speech → text | Apple `SpeechAnalyzer` / `SpeechTranscriber` first; FluidAudio (Nemotron 3.5 / Parakeet) as a later bake-off | Built in, streams while you talk, no dependencies |
| Polish | Apple Foundation Models (`LanguageModelSession`, guided generation) | On-device, system-managed memory (important on 8 GB) |
| Fallback | Paste raw transcript if polish errors, refuses, times out (~1.5s), or rewrites too much | Never lose what was said |
| Insertion | Clipboard paste (⌘V via `CGEvent`), restore old clipboard, mark as transient | Works everywhere incl. Electron/browsers/terminals |
| Pill UI | Small glass capsule, bottom-center by default, draggable, position remembered, double-click to reset | Minimal, out of the way |
| Cloud | Not now. Engines sit behind protocols so cloud can be added later | Local-first |

### Hardware notes (this Mac)
- MacBook M1, **8 GB RAM**: avoid running a separate local LLM (MLX) alongside; prefer Foundation Models.
- 2026-10-07: `SpeechTranscriber` available, English locales installed. Foundation Models reported
  `modelNotReady` (still downloading after disk was freed) — recheck before Phase 2.

## Architecture

```
Speak.app
├─ HotkeyMonitor        CGEventTap on flagsChanged → Fn down/up
├─ TriggerStateMachine  idle → holding → (short tap → wait for 2nd tap → handsFree) → finishing
├─ AudioRecorder        AVAudioEngine → 16 kHz mono buffers + level meter
├─ Transcriber          protocol; AppleSpeechTranscriber (later FluidAudioTranscriber)
├─ TextPolisher         protocol; FoundationModelsPolisher, PassthroughPolisher
├─ ContextProvider      frontmost app → style hint (chat / email / code / default)
├─ TextInserter         clipboard save → set → ⌘V → restore
├─ DictationController  @Observable @MainActor coordinator
├─ History              JSON file in Application Support, last 100 items (text only, no audio)
└─ UI                   PillPanel (NSPanel + SwiftUI glass), MenuBarExtra, Settings form
```

## Progress

### Phase 0 — Scaffold + spikes
- [x] `git init`, `.gitignore`
- [x] Xcode project: macOS 27, non-sandboxed, Swift 6, menu bar only, Apple Development signing
- [ ] Set System Settings → Keyboard → "Press 🌐 key to: Do Nothing" (manual)
- [x] Event tap for Fn (`HotkeyMonitor`) — tested end to end; still to check: fullscreen apps, after sleep/wake
- [x] Paste + clipboard restore (`TextInserter`) — tested in TextEdit and Notes; still to check: Safari, Slack, VS Code, Terminal

### Phase 1 — Raw dictation end to end
- [x] Hold Fn → record → `SpeechTranscriber` (streaming) → paste (verified headlessly via `speak-bench`)
- [x] Pill panel with live waveform (non-activating, all Spaces, over fullscreen) — checked visually
- [x] Pill draggable + remembered position + double-click reset — tested
- [x] Menu bar item (status, recent, paste last, polish toggle, settings, quit)
- [ ] Use it daily for a bit

### Phase 2 — Polish
- [x] Confirm Foundation Models is available; measure polish latency on M1
- [x] `FoundationModelsPolisher` + prompt tuned with `speak-bench cases` (plain text + worked examples)
- [x] App-aware style (`AppStyle.forBundleID`)
- [x] Fallbacks: timeout, refusal/error, too-much-rewrite guard; skip polish for short clean phrases
- [x] Personal dictionary → transcriber contextual strings + polish prompt
- [x] `Bench/polish-cases.json` (15 cases) + `speak-bench cases`

### Phase 3 — Feel
- [x] Double-tap Fn → hands-free; Fn again to stop
- [x] Esc cancels; Fn + other key cancels
- [x] Start/stop sounds (toggle in Settings)
- [x] History in menu bar (click to copy, "Paste last")
- [x] Settings window: microphone, dictionary, launch at login (`SMAppService`)
- [x] Smart spacing: add a leading space when the caret follows a non-space character (read via AX)
- [ ] Mid-sentence capitalization ("and Hey…" when dictating after existing text) — decide after hands-on use
- [ ] Optional: FluidAudio engine + bake-off on ~20 of my own clips (WER + latency), keep the winner

### Later / maybe
- [ ] Cloud engines
- [ ] Command mode (select text, speak an edit)
- [ ] Snippets

## Log

- 2026-10-07 — Plan agreed. VS Code 1.139 uses `nemotron-3.5-asr-streaming-0.6b` (ONNX via Foundry
  Local); CoreML conversions exist from FluidInference.
- 2026-10-07 — Scaffold built (app + SpeakKit). 19 unit tests pass. `speak-bench` transcription on synthetic
  speech: ~0.2s from end of audio to final text when streamed in real time; first-run cold start was 1.4s,
  fixed by warming the model at launch. Foundation Models still `modelNotReady` (downloading).
- 2026-10-07 — Independent review (2 rounds) fixed: event tap moved to its own thread; Fn state resync when
  macOS re-enables the tap; 5-min recording cap; finish() timeout; overlapping dictations allowed with pastes
  kept in spoken order; serialized clipboard paste/restore; 200 ms tail capture; paste skipped (copied instead)
  if the frontmost app changed; notices queued until visible. Still needs hands-on: pill double-click reset.
- 2026-10-07 — First hands-on run (automated with synthetic Fn/mouse events + `say` through the speakers).
  Passed: hold Fn → paste (0.42 s release → transcript incl. 200 ms tail), double-tap hands-free, Esc cancel
  (hold and hands-free), Fn+arrow cancel, single tap ignored, smart spacing, clipboard restored, copy-instead
  when the app changes, paste into Notes, pill drag/remember/double-click reset, menu, Settings.
  Fixed during testing: Settings opened behind other apps and scrolled; pill reset didn't move the window.
  Note for test harnesses: macOS 27 drops synthetic key events created without a `CGEventSource`.
  Apple Intelligence still `modelNotReady`; Settings only shows a "Siri" pane on this macOS 27 build.
- 2026-10-07 — Real-keyboard double-tap bug: after a quick Fn tap, macOS emits a synthetic Globe keyDown
  (keycode 179) that was treated as "another key" → cancel. Now ignored. Also: events are now timestamped on
  the tap thread (main-thread stalls had made a quick tap look like a hold), and Core Audio is warmed at
  launch (first mic start 0.7 s → 0.2 s).
- 2026-10-08 — Apple Intelligence model downloaded. Real dictations were timing out (4 of 6 > 2 s) with guided
  generation (~3 s/sentence on M1). Switched to plain-text output + worked examples in the instructions
  (processed during prewarm on Fn down): typical polish now 0.4–0.9 s. Timeout now 2 s + 10 ms/char (max 8 s);
  model prewarmed at launch. Known weak spots: code style invents snake_case identifiers; ordinals ("1st")
  and some mis-hearings ("docks") aren't fixed; email isn't reflowed into paragraphs.
