# Sotto

A voice dictation tool for macOS, designed the way the Human Interface
Guidelines suggest Apple would build one. It transcribes with OpenAI
Realtime and pastes the finished text into the app you're typing in.

## Build and run

Requires macOS 26 or later (Liquid Glass), Xcode command line tools, and CMake.

```sh
cmake -S . -B build -DSOTTO_CODESIGN_IDENTITY="Apple Development"
cmake --build build -j
ctest --test-dir build        # tests for the C++ models
open build/Sotto.app
```

The signing identity is optional. Without it the build is signed ad hoc,
and macOS asks again for keychain and microphone access after each rebuild.

Choose Settings > Dictation and enter an OpenAI API key. The key is kept in
your keychain. Sotto asks for the microphone on the first dictation and for
Accessibility the first time it inserts text.

Hold ⌥Space while you speak, or press it twice to dictate hands-free and
once more to finish. Escape cancels. You can also choose Start Dictation
from the microphone in the menu bar. Settings > Dictation changes the
shortcut (a key with modifiers, or modifier keys alone such as Right
Command) and the shortcut mode: Hold or Double-Tap, Hold, Tap, Double-Tap.

## Layout

| Path | Contents |
|---|---|
| `Sources/Core` | C++23, no Apple headers: the dictation session, the `Recognizer` interface, and the shortcut gesture. |
| `Sources/App` | Objective-C++ and AppKit: menu bar extra, dictation HUD, settings, welcome window, and the OpenAI Realtime recognizer. |
| `Tests` | Tests for the C++ models. |

## Adding a speech service

A speech service is a subclass of `sotto::Recognizer`
(`Sources/Core/Recognizer.hpp`). It gets a listener, reports text and input
level while it listens, and ends with `finished` or `failed`. The session
and the interface know nothing else about it.

1. Derive from `sotto::Recognizer`, as `OpenAIRealtimeRecognizer` does.
   `MicrophoneCapture` delivers audio from the chosen input as 16-bit mono
   PCM at the sample rate you ask for.
2. Add an entry to `RecognizerService.all` in `Sources/App/Recognizers.mm`
   with a title, its privacy text, and a function that builds the recognizer
   from the current settings.

The service then appears in Settings, with its own keychain entry.

## Design decisions and the guidance behind them

- **Menu bar extra with a menu, not a popover.** A template SF Symbol that
  fills while listening. People can hide it in Settings; opening the app
  again then shows Settings.
- **Small glass capsule instead of a window.** It sits at the bottom center
  of the active screen, never takes focus or clicks, and holds no controls.
  Color is limited to label colors. Words the recognizer may still revise
  are dimmer than settled ones.
- **Settings window with toolbar panes.** The title follows the pane, the
  last pane is restored, the window resizes to the pane, and minimize and
  zoom are unavailable.
- **Permissions asked in context.** The welcome window explains each
  permission before asking, after showing what the app does.
- **Accessibility.** Reduce Motion replaces the slide and bounce with a
  fade and stills the waveform ripple; state changes are announced to
  VoiceOver because the capsule never takes focus.
