#import "Shortcut.h"

#import <Carbon/Carbon.h>

#include <array>

#import "Defaults.h"
#import "HotKey.h"

NSNotificationName const ShortcutDidChangeNotification = @"ShortcutDidChange";
NSNotificationName const ShortcutRecordingDidBeginNotification = @"ShortcutRecordingDidBegin";
NSNotificationName const ShortcutRecordingDidEndNotification = @"ShortcutRecordingDidEnd";

static const NSEventModifierFlags kCommonModifiers =
    NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift | NSEventModifierFlagCommand;

namespace {
struct ModifierKey {
  NSInteger keyCode = 0;
  NSUInteger deviceFlag = 0;
  NSString *label = nil;
};

ModifierKey Key(NSInteger keyCode, NSUInteger deviceFlag, NSString *label) {
  return {.keyCode = keyCode, .deviceFlag = deviceFlag, .label = label};
}

const std::array<ModifierKey, 9> &ModifierKeys() {
  static const std::array<ModifierKey, 9> keys = {
      Key(kVK_Function, NSEventModifierFlagFunction, @"Fn"),
      Key(kVK_Control, 0x0001, @"Left Control"),
      Key(kVK_RightControl, 0x2000, @"Right Control"),
      Key(kVK_Option, 0x0020, @"Left Option"),
      Key(kVK_RightOption, 0x0040, @"Right Option"),
      Key(kVK_Shift, 0x0002, @"Left Shift"),
      Key(kVK_RightShift, 0x0004, @"Right Shift"),
      Key(kVK_Command, 0x0008, @"Left Command"),
      Key(kVK_RightCommand, 0x0010, @"Right Command"),
  };
  return keys;
}
}

NSArray<NSNumber *> *ModifierKeyCodesDown(NSEventModifierFlags flags) {
  NSMutableArray *down = [NSMutableArray new];
  for (const ModifierKey &key : ModifierKeys()) {
    if (flags & key.deviceFlag) [down addObject:@(key.keyCode)];
  }
  return down;
}

NSString *ModifierKeysDisplayString(NSArray<NSNumber *> *keyCodes) {
  NSMutableArray *names = [NSMutableArray new];
  for (const ModifierKey &key : ModifierKeys()) {
    if ([keyCodes containsObject:@(key.keyCode)]) [names addObject:key.label];
  }
  return [names componentsJoinedByString:@" + "];
}

static NSString *KeyName(NSInteger keyCode) {
  static NSDictionary<NSNumber *, NSString *> *named = @{
    @(kVK_Space) : @"Space", @(kVK_Return) : @"↩", @(kVK_Tab) : @"⇥", @(kVK_Delete) : @"⌫",
    @(kVK_ForwardDelete) : @"⌦", @(kVK_Escape) : @"esc", @(kVK_LeftArrow) : @"←", @(kVK_RightArrow) : @"→",
    @(kVK_UpArrow) : @"↑", @(kVK_DownArrow) : @"↓", @(kVK_F1) : @"F1", @(kVK_F2) : @"F2", @(kVK_F3) : @"F3",
    @(kVK_F4) : @"F4", @(kVK_F5) : @"F5", @(kVK_F6) : @"F6", @(kVK_F7) : @"F7", @(kVK_F8) : @"F8",
    @(kVK_F9) : @"F9", @(kVK_F10) : @"F10", @(kVK_F11) : @"F11", @(kVK_F12) : @"F12",
  };
  if (NSString *name = named[@(keyCode)]) return name;

  NSString *result = @"?";
  TISInputSourceRef source = TISCopyCurrentKeyboardLayoutInputSource();
  auto data = static_cast<CFDataRef>(TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData));
  if (data) {
    const void *bytes = CFDataGetBytePtr(data);
    const auto *layout = static_cast<const UCKeyboardLayout *>(bytes);
    UInt32 deadKeys = 0;
    std::array<UniChar, 4> chars{};
    UniCharCount length = 0;
    if (UCKeyTranslate(layout, static_cast<UInt16>(keyCode), kUCKeyActionDisplay, 0, LMGetKbdType(),
                       kUCKeyTranslateNoDeadKeysMask, &deadKeys, chars.size(), &length, chars.data()) == noErr &&
        length > 0 && length <= chars.size()) {
      result = [NSString stringWithCharacters:chars.data() length:length].uppercaseString;
    }
  }
  CFRelease(source);
  return result;
}

@implementation Shortcut

- (instancetype)initWithKeyCode:(NSInteger)keyCode modifiers:(NSEventModifierFlags)modifiers modifierKeyCodes:(NSArray *)keyCodes {
  self = [super init];
  if (!self) return nil;
  _keyCode = keyCode;
  _modifiers = modifiers & kCommonModifiers;
  _modifierKeyCodes = [keyCodes copy];
  return self;
}

+ (instancetype)shortcutWithKeyCode:(NSInteger)keyCode modifiers:(NSEventModifierFlags)modifiers {
  return [[self alloc] initWithKeyCode:keyCode modifiers:modifiers modifierKeyCodes:@[]];
}

+ (instancetype)shortcutWithModifierKeyCodes:(NSArray<NSNumber *> *)keyCodes {
  return [[self alloc] initWithKeyCode:-1 modifiers:0 modifierKeyCodes:keyCodes];
}

+ (Shortcut *)current {
  NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:kShortcutKey];
  NSNumber *keyCode = saved[@"keyCode"];
  NSArray *modifierKeyCodes = saved[@"modifierKeyCodes"];
  if (keyCode.integerValue >= 0 && [saved[@"modifiers"] unsignedIntegerValue]) {
    return [self shortcutWithKeyCode:keyCode.integerValue modifiers:[saved[@"modifiers"] unsignedIntegerValue]];
  }
  if (keyCode && modifierKeyCodes.count) return [self shortcutWithModifierKeyCodes:modifierKeyCodes];
  return [self shortcutWithKeyCode:kVK_Space modifiers:NSEventModifierFlagOption];
}

+ (void)setCurrent:(Shortcut *)shortcut {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  [defaults setObject:@{
    @"keyCode" : @(shortcut.keyCode),
    @"modifiers" : @(shortcut.modifiers),
    @"modifierKeyCodes" : shortcut.modifierKeyCodes,
  } forKey:kShortcutKey];
  if (!shortcut.hasKey && [defaults integerForKey:kShortcutModeKey] == kShortcutModeDoubleTap) {
    [defaults setInteger:kShortcutModeHoldOrDoubleTap forKey:kShortcutModeKey];
  }
  [NSNotificationCenter.defaultCenter postNotificationName:ShortcutDidChangeNotification object:nil];
}

- (BOOL)hasKey { return _keyCode >= 0; }

- (NSString *)displayString {
  if (!self.hasKey) return ModifierKeysDisplayString(_modifierKeyCodes);
  NSMutableString *string = [NSMutableString new];
  if (_modifiers & NSEventModifierFlagControl) [string appendString:@"⌃"];
  if (_modifiers & NSEventModifierFlagOption) [string appendString:@"⌥"];
  if (_modifiers & NSEventModifierFlagShift) [string appendString:@"⇧"];
  if (_modifiers & NSEventModifierFlagCommand) [string appendString:@"⌘"];
  [string appendString:KeyName(_keyCode)];
  return string;
}

- (NSString *)menuKeyEquivalent {
  if (!self.hasKey) return @"";
  if (_keyCode == kVK_Space) return @" ";
  NSString *name = KeyName(_keyCode);
  return name.length == 1 ? name.lowercaseString : @"";
}

@end

#pragma mark - Monitor

@implementation ShortcutMonitor {
  void (^_pressed)();
  void (^_released)();
  HotKey *_hotKey;
  id _globalMonitor;
  id _localMonitor;
  NSSet<NSNumber *> *_wantedModifiers;
  BOOL _modifiersDown;
}

- (instancetype)initWithPressed:(void (^)())pressed released:(void (^)())released {
  self = [super init];
  if (!self) return nil;
  _pressed = [pressed copy];
  _released = [released copy];
  NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
  [center addObserver:self selector:@selector(start) name:ShortcutDidChangeNotification object:nil];
  [center addObserver:self selector:@selector(stop) name:ShortcutRecordingDidBeginNotification object:nil];
  [center addObserver:self selector:@selector(start) name:ShortcutRecordingDidEndNotification object:nil];
  [self start];
  return self;
}

- (void)dealloc { [self stop]; }

- (void)stop {
  _hotKey = nil;
  if (_globalMonitor) [NSEvent removeMonitor:_globalMonitor];
  if (_localMonitor) [NSEvent removeMonitor:_localMonitor];
  _globalMonitor = _localMonitor = nil;
  _modifiersDown = NO;
}

- (void)start {
  [self stop];
  Shortcut *shortcut = Shortcut.current;
  __weak ShortcutMonitor *weakSelf = self;

  if (shortcut.hasKey) {
    uint32_t carbon = 0;
    if (shortcut.modifiers & NSEventModifierFlagControl) carbon |= controlKey;
    if (shortcut.modifiers & NSEventModifierFlagOption) carbon |= optionKey;
    if (shortcut.modifiers & NSEventModifierFlagShift) carbon |= shiftKey;
    if (shortcut.modifiers & NSEventModifierFlagCommand) carbon |= cmdKey;
    _hotKey = [[HotKey alloc] initWithKeyCode:static_cast<uint32_t>(shortcut.keyCode)
                                    modifiers:carbon
                                      pressed:_pressed
                                     released:_released];
    if (!_hotKey) NSLog(@"Sotto: %@ is taken by another app. Use the menu bar item instead.", shortcut.displayString);
    return;
  }

  _wantedModifiers = [NSSet setWithArray:shortcut.modifierKeyCodes];
  _globalMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskFlagsChanged handler:^(NSEvent *event) {
    [weakSelf modifiersChanged:event.modifierFlags];
  }];
  _localMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskFlagsChanged handler:^(NSEvent *event) {
    [weakSelf modifiersChanged:event.modifierFlags];
    return event;
  }];
}

- (void)modifiersChanged:(NSEventModifierFlags)flags {
  const BOOL down = [[NSSet setWithArray:ModifierKeyCodesDown(flags)] isEqualToSet:_wantedModifiers];
  if (down == _modifiersDown) return;
  _modifiersDown = down;
  down ? _pressed() : _released();
}

@end
