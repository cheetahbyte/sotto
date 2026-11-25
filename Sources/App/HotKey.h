#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// A system-wide key combination. Uses Carbon hot keys, which need no
// privacy permission. Unregisters when deallocated.
@interface HotKey : NSObject
// keyCode is a virtual key code (kVK_*), modifiers are Carbon modifier
// flags (optionKey, cmdKey, ...). Returns nil if the combination is taken.
- (nullable instancetype)initWithKeyCode:(uint32_t)keyCode
                               modifiers:(uint32_t)modifiers
                                 pressed:(void (^)(void))pressed
                                released:(nullable void (^)(void))released;
@end

NS_ASSUME_NONNULL_END
