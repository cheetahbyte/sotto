#import "StatusItemController.h"

#import "AppDelegate.h"
#import "AudioInput.h"
#import "Defaults.h"
#import "DictationController.h"
#import "Shortcut.h"

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
  // A template symbol, so the system colors it for any menu bar.
  NSImage *image = [NSImage imageWithSystemSymbolName:_dictation.active ? @"mic.fill" : @"mic"
                             accessibilityDescription:_dictation.active ? @"Sotto, listening" : @"Sotto"];
  _item.button.image = image;
}

#pragma mark Menu

- (void)menuNeedsUpdate:(NSMenu *)menu {
  [menu removeAllItems];
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;

  NSMenuItem *toggle = [self item:_dictation.active ? @"Stop Dictation" : @"Start Dictation" action:@selector(toggleDictation:)];
  toggle.keyEquivalent = Shortcut.current.menuKeyEquivalent;
  toggle.keyEquivalentModifierMask = Shortcut.current.modifiers;
  [menu addItem:toggle];
  [menu addItem:NSMenuItem.separatorItem];

  [menu addItem:[self choiceMenu:@"Language" titles:SottoLanguages() key:kLanguageKey]];
  [menu addItem:[self microphoneMenu]];

  NSMenuItem *recent = [self item:@"Recent" action:nil];
  recent.submenu = [NSMenu new];
  for (NSString *text in _dictation.recents) {
    NSString *title = text.length > 48 ? [[text substringToIndex:47] stringByAppendingString:@"…"] : text;
    NSMenuItem *entry = [self item:title action:@selector(copyRecent:)];
    entry.representedObject = text;
    entry.toolTip = @"Copy to Clipboard";
    [recent.submenu addItem:entry];
  }
  if (_dictation.recents.count) [recent.submenu addItem:NSMenuItem.separatorItem];
  [recent.submenu addItem:[self item:@"Clear Menu" action:_dictation.recents.count ? @selector(clearRecents:) : nil]];
  recent.submenu.autoenablesItems = NO;
  recent.submenu.itemArray.lastObject.enabled = _dictation.recents.count > 0;
  recent.hidden = ![defaults boolForKey:kKeepRecentsKey];
  [menu addItem:recent];
  [menu addItem:NSMenuItem.separatorItem];

  NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"Settings…" action:@selector(showSettings:) keyEquivalent:@","];
  settings.target = NSApp.delegate;
  [menu addItem:settings];

  // Not part of the design: shortcuts to states that are otherwise hard to reach.
  NSMenuItem *mockup = [self item:@"Mockup" action:nil];
  mockup.submenu = [NSMenu new];
  NSMenuItem *welcome = [[NSMenuItem alloc] initWithTitle:@"Show Welcome Window" action:@selector(showWelcome:) keyEquivalent:@""];
  welcome.target = NSApp.delegate;
  [mockup.submenu addItem:welcome];
  [mockup.submenu addItem:[self item:@"Show Microphone Error" action:@selector(showFailure:)]];
  [menu addItem:mockup];
  [menu addItem:NSMenuItem.separatorItem];

  [menu addItemWithTitle:@"Quit Sotto" action:@selector(terminate:) keyEquivalent:@"q"];
}

- (NSMenuItem *)item:(NSString *)title action:(SEL)action {
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
  item.target = self;
  return item;
}

- (NSMenuItem *)choiceMenu:(NSString *)title titles:(NSArray<NSString *> *)titles key:(NSString *)key {
  NSMenuItem *parent = [self item:title action:nil];
  parent.submenu = [NSMenu new];
  NSString *current = [NSUserDefaults.standardUserDefaults stringForKey:key];
  for (NSString *choice in titles) {
    NSMenuItem *item = [self item:choice action:@selector(choose:)];
    item.representedObject = key;
    item.state = [choice isEqualToString:current] ? NSControlStateValueOn : NSControlStateValueOff;
    [parent.submenu addItem:item];
  }
  return parent;
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
- (void)showFailure:(id)sender { [_dictation showMicrophoneFailure]; }
- (void)clearRecents:(id)sender { [_dictation clearRecents]; }

- (void)chooseMicrophone:(NSMenuItem *)sender {
  [NSUserDefaults.standardUserDefaults setObject:sender.representedObject forKey:kMicrophoneKey];
}

- (void)choose:(NSMenuItem *)sender {
  [NSUserDefaults.standardUserDefaults setObject:sender.title forKey:sender.representedObject];
}

- (void)copyRecent:(NSMenuItem *)sender {
  [NSPasteboard.generalPasteboard clearContents];
  [NSPasteboard.generalPasteboard setString:sender.representedObject forType:NSPasteboardTypeString];
}

@end
