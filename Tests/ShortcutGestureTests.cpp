#include "ShortcutGesture.hpp"

#include <cstdlib>
#include <print>
#include <source_location>
#include <string_view>

using namespace sotto;
using namespace std::chrono_literals;
using enum GestureCommand;

namespace {

int failures = 0;

void expect(GestureCommand got, GestureCommand want, std::string_view what,
            std::source_location at = std::source_location::current()) {
  if (got == want) return;
  ++failures;
  std::println(stderr, "FAIL line {}: {} (got {}, want {})", at.line(), what, static_cast<int>(got),
               static_cast<int>(want));
}

ShortcutGesture gesture(ShortcutMode mode) {
  ShortcutGesture g;
  g.set_mode(mode);
  return g;
}

void hold_mode() {
  auto g = gesture(ShortcutMode::Hold);
  expect(g.press(0s, false), Start, "press starts");
  expect(g.release(0.1s), Finish, "even a short hold finishes on release");
  expect(g.press(1s, false), Start, "starts again");
  expect(g.release(4s), Finish, "long hold finishes on release");
}

void tap_mode() {
  auto g = gesture(ShortcutMode::Tap);
  expect(g.press(0s, false), Start, "tap starts");
  expect(g.release(0.1s), None, "release does nothing");
  expect(g.poll(5s), None, "keeps going hands-free");
  expect(g.press(6s, true), Finish, "second tap finishes");
  expect(g.release(6.1s), None, "release does nothing");
  expect(g.press(7s, false), Start, "third tap starts again");
  // The session ended by itself (silence, Escape); the next tap starts a new one.
  expect(g.press(20s, false), Start, "tap after the session ended starts a new one");
}

void hold_or_double_tap_hold() {
  auto g = gesture(ShortcutMode::HoldOrDoubleTap);
  expect(g.press(0s, false), Start, "press starts");
  expect(g.poll(1s), None, "holding");
  expect(g.release(2s), Finish, "release after a hold finishes");
}

void hold_or_double_tap_double_tap() {
  auto g = gesture(ShortcutMode::HoldOrDoubleTap);
  expect(g.press(0s, false), Start, "first tap starts");
  expect(g.release(0.1s), None, "first tap ends, wait for a second");
  expect(g.poll(0.2s), None, "still inside the window");
  expect(g.press(0.3s, true), None, "second tap keeps the session");
  expect(g.release(0.4s), None, "hands-free now");
  expect(g.poll(10s), None, "no timeout while hands-free");
  expect(g.press(11s, true), Finish, "next press finishes");
  expect(g.release(11.1s), None, "and its release does nothing");
}

void hold_or_double_tap_single_tap_cancels() {
  auto g = gesture(ShortcutMode::HoldOrDoubleTap);
  expect(g.press(0s, false), Start, "tap starts");
  expect(g.release(0.1s), None, "tap ends");
  expect(g.poll(0.6s), Cancel, "no second tap: cancel");
  expect(g.poll(0.7s), None, "cancel is reported once");
  expect(g.press(1s, false), Start, "works again afterwards");
}

void double_tap_mode() {
  auto g = gesture(ShortcutMode::DoubleTap);
  expect(g.press(0s, false), None, "first tap starts nothing");
  expect(g.release(0.1s), None, "first tap ends");
  expect(g.press(0.3s, false), Start, "second tap starts");
  expect(g.release(0.4s), None, "hands-free");
  expect(g.press(5s, true), Finish, "a tap finishes");

  expect(g.press(10s, false), None, "first tap");
  expect(g.release(10.1s), None, "ends");
  expect(g.poll(11s), None, "a lone tap never cancels anything");
  expect(g.press(12s, false), None, "too late: counts as a new first tap");
  expect(g.release(13s), None, "a long press is not a tap");
  expect(g.press(13.1s, false), None, "so this is a first tap again");
}

void changing_mode_resets() {
  auto g = gesture(ShortcutMode::Tap);
  expect(g.press(0s, false), Start, "tap starts");
  g.set_mode(ShortcutMode::Hold);
  expect(g.press(1s, true), Finish, "a press finishes a session the gesture didn't start");
  expect(g.press(2s, false), Start, "and the new mode starts from idle");
}

}  // namespace

int main() {
  hold_mode();
  tap_mode();
  hold_or_double_tap_hold();
  hold_or_double_tap_double_tap();
  hold_or_double_tap_single_tap_cancels();
  double_tap_mode();
  changing_mode_resets();
  if (failures == 0) std::println("all shortcut gesture tests passed");
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
