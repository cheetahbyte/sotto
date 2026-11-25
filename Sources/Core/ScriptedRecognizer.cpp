#include "ScriptedRecognizer.hpp"

#include <algorithm>
#include <cmath>
#include <ranges>
#include <utility>

namespace sotto {
namespace {

constexpr Seconds kLeadIn{0.45};
constexpr Seconds kSilenceBeforeEnd{1.1};
constexpr Seconds kSettling{0.7};

bool ends_clause(std::string_view word) {
  return !word.empty() && std::string_view{".,?!;:"}.contains(word.back());
}

Seconds time_to_say(std::string_view word) {
  return Seconds{0.11 + 0.028 * static_cast<double>(word.size()) + (ends_clause(word) ? 0.28 : 0.0)};
}

std::string join(std::ranges::input_range auto&& words) {
  std::string out;
  for (std::string_view word : words) {
    if (!out.empty()) out += ' ';
    out += word;
  }
  return out;
}

}  // namespace

ScriptedRecognizer::ScriptedRecognizer(std::string script) : script_(std::move(script)) {
  words_ = script_ | std::views::split(' ') |
           std::views::transform([](auto&& part) { return std::string_view{part}; }) |
           std::views::filter([](std::string_view word) { return !word.empty(); }) |
           std::ranges::to<std::vector>();
}

void ScriptedRecognizer::start(Listener& listener) {
  listener_ = &listener;
  until_next_word_ = kLeadIn;
}

void ScriptedRecognizer::finish() { finishing_requested_ = true; }

void ScriptedRecognizer::advance(Seconds dt) {
  if (!listener_) return;

  if (finishing_requested_) {
    finishing_ += dt;
    if (finishing_ >= kSettling) {
      Listener* listener = std::exchange(listener_, nullptr);
      listener->finished(transcript().full());  // may destroy this recognizer
    }
    return;
  }

  elapsed_ += dt;
  until_next_word_ -= dt;
  bool heard_something = false;
  while (heard_ < words_.size() && until_next_word_ <= Seconds{}) {
    hear_next_word();
    heard_something = true;
  }
  if (heard_something) listener_->heard(transcript());

  // A voice-like level: each word is a burst that decays, with some wobble.
  const bool speaking = heard_ > 0 && heard_ < words_.size();
  energy_ *= std::exp(-dt.count() * 4.5);
  const double t = elapsed_.count();
  const double wobble = 0.5 + 0.25 * std::sin(t * 17.0) + 0.25 * std::sin(t * 29.0 + 1.3);
  const double target = speaking ? 0.18 + 0.8 * energy_ * (0.55 + 0.45 * wobble) : 0.04 + 0.5 * energy_;
  const double blend = 1.0 - std::exp(-dt.count() * 16.0);
  level_ = std::clamp(static_cast<float>(level_ + (target - level_) * blend), 0.0f, 1.0f);
  listener_->level_changed(level_);

  silence_ = heard_ == words_.size() ? silence_ + dt : Seconds{};
  if (silence_ >= kSilenceBeforeEnd && !reported_end_) {
    reported_end_ = true;
    listener_->speech_ended();
  }
}

void ScriptedRecognizer::hear_next_word() {
  const std::string_view word = words_[heard_++];
  // A clause boundary settles everything said so far. Otherwise only the
  // last two words stay open to revision.
  if (ends_clause(word)) {
    finalized_ = heard_;
  } else if (heard_ - finalized_ > 4) {
    finalized_ = heard_ - 2;
  }
  until_next_word_ += time_to_say(word);
  energy_ = 1.0;
}

Transcript ScriptedRecognizer::transcript() const {
  return {.finalized = join(words_ | std::views::take(finalized_)),
          .tentative = join(words_ | std::views::take(heard_) | std::views::drop(finalized_))};
}

}  // namespace sotto
