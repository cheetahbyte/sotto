#pragma once

#include <chrono>
#include <cstdint>
#include <variant>

namespace sotto {
enum class ShortcutMode : std::uint8_t {
  HoldOrDoubleTap,
  Hold,
  Tap,
  DoubleTap,
};

enum class GestureCommand : std::uint8_t { None, Start, Finish, Cancel };

class ShortcutGesture {
 public:
  using Seconds = std::chrono::duration<double>;

  static constexpr Seconds kTapLimit{0.3};
  static constexpr Seconds kDoubleTapWindow{0.35};

  void set_mode(ShortcutMode mode);
  [[nodiscard]] ShortcutMode mode() const { return mode_; }

  [[nodiscard]] GestureCommand press(Seconds now, bool dictating);
  [[nodiscard]] GestureCommand release(Seconds now);
  [[nodiscard]] GestureCommand poll(Seconds now);

 private:
  struct Idle {};
  struct Holding { Seconds since; };
  struct AwaitingSecondTap { Seconds since; };
  struct HandsFree {};

  using State = std::variant<Idle, Holding, AwaitingSecondTap, HandsFree>;

  ShortcutMode mode_ = ShortcutMode::HoldOrDoubleTap;
  State state_ = Idle{};
};

}
