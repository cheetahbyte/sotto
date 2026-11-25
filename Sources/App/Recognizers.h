#import <Foundation/Foundation.h>

#include <memory>

#include "Recognizer.hpp"

NS_ASSUME_NONNULL_BEGIN

// The speech services people can choose in Settings. To add one, write a
// sotto::Recognizer subclass and add an entry in Recognizers.mm.
@interface RecognizerService : NSObject
@property(nonatomic, readonly) NSString *identifier;  // saved in defaults
@property(nonatomic, readonly) NSString *title;
@property(nonatomic, readonly) BOOL usesAPIKey;
// Whether finished text is typed into the frontmost app. Off for the demo,
// whose sample sentences nobody wants in their document.
@property(nonatomic, readonly) BOOL insertsText;
// Shown in the Privacy pane: what happens to people's audio.
@property(nonatomic, readonly) NSString *privacyTitle;
@property(nonatomic, readonly) NSString *privacySummary;

@property(class, nonatomic, readonly) NSArray<RecognizerService *> *all;
@property(class, nonatomic, strong) RecognizerService *selected;

// The saved API key for this service, kept in the keychain.
@property(nonatomic, copy, nullable) NSString *apiKey;

// A recognizer for one dictation, configured from the current settings.
- (std::unique_ptr<sotto::Recognizer>)makeRecognizer;
@end

NS_ASSUME_NONNULL_END
