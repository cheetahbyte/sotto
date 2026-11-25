#pragma once

#include <cstdint>
#include <expected>
#include <memory>
#include <string>
#include <utility>
#include <variant>

#include "Recognizer.hpp"

namespace sotto {
enum class TransitionError { AlreadyActive, NotListening };

struct Idle {};
struct Listening {
  Transcript transcript;
  float level = 0;
};
struct Processing {
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

  auto start(std::unique_ptr<Recognizer> recognizer) -> std::expected<void, TransitionError>;
  auto stop() -> std::expected<void, TransitionError>;
  void cancel();
  void advance(Seconds dt);

  [[nodiscard]] const Phase& phase() const { return phase_; }
  [[nodiscard]] bool active() const { return !std::holds_alternative<Idle>(phase_); }
  [[nodiscard]] bool listening() const { return std::holds_alternative<Listening>(phase_); }
  [[nodiscard]] bool capturing() const { return listening() || std::holds_alternative<Processing>(phase_); }
  [[nodiscard]] std::uint64_t revision() const { return revision_; }

  template <class Self, class... Fs>
  decltype(auto) match(this Self&& self, Fs&&... fs) {
    return std::visit(overloaded{std::forward<Fs>(fs)...}, std::forward<Self>(self).phase_);
  }

 private:
  void heard(Transcript transcript) override;
  void level_changed(float level) override;
  void finished(std::string text) override;
  void failed(Failure reason) override;

  void enter(Phase next);

  std::unique_ptr<Recognizer> recognizer_;
  std::unique_ptr<Recognizer> retired_;
  Seconds in_phase_{};
  Phase phase_ = Idle{};
  std::uint64_t revision_ = 0;
};

}
