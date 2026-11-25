#pragma once

#include <string>
#include <string_view>
#include <vector>

#include "Recognizer.hpp"

namespace sotto {

// Hears nothing: replays a script word by word with voice-like timing
// and levels, then reports the end of speech. For demos and tests.
class ScriptedRecognizer final : public Recognizer {
 public:
  explicit ScriptedRecognizer(std::string script);

  void start(Listener& listener) override;
  void finish() override;
  void advance(Seconds dt) override;

 private:
  void hear_next_word();
  [[nodiscard]] Transcript transcript() const;

  std::string script_;
  std::vector<std::string_view> words_;
  Listener* listener_ = nullptr;
  std::size_t heard_ = 0;
  std::size_t finalized_ = 0;
  Seconds elapsed_{};
  Seconds until_next_word_{};
  Seconds silence_{};
  Seconds finishing_{};
  bool finishing_requested_ = false;
  bool reported_end_ = false;
  double energy_ = 0;
  float level_ = 0;
};

}  // namespace sotto
