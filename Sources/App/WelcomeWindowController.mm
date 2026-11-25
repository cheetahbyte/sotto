#import "WelcomeWindowController.h"

#import <AVFoundation/AVFoundation.h>

#import "AppDelegate.h"
#import "Shortcut.h"
#import "TextInserter.h"

static const CGFloat kWidth = 480;
static const CGFloat kTextWidth = 300;

static NSImageView *Symbol(NSString *name, CGFloat pointSize, NSFontWeight weight) {
  NSImageView *view = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil]];
  view.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
  view.contentTintColor = NSColor.controlAccentColor;
  return view;
}

static NSStackView *VStack(NSArray<NSView *> *views, CGFloat spacing, NSLayoutAttribute alignment) {
  NSStackView *stack = [NSStackView stackViewWithViews:views];
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = alignment;
  stack.spacing = spacing;
  return stack;
}

// Symbol, bold title, and a secondary description. `accessory` sits at
// the trailing edge when given.
static NSView *Row(NSString *symbol, NSString *title, NSString *body, NSView *accessory) {
  NSImageView *icon = Symbol(symbol, 26, NSFontWeightRegular);
  [icon.widthAnchor constraintEqualToConstant:40].active = YES;

  NSTextField *titleLabel = [NSTextField labelWithString:title];
  titleLabel.font = [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightSemibold];
  NSTextField *bodyLabel = [NSTextField wrappingLabelWithString:body];
  bodyLabel.textColor = NSColor.secondaryLabelColor;
  bodyLabel.selectable = NO;
  const CGFloat textWidth = accessory ? kTextWidth - 70 : kTextWidth;
  bodyLabel.preferredMaxLayoutWidth = textWidth;
  NSStackView *text = VStack(@[ titleLabel, bodyLabel ], 2, NSLayoutAttributeLeading);
  [text.widthAnchor constraintEqualToConstant:textWidth].active = YES;

  NSStackView *row = [NSStackView stackViewWithViews:accessory ? @[ icon, text, accessory ] : @[ icon, text ]];
  row.alignment = NSLayoutAttributeCenterY;
  row.spacing = 14;
  return row;
}

@implementation WelcomeWindowController {
  NSView *_page;
  NSButton *_continue;
  NSInteger _pageIndex;
}

- (instancetype)init {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWidth, 510)
                                                 styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                           NSWindowStyleMaskFullSizeContentView
                                                   backing:NSBackingStoreBuffered
                                                     defer:YES];
  window.title = @"Welcome to Sotto";  // for VoiceOver and Mission Control
  window.titleVisibility = NSWindowTitleHidden;
  window.titlebarAppearsTransparent = YES;
  window.movableByWindowBackground = YES;
  window.releasedWhenClosed = NO;
  [window standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
  [window standardWindowButton:NSWindowZoomButton].hidden = YES;
  if (!(self = [super initWithWindow:window])) return nil;

  _continue = [NSButton buttonWithTitle:@"Continue" target:self action:@selector(advance:)];
  _continue.controlSize = NSControlSizeLarge;
  _continue.keyEquivalent = @"\r";
  _continue.translatesAutoresizingMaskIntoConstraints = NO;
  [window.contentView addSubview:_continue];
  [NSLayoutConstraint activateConstraints:@[
    [_continue.centerXAnchor constraintEqualToAnchor:window.contentView.centerXAnchor],
    [_continue.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor constant:-32],
    [_continue.widthAnchor constraintGreaterThanOrEqualToConstant:200],
  ]];
  [self showPage:0];
  [window center];
  return self;
}

- (void)showWindow:(id)sender {
  if (!self.window.visible) [self showPage:0];
  [super showWindow:sender];
}

- (void)advance:(id)sender {
  if (_pageIndex == 0) {
    [self showPage:1];
  } else {
    [self close];
  }
}

- (void)showPage:(NSInteger)index {
  _pageIndex = index;
  _continue.title = index == 0 ? @"Continue" : @"Start Dictating";

  NSView *page = index == 0 ? [self featuresPage] : [self permissionsPage];
  page.translatesAutoresizingMaskIntoConstraints = NO;
  NSView *content = self.window.contentView;
  NSView *old = _page;
  _page = page;
  [content addSubview:page];
  [NSLayoutConstraint activateConstraints:@[
    [page.topAnchor constraintEqualToAnchor:content.topAnchor constant:56],
    [page.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
  ]];

  if (!old) return;
  page.alphaValue = 0;
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
    context.duration = 0.25;
    old.animator.alphaValue = 0;
    page.animator.alphaValue = 1;
  } completionHandler:^{
    [old removeFromSuperview];
  }];
}

- (NSView *)pageWithSymbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle rows:(NSArray<NSView *> *)rows {
  NSTextField *titleLabel = [NSTextField labelWithString:title];
  titleLabel.font = [NSFont systemFontOfSize:28 weight:NSFontWeightBold];
  NSTextField *subtitleLabel = [NSTextField wrappingLabelWithString:subtitle];
  subtitleLabel.alignment = NSTextAlignmentCenter;
  subtitleLabel.textColor = NSColor.secondaryLabelColor;
  subtitleLabel.selectable = NO;
  subtitleLabel.preferredMaxLayoutWidth = 340;

  NSStackView *rowStack = VStack(rows, 22, NSLayoutAttributeLeading);
  NSStackView *page = VStack(@[ Symbol(symbol, 52, NSFontWeightMedium), titleLabel, subtitleLabel, rowStack ], 10, NSLayoutAttributeCenterX);
  [page setCustomSpacing:18 afterView:page.views[0]];
  [page setCustomSpacing:36 afterView:subtitleLabel];
  return page;
}

- (NSView *)featuresPage {
  return [self pageWithSymbol:@"waveform.circle.fill"
                        title:@"Welcome to Sotto"
                     subtitle:@"Write anywhere on your Mac by speaking."
                         rows:@[
                           Row(@"waveform", @"Speak naturally",
                               [NSString stringWithFormat:@"Press %@ and start talking. Your words appear wherever you’re typing.",
                                                          Shortcut.current.displayString], nil),
                           Row(@"text.badge.checkmark", @"Punctuated for you",
                               @"Sotto adds punctuation and capitalization while you speak.", nil),
                           Row(@"key.fill", @"Your own OpenAI account",
                               @"Sotto sends your voice to OpenAI to turn it into text, using your API key.", nil),
                         ]];
}

- (NSView *)permissionsPage {
  return [self pageWithSymbol:@"checkmark.shield.fill"
                        title:@"Before You Start"
                     subtitle:@"Sotto needs three things from you. You can change them later."
                         rows:@[
                           Row(@"mic.fill", @"Microphone", @"To hear what you say while you dictate.", [self allowButton]),
                           Row(@"accessibility", @"Accessibility", @"To type the text into the app you’re using.",
                               [self accessibilityButton]),
                           Row(@"key.fill", @"OpenAI API key", @"Add it in Settings, under Dictation.", [self settingsButton]),
                         ]];
}

- (NSButton *)allowButton {
  NSButton *button = [NSButton buttonWithTitle:@"Allow" target:self action:@selector(allow:)];
  [button.widthAnchor constraintGreaterThanOrEqualToConstant:64].active = YES;
  if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusAuthorized) [self showAllowed:button];
  return button;
}

// macOS grants this one in System Settings, so the button leads there
// and shows the result when Sotto becomes active again.
- (NSButton *)accessibilityButton {
  NSButton *button = [NSButton buttonWithTitle:@"Allow" target:TextInserter.class action:@selector(requestPermission)];
  [button.widthAnchor constraintGreaterThanOrEqualToConstant:64].active = YES;
  if (TextInserter.isAllowed) [self showAllowed:button];
  __weak WelcomeWindowController *weakSelf = self;
  __weak NSButton *weakButton = button;
  [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *) {
    if (weakButton && TextInserter.isAllowed) [weakSelf showAllowed:weakButton];
  }];
  return button;
}

- (NSButton *)settingsButton {
  NSButton *button = [NSButton buttonWithTitle:@"Open…" target:NSApp.delegate action:@selector(showSettings:)];
  [button.widthAnchor constraintGreaterThanOrEqualToConstant:64].active = YES;
  return button;
}

// Shows the system's microphone alert the first time. After a refusal
// only System Settings can change the answer, so go there.
- (void)allow:(NSButton *)sender {
  if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusDenied) {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"]];
    return;
  }
  [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (granted) [self showAllowed:sender];
    });
  }];
}

- (void)showAllowed:(NSButton *)button {
  button.title = @"Allowed";
  button.image = [NSImage imageWithSystemSymbolName:@"checkmark" accessibilityDescription:nil];
  button.imagePosition = NSImageLeading;
  button.enabled = NO;
}

@end
