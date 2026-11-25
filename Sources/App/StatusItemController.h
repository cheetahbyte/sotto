#import <AppKit/AppKit.h>

@class DictationController;

NS_ASSUME_NONNULL_BEGIN

// The menu bar extra. Follows the "Show Sotto in menu bar" setting.
@interface StatusItemController : NSObject
- (instancetype)initWithDictation:(DictationController *)dictation;
@end

NS_ASSUME_NONNULL_END
