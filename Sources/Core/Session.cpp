#include "Session.hpp"

namespace sotto {
namespace {
constexpr Seconds kFinishedLinger{1.1};
constexpr Seconds kFailedLinger{2.8};

}

std::string Transcript::full() const {
  if (finalized.empty()) return tentative;
  if (tentative.empty()) return finalized;
  return finalized + ' ' + tentative;
}

auto Session::start(std::unique_ptr<Recognizer> recognizer) -> std::expected<void, TransitionError> {
  if (active()) return std::unexpected(TransitionError::AlreadyActive);
  retired_.reset();
  recognizer_ = std::move(recognizer);
  enter(Listening{});
  recognizer_->start(*this);
  return {};
}

auto Session::stop() -> std::expected<void, TransitionError> {
  auto* listening = std::get_if<Listening>(&phase_);
  if (!listening) return std::unexpected(TransitionError::NotListening);
  enter(Processing{listening->transcript.full()});
  recognizer_->finish();
  return {};
}

void Session::cancel() {
  if (active()) enter(Idle{});
  retired_.reset();
}

void Session::advance(Seconds dt) {
  retired_.reset();
  in_phase_ += dt;
  const bool lingered = (std::holds_alternative<Finished>(phase_) && in_phase_ >= kFinishedLinger) ||
                        (std::holds_alternative<Failed>(phase_) && in_phase_ >= kFailedLinger);
  if (lingered) enter(Idle{});
}

void Session::heard(Transcript transcript) {
  auto* listening = std::get_if<Listening>(&phase_);
  if (!listening) return;
  listening->transcript = std::move(transcript);
  ++revision_;
}

void Session::level_changed(float level) {
  if (auto* listening = std::get_if<Listening>(&phase_)) listening->level = level;
}

void Session::finished(std::string text) {
  if (text.empty()) {
    enter(Idle{});
  } else {
    enter(Finished{std::move(text)});
  }
}

void Session::failed(Failure reason) { enter(Failed{reason}); }

void Session::enter(Phase next) {
  phase_ = std::move(next);
  if (!capturing() && recognizer_) retired_ = std::move(recognizer_);
  in_phase_ = Seconds{};
  ++revision_;
}

}
