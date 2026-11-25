#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// Menu titles for the shortcut modes, in the order of sotto::ShortcutMode.
NSArray<NSString *> *ShortcutModeTitles(void);
NSString *ShortcutModeSummary(NSInteger mode);

// Shows the saved shortcut the way a text field would. Click it (or press
// Space when it has focus) and type a new shortcut: a key with modifiers,
// or modifier keys alone, pressed and let go. Escape cancels.
@interface ShortcutRecorderView : NSView
@end

NS_ASSUME_NONNULL_END
