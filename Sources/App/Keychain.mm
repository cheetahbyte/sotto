#import "Keychain.h"

#import <Security/Security.h>

#import "Defaults.h"

static NSMutableDictionary *Query(NSString *account) {
  return [@{
    (id)kSecClass : (id)kSecClassGenericPassword,
    (id)kSecAttrService : OrEmpty(NSBundle.mainBundle.bundleIdentifier),
    (id)kSecAttrAccount : account,
  } mutableCopy];
}

NSString *KeychainRead(NSString *account) {
  NSMutableDictionary *query = Query(account);
  query[(id)kSecReturnData] = @YES;
  CFTypeRef result = nullptr;
  if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess) return nil;
  NSData *data = CFBridgingRelease(result);
  if (!data) return nil;
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

void KeychainWrite(NSString *account, NSString *secret) {
  SecItemDelete((__bridge CFDictionaryRef)Query(account));
  if (secret.length == 0) return;
  NSMutableDictionary *item = Query(account);
  item[(id)kSecValueData] = [secret dataUsingEncoding:NSUTF8StringEncoding];
  const OSStatus status = SecItemAdd((__bridge CFDictionaryRef)item, nullptr);
  if (status != errSecSuccess) NSLog(@"Sotto: could not save to the keychain (%d)", (int)status);
}
