#import <Foundation/Foundation.h>

#include <string>
#include <vector>

#include "Recognizer.hpp"

@class OpenAIRealtimeClient;

class OpenAIRealtimeRecognizer final : public sotto::Recognizer {
 public:
  struct Options {
    std::string api_key;
    std::string language;
    std::vector<std::string> keywords;
    std::string input_device_uid;
  };

  explicit OpenAIRealtimeRecognizer(Options options);
  ~OpenAIRealtimeRecognizer() override;

  void start(Listener& listener) override;
  void finish() override;

 private:
  OpenAIRealtimeClient *client_;
};
