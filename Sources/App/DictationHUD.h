#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// The dictation indicator: a small Liquid Glass capsule at the bottom
// center of the screen. It never takes focus or mouse events, so typing
// continues in the app being dictated into. Each show... call brings the
// HUD on screen if needed.
@interface DictationHUD : NSObject
@property(nonatomic) CGFloat level;  // input level 0...1, drives the waveform

- (void)showListeningWithFinalized:(NSString *)finalized tentative:(NSString *)tentative;
- (void)showProcessingWithText:(NSString *)text;
- (void)showFinishedWithText:(NSString *)text;
- (void)showMessageWithSymbolName:(NSString *)symbolName message:(NSString *)message;
- (void)dismiss;
@end

NS_ASSUME_NONNULL_END
