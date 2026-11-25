#pragma once

#include <chrono>
#include <cstdint>
#include <string>

namespace sotto {
using Seconds = std::chrono::duration<double>;

struct Transcript {
  std::string finalized;
  std::string tentative;

  [[nodiscard]] bool empty() const { return finalized.empty() && tentative.empty(); }
  [[nodiscard]] std::string full() const;
};

enum class Failure : std::uint8_t {
  MicrophoneAccessDenied,
  MicrophoneSilent,
  APIKeyMissing,
  APIKeyRejected,
  ServiceUnavailable,
};

class Recognizer {
 public:
  class Listener {
   public:
    Listener() = default;
    Listener(const Listener&) = delete;
    Listener& operator=(const Listener&) = delete;
    Listener(Listener&&) = delete;
    Listener& operator=(Listener&&) = delete;

    virtual void heard(Transcript transcript) = 0;
    virtual void level_changed(float level) = 0;
    virtual void finished(std::string text) = 0;
    virtual void failed(Failure reason) = 0;

   protected:
    ~Listener() = default;
  };

  Recognizer() = default;
  Recognizer(const Recognizer&) = delete;
  Recognizer& operator=(const Recognizer&) = delete;
  Recognizer(Recognizer&&) = delete;
  Recognizer& operator=(Recognizer&&) = delete;
  virtual ~Recognizer() = default;

  virtual void start(Listener& listener) = 0;
  virtual void finish() = 0;
};

}
