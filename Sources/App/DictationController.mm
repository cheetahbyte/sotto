#import "DictationController.h"

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

#import "Defaults.h"
#import "DictationHUD.h"
#import "HotKey.h"
#import "Recognizers.h"
#import "Session.hpp"
#import "Shortcut.h"
#import "ShortcutGesture.hpp"
#import "TextInserter.h"

NSNotificationName const DictationDidChangeNotification = @"DictationDidChange";

static const NSUInteger kMaxRecents = 8;

static NSString *String(const std::string &s) { return [NSString stringWithUTF8String:s.c_str()] ?: @""; }

@implementation DictationController {
  sotto::Session _session;
  DictationHUD *_hud;
  NSMutableArray<NSString *> *_recents;
  NSTimer *_timer;
  CFTimeInterval _lastTick;
  uint64_t _shownRevision;
  size_t _shownPhase;
  BOOL _wasCapturing;
  ShortcutMonitor *_shortcut;
  sotto::ShortcutGesture _gesture;
  HotKey *_escapeKey;  // held only while a session is on screen
}

- (instancetype)init {
  if (!(self = [super init])) return nil;
  _hud = [DictationHUD new];
  _recents = [NSMutableArray new];

  __weak DictationController *weakSelf = self;
  _shortcut = [[ShortcutMonitor alloc] initWithPressed:^{ [weakSelf shortcutPressed]; }
                                              released:^{ [weakSelf shortcutReleased]; }];
  return self;
}

- (BOOL)isActive { return _session.active(); }
- (NSArray<NSString *> *)recents { return [_recents copy]; }

- (void)toggle {
  if (!_session.active()) {
    [self start];
  } else {
    (void)_session.stop();  // ignored unless listening
  }
  [self render];
}

// Each dictation gets a fresh recognizer from the service chosen in Settings.
- (void)start {
  if (_session.start([RecognizerService.selected makeRecognizer])) [self startTicking];
}

- (void)cancel {
  _session.cancel();
  [self render];
}

- (void)clearRecents {
  [_recents removeAllObjects];
  [NSNotificationCenter.defaultCenter postNotificationName:DictationDidChangeNotification object:self];
}

- (void)showMicrophoneFailure {
  _session.fail(sotto::Failure::MicrophoneAccessDenied);
  [self startTicking];
  [self render];
}

#pragma mark Shortcut

// The gesture decides what a press or release means in the chosen
// shortcut mode; this only carries its commands out.
- (void)shortcutPressed {
  const auto mode = static_cast<sotto::ShortcutMode>([NSUserDefaults.standardUserDefaults integerForKey:kShortcutModeKey]);
  if (_gesture.mode() != mode) _gesture.set_mode(mode);
  const bool listening = std::holds_alternative<sotto::Listening>(_session.phase());
  [self perform:_gesture.press(sotto::Seconds{CACurrentMediaTime()}, listening)];
}

- (void)shortcutReleased {
  [self perform:_gesture.release(sotto::Seconds{CACurrentMediaTime()})];
}

- (void)perform:(sotto::GestureCommand)command {
  switch (command) {
    case sotto::GestureCommand::None:
      return;
    case sotto::GestureCommand::Start:
      [self start];
      break;
    case sotto::GestureCommand::Finish:
      (void)_session.stop();  // ignored unless listening
      break;
    case sotto::GestureCommand::Cancel:
      // Only a dictation still listening is dropped; an error stays readable.
      if (std::holds_alternative<sotto::Listening>(_session.phase())) _session.cancel();
      break;
  }
  [self render];
}

#pragma mark Simulation clock

- (void)startTicking {
  if (_timer) return;
  _lastTick = CACurrentMediaTime();
  _timer = [NSTimer timerWithTimeInterval:1.0 / 60 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
  // Common modes keep the HUD moving while a menu is open.
  [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)tick:(NSTimer *)timer {
  const CFTimeInterval now = CACurrentMediaTime();
  _session.advance(sotto::Seconds{now - _lastTick});
  _lastTick = now;
  [self perform:_gesture.poll(sotto::Seconds{now})];
  [self render];
}

#pragma mark Rendering

- (void)render {
  if (auto *listening = std::get_if<sotto::Listening>(&_session.phase())) _hud.level = listening->level;
  if (_session.revision() == _shownRevision) return;
  _shownRevision = _session.revision();

  const BOOL phaseChanged = _session.phase().index() != _shownPhase;
  _shownPhase = _session.phase().index();
  // Going idle straight from listening or processing means it was
  // cancelled, or nothing was said.
  const BOOL endedWithoutText = _wasCapturing;
  _wasCapturing = std::holds_alternative<sotto::Listening>(_session.phase()) ||
                  std::holds_alternative<sotto::Processing>(_session.phase());

  _session.match(
      [&](const sotto::Idle &) {
        if (phaseChanged && endedWithoutText) [self playSound:@"cancel"];
        [_hud dismiss];
        [_timer invalidate];
        _timer = nil;
      },
      [&](const sotto::Listening &l) {
        if (phaseChanged) {
          [self playSound:@"start"];
          [self announce:@"Listening"];
        }
        [_hud showListeningWithFinalized:String(l.transcript.finalized) tentative:String(l.transcript.tentative)];
      },
      [&](const sotto::Processing &p) {
        if (phaseChanged) [self playSound:@"stop"];
        [_hud showProcessingWithText:String(p.text)];
      },
      [&](const sotto::Finished &f) {
        NSString *text = String(f.text);
        if (!RecognizerService.selected.insertsText || [TextInserter insert:text]) {
          [_hud showFinishedWithText:text];
        } else {
          // Not allowed to type yet: the text waits on the clipboard.
          [_hud showMessageWithSymbolName:@"doc.on.clipboard" message:@"Copied to Clipboard"];
        }
        [self announce:text];
        if ([NSUserDefaults.standardUserDefaults boolForKey:kKeepRecentsKey]) {
          [_recents insertObject:text atIndex:0];
          if (_recents.count > kMaxRecents) [_recents removeLastObject];
        }
      },
      [&](const sotto::Failed &failed) {
        if (phaseChanged) [self playSound:@"error"];
        switch (failed.reason) {
          case sotto::Failure::MicrophoneAccessDenied:
            return [_hud showMessageWithSymbolName:@"mic.slash.fill" message:@"Sotto can’t access the microphone"];
          case sotto::Failure::MicrophoneSilent:
            return [_hud showMessageWithSymbolName:@"mic.slash.fill" message:@"No sound from the microphone. Choose another in Settings."];
          case sotto::Failure::APIKeyMissing:
            return [_hud showMessageWithSymbolName:@"key.fill" message:@"Add your API key in Sotto Settings"];
          case sotto::Failure::APIKeyRejected:
            return [_hud showMessageWithSymbolName:@"key.fill" message:@"The API key wasn’t accepted"];
          case sotto::Failure::ServiceUnavailable:
            return [_hud showMessageWithSymbolName:@"wifi.exclamationmark" message:@"Couldn’t reach the dictation service"];
        }
      });

  if (phaseChanged) {
    [self updateEscapeKey];
    [NSNotificationCenter.defaultCenter postNotificationName:DictationDidChangeNotification object:self];
  }
}

// Escape cancels, but only while dictation is on screen, so other apps
// keep the key the rest of the time.
- (void)updateEscapeKey {
  if (!_session.active()) {
    _escapeKey = nil;
  } else if (!_escapeKey) {
    __weak DictationController *weakSelf = self;
    _escapeKey = [[HotKey alloc] initWithKeyCode:kVK_Escape modifiers:0 pressed:^{ [weakSelf cancel]; } released:nil];
  }
}

// Plays one of the feedback sounds in Resources/Sounds.
- (void)playSound:(NSString *)name {
  if (![NSUserDefaults.standardUserDefaults boolForKey:kPlaySoundsKey]) return;
  static NSMutableDictionary<NSString *, NSSound *> *sounds = [NSMutableDictionary new];
  NSSound *sound = sounds[name];
  if (!sound) {
    NSURL *url = [NSBundle.mainBundle URLForResource:name withExtension:@"wav" subdirectory:@"Sounds"];
    sound = url ? [[NSSound alloc] initWithContentsOfURL:url byReference:YES] : nil;
    sound.volume = 0.5;
    sounds[name] = sound;
  }
  [sound stop];  // so a quick repeat restarts it
  [sound play];
}

// The HUD never takes focus, so tell VoiceOver what happened.
- (void)announce:(NSString *)announcement {
  NSAccessibilityPostNotificationWithUserInfo(NSApp, NSAccessibilityAnnouncementRequestedNotification, @{
    NSAccessibilityAnnouncementKey : announcement,
    NSAccessibilityPriorityKey : @(NSAccessibilityPriorityMedium),
  });
}

@end
