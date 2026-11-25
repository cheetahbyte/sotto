#import <Foundation/Foundation.h>

// NSUserDefaults keys. Settings controls bind to these directly.
static NSString *const kShowMenuBarExtraKey = @"ShowMenuBarExtra";
static NSString *const kOpenAtLoginKey = @"OpenAtLogin";
static NSString *const kPlaySoundsKey = @"PlaySounds";
static NSString *const kServiceKey = @"Service";  // a RecognizerService identifier
static NSString *const kLanguageKey = @"Language";
static NSString *const kMicrophoneKey = @"MicrophoneUID";  // empty: the system default input
static NSString *const kShortcutKey = @"DictationShortcut";  // dictionary, see Shortcut
static NSString *const kShortcutModeKey = @"ShortcutMode";  // matches sotto::ShortcutMode
enum : NSInteger { kShortcutModeHoldOrDoubleTap = 0, kShortcutModeDoubleTap = 3 };
static NSString *const kAutoPunctuationKey = @"AutoPunctuation";
static NSString *const kRemoveFillerWordsKey = @"RemoveFillerWords";
static NSString *const kKeepRecentsKey = @"KeepRecents";
static NSString *const kVocabularyKey = @"Vocabulary";
static NSString *const kSettingsPaneKey = @"SettingsPane";
static NSString *const kDidShowWelcomeKey = @"DidShowWelcome";

static inline NSArray<NSString *> *SottoLanguages(void) {
  return @[ @"English (United States)", @"English (United Kingdom)", @"Deutsch (Deutschland)",
            @"Français (France)", @"Español (España)", @"日本語" ];
}
// ISO 639-1 code for a title from SottoLanguages().
static inline NSString *SottoLanguageCode(NSString *title) {
  NSArray<NSString *> *codes = @[ @"en", @"en", @"de", @"fr", @"es", @"ja" ];
  const NSUInteger index = [SottoLanguages() indexOfObject:title ?: @""];
  return index == NSNotFound ? @"" : codes[index];
}
