#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DictationHUD : NSObject
@property(nonatomic) CGFloat level;

- (void)showListeningWithFinalized:(NSString *)finalized tentative:(NSString *)tentative;
- (void)showProcessingWithText:(NSString *)text;
- (void)showFinishedWithText:(NSString *)text;
- (void)showMessageWithSymbolName:(NSString *)symbolName message:(NSString *)message;
- (void)dismiss;
@end

NS_ASSUME_NONNULL_END
