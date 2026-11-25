#import <Foundation/Foundation.h>

#include <string>

static inline NSString *OrEmpty(NSString *string) { return string ? string : @""; }

static inline std::string StdString(NSString *string) {
  const char *utf8 = string.UTF8String;
  return utf8 ? std::string{utf8} : std::string{};
}
