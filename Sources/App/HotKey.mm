#import "HotKey.h"

#import <Carbon/Carbon.h>

@interface HotKey ()
@property(nonatomic, copy) void (^pressed)(void);
@property(nonatomic, copy, nullable) void (^released)(void);
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
                        pressed:(void (^)(void))pressed
                       released:(void (^)(void))released {
  if (!(self = [super init])) return nil;

  static dispatch_once_t once;
  dispatch_once(&once, ^{
    const EventTypeSpec kinds[] = {{kEventClassKeyboard, kEventHotKeyPressed},
                                   {kEventClassKeyboard, kEventHotKeyReleased}};
    InstallApplicationEventHandler(&HandleHotKey, 2, kinds, nullptr, nullptr);
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
