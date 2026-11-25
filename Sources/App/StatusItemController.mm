#import "StatusItemController.h"

#import "AppDelegate.h"
#import "AudioInput.h"
#import "Defaults.h"
#import "DictationController.h"
#import "Shortcut.h"

static const NSUInteger kRecentTitleLength = 48;

@interface StatusItemController () <NSMenuDelegate>
@end

@implementation StatusItemController {
  DictationController *_dictation;
  NSStatusItem *_item;
}

- (instancetype)initWithDictation:(DictationController *)dictation {
  if (!(self = [super init])) return nil;
  _dictation = dictation;

  _item = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
  _item.menu = [NSMenu new];
  _item.menu.delegate = self;
  [self dictationDidChange:nil];

  [NSNotificationCenter.defaultCenter addObserver:self
                                         selector:@selector(dictationDidChange:)
                                             name:DictationDidChangeNotification
                                           object:dictation];
  [NSUserDefaults.standardUserDefaults addObserver:self
                                        forKeyPath:kShowMenuBarExtraKey
                                           options:NSKeyValueObservingOptionInitial
                                           context:nil];
  return self;
}

- (void)dealloc {
  [NSUserDefaults.standardUserDefaults removeObserver:self forKeyPath:kShowMenuBarExtraKey];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
  _item.visible = [NSUserDefaults.standardUserDefaults boolForKey:kShowMenuBarExtraKey];
}

- (void)dictationDidChange:(NSNotification *)notification {
  NSImage *image = [NSImage imageWithSystemSymbolName:_dictation.active ? @"mic.fill" : @"mic"
                             accessibilityDescription:_dictation.active ? @"Sotto, listening" : @"Sotto"];
  _item.button.image = image;
}

#pragma mark Menu

- (void)menuNeedsUpdate:(NSMenu *)menu {
  [menu removeAllItems];
  [menu addItem:[self toggleItem]];
  [menu addItem:NSMenuItem.separatorItem];
  [menu addItem:[self languageMenu]];
  [menu addItem:[self microphoneMenu]];
  [menu addItem:[self recentMenu]];
  [menu addItem:NSMenuItem.separatorItem];
  [menu addItem:[self settingsItem]];
  [menu addItem:NSMenuItem.separatorItem];
  [menu addItemWithTitle:@"Quit Sotto" action:@selector(terminate:) keyEquivalent:@"q"];
}

- (NSMenuItem *)toggleItem {
  NSMenuItem *item = [self item:_dictation.active ? @"Stop Dictation" : @"Start Dictation" action:@selector(toggleDictation:)];
  item.keyEquivalent = Shortcut.current.menuKeyEquivalent;
  item.keyEquivalentModifierMask = Shortcut.current.modifiers;
  return item;
}

- (NSMenuItem *)settingsItem {
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Settings…" action:@selector(showSettings:) keyEquivalent:@","];
  item.target = NSApp.delegate;
  return item;
}

- (NSMenuItem *)recentMenu {
  NSArray<NSString *> *recents = _dictation.recents;
  NSMenuItem *parent = [self item:@"Recent" action:nil];
  parent.hidden = ![NSUserDefaults.standardUserDefaults boolForKey:kKeepRecentsKey];
  parent.submenu = [NSMenu new];
  parent.submenu.autoenablesItems = NO;
  for (NSString *text in recents) {
    NSString *title = text.length > kRecentTitleLength ? [[text substringToIndex:kRecentTitleLength - 1] stringByAppendingString:@"…"] : text;
    NSMenuItem *item = [self item:title action:@selector(copyRecent:)];
    item.representedObject = text;
    item.toolTip = @"Copy to Clipboard";
    [parent.submenu addItem:item];
  }
  if (recents.count) [parent.submenu addItem:NSMenuItem.separatorItem];
  NSMenuItem *clear = [self item:@"Clear Menu" action:@selector(clearRecents:)];
  clear.enabled = recents.count > 0;
  [parent.submenu addItem:clear];
  return parent;
}

- (NSMenuItem *)languageMenu {
  NSMenuItem *parent = [self item:@"Language" action:nil];
  parent.submenu = [NSMenu new];
  NSString *selected = [NSUserDefaults.standardUserDefaults stringForKey:kLanguageKey];
  for (NSString *language in SottoLanguages()) {
    NSMenuItem *item = [self item:language action:@selector(chooseLanguage:)];
    item.state = [language isEqualToString:selected] ? NSControlStateValueOn : NSControlStateValueOff;
    [parent.submenu addItem:item];
  }
  return parent;
}

- (NSMenuItem *)item:(NSString *)title action:(SEL)action {
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
  item.target = self;
  return item;
}

- (NSMenuItem *)microphoneMenu {
  NSMenuItem *parent = [self item:@"Microphone" action:nil];
  parent.submenu = [NSMenu new];
  NSString *selected = [NSUserDefaults.standardUserDefaults stringForKey:kMicrophoneKey] ?: @"";
  NSMutableArray<NSArray<NSString *> *> *choices = [@[ @[ @"System Default", @"" ] ] mutableCopy];
  for (AudioInputDevice *device in AudioInputDevice.all) [choices addObject:@[ device.name, device.uid ]];
  for (NSArray<NSString *> *choice in choices) {
    NSMenuItem *item = [self item:choice[0] action:@selector(chooseMicrophone:)];
    item.representedObject = choice[1];
    item.state = [choice[1] isEqualToString:selected] ? NSControlStateValueOn : NSControlStateValueOff;
    [parent.submenu addItem:item];
  }
  return parent;
}

#pragma mark Actions

- (void)toggleDictation:(id)sender { [_dictation toggle]; }
- (void)clearRecents:(id)sender { [_dictation clearRecents]; }

- (void)chooseMicrophone:(NSMenuItem *)sender {
  [NSUserDefaults.standardUserDefaults setObject:sender.representedObject forKey:kMicrophoneKey];
}

- (void)chooseLanguage:(NSMenuItem *)sender {
  [NSUserDefaults.standardUserDefaults setObject:sender.title forKey:kLanguageKey];
}

- (void)copyRecent:(NSMenuItem *)sender {
  [NSPasteboard.generalPasteboard clearContents];
  [NSPasteboard.generalPasteboard setString:sender.representedObject forType:NSPasteboardTypeString];
}

@end
