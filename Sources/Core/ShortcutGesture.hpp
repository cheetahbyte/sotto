#pragma once

#include <chrono>
#include <variant>

// Turns presses and releases of the dictation shortcut into commands,
// according to the shortcut mode chosen in Settings.
namespace sotto {

enum class ShortcutMode {
  HoldOrDoubleTap,  // hold to talk, or double-tap to talk hands-free
  Hold,             // hold to talk, let go to finish
  Tap,              // tap to talk hands-free, tap again to finish
  DoubleTap,        // double-tap to talk hands-free, tap to finish
};

enum class GestureCommand { None, Start, Finish, Cancel };

class ShortcutGesture {
 public:
  using Seconds = std::chrono::duration<double>;

  // A press shorter than this is a tap, not a hold.
  static constexpr Seconds kTapLimit{0.3};
  // The second tap of a double-tap must begin this soon after the first ends.
  static constexpr Seconds kDoubleTapWindow{0.35};

  void set_mode(ShortcutMode mode);
  [[nodiscard]] ShortcutMode mode() const { return mode_; }

  // `now` is any monotonic clock. `dictating` says whether a session is
  // listening right now; sessions also end on their own, and the gesture
  // starts over when that happened.
  [[nodiscard]] GestureCommand press(Seconds now, bool dictating);
  [[nodiscard]] GestureCommand release(Seconds now);
  // Call regularly while dictating. Returns Cancel when a single tap in
  // HoldOrDoubleTap mode was not followed by a second one.
  [[nodiscard]] GestureCommand poll(Seconds now);

 private:
  struct Idle {};
  struct Holding { Seconds since; };            // key down, talking
  struct AwaitingSecondTap { Seconds since; };  // first tap ended
  struct HandsFree {};                          // talking with the key up

  using State = std::variant<Idle, Holding, AwaitingSecondTap, HandsFree>;

  ShortcutMode mode_ = ShortcutMode::HoldOrDoubleTap;
  State state_ = Idle{};
};

}  // namespace sotto
