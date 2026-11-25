#include "Session.hpp"

namespace sotto {
namespace {

constexpr Seconds kFinishedLinger{1.1};
constexpr Seconds kFailedLinger{2.8};

}  // namespace

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
  recognizer_->start(*this);  // may already fail or finish
  return {};
}

auto Session::stop() -> std::expected<void, TransitionError> {
  auto* listening = std::get_if<Listening>(&phase_);
  if (!listening) return std::unexpected(TransitionError::NotListening);
  enter(Processing{listening->transcript.full()});
  recognizer_->finish();
  return {};
}

// These two come from outside the recognizer, so it can go at once.
void Session::cancel() {
  if (active()) enter(Idle{});
  retired_.reset();
}

void Session::fail(Failure reason) {
  enter(Failed{reason});
  retired_.reset();
}

void Session::advance(Seconds dt) {
  retired_.reset();
  in_phase_ += dt;
  if (recognizer_) recognizer_->advance(dt);
  match(
      [](Idle&) {}, [](Listening&) {}, [](Processing&) {},
      [&](Finished&) {
        if (in_phase_ >= kFinishedLinger) enter(Idle{});
      },
      [&](Failed&) {
        if (in_phase_ >= kFailedLinger) enter(Idle{});
      });
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

void Session::speech_ended() { (void)stop(); }

void Session::finished(std::string text) {
  if (text.empty()) {
    enter(Idle{});
  } else {
    enter(Finished{std::move(text)});
  }
}

void Session::failed(Failure reason) { enter(Failed{reason}); }

// Only Listening and Processing have a recognizer; leaving them lets it go.
void Session::enter(Phase next) {
  const bool keeps_recognizer = std::holds_alternative<Listening>(next) || std::holds_alternative<Processing>(next);
  if (!keeps_recognizer && recognizer_) retired_ = std::move(recognizer_);
  phase_ = std::move(next);
  in_phase_ = Seconds{};
  ++revision_;
}

}  // namespace sotto
