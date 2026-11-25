#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSString *_Nullable KeychainRead(NSString *account);
void KeychainWrite(NSString *account, NSString *_Nullable secret);

NS_ASSUME_NONNULL_END
