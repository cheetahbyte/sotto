#import <Foundation/Foundation.h>

#include <memory>

#include "Recognizer.hpp"

NS_ASSUME_NONNULL_BEGIN

@interface RecognizerService : NSObject
@property(nonatomic, readonly) NSString *identifier;
@property(nonatomic, readonly) NSString *title;
@property(nonatomic, readonly) NSString *privacyTitle;
@property(nonatomic, readonly) NSString *privacySummary;
@property(nonatomic, copy, nullable) NSString *apiKey;

@property(class, nonatomic, readonly) NSArray<RecognizerService *> *all;
@property(class, nonatomic, strong) RecognizerService *selected;

- (std::unique_ptr<sotto::Recognizer>)makeRecognizer;
@end

NS_ASSUME_NONNULL_END
