#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TextInserter : NSObject
@property(class, nonatomic, readonly) BOOL isAllowed;
+ (void)requestPermission;

+ (BOOL)insert:(NSString *)text;
@end

NS_ASSUME_NONNULL_END
