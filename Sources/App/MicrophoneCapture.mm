#import "MicrophoneCapture.h"

#import <AVFoundation/AVFoundation.h>

#include <algorithm>
#include <cmath>
#include <span>

static const float kQuietDecibels = -55;
static const float kLoudDecibels = -10;

static float Level(std::span<const int16_t> samples) {
  double sum = 0;
  for (int16_t sample : samples) sum += double(sample) * sample;
  const float rms = static_cast<float>(std::sqrt(sum / samples.size()) / 32768.0);
  const float decibels = 20 * std::log10(std::max(rms, 1e-6f));
  return std::clamp((decibels - kQuietDecibels) / (kLoudDecibels - kQuietDecibels), 0.0f, 1.0f);
}

@interface MicrophoneCapture () <AVCaptureAudioDataOutputSampleBufferDelegate>
@end

@implementation MicrophoneCapture {
  NSString *_deviceUID;
  double _sampleRate;
  MicrophoneCaptureHandler _handler;
  AVCaptureSession *_session;
  dispatch_queue_t _queue;
  BOOL _running;
}

+ (void)requestAccess:(void (^)(BOOL granted))completion {
  switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]) {
    case AVAuthorizationStatusAuthorized:
      return completion(YES);
    case AVAuthorizationStatusNotDetermined:
      return [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(granted); });
      }];
    default:
      return completion(NO);
  }
}

- (instancetype)initWithDeviceUID:(NSString *)deviceUID sampleRate:(double)sampleRate handler:(MicrophoneCaptureHandler)handler {
  if (!(self = [super init])) return nil;
  _deviceUID = [deviceUID copy];
  _sampleRate = sampleRate;
  _handler = [handler copy];
  _queue = dispatch_queue_create("sotto.microphone", DISPATCH_QUEUE_SERIAL);
  return self;
}

- (AVCaptureDevice *)device {
  AVCaptureDevice *chosen = _deviceUID.length ? [AVCaptureDevice deviceWithUniqueID:_deviceUID] : nil;
  return chosen ?: [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
}

- (BOOL)start {
  AVCaptureDevice *device = [self device];
  NSError *error = nil;
  AVCaptureDeviceInput *input = device ? [AVCaptureDeviceInput deviceInputWithDevice:device error:&error] : nil;
  if (!input) {
    NSLog(@"Sotto: no usable microphone: %@", error.localizedDescription);
    return NO;
  }

  AVCaptureAudioDataOutput *output = [AVCaptureAudioDataOutput new];
  output.audioSettings = @{
    AVFormatIDKey : @(kAudioFormatLinearPCM),
    AVSampleRateKey : @(_sampleRate),
    AVNumberOfChannelsKey : @1,
    AVLinearPCMBitDepthKey : @16,
    AVLinearPCMIsFloatKey : @NO,
    AVLinearPCMIsBigEndianKey : @NO,
    AVLinearPCMIsNonInterleaved : @NO,
  };
  [output setSampleBufferDelegate:self queue:_queue];

  AVCaptureSession *session = [AVCaptureSession new];
  if (![session canAddInput:input] || ![session canAddOutput:output]) return NO;
  [session addInput:input];
  [session addOutput:output];
  _session = session;
  _running = YES;
  dispatch_async(_queue, ^{ [session startRunning]; });
  return YES;
}

- (void)stop {
  _running = NO;
  AVCaptureSession *session = _session;
  _session = nil;
  if (session) dispatch_async(_queue, ^{ [session stopRunning]; });
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
  CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sampleBuffer);
  const size_t sampleCount = block ? CMBlockBufferGetDataLength(block) / sizeof(int16_t) : 0;
  if (sampleCount == 0) return;
  NSMutableData *pcm = [NSMutableData dataWithLength:sampleCount * sizeof(int16_t)];
  if (CMBlockBufferCopyDataBytes(block, 0, pcm.length, pcm.mutableBytes) != kCMBlockBufferNoErr) return;

  const float level = Level({static_cast<const int16_t *>(pcm.bytes), sampleCount});
  __weak MicrophoneCapture *weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    MicrophoneCapture *self = weakSelf;
    if (self && self->_running) self->_handler(pcm, level);
  });
}

@end
