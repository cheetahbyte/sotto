#pragma once

#include <cstdint>
#include <expected>
#include <memory>
#include <string>
#include <utility>
#include <variant>

#include "Recognizer.hpp"

// One dictation at a time, from the first word to the inserted text. The
// session owns the phases the interface shows; a Recognizer supplies the
// words.
namespace sotto {

enum class TransitionError { AlreadyActive, NotListening };

struct Idle {};
struct Listening {
  Transcript transcript;
  float level = 0;  // input level, 0...1
};
struct Processing {  // listening is over, the recognizer is settling the text
  std::string text;
};
struct Finished {
  std::string text;
};
struct Failed {
  Failure reason;
};
using Phase = std::variant<Idle, Listening, Processing, Finished, Failed>;

template <class... Fs>
struct overloaded : Fs... {
  using Fs::operator()...;
};

class Session final : private Recognizer::Listener {
 public:
  Session() = default;
  Session(const Session&) = delete;
  Session& operator=(const Session&) = delete;

  // Begins dictating with `recognizer`, which the session keeps until the
  // dictation ends.
  auto start(std::unique_ptr<Recognizer> recognizer) -> std::expected<void, TransitionError>;
  // Ends listening. The session shows Processing until the recognizer
  // delivers the text, then Finished for a moment, then returns to Idle.
  // With nothing said it returns to Idle directly.
  auto stop() -> std::expected<void, TransitionError>;
  void cancel();
  void fail(Failure reason);

  // Call regularly while active. Moves Finished and Failed on to Idle and
  // gives the recognizer its clock.
  void advance(Seconds dt);

  [[nodiscard]] const Phase& phase() const { return phase_; }
  [[nodiscard]] bool active() const { return !std::holds_alternative<Idle>(phase_); }
  // Changes when the phase or the transcript changes, not on level updates.
  [[nodiscard]] std::uint64_t revision() const { return revision_; }

  template <class Self, class... Fs>
  decltype(auto) match(this Self&& self, Fs&&... fs) {
    return std::visit(overloaded{std::forward<Fs>(fs)...}, std::forward<Self>(self).phase_);
  }

 private:
  void heard(Transcript transcript) override;
  void level_changed(float level) override;
  void speech_ended() override;
  void finished(std::string text) override;
  void failed(Failure reason) override;

  void enter(Phase next);

  std::unique_ptr<Recognizer> recognizer_;
  // A recognizer may end the dictation from inside its own member
  // function, so it is destroyed later, from advance().
  std::unique_ptr<Recognizer> retired_;
  Seconds in_phase_{};
  Phase phase_ = Idle{};
  std::uint64_t revision_ = 0;
};

}  // namespace sotto
