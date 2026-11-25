#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Puts dictated text into whatever app has keyboard focus.
@interface TextInserter : NSObject
// Whether macOS lets Sotto type into other apps (the Accessibility permission).
@property(class, nonatomic, readonly) BOOL isAllowed;
// Shows the system alert that leads to Privacy & Security > Accessibility.
+ (void)requestPermission;

// Inserts `text` at the insertion point of the frontmost app and returns
// YES. Without permission it leaves `text` on the clipboard, asks for
// permission, and returns NO.
+ (BOOL)insert:(NSString *)text;
@end

NS_ASSUME_NONNULL_END
