#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioInputDevice : NSObject
@property(nonatomic, readonly) NSString *uid;
@property(nonatomic, readonly) NSString *name;

@property(class, nonatomic, readonly) NSArray<AudioInputDevice *> *all;
@end

NS_ASSUME_NONNULL_END
