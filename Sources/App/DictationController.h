#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const DictationDidChangeNotification;

// Runs the simulated dictation session and shows it in the HUD. Posts
// DictationDidChangeNotification when `active` or `recents` change.
@interface DictationController : NSObject
@property(nonatomic, readonly, getter=isActive) BOOL active;
@property(nonatomic, readonly) NSArray<NSString *> *recents;  // newest first

- (void)toggle;  // start, or finish if already listening
- (void)cancel;
- (void)clearRecents;
- (void)showMicrophoneFailure;  // mockup aid: shows the error state
@end

NS_ASSUME_NONNULL_END
