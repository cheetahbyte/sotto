#pragma once

#include <chrono>
#include <string>

// The seam between a dictation session and whatever turns speech into
// text. To add a speech service, derive from Recognizer and add it to the
// catalog in Sources/App/Recognizers.mm.
namespace sotto {

using Seconds = std::chrono::duration<double>;

// `finalized` no longer changes; `tentative` may still be rewritten and
// is drawn dimmer.
struct Transcript {
  std::string finalized;
  std::string tentative;

  [[nodiscard]] bool empty() const { return finalized.empty() && tentative.empty(); }
  [[nodiscard]] std::string full() const;
};

enum class Failure {
  MicrophoneAccessDenied,
  MicrophoneSilent,  // audio arrived, but it was pure silence
  APIKeyMissing,
  APIKeyRejected,
  ServiceUnavailable,
};

// One recognizer serves one dictation: it is created, started once, and
// destroyed. Destroying it at any time must stop capture and all
// callbacks; that is how a session cancels.
class Recognizer {
 public:
  // Receives what the recognizer hears. All calls must come on the thread
  // that called start(), and may come from inside start() or finish().
  class Listener {
   public:
    virtual void heard(Transcript transcript) = 0;  // the text so far, replacing earlier calls
    virtual void level_changed(float level) = 0;    // input level, 0...1
    // The speaker seems to be done. Optional; the session then calls finish().
    virtual void speech_ended() = 0;
    // Exactly one of these ends the dictation. Nothing may follow it.
    virtual void finished(std::string text) = 0;  // empty when nothing was said
    virtual void failed(Failure reason) = 0;

   protected:
    ~Listener() = default;
  };

  virtual ~Recognizer() = default;

  // Starts listening. `listener` outlives the recognizer.
  virtual void start(Listener& listener) = 0;
  // Stops listening. The recognizer must then call finished() or failed(),
  // after however long it needs to settle the text.
  virtual void finish() = 0;
  // Time passing, for recognizers that keep their own clock.
  virtual void advance(Seconds) {}
};

}  // namespace sotto
