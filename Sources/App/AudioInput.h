#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// A microphone or other sound input connected to this Mac.
@interface AudioInputDevice : NSObject
@property(nonatomic, readonly) NSString *uid;  // stable across restarts; saved in defaults
@property(nonatomic, readonly) NSString *name;

@property(class, nonatomic, readonly) NSArray<AudioInputDevice *> *all;
@end

NS_ASSUME_NONNULL_END
