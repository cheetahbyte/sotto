#import <Foundation/Foundation.h>

#include <string>
#include <vector>

#include "Recognizer.hpp"

@class OpenAIRealtimeClient;

// Streams the microphone to an OpenAI Realtime transcription session and
// reports the text as it arrives.
// https://developers.openai.com/api/docs/guides/realtime-transcription
class OpenAIRealtimeRecognizer final : public sotto::Recognizer {
 public:
  struct Options {
    std::string api_key;
    std::string language;               // ISO 639-1, or empty to let the model decide
    std::vector<std::string> keywords;  // names and terms to spell as given
    std::string input_device_uid;       // empty: the system default input
  };

  explicit OpenAIRealtimeRecognizer(Options options);
  ~OpenAIRealtimeRecognizer() override;

  void start(Listener& listener) override;
  void finish() override;

 private:
  OpenAIRealtimeClient *client_;
};
