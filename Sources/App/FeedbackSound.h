#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

using FeedbackSoundName = NSString *;
extern FeedbackSoundName const FeedbackSoundStart;
extern FeedbackSoundName const FeedbackSoundStop;
extern FeedbackSoundName const FeedbackSoundCancel;
extern FeedbackSoundName const FeedbackSoundError;

void PlayFeedbackSound(FeedbackSoundName name);

NS_ASSUME_NONNULL_END
