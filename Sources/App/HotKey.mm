#import "HotKey.h"

#import <Carbon/Carbon.h>

#include <array>

@interface HotKey ()
@property(nonatomic, copy) void (^pressed)();
@property(nonatomic, copy, nullable) void (^released)();
@end

static NSMapTable<NSNumber *, HotKey *> *Registry() {
  static NSMapTable *table = [NSMapTable strongToWeakObjectsMapTable];
  return table;
}

static OSStatus HandleHotKey(EventHandlerCallRef, EventRef event, void *) {
  EventHotKeyID hotKeyID;
  GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, nullptr, sizeof hotKeyID, nullptr, &hotKeyID);
  HotKey *hotKey = [Registry() objectForKey:@(hotKeyID.id)];
  if (!hotKey) return eventNotHandledErr;
  if (GetEventKind(event) == kEventHotKeyPressed) {
    hotKey.pressed();
  } else if (hotKey.released) {
    hotKey.released();
  }
  return noErr;
}

@implementation HotKey {
  EventHotKeyRef _ref;
}

- (instancetype)initWithKeyCode:(uint32_t)keyCode
                      modifiers:(uint32_t)modifiers
                        pressed:(void (^)())pressed
                       released:(void (^)())released {
  self = [super init];
  if (!self) return nil;

  static dispatch_once_t once;
  dispatch_once(&once, ^{
    const std::array<EventTypeSpec, 2> kinds = {{
        {.eventClass = kEventClassKeyboard, .eventKind = kEventHotKeyPressed},
        {.eventClass = kEventClassKeyboard, .eventKind = kEventHotKeyReleased},
    }};
    InstallApplicationEventHandler(&HandleHotKey, kinds.size(), kinds.data(), nullptr, nullptr);
  });

  static uint32_t nextID = 1;
  const EventHotKeyID hotKeyID = {.signature = 'SOTO', .id = nextID++};
  if (RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &_ref) != noErr) return nil;

  _pressed = [pressed copy];
  _released = [released copy];
  [Registry() setObject:self forKey:@(hotKeyID.id)];
  return self;
}

- (void)dealloc {
  if (_ref) UnregisterEventHotKey(_ref);
}

@end
