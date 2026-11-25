#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// Posted when the saved shortcut changes.
extern NSNotificationName const ShortcutDidChangeNotification;
// Posted by the recorder so the live shortcut doesn't fire while people
// type a new one.
extern NSNotificationName const ShortcutRecordingDidBeginNotification;
extern NSNotificationName const ShortcutRecordingDidEndNotification;

// The dictation shortcut. Either a key with modifiers (⌥Space), or
// modifier keys alone, where left and right keys are distinct (Right Command).
@interface Shortcut : NSObject
+ (instancetype)shortcutWithKeyCode:(NSInteger)keyCode modifiers:(NSEventModifierFlags)modifiers;
+ (instancetype)shortcutWithModifierKeyCodes:(NSArray<NSNumber *> *)keyCodes;

// The saved shortcut. Setting it saves and posts ShortcutDidChangeNotification.
// Double-tap mode needs a key, so saving a modifier-only shortcut in that
// mode switches the mode to hold or double-tap.
@property(class, nonatomic, strong) Shortcut *current;

@property(nonatomic, readonly) BOOL hasKey;
@property(nonatomic, readonly) NSInteger keyCode;                         // -1 without a key
@property(nonatomic, readonly) NSEventModifierFlags modifiers;            // with a key
@property(nonatomic, readonly) NSArray<NSNumber *> *modifierKeyCodes;     // without a key
@property(nonatomic, readonly) NSString *displayString;                   // "⌥Space" or "Right Command"
@property(nonatomic, readonly) NSString *menuKeyEquivalent;               // "" if a menu can't show it
@end

// Key codes of the modifier keys that are down according to `flags`,
// in display order.
NSArray<NSNumber *> *ModifierKeyCodesDown(NSEventModifierFlags flags);
// "Left Shift + Left Command"
NSString *ModifierKeysDisplayString(NSArray<NSNumber *> *keyCodes);

// Watches for the saved shortcut system-wide and reports presses and
// releases. Follows changes to the shortcut and pauses during recording.
@interface ShortcutMonitor : NSObject
- (instancetype)initWithPressed:(void (^)(void))pressed released:(void (^)(void))released;
@end

NS_ASSUME_NONNULL_END
