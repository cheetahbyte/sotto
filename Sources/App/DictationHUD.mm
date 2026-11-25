#import "DictationHUD.h"

#import <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <array>
#include <cmath>

static const CGFloat kHeight = 44;
static const CGFloat kIndicatorSize = 28;
static const CGFloat kLeading = 14;
static const CGFloat kGap = 8;
static const CGFloat kTrailing = 18;
static const CGFloat kCompactWidth = kLeading + kIndicatorSize + kLeading;
static const CGFloat kMaxWidth = 560;
static const CGFloat kBottomMargin = 28;
static const CGFloat kSlideDistance = 10;
static const NSSize kPanelSize = {kMaxWidth + 80, kHeight + kBottomMargin + 48};  // room for the glass shadow

static BOOL ReduceMotion() { return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion; }

#pragma mark - Waveform

// Five capsule bars that follow the input level.
@interface WaveformView : NSView
@property(nonatomic) CGFloat level;
@end

@implementation WaveformView {
  std::array<CGFloat, 5> _bars;
}

- (void)setLevel:(CGFloat)level {
  _level = level;
  static constexpr std::array<CGFloat, 5> kWeight = {0.55, 0.85, 1.0, 0.8, 0.5};
  const CFTimeInterval t = CACurrentMediaTime();
  for (size_t i = 0; i < _bars.size(); ++i) {
    // Reduce Motion keeps the level feedback but drops the decorative ripple.
    const CGFloat ripple = ReduceMotion() ? 0.85 : 0.7 + 0.3 * std::sin(t * (9.0 + 2.3 * i) + 1.7 * i);
    const CGFloat target = std::clamp<CGFloat>(level * kWeight[i] * ripple * 1.25, 0, 1);
    _bars[i] += (target - _bars[i]) * 0.35;
  }
  self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
  const CGFloat barWidth = 3, spacing = 2.5, minHeight = 3;
  const CGFloat total = _bars.size() * barWidth + (_bars.size() - 1) * spacing;
  CGFloat x = NSMidX(self.bounds) - total / 2;
  [NSColor.labelColor setFill];
  for (CGFloat bar : _bars) {
    const CGFloat h = minHeight + (NSHeight(self.bounds) - 6 - minHeight) * bar;
    const NSRect rect = NSMakeRect(x, NSMidY(self.bounds) - h / 2, barWidth, h);
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:barWidth / 2 yRadius:barWidth / 2] fill];
    x += barWidth + spacing;
  }
}

- (BOOL)isAccessibilityElement { return NO; }

@end

#pragma mark - HUD

@implementation DictationHUD {
  NSPanel *_panel;
  NSGlassEffectView *_glass;
  NSLayoutConstraint *_width;
  NSLayoutConstraint *_bottom;
  NSLayoutConstraint *_labelWidth;
  WaveformView *_waveform;
  NSProgressIndicator *_spinner;
  NSImageView *_symbol;
  NSTextField *_label;
  BOOL _visible;
  NSUInteger _generation;  // invalidates a pending hide when shown again
}

- (instancetype)init {
  if (!(self = [super init])) return nil;

  _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, kPanelSize.width, kPanelSize.height)
                                      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                        backing:NSBackingStoreBuffered
                                          defer:YES];
  _panel.opaque = NO;
  _panel.backgroundColor = NSColor.clearColor;
  _panel.hasShadow = NO;
  _panel.level = NSStatusWindowLevel;
  _panel.ignoresMouseEvents = YES;
  _panel.hidesOnDeactivate = NO;
  _panel.animationBehavior = NSWindowAnimationBehaviorNone;
  _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                              NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorStationary;
  _panel.alphaValue = 0;

  _waveform = [WaveformView new];
  _spinner = [NSProgressIndicator new];
  _spinner.style = NSProgressIndicatorStyleSpinning;
  _spinner.controlSize = NSControlSizeSmall;
  _symbol = [NSImageView new];
  _symbol.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:19 weight:NSFontWeightMedium];
  _symbol.contentTintColor = NSColor.labelColor;

  _label = [NSTextField labelWithString:@""];
  _label.lineBreakMode = NSLineBreakByTruncatingHead;  // keep the newest words visible
  _label.maximumNumberOfLines = 1;
  _label.translatesAutoresizingMaskIntoConstraints = NO;
  // The label takes its final width at once and this view clips it, so
  // new words are revealed as the capsule grows instead of flickering
  // through an ellipsis.
  NSView *labelClip = [NSView new];
  labelClip.clipsToBounds = YES;
  [labelClip addSubview:_label];
  _labelWidth = [_label.widthAnchor constraintEqualToConstant:0];

  NSView *content = [NSView new];
  NSView *indicator = [NSView new];
  for (NSView *view in @[ _waveform, _spinner, _symbol ]) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.alphaValue = 0;
    [indicator addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
      [view.centerXAnchor constraintEqualToAnchor:indicator.centerXAnchor],
      [view.centerYAnchor constraintEqualToAnchor:indicator.centerYAnchor],
    ]];
  }
  [NSLayoutConstraint activateConstraints:@[
    [_waveform.widthAnchor constraintEqualToConstant:kIndicatorSize],
    [_waveform.heightAnchor constraintEqualToConstant:kIndicatorSize],
  ]];
  for (NSView *view in @[ indicator, labelClip ]) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:view];
  }
  NSLayoutConstraint *clipTrailing = [labelClip.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-kTrailing];
  clipTrailing.priority = NSLayoutPriorityDefaultHigh;  // yields while the capsule is compact
  [NSLayoutConstraint activateConstraints:@[
    [indicator.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:kLeading],
    [indicator.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
    [indicator.widthAnchor constraintEqualToConstant:kIndicatorSize],
    [indicator.heightAnchor constraintEqualToConstant:kIndicatorSize],
    [labelClip.leadingAnchor constraintEqualToAnchor:indicator.trailingAnchor constant:kGap],
    [labelClip.topAnchor constraintEqualToAnchor:content.topAnchor],
    [labelClip.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    clipTrailing,
    [_label.leadingAnchor constraintEqualToAnchor:labelClip.leadingAnchor],
    [_label.centerYAnchor constraintEqualToAnchor:labelClip.centerYAnchor],
    _labelWidth,
  ]];

  _glass = [NSGlassEffectView new];
  _glass.cornerRadius = kHeight / 2;
  _glass.contentView = content;
  _glass.translatesAutoresizingMaskIntoConstraints = NO;

  NSView *root = [NSView new];
  [root addSubview:_glass];
  _panel.contentView = root;
  _width = [_glass.widthAnchor constraintEqualToConstant:kCompactWidth];
  _bottom = [_glass.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-(kBottomMargin - kSlideDistance)];
  [NSLayoutConstraint activateConstraints:@[
    _width, _bottom,
    [_glass.heightAnchor constraintEqualToConstant:kHeight],
    [_glass.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
  ]];
  return self;
}

- (void)setLevel:(CGFloat)level {
  _level = level;
  _waveform.level = level;
}

#pragma mark States

- (void)showListeningWithFinalized:(NSString *)finalized tentative:(NSString *)tentative {
  NSMutableAttributedString *text = [self text:finalized color:NSColor.labelColor];
  if (finalized.length && tentative.length) [text appendAttributedString:[self text:@" " color:NSColor.labelColor]];
  // Words the recognizer may still revise are dimmer.
  [text appendAttributedString:[self text:tentative color:NSColor.secondaryLabelColor]];
  [self showIndicator:_waveform text:text];
}

- (void)showProcessingWithText:(NSString *)text {
  [_spinner startAnimation:nil];
  [self showIndicator:_spinner text:[self text:text color:NSColor.secondaryLabelColor]];
}

- (void)showFinishedWithText:(NSString *)text {
  _symbol.image = [NSImage imageWithSystemSymbolName:@"checkmark.circle.fill" accessibilityDescription:@"Inserted"];
  [self showIndicator:_symbol text:[self text:text color:NSColor.labelColor]];
  if (!ReduceMotion()) [_symbol addSymbolEffect:[NSSymbolBounceEffect bounceUpEffect] options:NSSymbolEffectOptions.optionsWithNonRepeating];
}

- (void)showMessageWithSymbolName:(NSString *)symbolName message:(NSString *)message {
  _symbol.image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
  [self showIndicator:_symbol text:[self text:message color:NSColor.labelColor]];
}

- (void)dismiss {
  if (!_visible) return;
  _visible = NO;
  const NSUInteger generation = ++_generation;
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
    context.duration = 0.22;
    context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    self->_panel.animator.alphaValue = 0;
    if (!ReduceMotion()) self->_bottom.animator.constant = -(kBottomMargin - kSlideDistance);
  } completionHandler:^{
    if (generation != self->_generation) return;
    [self->_panel orderOut:nil];
    [self->_spinner stopAnimation:nil];
    self->_width.constant = kCompactWidth;
    self->_label.stringValue = @"";
  }];
}

#pragma mark Layout

- (NSMutableAttributedString *)text:(NSString *)string color:(NSColor *)color {
  NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
  style.lineBreakMode = NSLineBreakByTruncatingHead;
  return [[NSMutableAttributedString alloc] initWithString:string attributes:@{
    NSFontAttributeName : [NSFont systemFontOfSize:15],
    NSForegroundColorAttributeName : color,
    NSParagraphStyleAttributeName : style,
  }];
}

- (void)showIndicator:(NSView *)indicator text:(NSAttributedString *)text {
  _label.attributedStringValue = text;
  _label.hidden = text.length == 0;
  const CGFloat chrome = kLeading + kIndicatorSize + kGap + kTrailing;
  const CGFloat textWidth = std::min(std::ceil(text.size.width) + 4, kMaxWidth - chrome);
  const CGFloat width = text.length == 0 ? kCompactWidth : chrome + textWidth;
  _labelWidth.constant = textWidth;

  const BOOL appearing = !_visible;
  if (appearing) {
    _visible = YES;
    ++_generation;
    [self positionOnActiveScreen];
    _width.constant = width;
    [_panel.contentView layoutSubtreeIfNeeded];
    [_panel orderFrontRegardless];
  }

  [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
    context.duration = appearing ? 0.35 : 0.25;
    context.timingFunction = appearing ? [CAMediaTimingFunction functionWithControlPoints:0.2 :0.9 :0.3 :1.0]
                                       : [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    context.allowsImplicitAnimation = YES;
    for (NSView *view in @[ self->_waveform, self->_spinner, self->_symbol ]) view.animator.alphaValue = view == indicator;
    self->_panel.animator.alphaValue = 1;
    self->_bottom.animator.constant = -kBottomMargin;
    self->_width.animator.constant = width;
    [self->_panel.contentView layoutSubtreeIfNeeded];
  }];
}

// Bottom center of the screen people are working on, above the Dock.
- (void)positionOnActiveScreen {
  NSScreen *screen = NSScreen.mainScreen;
  const NSPoint mouse = NSEvent.mouseLocation;
  for (NSScreen *candidate in NSScreen.screens) {
    if (NSMouseInRect(mouse, candidate.frame, NO)) screen = candidate;
  }
  const NSRect area = screen.visibleFrame;
  [_panel setFrame:NSMakeRect(NSMidX(area) - kPanelSize.width / 2, NSMinY(area), kPanelSize.width, kPanelSize.height)
           display:NO];
}

@end
