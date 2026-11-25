#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HotKey : NSObject
- (nullable instancetype)initWithKeyCode:(uint32_t)keyCode
                               modifiers:(uint32_t)modifiers
                                 pressed:(void (^)())pressed
                                released:(nullable void (^)())released;
@end

NS_ASSUME_NONNULL_END
