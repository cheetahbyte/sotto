#import "Recognizers.h"

#import "Defaults.h"
#import "Keychain.h"
#import "OpenAIRealtimeRecognizer.h"
#import "ScriptedRecognizer.hpp"

using Factory = std::unique_ptr<sotto::Recognizer> (*)(RecognizerService *service);

static std::unique_ptr<sotto::Recognizer> MakeOpenAIRealtime(RecognizerService *service) {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  OpenAIRealtimeRecognizer::Options options;
  options.api_key = (service.apiKey ?: @"").UTF8String;
  options.input_device_uid = ([NSUserDefaults.standardUserDefaults stringForKey:kMicrophoneKey] ?: @"").UTF8String;
  options.language = SottoLanguageCode([defaults stringForKey:kLanguageKey]).UTF8String;
  for (NSString *word in [defaults stringArrayForKey:kVocabularyKey]) options.keywords.push_back(word.UTF8String);
  return std::make_unique<OpenAIRealtimeRecognizer>(std::move(options));
}

static std::unique_ptr<sotto::Recognizer> MakeDemo(RecognizerService *) {
  static NSArray<NSString *> *scripts = @[
    (@"Hey Sam, thanks for sending the draft over. I read it on the train this morning, and I think the second "
     @"section is much stronger now."),
    (@"Remind me to book the flights to Lisbon before Friday, and ask Mira whether she still wants the window seat."),
    @"The quick answer is yes. We can ship it this week, as long as the review is done by Wednesday.",
  ];
  static NSUInteger next = 0;
  return std::make_unique<sotto::ScriptedRecognizer>(scripts[next++ % scripts.count].UTF8String);
}

@implementation RecognizerService {
  Factory _factory;
  // The keychain can stop to ask for permission, so it is read once and
  // not while a dictation starts.
  NSString *_cachedAPIKey;
  BOOL _didReadAPIKey;
}

+ (instancetype)serviceWithIdentifier:(NSString *)identifier
                                title:(NSString *)title
                           usesAPIKey:(BOOL)usesAPIKey
                          insertsText:(BOOL)insertsText
                         privacyTitle:(NSString *)privacyTitle
                       privacySummary:(NSString *)privacySummary
                              factory:(Factory)factory {
  RecognizerService *service = [self new];
  service->_identifier = identifier;
  service->_title = title;
  service->_usesAPIKey = usesAPIKey;
  service->_insertsText = insertsText;
  service->_privacyTitle = privacyTitle;
  service->_privacySummary = privacySummary;
  service->_factory = factory;
  return service;
}

+ (NSArray<RecognizerService *> *)all {
  static NSArray *services = @[
    [self serviceWithIdentifier:@"openai-realtime"
                          title:@"OpenAI Realtime"
                     usesAPIKey:YES
                    insertsText:YES
                   privacyTitle:@"Your voice is sent to OpenAI"
                 privacySummary:(@"While you dictate, Sotto sends the audio from your microphone to OpenAI to turn it "
                                 @"into text, using your API key. Sotto doesn’t store audio.")
                        factory:&MakeOpenAIRealtime],
    [self serviceWithIdentifier:@"demo"
                          title:@"Demo (Sample Sentences)"
                     usesAPIKey:NO
                    insertsText:NO
                   privacyTitle:@"The demo doesn’t listen"
                 privacySummary:@"Sotto plays back sample sentences. The microphone stays off and nothing is sent anywhere."
                        factory:&MakeDemo],
  ];
  return services;
}

+ (RecognizerService *)selected {
  NSString *identifier = [NSUserDefaults.standardUserDefaults stringForKey:kServiceKey];
  for (RecognizerService *service in self.all) {
    if ([service.identifier isEqualToString:identifier]) return service;
  }
  return self.all.firstObject;
}

+ (void)setSelected:(RecognizerService *)service {
  [NSUserDefaults.standardUserDefaults setObject:service.identifier forKey:kServiceKey];
}

- (NSString *)apiKey {
  if (!_usesAPIKey) return nil;
  if (!_didReadAPIKey) {
    _cachedAPIKey = KeychainRead(_identifier);
    _didReadAPIKey = YES;
  }
  return _cachedAPIKey;
}

- (void)setApiKey:(NSString *)apiKey {
  _cachedAPIKey = [apiKey stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  _didReadAPIKey = YES;
  KeychainWrite(_identifier, _cachedAPIKey);
}

- (std::unique_ptr<sotto::Recognizer>)makeRecognizer { return _factory(self); }

@end
