#import <Foundation/Foundation.h>

static NSString *const kShowMenuBarExtraKey = @"ShowMenuBarExtra";
static NSString *const kPlaySoundsKey = @"PlaySounds";
static NSString *const kServiceKey = @"Service";
static NSString *const kLanguageKey = @"Language";
static NSString *const kMicrophoneKey = @"MicrophoneUID";
static NSString *const kShortcutKey = @"DictationShortcut";
static NSString *const kShortcutModeKey = @"ShortcutMode";
enum : NSInteger { kShortcutModeHoldOrDoubleTap = 0, kShortcutModeDoubleTap = 3 };
static NSString *const kKeepRecentsKey = @"KeepRecents";
static NSString *const kVocabularyKey = @"Vocabulary";
static NSString *const kSettingsPaneKey = @"SettingsPane";
static NSString *const kDidShowWelcomeKey = @"DidShowWelcome";

static inline NSArray<NSString *> *SottoLanguages(void) {
  return @[ @"English (United States)", @"English (United Kingdom)", @"Deutsch (Deutschland)",
            @"Français (France)", @"Español (España)", @"日本語" ];
}
static inline NSString *SottoLanguageCode(NSString *title) {
  NSArray<NSString *> *codes = @[ @"en", @"en", @"de", @"fr", @"es", @"ja" ];
  const NSUInteger index = [SottoLanguages() indexOfObject:title ?: @""];
  return index == NSNotFound ? @"" : codes[index];
}
