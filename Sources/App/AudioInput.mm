#import "AudioInput.h"

#import <AVFoundation/AVFoundation.h>

@implementation AudioInputDevice

+ (NSArray<AudioInputDevice *> *)all {
  AVCaptureDeviceDiscoverySession *discovery =
      [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeMicrophone ]
                                                             mediaType:AVMediaTypeAudio
                                                              position:AVCaptureDevicePositionUnspecified];
  NSMutableArray *all = [NSMutableArray new];
  for (AVCaptureDevice *capture in discovery.devices) {
    AudioInputDevice *device = [AudioInputDevice new];
    device->_uid = capture.uniqueID;
    device->_name = capture.localizedName;
    [all addObject:device];
  }
  return all;
}

@end
