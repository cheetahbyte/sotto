# Sotto

Voice dictation for macOS. Hold a shortcut, speak, and Sotto types what you
said into the app you're using. Transcription uses OpenAI Realtime.

## Build

Sotto needs macOS 26 or later, the Xcode command line tools, and CMake.

```sh
cmake -S . -B build
cmake --build build -j
open build/Sotto.app
```

## Set up

1. Open **Settings** from the microphone in the menu bar.
2. In **Dictation**, enter your OpenAI API key and select your microphone.
3. Allow microphone and Accessibility access when macOS asks.

## Dictate

Hold ⌥Space while you speak, or press it twice to dictate hands-free and
once more to finish. Press Escape to cancel. You can change the shortcut and
how it behaves in **Settings**.

## Develop

```sh
ctest --test-dir build
cmake --build build --target tidy
```

The `tidy` target needs clang-tidy from LLVM. To keep keychain and privacy
permissions across rebuilds, configure with a signing identity:

```sh
cmake -S . -B build -DSOTTO_CODESIGN_IDENTITY="Apple Development"
```

To run the tests under sanitizers, configure a separate build directory with
`-DSOTTO_SANITIZE=address,undefined` or `-DSOTTO_SANITIZE=thread`.

The feedback sounds come from Hex. See `THIRD_PARTY_NOTICES.md`.
