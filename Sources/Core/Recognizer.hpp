#pragma once

#include <chrono>
#include <string>

namespace sotto {
using Seconds = std::chrono::duration<double>;

struct Transcript {
  std::string finalized;
  std::string tentative;

  [[nodiscard]] bool empty() const { return finalized.empty() && tentative.empty(); }
  [[nodiscard]] std::string full() const;
};

enum class Failure {
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
    virtual void heard(Transcript transcript) = 0;
    virtual void level_changed(float level) = 0;
    virtual void finished(std::string text) = 0;
    virtual void failed(Failure reason) = 0;

   protected:
    ~Listener() = default;
  };

  virtual ~Recognizer() = default;

  virtual void start(Listener& listener) = 0;
  virtual void finish() = 0;
};

}
