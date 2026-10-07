# Speak

Hold a key, talk, let go, and tidy text appears wherever your cursor is. A small, private take on
[Wispr Flow](https://wisprflow.ai) for macOS. Speech recognition and cleanup both run on your Mac;
nothing is sent anywhere.

## Requirements

- macOS 27 on Apple Silicon
- English
- Optional: Apple Intelligence turned on, for cleanup (removing "um"s, applying "no wait, Thursday"
  corrections, punctuation). Without it Speak pastes exactly what it heard.

## Using it

| | |
|---|---|
| **Hold fn** | Dictate while held; release to paste |
| **Double-tap fn** | Hands-free: keeps listening until you press fn again |
| **Esc** | Cancel |
| **"new line" / "new paragraph"** | Inserts a line or paragraph break |

The trigger key can be changed to right Option or right Command in Settings (handy for keyboards
without a fn/Globe key). The menu bar icon shows recent dictations: click one to copy it, or hold ⌥
to copy what you actually said before cleanup.

## Setup

On first launch Speak asks for:

- **Microphone**: to hear you while you hold the trigger key. Audio is never saved.
- **Accessibility**: to notice the trigger key and paste where your cursor is.
- **System Settings → Keyboard → "Press 🌐 key to" → Do Nothing**: only if you use fn, so the key
  doesn't also open emoji or dictation.

If another app also listens to the fn/Globe key, pick a different trigger key in one of them.

## Privacy

Audio goes from the microphone straight to Apple's on-device speech recognizer and is discarded.
The last 100 dictations (text only) are kept in `~/Library/Application Support/Speak/history.json`
for the menu; clear them from Settings.

## Building

```sh
open Speak.xcodeproj    # set your own team under Signing & Capabilities, then Run
```

Development notes are in `CLAUDE.md` and the roadmap in `PLAN.md`.
