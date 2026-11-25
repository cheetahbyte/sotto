#import "OpenAIRealtimeRecognizer.h"

#import <AVFoundation/AVFoundation.h>

#include <algorithm>
#include <cmath>

using Listener = sotto::Recognizer::Listener;

static NSString *const kEndpoint = @"wss://api.openai.com/v1/realtime?intent=transcription";
static NSString *const kModel = @"gpt-live-transcribe";
static const double kSampleRate = 24000;  // mono 16-bit PCM, as configured in the session
// How long to wait for the final transcript after the audio is committed.
static const NSTimeInterval kSettleTimeout = 10;
static const NSUInteger kBatchBytes = 4800;  // 100 ms of audio

// Does the work: microphone capture, the WebSocket, and the event
// protocol. Everything except the capture callback runs on the main queue.
@interface OpenAIRealtimeClient : NSObject <NSURLSessionWebSocketDelegate, AVCaptureAudioDataOutputSampleBufferDelegate>
- (instancetype)initWithOptions:(const OpenAIRealtimeRecognizer::Options &)options;
- (void)startWithListener:(Listener *)listener;
- (void)finish;
- (void)invalidate;  // stops everything; no callbacks afterwards
@end

@implementation OpenAIRealtimeClient {
  NSString *_apiKey;
  NSString *_language;
  NSArray<NSString *> *_keywords;
  Listener *_listener;  // null once the dictation ended

  NSURLSession *_urlSession;
  NSURLSessionWebSocketTask *_socket;
  AVCaptureSession *_capture;
  dispatch_queue_t _captureQueue;

  BOOL _sessionReady;                       // the service accepted the configuration
  NSMutableArray<NSData *> *_pendingAudio;  // captured before the session was ready
  BOOL _capturedAudio;
  BOOL _heardSound;  // any sample that wasn't zero
  NSMutableData *_batch;  // audio not yet sent
  NSUInteger _chunkCount;
  float _peakLevel;
  NSString *_inputDeviceUID;
  BOOL _finishRequested;

  // Transcript text per conversation item, in order of appearance.
  NSMutableArray<NSString *> *_itemOrder;
  NSMutableDictionary<NSString *, NSString *> *_itemText;
  NSMutableSet<NSString *> *_settledItems;  // completed or failed
  NSString *_committedItem;                 // the item made by our final commit
}

- (instancetype)initWithOptions:(const OpenAIRealtimeRecognizer::Options &)options {
  if (!(self = [super init])) return nil;
  _apiKey = @(options.api_key.c_str());
  _inputDeviceUID = @(options.input_device_uid.c_str());
  _language = @(options.language.c_str());
  NSMutableArray *keywords = [NSMutableArray new];
  NSCharacterSet *forbidden = [NSCharacterSet characterSetWithCharactersInString:@"<>\r\n"];
  for (const std::string &keyword : options.keywords) {
    NSString *word = @(keyword.c_str());
    // The API rejects the whole configuration over one bad keyword.
    if (word.length && [word rangeOfCharacterFromSet:forbidden].location == NSNotFound) [keywords addObject:word];
  }
  _keywords = keywords;
  _pendingAudio = [NSMutableArray new];
  _batch = [NSMutableData new];
  _itemOrder = [NSMutableArray new];
  _itemText = [NSMutableDictionary new];
  _settledItems = [NSMutableSet new];
  return self;
}

- (void)startWithListener:(Listener *)listener {
  _listener = listener;
  if (_apiKey.length == 0) return [self endWithFailure:sotto::Failure::APIKeyMissing];

  switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]) {
    case AVAuthorizationStatusAuthorized:
      return [self begin];
    case AVAuthorizationStatusNotDetermined: {
      __weak OpenAIRealtimeClient *weakSelf = self;
      [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
          OpenAIRealtimeClient *self = weakSelf;
          if (!self || !self->_listener) return;
          granted ? [self begin] : [self endWithFailure:sotto::Failure::MicrophoneAccessDenied];
        });
      }];
      return;
    }
    default:
      return [self endWithFailure:sotto::Failure::MicrophoneAccessDenied];
  }
}

- (void)begin {
  // Capture starts at once; audio waits in _pendingAudio while the
  // connection is being set up, so the first words aren't lost.
  if (![self startCapture]) return [self endWithFailure:sotto::Failure::MicrophoneAccessDenied];

  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kEndpoint]];
  [request setValue:[@"Bearer " stringByAppendingString:_apiKey] forHTTPHeaderField:@"Authorization"];
  _urlSession = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration
                                              delegate:self
                                         delegateQueue:NSOperationQueue.mainQueue];
  _socket = [_urlSession webSocketTaskWithRequest:request];
  [_socket resume];
  [self receiveNextEvent];
}

- (void)finish {
  if (!_listener || _finishRequested) return;
  _finishRequested = YES;
  [self stopCapture];
  NSLog(@"Sotto: captured %lu audio chunks, peak level %.2f", (unsigned long)_chunkCount, _peakLevel);
  if (!_capturedAudio) return [self endWithText];
  // Exact digital silence means a dead input, like a MacBook's own
  // microphone while the lid is closed. Say so; don't transcribe nothing.
  if (!_heardSound) return [self endWithFailure:sotto::Failure::MicrophoneSilent];
  [self flushBatch];
  if (_sessionReady) [self commit];  // otherwise once the session is ready

  __weak OpenAIRealtimeClient *weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSettleTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    OpenAIRealtimeClient *self = weakSelf;
    if (!self || !self->_listener) return;
    NSLog(@"Sotto: no final transcript after %.0f s", kSettleTimeout);
    [self transcript].length ? [self endWithText] : [self endWithFailure:sotto::Failure::ServiceUnavailable];
  });
}

- (void)invalidate {
  _listener = nullptr;
  [self stopCapture];
  [_socket cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
  [_urlSession invalidateAndCancel];  // also releases the session's hold on self
  _socket = nil;
  _urlSession = nil;
}

// Both of these end the dictation. The listener may destroy the
// recognizer in response, so nothing touches self afterwards.
- (void)endWithText {
  Listener *listener = _listener;
  if (!listener) return;
  NSString *text = [self transcript];
  [self invalidate];
  listener->finished(text.UTF8String);
}

- (void)endWithFailure:(sotto::Failure)reason {
  Listener *listener = _listener;
  if (!listener) return;
  [self invalidate];
  listener->failed(reason);
}

#pragma mark Microphone

// A capture session hands over audio from the chosen device already
// converted to the wire format.
- (BOOL)startCapture {
  AVCaptureDevice *device = _inputDeviceUID.length ? [AVCaptureDevice deviceWithUniqueID:_inputDeviceUID] : nil;
  if (!device) device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];  // also when the chosen one is unplugged
  NSError *error = nil;
  AVCaptureDeviceInput *input = device ? [AVCaptureDeviceInput deviceInputWithDevice:device error:&error] : nil;
  if (!input) {
    NSLog(@"Sotto: no usable microphone: %@", error.localizedDescription);
    return NO;
  }

  AVCaptureAudioDataOutput *output = [AVCaptureAudioDataOutput new];
  output.audioSettings = @{
    AVFormatIDKey : @(kAudioFormatLinearPCM),
    AVSampleRateKey : @(kSampleRate),
    AVNumberOfChannelsKey : @1,
    AVLinearPCMBitDepthKey : @16,
    AVLinearPCMIsFloatKey : @NO,
    AVLinearPCMIsBigEndianKey : @NO,
    AVLinearPCMIsNonInterleaved : @NO,
  };
  _captureQueue = dispatch_queue_create("sotto.capture", DISPATCH_QUEUE_SERIAL);
  [output setSampleBufferDelegate:self queue:_captureQueue];

  _capture = [AVCaptureSession new];
  if (![_capture canAddInput:input] || ![_capture canAddOutput:output]) return NO;
  [_capture addInput:input];
  [_capture addOutput:output];
  AVCaptureSession *capture = _capture;
  dispatch_async(_captureQueue, ^{ [capture startRunning]; });  // blocks until the device runs
  return YES;
}

- (void)stopCapture {
  AVCaptureSession *capture = _capture;
  _capture = nil;
  if (capture) dispatch_async(_captureQueue, ^{ [capture stopRunning]; });
}

// Runs on the capture queue.
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
  CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sampleBuffer);
  const size_t length = block ? CMBlockBufferGetDataLength(block) : 0;
  if (length < sizeof(int16_t)) return;
  NSMutableData *pcm = [NSMutableData dataWithLength:length - length % sizeof(int16_t)];
  if (CMBlockBufferCopyDataBytes(block, 0, pcm.length, pcm.mutableBytes) != kCMBlockBufferNoErr) return;

  auto samples = static_cast<const int16_t *>(pcm.bytes);
  const size_t count = pcm.length / sizeof(int16_t);
  double sum = 0;
  for (size_t i = 0; i < count; ++i) sum += double(samples[i]) * samples[i];
  const float rms = static_cast<float>(std::sqrt(sum / count) / 32768.0);
  // Map roughly -55...-10 dBFS, quiet room to loud speech, onto 0...1.
  const float level = std::clamp((20 * std::log10(std::max(rms, 1e-6f)) + 55) / 45, 0.0f, 1.0f);
  const BOOL sound = sum > 0;
  __weak OpenAIRealtimeClient *weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf captured:pcm level:level sound:sound]; });
}

- (void)captured:(NSData *)pcm level:(float)level sound:(BOOL)sound {
  if (!_listener || _finishRequested) return;
  _capturedAudio = YES;
  _heardSound |= sound;
  _chunkCount += 1;
  _peakLevel = std::max(_peakLevel, level);
  _listener->level_changed(level);
  // The device delivers a few milliseconds at a time; send about ten
  // messages a second instead of hundreds.
  [_batch appendData:pcm];
  if (_batch.length >= kBatchBytes) [self flushBatch];
}

- (void)flushBatch {
  if (_batch.length == 0) return;
  NSData *pcm = [_batch copy];
  _batch.length = 0;
  _sessionReady ? [self sendAudio:pcm] : [_pendingAudio addObject:pcm];
}

#pragma mark Protocol

- (void)send:(NSDictionary *)event {
  NSData *json = [NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
  NSString *string = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
  [_socket sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithString:string] completionHandler:^(NSError *) {
    // A broken connection is reported once, through the session delegate.
  }];
}

- (void)sendAudio:(NSData *)pcm {
  [self send:@{@"type" : @"input_audio_buffer.append", @"audio" : [pcm base64EncodedStringWithOptions:0]}];
}

// Ends the audio turn; the service answers with the final transcript.
- (void)commit { [self send:@{@"type" : @"input_audio_buffer.commit"}]; }

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
          // This model has no server-side turn detection; the turn ends when we commit.
          @"turn_detection" : NSNull.null,
        }
      }
    }
  }];
}

- (void)receiveNextEvent {
  __weak OpenAIRealtimeClient *weakSelf = self;
  [_socket receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      OpenAIRealtimeClient *self = weakSelf;
      if (!self || !self->_listener || error) return;  // errors arrive through the delegate
      NSData *json = message.type == NSURLSessionWebSocketMessageTypeString ? [message.string dataUsingEncoding:NSUTF8StringEncoding] : message.data;
      NSDictionary *event = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
      if ([event isKindOfClass:NSDictionary.class]) [self handle:event];
      if (self->_listener) [self receiveNextEvent];
    });
  }];
}

- (void)handle:(NSDictionary *)event {
  NSString *type = event[@"type"];
  NSString *item = event[@"item_id"];

  if ([type isEqualToString:@"session.updated"]) {
    _sessionReady = YES;
    for (NSData *pcm in _pendingAudio) [self sendAudio:pcm];
    [_pendingAudio removeAllObjects];
    if (_finishRequested) [self commit];

  } else if ([type isEqualToString:@"conversation.item.input_audio_transcription.delta"]) {
    [self setText:[(_itemText[item] ?: @"") stringByAppendingString:event[@"delta"] ?: @""] forItem:item];

  } else if ([type isEqualToString:@"conversation.item.input_audio_transcription.completed"]) {
    [self setText:event[@"transcript"] ?: @"" forItem:item];
    [_settledItems addObject:item];
    [self endIfSettled];

  } else if ([type isEqualToString:@"conversation.item.input_audio_transcription.failed"]) {
    [_settledItems addObject:item];
    [self endIfSettled];

  } else if ([type isEqualToString:@"input_audio_buffer.committed"]) {
    _committedItem = item;
    [self endIfSettled];

  } else if ([type isEqualToString:@"error"]) {
    NSLog(@"Sotto: OpenAI Realtime error: %@", event[@"error"][@"message"]);
    // A wrong key is reported here, after the connection opens, not as an HTTP status.
    if ([event[@"error"][@"code"] isEqual:@"invalid_api_key"]) return [self endWithFailure:sotto::Failure::APIKeyRejected];
    // After finishing, the usual cause is too little audio to commit:
    // keep what was heard. Before that the session is unusable.
    _finishRequested ? [self endWithText] : [self endWithFailure:sotto::Failure::ServiceUnavailable];
  }
}

- (void)setText:(NSString *)text forItem:(NSString *)item {
  if (!item) return;
  if (!_itemText[item]) [_itemOrder addObject:item];
  _itemText[item] = text;
  // Deltas only ever add text, so it is shown as settled.
  if (_listener) _listener->heard({.finalized = [self transcript].UTF8String, .tentative = {}});
}

- (NSString *)transcript {
  NSMutableArray *parts = [NSMutableArray new];
  for (NSString *item in _itemOrder) {
    NSString *text = [_itemText[item] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length) [parts addObject:text];
  }
  return [parts componentsJoinedByString:@" "];
}

// Completion events aren't ordered, so wait for the one that belongs to our commit.
- (void)endIfSettled {
  if (_finishRequested && _committedItem && [_settledItems containsObject:_committedItem]) [self endWithText];
}

#pragma mark Connection loss

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
  if (!_listener) return;
  NSLog(@"Sotto: OpenAI Realtime connection ended: %@", error.localizedDescription);
  [self transcript].length ? [self endWithText] : [self endWithFailure:sotto::Failure::ServiceUnavailable];
}

@end

#pragma mark - Recognizer

OpenAIRealtimeRecognizer::OpenAIRealtimeRecognizer(Options options)
    : client_([[OpenAIRealtimeClient alloc] initWithOptions:options]) {}

OpenAIRealtimeRecognizer::~OpenAIRealtimeRecognizer() { [client_ invalidate]; }

void OpenAIRealtimeRecognizer::start(Listener& listener) { [client_ startWithListener:&listener]; }

void OpenAIRealtimeRecognizer::finish() { [client_ finish]; }
