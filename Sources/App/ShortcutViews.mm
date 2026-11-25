#import "ShortcutViews.h"

#import <Carbon/Carbon.h>

#import "Shortcut.h"

NSArray<NSString *> *ShortcutModeTitles(void) {
  return @[ @"Hold or Double-Tap", @"Hold", @"Tap", @"Double-Tap" ];
}

NSString *ShortcutModeSummary(NSInteger mode) {
  return @[
    @"Hold the shortcut while you speak, or press it twice to dictate hands-free.",
    @"Hold the shortcut while you speak and let go to finish.",
    @"Press the shortcut to start dictating and press it again to finish.",
    @"Press the shortcut twice to start dictating and once to finish.",
  ][mode];
}

static const CGFloat kInset = 8;
static const CGFloat kCancelSize = 14;

@implementation ShortcutRecorderView {
  BOOL _recording;
  NSArray<NSNumber *> *_heldModifiers;  // down right now
  NSArray<NSNumber *> *_peakModifiers;  // the most held at once since recording began
}

- (instancetype)initWithFrame:(NSRect)frame {
  if (!(self = [super initWithFrame:frame])) return nil;
  self.toolTip = @"Click to record a new shortcut";
  [self setAccessibilityElement:YES];
  [self setAccessibilityRole:NSAccessibilityButtonRole];
  [self setAccessibilityLabel:@"Shortcut"];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(shortcutDidChange:) name:ShortcutDidChangeNotification object:nil];
  return self;
}

- (void)shortcutDidChange:(NSNotification *)notification { self.needsDisplay = YES; }

- (NSSize)intrinsicContentSize { return NSMakeSize(190, 24); }
- (CGFloat)firstBaselineOffsetFromTop { return 16.5; }  // lines the text up with the form label
- (BOOL)acceptsFirstResponder { return YES; }
// Like buttons, in the Tab order only with Keyboard Navigation turned on.
- (BOOL)canBecomeKeyView { return NSApp.fullKeyboardAccessEnabled; }
- (id)accessibilityValue { return _recording ? @"Recording" : Shortcut.current.displayString; }
- (BOOL)accessibilityPerformPress {
  [self.window makeFirstResponder:self];
  [self beginRecording];
  return YES;
}

#pragma mark Drawing

- (NSBezierPath *)bezel { return [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6 yRadius:6]; }
- (void)drawFocusRingMask { [[self bezel] fill]; }
- (NSRect)focusRingMaskBounds { return self.bounds; }

- (NSRect)cancelRect {
  return NSMakeRect(NSMaxX(self.bounds) - kInset - kCancelSize + 2, NSMidY(self.bounds) - kCancelSize / 2, kCancelSize, kCancelSize);
}

- (void)drawRect:(NSRect)dirtyRect {
  [NSColor.tertiarySystemFillColor setFill];
  [[self bezel] fill];

  NSString *text = Shortcut.current.displayString;
  NSColor *color = NSColor.labelColor;
  if (_recording) {
    // While recording, show the modifiers held so far.
    text = _heldModifiers.count ? [ModifierKeysDisplayString(_heldModifiers) stringByAppendingString:@" …"] : @"Type shortcut";
    color = _heldModifiers.count ? NSColor.labelColor : NSColor.placeholderTextColor;

    NSImage *cancel = [NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:@"Cancel"];
    NSImageSymbolConfiguration *tint = [NSImageSymbolConfiguration configurationWithHierarchicalColor:NSColor.secondaryLabelColor];
    [[cancel imageWithSymbolConfiguration:tint] drawInRect:[self cancelRect]];
  }
  NSDictionary *attributes = @{NSFontAttributeName : [NSFont systemFontOfSize:NSFont.systemFontSize], NSForegroundColorAttributeName : color};
  const CGFloat height = [text sizeWithAttributes:attributes].height;
  [text drawAtPoint:NSMakePoint(kInset, NSMidY(self.bounds) - height / 2) withAttributes:attributes];
}

#pragma mark Recording

- (void)beginRecording {
  if (_recording) return;
  _recording = YES;
  _heldModifiers = _peakModifiers = @[];
  [NSNotificationCenter.defaultCenter postNotificationName:ShortcutRecordingDidBeginNotification object:self];
  self.needsDisplay = YES;
}

- (void)endRecordingSaving:(Shortcut *)shortcut {
  if (!_recording) return;
  _recording = NO;
  if (shortcut) Shortcut.current = shortcut;
  [NSNotificationCenter.defaultCenter postNotificationName:ShortcutRecordingDidEndNotification object:self];
  self.needsDisplay = YES;
  NSAccessibilityPostNotification(self, NSAccessibilityValueChangedNotification);
}

- (BOOL)resignFirstResponder {
  [self endRecordingSaving:nil];
  return [super resignFirstResponder];
}

- (void)mouseDown:(NSEvent *)event {
  const NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  if (_recording) {
    if (NSPointInRect(point, NSInsetRect([self cancelRect], -4, -4))) [self endRecordingSaving:nil];
    return;
  }
  [self.window makeFirstResponder:self];
  [self beginRecording];
}

- (void)keyDown:(NSEvent *)event {
  if (!_recording) {
    if (event.keyCode == kVK_Space) return [self beginRecording];
    return [super keyDown:event];
  }
  const NSEventModifierFlags modifiers = event.modifierFlags &
      (NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift | NSEventModifierFlagCommand);
  if (event.keyCode == kVK_Escape && !modifiers) return [self endRecordingSaving:nil];
  // A plain key would fire while typing, so a shortcut needs a modifier.
  // Function keys are the exception.
  const BOOL functionKey = (event.modifierFlags & NSEventModifierFlagFunction) && event.keyCode >= kVK_F5;
  if (!modifiers && !functionKey) return NSBeep();
  [self endRecordingSaving:[Shortcut shortcutWithKeyCode:event.keyCode modifiers:modifiers]];
}

// Command combinations arrive here before the menus see them.
- (BOOL)performKeyEquivalent:(NSEvent *)event {
  if (!_recording || event.type != NSEventTypeKeyDown) return [super performKeyEquivalent:event];
  [self keyDown:event];
  return YES;
}

// Modifier keys pressed and let go without another key make a
// modifier-only shortcut out of the keys that were down together.
- (void)flagsChanged:(NSEvent *)event {
  if (!_recording) return [super flagsChanged:event];
  _heldModifiers = ModifierKeyCodesDown(event.modifierFlags);
  if (_heldModifiers.count >= _peakModifiers.count) {
    _peakModifiers = _heldModifiers;
  } else if (_heldModifiers.count == 0) {
    return [self endRecordingSaving:[Shortcut shortcutWithModifierKeyCodes:_peakModifiers]];
  }
  self.needsDisplay = YES;
}

@end
