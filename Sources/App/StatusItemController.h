#import <AppKit/AppKit.h>

@class DictationController;

NS_ASSUME_NONNULL_BEGIN

@interface StatusItemController : NSObject
- (instancetype)initWithDictation:(DictationController *)dictation;
@end

NS_ASSUME_NONNULL_END
