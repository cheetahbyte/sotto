#import "FeedbackSound.h"

#import <AppKit/AppKit.h>

#import "Defaults.h"

FeedbackSoundName const FeedbackSoundStart = @"start";
FeedbackSoundName const FeedbackSoundStop = @"stop";
FeedbackSoundName const FeedbackSoundCancel = @"cancel";
FeedbackSoundName const FeedbackSoundError = @"error";

static const float kVolume = 0.5;

static NSSound *Sound(FeedbackSoundName name) {
  static NSMutableDictionary<NSString *, NSSound *> *loaded = [NSMutableDictionary new];
  if (!loaded[name]) {
    NSURL *url = [NSBundle.mainBundle URLForResource:name withExtension:@"wav" subdirectory:@"Sounds"];
    NSSound *sound = url ? [[NSSound alloc] initWithContentsOfURL:url byReference:YES] : nil;
    sound.volume = kVolume;
    loaded[name] = sound;
  }
  return loaded[name];
}

void PlayFeedbackSound(FeedbackSoundName name) {
  if (![NSUserDefaults.standardUserDefaults boolForKey:kPlaySoundsKey]) return;
  NSSound *sound = Sound(name);
  [sound stop];
  [sound play];
}
