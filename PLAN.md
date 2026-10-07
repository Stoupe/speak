# Speak — Plan

A tiny, local-only, Wispr Flow–style dictation app for macOS. Hold **Fn** (or double-tap Fn for
hands-free), talk, release, and polished text is pasted into whatever field has focus.

Personal tool: no onboarding, no accounts, no distribution. English only.

## Decisions

| Area | Decision | Why |
|---|---|---|
| Platform | macOS 27, Xcode 27, Swift 6 (strict concurrency), SwiftUI + AppKit where needed | Native, minimal |
| App type | Menu bar only (`LSUIElement`), not sandboxed | Event taps and synthetic keystrokes don't work in the sandbox |
| Project | Plain Xcode project with buildable (folder-synced) groups | No extra tooling |
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
├─ HistoryStore         SwiftData, last ~100 items (text only, no audio)
└─ UI                   PillPanel (NSPanel + SwiftUI glass), MenuBarExtra, Settings form
```

## Progress

### Phase 0 — Scaffold + spikes
- [ ] `git init`, `.gitignore`
- [ ] Xcode project: macOS 27, non-sandboxed, Swift 6, menu bar only, Apple Development signing
- [ ] Set System Settings → Keyboard → "Press 🌐 key to: Do Nothing" (manual)
- [ ] Spike: event tap logs Fn down/up (incl. fullscreen apps, after sleep/wake)
- [ ] Spike: paste a fixed string into Notes, Safari, Slack, VS Code, Terminal; clipboard restored

### Phase 1 — Raw dictation end to end
- [ ] Hold Fn → record → `SpeechTranscriber` (streaming) → paste raw text
- [ ] Pill panel with live waveform (non-activating, all Spaces, over fullscreen)
- [ ] Pill draggable + remembered position + double-click reset
- [ ] Menu bar item (status, Quit)
- [ ] Use it daily for a bit

### Phase 2 — Polish
- [ ] Confirm Foundation Models is available; measure polish latency on M1
- [ ] `FoundationModelsPolisher`: filler removal, self-corrections, punctuation/paragraphs, spoken lists
- [ ] App-aware style via `ContextProvider`
- [ ] Fallbacks: timeout, refusal/error, too-much-rewrite guard; skip polish for short clean phrases
- [ ] Personal dictionary → transcriber custom vocabulary + polish prompt
- [ ] Test target: ~20 raw → expected cases for prompt tuning

### Phase 3 — Feel
- [ ] Double-tap Fn → hands-free; Fn again to stop
- [ ] Esc cancels; Fn + other key cancels
- [ ] Start/stop sounds
- [ ] History in menu bar (click to copy, "Paste last")
- [ ] Settings window: microphone, dictionary, launch at login (`SMAppService`)
- [ ] Optional: FluidAudio engine + bake-off on ~20 of my own clips (WER + latency), keep the winner

### Later / maybe
- [ ] Cloud engines
- [ ] Command mode (select text, speak an edit)
- [ ] Snippets

## Log

- 2026-10-07 — Plan agreed. VS Code 1.139 uses `nemotron-3.5-asr-streaming-0.6b` (ONNX via Foundry
  Local); CoreML conversions exist from FluidInference.
