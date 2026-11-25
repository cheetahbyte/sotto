#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Secrets in the login keychain, under this app's bundle identifier.
NSString *_Nullable KeychainRead(NSString *account);
// Passing nil or an empty string removes the entry.
void KeychainWrite(NSString *account, NSString *_Nullable secret);

NS_ASSUME_NONNULL_END
