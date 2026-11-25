#import "SettingsPanes.h"

#import "AudioInput.h"
#import "Defaults.h"
#import "Recognizers.h"
#import "Shortcut.h"
#import "ShortcutRecorderView.h"

static const CGFloat kPaneWidth = 560;
static const CGFloat kMargin = 20;
static const CGFloat kFootnoteWidth = 320;

static NSArray<NSString *> *ShortcutModeTitles() {
  return @[ @"Hold or Double-Tap", @"Hold", @"Tap", @"Double-Tap" ];
}

static NSString *ShortcutModeSummary(NSInteger mode) {
  return @[
    @"Hold the shortcut while you speak, or press it twice to dictate hands-free.",
    @"Hold the shortcut while you speak and let go to finish.",
    @"Press the shortcut to start dictating and press it again to finish.",
    @"Press the shortcut twice to start dictating and once to finish.",
  ][mode];
}

#pragma mark - Building blocks

static NSString *DefaultsPath(NSString *key) { return [@"values." stringByAppendingString:key]; }

static NSTextField *Label(NSString *text) { return [NSTextField labelWithString:text]; }

static NSTextField *Footnote(NSString *text, CGFloat width) {
  NSTextField *label = [NSTextField wrappingLabelWithString:text];
  label.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
  label.textColor = NSColor.secondaryLabelColor;
  label.preferredMaxLayoutWidth = width;
  return label;
}

static NSButton *Checkbox(NSString *title, NSString *key) {
  NSButton *box = [NSButton checkboxWithTitle:title target:nil action:nil];
  [box bind:NSValueBinding toObject:NSUserDefaultsController.sharedUserDefaultsController withKeyPath:DefaultsPath(key) options:nil];
  return box;
}

static NSPopUpButton *PopUp(NSArray<NSString *> *titles, NSString *key) {
  NSPopUpButton *popUp = [NSPopUpButton new];
  [popUp addItemsWithTitles:titles];
  [popUp bind:NSSelectedValueBinding toObject:NSUserDefaultsController.sharedUserDefaultsController withKeyPath:DefaultsPath(key) options:nil];
  return popUp;
}

static NSView *FormPane(NSArray<NSArray<NSView *> *> *rows) {
  NSGridView *grid = [NSGridView gridViewWithViews:rows];
  grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
  grid.rowSpacing = 8;
  grid.columnSpacing = 8;
  [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
  grid.translatesAutoresizingMaskIntoConstraints = NO;

  NSView *pane = [NSView new];
  [pane addSubview:grid];
  [NSLayoutConstraint activateConstraints:@[
    [pane.widthAnchor constraintEqualToConstant:kPaneWidth],
    [grid.topAnchor constraintEqualToAnchor:pane.topAnchor constant:kMargin],
    [grid.bottomAnchor constraintEqualToAnchor:pane.bottomAnchor constant:-kMargin],
    [grid.centerXAnchor constraintEqualToAnchor:pane.centerXAnchor],
    [grid.leadingAnchor constraintGreaterThanOrEqualToAnchor:pane.leadingAnchor constant:kMargin],
  ]];
  return pane;
}

static NSView *StackPane(NSArray<NSView *> *views) {
  NSStackView *stack = [NSStackView stackViewWithViews:views];
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.spacing = 10;
  stack.edgeInsets = NSEdgeInsetsMake(kMargin, kMargin, kMargin, kMargin);
  [stack.widthAnchor constraintEqualToConstant:kPaneWidth].active = YES;
  return stack;
}

#pragma mark - Panes

@implementation GeneralPane
- (void)loadView {
  self.view = FormPane(@[
    @[ Label(@"Menu bar:"), Checkbox(@"Show Sotto in menu bar", kShowMenuBarExtraKey) ],
    @[ NSGridCell.emptyContentView, Footnote(@"When hidden, open Sotto again to show its settings.", kFootnoteWidth) ],
    @[ Label(@"Sound:"), Checkbox(@"Play sound when dictation starts and ends", kPlaySoundsKey) ],
  ]);
}
@end

@interface DictationPane () <NSTextFieldDelegate>
@end
@implementation DictationPane {
  NSPopUpButton *_service;
  NSSecureTextField *_apiKey;
  NSPopUpButton *_mode;
  NSTextField *_modeSummary;
}

- (void)loadView {
  _service = [NSPopUpButton new];
  for (RecognizerService *service in RecognizerService.all) [_service addItemWithTitle:service.title];
  _service.target = self;
  _service.action = @selector(chooseService:);
  _apiKey = [NSSecureTextField new];
  _apiKey.placeholderString = @"Required";
  _apiKey.delegate = self;
  [_apiKey.widthAnchor constraintEqualToConstant:230].active = YES;
  [self showService];

  _mode = [NSPopUpButton new];
  [_mode addItemsWithTitles:ShortcutModeTitles()];
  _mode.autoenablesItems = NO;
  [_mode bind:NSSelectedIndexBinding toObject:NSUserDefaultsController.sharedUserDefaultsController withKeyPath:DefaultsPath(kShortcutModeKey) options:nil];
  _modeSummary = Footnote(@"", kFootnoteWidth);

  self.view = FormPane(@[
    @[ Label(@"Service:"), _service ],
    @[ Label(@"API key:"), _apiKey ],
    @[ NSGridCell.emptyContentView, Footnote(@"Kept in your keychain and sent only to the service.", kFootnoteWidth) ],
    @[ Label(@"Language:"), PopUp(SottoLanguages(), kLanguageKey) ],
    @[ Label(@"Microphone:"), [self microphonePopUp] ],
    @[ Label(@"Shortcut:"), [ShortcutRecorderView new] ],
    @[ Label(@"Shortcut mode:"), _mode ],
    @[ NSGridCell.emptyContentView, _modeSummary ],
  ]);
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(showMode) name:NSUserDefaultsDidChangeNotification object:nil];
  [self showMode];
}

- (NSPopUpButton *)microphonePopUp {
  NSPopUpButton *popUp = [NSPopUpButton new];
  [popUp addItemWithTitle:@"System Default"];
  popUp.lastItem.representedObject = @"";
  [popUp.menu addItem:NSMenuItem.separatorItem];
  NSString *selected = [NSUserDefaults.standardUserDefaults stringForKey:kMicrophoneKey];
  for (AudioInputDevice *device in AudioInputDevice.all) {
    [popUp addItemWithTitle:device.name];
    popUp.lastItem.representedObject = device.uid;
    if ([device.uid isEqualToString:selected]) [popUp selectItem:popUp.lastItem];
  }
  popUp.target = self;
  popUp.action = @selector(chooseMicrophone:);
  return popUp;
}

- (void)chooseMicrophone:(NSPopUpButton *)sender {
  [NSUserDefaults.standardUserDefaults setObject:sender.selectedItem.representedObject forKey:kMicrophoneKey];
}

- (void)showService {
  RecognizerService *service = RecognizerService.selected;
  [_service selectItemAtIndex:[RecognizerService.all indexOfObject:service]];
  _apiKey.stringValue = service.apiKey ?: @"";
}

- (void)chooseService:(NSPopUpButton *)sender {
  RecognizerService.selected = RecognizerService.all[sender.indexOfSelectedItem];
  [self showService];
}

- (void)controlTextDidChange:(NSNotification *)notification {
  if (notification.object == _apiKey) RecognizerService.selected.apiKey = _apiKey.stringValue;
}

- (void)showMode {
  const NSInteger mode = [NSUserDefaults.standardUserDefaults integerForKey:kShortcutModeKey];
  _modeSummary.stringValue = [ShortcutModeSummary(mode) stringByAppendingString:@" Press Escape to cancel."];
  [_mode itemAtIndex:kShortcutModeDoubleTap].enabled = Shortcut.current.hasKey;
}
@end

@interface VocabularyPane () <NSTableViewDataSource, NSTableViewDelegate>
@end
@implementation VocabularyPane {
  NSMutableArray<NSString *> *_words;
  NSTableView *_table;
  NSSegmentedControl *_addRemove;
}

- (void)loadView {
  _words = [[NSUserDefaults.standardUserDefaults stringArrayForKey:kVocabularyKey] mutableCopy] ?: [NSMutableArray new];

  _table = [NSTableView new];
  _table.headerView = nil;
  _table.style = NSTableViewStyleFullWidth;
  _table.usesAlternatingRowBackgroundColors = YES;
  _table.allowsMultipleSelection = YES;
  [_table addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"word"]];
  _table.dataSource = self;
  _table.delegate = self;
  [_table setAccessibilityLabel:@"Vocabulary"];

  NSScrollView *scroll = [NSScrollView new];
  scroll.documentView = _table;
  scroll.hasVerticalScroller = YES;
  scroll.borderType = NSBezelBorder;

  _addRemove = [NSSegmentedControl segmentedControlWithImages:@[
    [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"Add Word"],
    [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:@"Remove Word"],
  ] trackingMode:NSSegmentSwitchTrackingMomentary target:self action:@selector(addOrRemove:)];
  _addRemove.segmentStyle = NSSegmentStyleSmallSquare;

  self.view = StackPane(@[
    [NSTextField wrappingLabelWithString:@"Add names, places, and terms you use often so Sotto spells them the way you do."],
    scroll, _addRemove,
  ]);
  [NSLayoutConstraint activateConstraints:@[
    [scroll.widthAnchor constraintEqualToConstant:kPaneWidth - 2 * kMargin],
    [scroll.heightAnchor constraintEqualToConstant:180],
  ]];
  [self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:_table]];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return _words.count; }

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  NSTableCellView *cell = [tableView makeViewWithIdentifier:@"word" owner:self];
  if (!cell) {
    cell = [NSTableCellView new];
    cell.identifier = @"word";
    NSTextField *field = [NSTextField labelWithString:@""];
    field.editable = YES;
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    field.target = self;
    field.action = @selector(wordEdited:);
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:field];
    cell.textField = field;
    [NSLayoutConstraint activateConstraints:@[
      [field.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
      [field.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
      [field.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
  }
  cell.textField.stringValue = _words[row];
  return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  [_addRemove setEnabled:_table.selectedRowIndexes.count > 0 forSegment:1];
}

- (void)addOrRemove:(NSSegmentedControl *)sender {
  if (sender.selectedSegment == 0) {
    [_words addObject:@""];
    const NSInteger row = _words.count - 1;
    [_table insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:row] withAnimation:NSTableViewAnimationEffectNone];
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [_table scrollRowToVisible:row];
    [_table editColumn:0 row:row withEvent:nil select:YES];
  } else {
    NSIndexSet *rows = _table.selectedRowIndexes;
    [_words removeObjectsAtIndexes:rows];
    [_table removeRowsAtIndexes:rows withAnimation:NSTableViewAnimationSlideUp];
    [self save];
  }
}

- (void)wordEdited:(NSTextField *)sender {
  const NSInteger row = [_table rowForView:sender];
  if (row < 0) return;
  NSString *word = [sender.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
  if (word.length == 0) {
    [_words removeObjectAtIndex:row];
    [_table removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:row] withAnimation:NSTableViewAnimationEffectNone];
  } else {
    _words[row] = word;
  }
  [self save];
}

- (void)save { [NSUserDefaults.standardUserDefaults setObject:_words forKey:kVocabularyKey]; }

@end

@implementation PrivacyPane {
  NSTextField *_title;
  NSTextField *_summary;
}

- (void)showService {
  _title.stringValue = RecognizerService.selected.privacyTitle;
  _summary.stringValue = RecognizerService.selected.privacySummary;
}

- (void)loadView {
  NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"hand.raised.fill" accessibilityDescription:nil]];
  icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:30 weight:NSFontWeightRegular];
  icon.contentTintColor = NSColor.controlAccentColor;
  [icon.widthAnchor constraintEqualToConstant:40].active = YES;

  NSTextField *title = _title = Label(@"");
  title.font = [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightSemibold];
  NSTextField *body = _summary = [NSTextField wrappingLabelWithString:RecognizerService.all.firstObject.privacySummary];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(showService) name:NSUserDefaultsDidChangeNotification object:nil];
  body.textColor = NSColor.secondaryLabelColor;
  body.preferredMaxLayoutWidth = kPaneWidth - 2 * kMargin - 52;
  NSStackView *text = [NSStackView stackViewWithViews:@[ title, body ]];
  text.orientation = NSUserInterfaceLayoutOrientationVertical;
  text.alignment = NSLayoutAttributeLeading;
  text.spacing = 3;
  NSStackView *header = [NSStackView stackViewWithViews:@[ icon, text ]];
  header.alignment = NSLayoutAttributeTop;
  header.spacing = 12;

  NSBox *separator = [NSBox new];
  separator.boxType = NSBoxSeparator;

  NSButton *clear = [NSButton buttonWithTitle:@"Clear Recent Dictations…" target:self action:@selector(confirmClear:)];

  NSStackView *pane = (NSStackView *)StackPane(@[
    header, separator,
    Checkbox(@"Keep recent dictations in the menu", kKeepRecentsKey),
    Footnote(@"Recent dictations are kept until you quit Sotto.", kPaneWidth - 2 * kMargin - 20),
    clear,
  ]);
  [pane setCustomSpacing:14 afterView:header];
  [pane setCustomSpacing:14 afterView:separator];
  [pane setCustomSpacing:4 afterView:pane.views[2]];
  [pane setCustomSpacing:14 afterView:pane.views[3]];
  [separator.widthAnchor constraintEqualToConstant:kPaneWidth - 2 * kMargin].active = YES;
  [pane.views[3].leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:kMargin + 20].active = YES;
  self.view = pane;
  [self showService];
}

- (void)confirmClear:(id)sender {
  NSAlert *alert = [NSAlert new];
  alert.messageText = @"Clear all recent dictations?";
  alert.informativeText = @"You can’t undo this action.";
  [alert addButtonWithTitle:@"Clear"].hasDestructiveAction = YES;
  [alert addButtonWithTitle:@"Cancel"];
  [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
    if (response == NSAlertFirstButtonReturn) [NSApp sendAction:NSSelectorFromString(@"clearRecents:") to:nil from:self];
  }];
}
@end
