#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const DictationDidChangeNotification;

@interface DictationController : NSObject
@property(nonatomic, readonly, getter=isActive) BOOL active;
@property(nonatomic, readonly) NSArray<NSString *> *recents;

- (void)toggle;
- (void)cancel;
- (void)clearRecents;
@end

NS_ASSUME_NONNULL_END
