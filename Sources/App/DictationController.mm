#import "DictationController.h"

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

#import "Defaults.h"
#import "DictationHUD.h"
#import "FeedbackSound.h"
#import "HotKey.h"
#import "Recognizers.h"
#import "Session.hpp"
#import "Shortcut.h"
#import "ShortcutGesture.hpp"
#import "TextInserter.h"

NSNotificationName const DictationDidChangeNotification = @"DictationDidChange";

static const NSUInteger kMaxRecents = 8;
static const NSTimeInterval kTickInterval = 1.0 / 60;

static NSString *String(const std::string &s) { return [NSString stringWithUTF8String:s.c_str()] ?: @""; }

static sotto::Seconds Now() { return sotto::Seconds{CACurrentMediaTime()}; }

struct FailureMessage {
  NSString *symbol;
  NSString *text;
};

static FailureMessage MessageFor(sotto::Failure reason) {
  switch (reason) {
    case sotto::Failure::MicrophoneAccessDenied:
      return {@"mic.slash.fill", @"Sotto can’t access the microphone"};
    case sotto::Failure::MicrophoneSilent:
      return {@"mic.slash.fill", @"No sound from the microphone. Choose another in Settings."};
    case sotto::Failure::APIKeyMissing:
      return {@"key.fill", @"Add your API key in Sotto Settings"};
    case sotto::Failure::APIKeyRejected:
      return {@"key.fill", @"The API key wasn’t accepted"};
    case sotto::Failure::ServiceUnavailable:
      return {@"wifi.exclamationmark", @"Couldn’t reach the dictation service"};
  }
}

static void Announce(NSString *announcement) {
  NSAccessibilityPostNotificationWithUserInfo(NSApp, NSAccessibilityAnnouncementRequestedNotification, @{
    NSAccessibilityAnnouncementKey : announcement,
    NSAccessibilityPriorityKey : @(NSAccessibilityPriorityMedium),
  });
}

@implementation DictationController {
  sotto::Session _session;
  sotto::ShortcutGesture _gesture;
  ShortcutMonitor *_shortcut;
  HotKey *_escapeKey;
  DictationHUD *_hud;
  NSMutableArray<NSString *> *_recents;
  NSTimer *_timer;
  sotto::Seconds _lastTick;
  uint64_t _shownRevision;
  size_t _shownPhase;
  BOOL _wasCapturing;
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
  [self perform:_session.active() ? sotto::GestureCommand::Finish : sotto::GestureCommand::Start];
}

- (void)cancel {
  _session.cancel();
  [self show];
}

- (void)clearRecents {
  [_recents removeAllObjects];
  [NSNotificationCenter.defaultCenter postNotificationName:DictationDidChangeNotification object:self];
}

#pragma mark Shortcut

- (void)shortcutPressed {
  const auto mode = static_cast<sotto::ShortcutMode>([NSUserDefaults.standardUserDefaults integerForKey:kShortcutModeKey]);
  if (_gesture.mode() != mode) _gesture.set_mode(mode);
  [self perform:_gesture.press(Now(), _session.listening())];
}

- (void)shortcutReleased {
  [self perform:_gesture.release(Now())];
}

- (void)perform:(sotto::GestureCommand)command {
  switch (command) {
    case sotto::GestureCommand::None:
      return;
    case sotto::GestureCommand::Start:
      if (_session.start([RecognizerService.selected makeRecognizer])) [self startTicking];
      break;
    case sotto::GestureCommand::Finish:
      (void)_session.stop();
      break;
    case sotto::GestureCommand::Cancel:
      if (_session.listening()) _session.cancel();
      break;
  }
  [self show];
}

#pragma mark Clock

- (void)startTicking {
  if (_timer) return;
  _lastTick = Now();
  _timer = [NSTimer timerWithTimeInterval:kTickInterval target:self selector:@selector(tick:) userInfo:nil repeats:YES];
  [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)stopTicking {
  [_timer invalidate];
  _timer = nil;
}

- (void)tick:(NSTimer *)timer {
  const sotto::Seconds now = Now();
  _session.advance(now - _lastTick);
  _lastTick = now;
  [self perform:_gesture.poll(now)];
  [self show];
}

#pragma mark Presentation

- (void)show {
  if (auto *listening = std::get_if<sotto::Listening>(&_session.phase())) _hud.level = listening->level;
  if (_session.revision() == _shownRevision) return;
  _shownRevision = _session.revision();

  if (_session.phase().index() != _shownPhase) {
    _shownPhase = _session.phase().index();
    [self phaseDidChange];
  }
  _session.match(
      [&](const sotto::Listening &listening) {
        [_hud showListeningWithFinalized:String(listening.transcript.finalized)
                               tentative:String(listening.transcript.tentative)];
      },
      [&](const sotto::Processing &processing) { [_hud showProcessingWithText:String(processing.text)]; },
      [](const auto &) {});
}

- (void)phaseDidChange {
  const BOOL endedWithoutText = _wasCapturing;
  _wasCapturing = _session.capturing();

  _session.match(
      [&](const sotto::Idle &) {
        if (endedWithoutText) PlayFeedbackSound(FeedbackSoundCancel);
        [_hud dismiss];
        [self stopTicking];
      },
      [&](const sotto::Listening &) {
        PlayFeedbackSound(FeedbackSoundStart);
        Announce(@"Listening");
      },
      [&](const sotto::Processing &) { PlayFeedbackSound(FeedbackSoundStop); },
      [&](const sotto::Finished &finished) { [self deliver:String(finished.text)]; },
      [&](const sotto::Failed &failed) {
        const FailureMessage message = MessageFor(failed.reason);
        PlayFeedbackSound(FeedbackSoundError);
        [_hud showMessageWithSymbolName:message.symbol message:message.text];
      });

  [self updateEscapeKey];
  [NSNotificationCenter.defaultCenter postNotificationName:DictationDidChangeNotification object:self];
}

- (void)deliver:(NSString *)text {
  if ([TextInserter insert:text]) {
    [_hud showFinishedWithText:text];
  } else {
    [_hud showMessageWithSymbolName:@"doc.on.clipboard" message:@"Copied to Clipboard"];
  }
  Announce(text);
  if (![NSUserDefaults.standardUserDefaults boolForKey:kKeepRecentsKey]) return;
  [_recents insertObject:text atIndex:0];
  if (_recents.count > kMaxRecents) [_recents removeLastObject];
}

- (void)updateEscapeKey {
  if (!_session.active()) {
    _escapeKey = nil;
  } else if (!_escapeKey) {
    __weak DictationController *weakSelf = self;
    _escapeKey = [[HotKey alloc] initWithKeyCode:kVK_Escape modifiers:0 pressed:^{ [weakSelf cancel]; } released:nil];
  }
}

@end
