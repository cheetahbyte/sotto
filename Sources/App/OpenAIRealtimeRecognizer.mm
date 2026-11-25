#import "OpenAIRealtimeRecognizer.h"

#include <algorithm>

#import "Defaults.h"
#import "MicrophoneCapture.h"

using Listener = sotto::Recognizer::Listener;

static NSString *const kEndpoint = @"wss://api.openai.com/v1/realtime?intent=transcription";
static NSString *const kModel = @"gpt-live-transcribe";
static const double kSampleRate = 24000;
static const NSUInteger kMessageBytes = 4800;
static const NSTimeInterval kSettleTimeout = 10;

static NSString *const kTranscriptDelta = @"conversation.item.input_audio_transcription.delta";
static NSString *const kTranscriptCompleted = @"conversation.item.input_audio_transcription.completed";
static NSString *const kTranscriptFailed = @"conversation.item.input_audio_transcription.failed";

static BOOL ContainsSound(NSData *pcm) {
  NSData *silence = [NSMutableData dataWithLength:pcm.length];
  return silence && ![pcm isEqualToData:silence];
}

static NSArray<NSString *> *AcceptedKeywords(const std::vector<std::string> &keywords) {
  NSCharacterSet *rejected = [NSCharacterSet characterSetWithCharactersInString:@"<>\r\n"];
  NSMutableArray *accepted = [NSMutableArray new];
  for (const std::string &keyword : keywords) {
    NSString *word = @(keyword.c_str());
    if (word.length && [word rangeOfCharacterFromSet:rejected].location == NSNotFound) [accepted addObject:word];
  }
  return accepted;
}

@interface OpenAIRealtimeClient : NSObject <NSURLSessionWebSocketDelegate>
- (instancetype)initWithOptions:(const OpenAIRealtimeRecognizer::Options &)options;
- (void)startWithListener:(Listener *)listener;
- (void)finish;
- (void)invalidate;
@end

@implementation OpenAIRealtimeClient {
  NSString *_apiKey;
  NSString *_language;
  NSArray<NSString *> *_keywords;
  Listener *_listener;

  MicrophoneCapture *_microphone;
  NSMutableData *_unsentAudio;
  BOOL _capturedAudio;
  BOOL _heardSound;

  NSURLSession *_urlSession;
  NSURLSessionWebSocketTask *_socket;
  BOOL _sessionReady;
  BOOL _finishRequested;

  NSMutableArray<NSString *> *_itemOrder;
  NSMutableDictionary<NSString *, NSString *> *_itemText;
  NSMutableSet<NSString *> *_settledItems;
  NSString *_committedItem;
}

- (instancetype)initWithOptions:(const OpenAIRealtimeRecognizer::Options &)options {
  self = [super init];
  if (!self) return nil;
  _apiKey = @(options.api_key.c_str());
  _language = @(options.language.c_str());
  _keywords = AcceptedKeywords(options.keywords);
  _unsentAudio = [NSMutableData new];
  _itemOrder = [NSMutableArray new];
  _itemText = [NSMutableDictionary new];
  _settledItems = [NSMutableSet new];

  __weak OpenAIRealtimeClient *weakSelf = self;
  _microphone = [[MicrophoneCapture alloc] initWithDeviceUID:@(options.input_device_uid.c_str())
                                                  sampleRate:kSampleRate
                                                     handler:^(NSData *pcm, float level) { [weakSelf captured:pcm level:level]; }];
  return self;
}

#pragma mark Lifecycle

- (void)startWithListener:(Listener *)listener {
  _listener = listener;
  if (_apiKey.length == 0) return [self endWithFailure:sotto::Failure::APIKeyMissing];

  __weak OpenAIRealtimeClient *weakSelf = self;
  [MicrophoneCapture requestAccess:^(BOOL granted) {
    OpenAIRealtimeClient *client = weakSelf;
    if (!client || !client->_listener) return;
    if (!granted || ![client->_microphone start]) return [client endWithFailure:sotto::Failure::MicrophoneAccessDenied];
    [client connect];
  }];
}

- (void)finish {
  if (!_listener || _finishRequested) return;
  _finishRequested = YES;
  [_microphone stop];
  if (!_capturedAudio) return [self endWithText];
  if (!_heardSound) return [self endWithFailure:sotto::Failure::MicrophoneSilent];
  [self sendAudioAndCommitIfReady];

  __weak OpenAIRealtimeClient *weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSettleTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [weakSelf endWithWhateverArrived];
  });
}

- (void)invalidate {
  _listener = nullptr;
  [_microphone stop];
  [_socket cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
  [_urlSession invalidateAndCancel];
  _socket = nil;
  _urlSession = nil;
}

- (void)endWithText {
  Listener *listener = _listener;
  if (!listener) return;
  NSString *text = [self transcript];
  [self invalidate];
  listener->finished(StdString(text));
}

- (void)endWithFailure:(sotto::Failure)reason {
  Listener *listener = _listener;
  if (!listener) return;
  [self invalidate];
  listener->failed(reason);
}

- (void)endWithWhateverArrived {
  [self transcript].length ? [self endWithText] : [self endWithFailure:sotto::Failure::ServiceUnavailable];
}

#pragma mark Audio

- (void)captured:(NSData *)pcm level:(float)level {
  if (!_listener || _finishRequested) return;
  _capturedAudio = YES;
  _heardSound = _heardSound || ContainsSound(pcm);
  _listener->level_changed(level);
  [_unsentAudio appendData:pcm];
  if (_sessionReady) [self sendAudioLeavingRemainder:YES];
}

- (void)sendAudioLeavingRemainder:(BOOL)leaveRemainder {
  NSUInteger sent = 0;
  while (_unsentAudio.length - sent >= (leaveRemainder ? kMessageBytes : 1)) {
    const NSUInteger length = std::min(kMessageBytes, _unsentAudio.length - sent);
    NSData *chunk = [_unsentAudio subdataWithRange:NSMakeRange(sent, length)];
    [self send:@{@"type" : @"input_audio_buffer.append", @"audio" : [chunk base64EncodedStringWithOptions:0]}];
    sent += length;
  }
  [_unsentAudio replaceBytesInRange:NSMakeRange(0, sent) withBytes:nullptr length:0];
}

- (void)sendAudioAndCommitIfReady {
  if (!_sessionReady) return;
  [self sendAudioLeavingRemainder:NO];
  [self send:@{@"type" : @"input_audio_buffer.commit"}];
}

#pragma mark Connection

- (void)connect {
  NSURL *endpoint = [NSURL URLWithString:kEndpoint];
  if (!endpoint) return [self endWithFailure:sotto::Failure::ServiceUnavailable];
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:endpoint];
  [request setValue:[@"Bearer " stringByAppendingString:_apiKey] forHTTPHeaderField:@"Authorization"];
  _urlSession = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration
                                              delegate:self
                                         delegateQueue:NSOperationQueue.mainQueue];
  _socket = [_urlSession webSocketTaskWithRequest:request];
  [_socket resume];
  [self receiveNextEvent];
}

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)task didOpenWithProtocol:(NSString *)protocol {
  NSMutableDictionary *transcription = [@{@"model" : kModel} mutableCopy];
  if (_language.length) transcription[@"languages"] = @[ _language ];
  if (_keywords.count) transcription[@"keywords"] = _keywords;
  [self send:@{
    @"type" : @"session.update",
    @"session" : @{
      @"type" : @"transcription",
      @"audio" : @{
        @"input" : @{
          @"format" : @{@"type" : @"audio/pcm", @"rate" : @(kSampleRate)},
          @"transcription" : transcription,
          @"turn_detection" : NSNull.null,
        }
      }
    }
  }];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
  if (!_listener) return;
  NSLog(@"Sotto: OpenAI Realtime connection ended: %@", error.localizedDescription);
  [self endWithWhateverArrived];
}

- (void)send:(NSDictionary *)event {
  NSData *json = [NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
  if (!json) return;
  NSString *string = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
  [_socket sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithString:string] completionHandler:^(NSError *) {}];
}

- (void)receiveNextEvent {
  __weak OpenAIRealtimeClient *weakSelf = self;
  [_socket receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      OpenAIRealtimeClient *client = weakSelf;
      if (!client || !client->_listener || error) return;
      NSData *json = message.type == NSURLSessionWebSocketMessageTypeString ? [message.string dataUsingEncoding:NSUTF8StringEncoding] : message.data;
      NSDictionary *event = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
      if ([event isKindOfClass:NSDictionary.class]) [client handle:event];
      if (client->_listener) [client receiveNextEvent];
    });
  }];
}

#pragma mark Events

- (void)handle:(NSDictionary *)event {
  NSString *type = event[@"type"];
  NSString *item = event[@"item_id"];

  if ([type isEqualToString:@"session.updated"]) {
    _sessionReady = YES;
    _finishRequested ? [self sendAudioAndCommitIfReady] : [self sendAudioLeavingRemainder:YES];
  } else if ([type isEqualToString:kTranscriptDelta]) {
    [self setText:[OrEmpty(_itemText[item]) stringByAppendingString:OrEmpty(event[@"delta"])] forItem:item];
  } else if ([type isEqualToString:kTranscriptCompleted]) {
    [self setText:OrEmpty(event[@"transcript"]) forItem:item];
    [self settle:item];
  } else if ([type isEqualToString:kTranscriptFailed]) {
    [self settle:item];
  } else if ([type isEqualToString:@"input_audio_buffer.committed"]) {
    _committedItem = item;
    [self endIfSettled];
  } else if ([type isEqualToString:@"error"]) {
    [self handleError:event[@"error"]];
  }
}

- (void)handleError:(NSDictionary *)error {
  NSLog(@"Sotto: OpenAI Realtime error: %@", error[@"message"]);
  if ([error[@"code"] isEqual:@"invalid_api_key"]) return [self endWithFailure:sotto::Failure::APIKeyRejected];
  _finishRequested ? [self endWithText] : [self endWithFailure:sotto::Failure::ServiceUnavailable];
}

- (void)setText:(NSString *)text forItem:(NSString *)item {
  if (!item) return;
  if (!_itemText[item]) [_itemOrder addObject:item];
  _itemText[item] = text;
  if (_listener) _listener->heard({.finalized = StdString([self transcript]), .tentative = {}});
}

- (void)settle:(NSString *)item {
  if (item) [_settledItems addObject:item];
  [self endIfSettled];
}

- (void)endIfSettled {
  if (_finishRequested && _committedItem && [_settledItems containsObject:_committedItem]) [self endWithText];
}

- (NSString *)transcript {
  NSMutableArray *parts = [NSMutableArray new];
  for (NSString *item in _itemOrder) {
    NSString *text = [_itemText[item] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length) [parts addObject:text];
  }
  return [parts componentsJoinedByString:@" "];
}

@end

#pragma mark - Recognizer

OpenAIRealtimeRecognizer::OpenAIRealtimeRecognizer(const Options& options)
    : client_([[OpenAIRealtimeClient alloc] initWithOptions:options]) {}

OpenAIRealtimeRecognizer::~OpenAIRealtimeRecognizer() { [client_ invalidate]; }

void OpenAIRealtimeRecognizer::start(Listener& listener) { [client_ startWithListener:&listener]; }

void OpenAIRealtimeRecognizer::finish() { [client_ finish]; }
