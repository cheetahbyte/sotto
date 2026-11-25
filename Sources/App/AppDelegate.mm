#import "AppDelegate.h"

#import "Defaults.h"
#import "DictationController.h"
#import "Recognizers.h"
#import "SettingsWindowController.h"
#import "StatusItemController.h"
#import "WelcomeWindowController.h"

@implementation AppDelegate {
  DictationController *_dictation;
  StatusItemController *_statusItem;
  SettingsWindowController *_settings;
  WelcomeWindowController *_welcome;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  [NSUserDefaults.standardUserDefaults registerDefaults:@{
    kShowMenuBarExtraKey : @YES,
    kPlaySoundsKey : @YES,
    kLanguageKey : SottoLanguages().firstObject,
    kMicrophoneKey : @"",
    kShortcutModeKey : @(kShortcutModeHoldOrDoubleTap),
    kKeepRecentsKey : @YES,
    kVocabularyKey : @[ @"AppKit", @"Objective-C", @"Cupertino" ],
  }];

  (void)RecognizerService.selected.apiKey;

  NSApp.mainMenu = [self makeMainMenu];
  _dictation = [DictationController new];
  _statusItem = [[StatusItemController alloc] initWithDictation:_dictation];

  if (![NSUserDefaults.standardUserDefaults boolForKey:kDidShowWelcomeKey]) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:kDidShowWelcomeKey];
    [self showWelcome:nil];
  }
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)hasVisibleWindows {
  if (!hasVisibleWindows) [self showSettings:nil];
  return NO;
}

- (IBAction)showSettings:(id)sender {
  if (!_settings) _settings = [SettingsWindowController new];
  [NSApp activate];
  [_settings showWindow:sender];
  [_settings.window orderFrontRegardless];
}

- (IBAction)clearRecents:(id)sender {
  [_dictation clearRecents];
}

- (IBAction)showWelcome:(id)sender {
  if (!_welcome) _welcome = [WelcomeWindowController new];
  [NSApp activate];
  [_welcome showWindow:sender];
  [_welcome.window orderFrontRegardless];
}

- (NSMenu *)makeMainMenu {
  NSMenu *main = [NSMenu new];

  NSMenu *app = [[NSMenu alloc] initWithTitle:@"Sotto"];
  [app addItemWithTitle:@"About Sotto" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
  [app addItem:NSMenuItem.separatorItem];
  [app addItemWithTitle:@"Settings…" action:@selector(showSettings:) keyEquivalent:@","];
  [app addItem:NSMenuItem.separatorItem];
  [app addItemWithTitle:@"Hide Sotto" action:@selector(hide:) keyEquivalent:@"h"];
  NSMenuItem *hideOthers = [app addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
  hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
  [app addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
  [app addItem:NSMenuItem.separatorItem];
  [app addItemWithTitle:@"Quit Sotto" action:@selector(terminate:) keyEquivalent:@"q"];

  NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"];
  [edit addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
  [edit addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
  [edit addItem:NSMenuItem.separatorItem];
  [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
  [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
  [edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
  [edit addItemWithTitle:@"Delete" action:@selector(delete:) keyEquivalent:@""];
  [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];

  NSMenu *window = [[NSMenu alloc] initWithTitle:@"Window"];
  [window addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
  [window addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
  NSApp.windowsMenu = window;

  for (NSMenu *menu in @[ app, edit, window ]) {
    NSMenuItem *item = [main addItemWithTitle:menu.title action:nil keyEquivalent:@""];
    item.submenu = menu;
  }
  return main;
}

@end
