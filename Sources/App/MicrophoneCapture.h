#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

using MicrophoneCaptureHandler = void (^)(NSData *pcm, float level);

@interface MicrophoneCapture : NSObject
+ (void)requestAccess:(void (^)(BOOL granted))completion;

- (instancetype)initWithDeviceUID:(NSString *)deviceUID sampleRate:(double)sampleRate handler:(MicrophoneCaptureHandler)handler;
- (BOOL)start;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
