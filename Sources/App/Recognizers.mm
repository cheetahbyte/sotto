#import "Recognizers.h"

#import "Defaults.h"
#import "Keychain.h"
#import "OpenAIRealtimeRecognizer.h"

using Factory = std::unique_ptr<sotto::Recognizer> (*)(RecognizerService *service);

static std::unique_ptr<sotto::Recognizer> MakeOpenAIRealtime(RecognizerService *service) {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  OpenAIRealtimeRecognizer::Options options;
  options.api_key = (service.apiKey ?: @"").UTF8String;
  options.input_device_uid = ([defaults stringForKey:kMicrophoneKey] ?: @"").UTF8String;
  options.language = SottoLanguageCode([defaults stringForKey:kLanguageKey]).UTF8String;
  for (NSString *word in [defaults stringArrayForKey:kVocabularyKey]) options.keywords.push_back(word.UTF8String);
  return std::make_unique<OpenAIRealtimeRecognizer>(std::move(options));
}

@implementation RecognizerService {
  Factory _factory;
  NSString *_cachedAPIKey;
  BOOL _didReadAPIKey;
}

+ (instancetype)serviceWithIdentifier:(NSString *)identifier
                                title:(NSString *)title
                         privacyTitle:(NSString *)privacyTitle
                       privacySummary:(NSString *)privacySummary
                              factory:(Factory)factory {
  RecognizerService *service = [self new];
  service->_identifier = identifier;
  service->_title = title;
  service->_privacyTitle = privacyTitle;
  service->_privacySummary = privacySummary;
  service->_factory = factory;
  return service;
}

+ (NSArray<RecognizerService *> *)all {
  static NSArray *services = @[
    [self serviceWithIdentifier:@"openai-realtime"
                          title:@"OpenAI Realtime"
                   privacyTitle:@"Your voice is sent to OpenAI"
                 privacySummary:(@"While you dictate, Sotto sends the audio from your microphone to OpenAI to turn it "
                                 @"into text, using your API key. Sotto doesn’t store audio.")
                        factory:&MakeOpenAIRealtime],
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
