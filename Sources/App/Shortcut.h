#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const ShortcutDidChangeNotification;
extern NSNotificationName const ShortcutRecordingDidBeginNotification;
extern NSNotificationName const ShortcutRecordingDidEndNotification;

@interface Shortcut : NSObject
+ (instancetype)shortcutWithKeyCode:(NSInteger)keyCode modifiers:(NSEventModifierFlags)modifiers;
+ (instancetype)shortcutWithModifierKeyCodes:(NSArray<NSNumber *> *)keyCodes;

@property(class, nonatomic, strong) Shortcut *current;

@property(nonatomic, readonly) BOOL hasKey;
@property(nonatomic, readonly) NSInteger keyCode;
@property(nonatomic, readonly) NSEventModifierFlags modifiers;
@property(nonatomic, readonly) NSArray<NSNumber *> *modifierKeyCodes;
@property(nonatomic, readonly) NSString *displayString;
@property(nonatomic, readonly) NSString *menuKeyEquivalent;
@end

NSArray<NSNumber *> *ModifierKeyCodesDown(NSEventModifierFlags flags);
NSString *ModifierKeysDisplayString(NSArray<NSNumber *> *keyCodes);

@interface ShortcutMonitor : NSObject
- (instancetype)initWithPressed:(void (^)(void))pressed released:(void (^)(void))released;
@end

NS_ASSUME_NONNULL_END
