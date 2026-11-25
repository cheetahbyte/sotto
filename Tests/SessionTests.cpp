#include "ScriptedRecognizer.hpp"
#include "Session.hpp"

#include <cstdlib>
#include <print>
#include <source_location>

using namespace sotto;
using namespace std::chrono_literals;

namespace {

int failures = 0;

void check(bool ok, std::string_view what, std::source_location at = std::source_location::current()) {
  if (ok) return;
  ++failures;
  std::println(stderr, "FAIL line {}: {}", at.line(), what);
}

template <class T>
bool is(const Session& session) {
  return std::holds_alternative<T>(session.phase());
}

void run(Session& session, Seconds duration) {
  for (Seconds t{}; t < duration; t += 10ms) session.advance(10ms);
}

auto scripted(std::string script) { return std::make_unique<ScriptedRecognizer>(std::move(script)); }

// A recognizer the test drives by hand, like a network service would.
struct ManualRecognizer final : Recognizer {
  struct Probe {
    Listener* listener = nullptr;
    bool finish_requested = false;
    bool destroyed = false;
  };
  explicit ManualRecognizer(Probe& probe, bool fail_on_start = false) : probe(probe), fail_on_start(fail_on_start) {}
  ~ManualRecognizer() override { probe.destroyed = true; }
  void start(Listener& listener) override {
    probe.listener = &listener;
    if (fail_on_start) listener.failed(Failure::APIKeyMissing);
  }
  void finish() override { probe.finish_requested = true; }
  Probe& probe;
  bool fail_on_start;
};

void scripted_run_reaches_finished_with_whole_script() {
  Session session;
  check(session.start(scripted("Hello there, this is a test.")).has_value(), "start from idle");
  check(session.start(scripted("Ignored")).error() == TransitionError::AlreadyActive, "second start is rejected");

  std::string finished;
  bool saw_tentative = false, saw_processing = false;
  for (int i = 0; i < 2000 && session.active(); ++i) {
    session.advance(10ms);
    session.match(
        [&](const Listening& l) {
          saw_tentative |= !l.transcript.tentative.empty();
          check(l.level >= 0 && l.level <= 1, "level in range");
        },
        [&](const Processing&) { saw_processing = true; },
        [&](const Finished& f) { finished = f.text; },
        [](const auto&) {});
  }
  check(saw_tentative, "tentative words appear while listening");
  check(saw_processing, "processing precedes finished");
  check(finished == "Hello there, this is a test.", "finished text is the script");
  check(is<Idle>(session), "returns to idle by itself");
}

void scripted_clause_end_finalizes_everything() {
  Session session;
  (void)session.start(scripted("One two, three"));
  for (int i = 0; i < 500; ++i) {
    session.advance(10ms);
    if (auto* l = std::get_if<Listening>(&session.phase()); l && l->transcript.finalized == "One two,") {
      check(l->transcript.tentative.empty() || l->transcript.tentative == "three", "words after comma are tentative");
      return;
    }
  }
  check(false, "never saw the clause finalized");
}

void stop_without_words_goes_idle() {
  Session session;
  (void)session.start(scripted("Late words"));
  session.advance(50ms);
  check(session.stop().has_value(), "stop while listening");
  check(is<Processing>(session), "waits for the recognizer");
  run(session, 1s);
  check(is<Idle>(session), "nothing heard means no result");
  check(session.stop().error() == TransitionError::NotListening, "stop when idle is rejected");
}

void early_stop_keeps_partial_text() {
  Session session;
  (void)session.start(scripted("Alpha beta gamma delta epsilon zeta eta theta"));
  run(session, 1.2s);
  (void)session.stop();
  auto* processing = std::get_if<Processing>(&session.phase());
  check(processing && processing->text.starts_with("Alpha") && processing->text.size() < 45, "partial text shown");
  run(session, 1s);
  auto* finished = std::get_if<Finished>(&session.phase());
  check(finished && finished->text.starts_with("Alpha"), "partial text delivered");
}

void recognizer_drives_the_session() {
  ManualRecognizer::Probe probe;
  Session session;
  (void)session.start(std::make_unique<ManualRecognizer>(probe));
  const auto before = session.revision();
  probe.listener->level_changed(0.5f);
  check(session.revision() == before, "level alone is not a revision");
  probe.listener->heard({.finalized = "Hello", .tentative = "wor"});
  check(session.revision() != before, "new text is a revision");
  auto* listening = std::get_if<Listening>(&session.phase());
  check(listening && listening->transcript.full() == "Hello wor" && listening->level == 0.5f, "listener updates listening");

  (void)session.stop();
  check(probe.finish_requested, "stop asks the recognizer to finish");
  check(is<Processing>(session), "processing until the text arrives");
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

void recognizer_can_end_on_its_own_or_fail() {
  ManualRecognizer::Probe probe;
  Session session;
  (void)session.start(std::make_unique<ManualRecognizer>(probe));
  probe.listener->speech_ended();
  check(is<Processing>(session) && probe.finish_requested, "end of speech stops the session");
  probe.listener->failed(Failure::ServiceUnavailable);
  auto* failed = std::get_if<Failed>(&session.phase());
  check(failed && failed->reason == Failure::ServiceUnavailable, "failure is shown");
  run(session, 5s);
  check(is<Idle>(session) && probe.destroyed, "failure clears by itself");

  ManualRecognizer::Probe failing;
  check(session.start(std::make_unique<ManualRecognizer>(failing, true)).has_value(), "start succeeds");
  check(is<Failed>(session), "a recognizer may fail inside start()");
}

void cancel_destroys_the_recognizer() {
  ManualRecognizer::Probe probe;
  Session session;
  (void)session.start(std::make_unique<ManualRecognizer>(probe));
  session.cancel();
  check(is<Idle>(session), "cancel returns to idle");
  check(probe.destroyed, "cancel lets the recognizer go at once");

  session.fail(Failure::MicrophoneAccessDenied);
  check(is<Failed>(session), "a failure can be shown without a recognizer");
}

}  // namespace

int main() {
  scripted_run_reaches_finished_with_whole_script();
  scripted_clause_end_finalizes_everything();
  stop_without_words_goes_idle();
  early_stop_keeps_partial_text();
  recognizer_drives_the_session();
  recognizer_can_end_on_its_own_or_fail();
  cancel_destroys_the_recognizer();
  if (failures == 0) std::println("all session tests passed");
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
