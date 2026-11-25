#include "ShortcutGesture.hpp"

namespace sotto {

void ShortcutGesture::set_mode(ShortcutMode mode) {
  mode_ = mode;
  state_ = Idle{};
}

GestureCommand ShortcutGesture::press(Seconds now, bool dictating) {
  // In DoubleTap mode the first tap happens before any session exists.
  const bool waiting_for_start = mode_ == ShortcutMode::DoubleTap && std::holds_alternative<AwaitingSecondTap>(state_);
  if (!dictating && !waiting_for_start) state_ = Idle{};

  // Also finishes a session that was started some other way, like the menu.
  if (std::holds_alternative<HandsFree>(state_) || (dictating && std::holds_alternative<Idle>(state_))) {
    state_ = Idle{};
    return GestureCommand::Finish;
  }

  switch (mode_) {
    case ShortcutMode::Hold:
      state_ = Holding{now};
      return GestureCommand::Start;

    case ShortcutMode::Tap:
      state_ = HandsFree{};
      return GestureCommand::Start;

    case ShortcutMode::HoldOrDoubleTap:
      if (std::holds_alternative<AwaitingSecondTap>(state_)) {
        state_ = HandsFree{};  // the session from the first tap keeps going
        return GestureCommand::None;
      }
      state_ = Holding{now};
      return GestureCommand::Start;

    case ShortcutMode::DoubleTap:
      if (auto* first = std::get_if<AwaitingSecondTap>(&state_); first && now - first->since <= kDoubleTapWindow) {
        state_ = HandsFree{};
        return GestureCommand::Start;
      }
      state_ = Holding{now};  // possibly the first tap; nothing starts yet
      return GestureCommand::None;
  }
  return GestureCommand::None;
}

GestureCommand ShortcutGesture::release(Seconds now) {
  auto* holding = std::get_if<Holding>(&state_);
  if (!holding) return GestureCommand::None;
  const bool tapped = now - holding->since < kTapLimit;

  switch (mode_) {
    case ShortcutMode::Hold:
      state_ = Idle{};
      return GestureCommand::Finish;

    case ShortcutMode::HoldOrDoubleTap:
      if (tapped) {
        state_ = AwaitingSecondTap{now};
        return GestureCommand::None;
      }
      state_ = Idle{};
      return GestureCommand::Finish;

    case ShortcutMode::DoubleTap:
      state_ = tapped ? State{AwaitingSecondTap{now}} : State{Idle{}};
      return GestureCommand::None;

    case ShortcutMode::Tap:
      break;
  }
  return GestureCommand::None;
}

GestureCommand ShortcutGesture::poll(Seconds now) {
  auto* first = std::get_if<AwaitingSecondTap>(&state_);
  if (!first || now - first->since <= kDoubleTapWindow) return GestureCommand::None;
  state_ = Idle{};
  // Only HoldOrDoubleTap started a session on the first tap.
  return mode_ == ShortcutMode::HoldOrDoubleTap ? GestureCommand::Cancel : GestureCommand::None;
}

}  // namespace sotto
