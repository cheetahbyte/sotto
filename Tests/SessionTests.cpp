#include "Session.hpp"

#include <cstdlib>
#include <print>
#include <source_location>
#include <string_view>

using namespace sotto;
using namespace std::chrono_literals;

namespace {
int& failures() {
  static int count = 0;
  return count;
}

void check(bool ok, std::string_view what, std::source_location at = std::source_location::current()) {
  if (ok) return;
  ++failures();
  std::println(stderr, "FAIL line {}: {}", at.line(), what);
}

template <class T>
bool is(const Session& session) {
  return std::holds_alternative<T>(session.phase());
}

void run(Session& session, Seconds duration) {
  for (Seconds t{}; t < duration; t += 10ms) session.advance(10ms);
}

struct Probe {
  Recognizer::Listener* listener = nullptr;
  bool finish_requested = false;
  bool destroyed = false;
};

class FakeRecognizer final : public Recognizer {
 public:
  explicit FakeRecognizer(Probe& probe, bool fail_on_start = false) : probe_(&probe), fail_on_start_(fail_on_start) {}
  FakeRecognizer(const FakeRecognizer&) = delete;
  FakeRecognizer& operator=(const FakeRecognizer&) = delete;
  FakeRecognizer(FakeRecognizer&&) = delete;
  FakeRecognizer& operator=(FakeRecognizer&&) = delete;
  ~FakeRecognizer() override { probe_->destroyed = true; }

  void start(Listener& listener) override {
    probe_->listener = &listener;
    if (fail_on_start_) listener.failed(Failure::APIKeyMissing);
  }
  void finish() override { probe_->finish_requested = true; }

 private:
  Probe* probe_;
  bool fail_on_start_;
};

void begin(Session& session, Probe& probe) {
  check(session.start(std::make_unique<FakeRecognizer>(probe)).has_value(), "start from idle");
}

void transitions_are_checked() {
  Probe probe, ignored;
  Session session;
  check(session.stop().error() == TransitionError::NotListening, "stop when idle is rejected");
  check(session.start(std::make_unique<FakeRecognizer>(probe)).has_value(), "start from idle");
  check(session.start(std::make_unique<FakeRecognizer>(ignored)).error() == TransitionError::AlreadyActive,
        "second start is rejected");
  check(session.listening() && session.capturing() && session.active(), "listening after start");
}

void dictation_runs_from_listening_to_finished() {
  Probe probe;
  Session session;
  begin(session, probe);

  const auto before = session.revision();
  probe.listener->level_changed(0.5f);
  check(session.revision() == before, "level alone is not a revision");
  probe.listener->heard({.finalized = "Hello", .tentative = "wor"});
  check(session.revision() != before, "new text is a revision");
  auto* listening = std::get_if<Listening>(&session.phase());
  check(listening && listening->transcript.full() == "Hello wor" && listening->level == 0.5f, "listener updates listening");

  check(session.stop().has_value(), "stop while listening");
  check(probe.finish_requested, "stop asks the recognizer to finish");
  auto* processing = std::get_if<Processing>(&session.phase());
  check(processing && processing->text == "Hello wor", "processing shows the text so far");
  check(session.capturing() && !session.listening(), "processing still holds the recognizer");
  run(session, 30s);
  check(is<Processing>(session), "the session doesn't time out on its own");

  probe.listener->finished("Hello world.");
  auto* finished = std::get_if<Finished>(&session.phase());
  check(finished && finished->text == "Hello world.", "the recognizer's final text wins");
  check(!probe.destroyed, "recognizer survives its own callback");
  session.advance(10ms);
  check(probe.destroyed, "and is destroyed afterwards");
  run(session, 2s);
  check(is<Idle>(session), "finished clears by itself");
}

void nothing_said_returns_to_idle() {
  Probe probe;
  Session session;
  begin(session, probe);
  check(session.stop().has_value(), "stop while listening");
  probe.listener->finished("");
  check(is<Idle>(session), "empty text means no result");
}

void failures_are_shown_then_cleared() {
  Probe probe, failing;
  Session session;
  begin(session, probe);
  probe.listener->failed(Failure::ServiceUnavailable);
  auto* failed = std::get_if<Failed>(&session.phase());
  check(failed && failed->reason == Failure::ServiceUnavailable, "failure is shown");
  run(session, 5s);
  check(is<Idle>(session) && probe.destroyed, "failure clears by itself");

  check(session.start(std::make_unique<FakeRecognizer>(failing, true)).has_value(), "start succeeds");
  check(is<Failed>(session), "a recognizer may fail inside start()");
}

void cancel_destroys_the_recognizer() {
  Probe probe;
  Session session;
  begin(session, probe);
  session.cancel();
  check(is<Idle>(session), "cancel returns to idle");
  check(probe.destroyed, "cancel lets the recognizer go at once");
}

}

int main() {
  try {
    transitions_are_checked();
    dictation_runs_from_listening_to_finished();
    nothing_said_returns_to_idle();
    failures_are_shown_then_cleared();
    cancel_destroys_the_recognizer();
    if (failures() == 0) std::println("all session tests passed");
    return failures() == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
  } catch (...) {
    return EXIT_FAILURE;
  }
}
