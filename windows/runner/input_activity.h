#pragma once
#include <array>
#include <algorithm>
#include <cstdint>
#include <cstdlib>

struct ControllerSample {
  uint32_t buttons = 0;
  std::array<int, 4> axes{};
  std::array<int, 2> triggers{};
};

// One short-lived anchor per device. No input history is persisted or logged.
class ControllerActivity {
 public:
  bool Observe(const ControllerSample& current, const std::array<int, 4>& deadzones,
               int axisNoise, int triggerThreshold, int triggerNoise) {
    bool changed = current.buttons != previous_.buttons;
    for (size_t i = 0; i < 4; ++i) {
      if ((std::abs(current.axes[i]) > deadzones[i] ||
           std::abs(previous_.axes[i]) > deadzones[i]) &&
          std::abs(current.axes[i] - previous_.axes[i]) > axisNoise) changed = true;
    }
    for (size_t i = 0; i < 2; ++i) {
      if ((current.triggers[i] > triggerThreshold || previous_.triggers[i] > triggerThreshold) &&
          std::abs(current.triggers[i] - previous_.triggers[i]) > triggerNoise) changed = true;
    }
    if (changed) previous_ = current;
    return changed;
  }
  void Reset() { previous_ = {}; }
 private:
  ControllerSample previous_{};
};

// Physical relative movement, button edges and wheels count; empty reports do not.
// Absolute devices compare coordinates instead of treating a stationary position as motion.
class MouseActivity {
 public:
  bool Observe(bool absolute, long x, long y, unsigned short buttons) {
    const bool moved = absolute ? (absolute_ && (x != x_ || y != y_)) : (x != 0 || y != 0);
    absolute_ = absolute; x_ = x; y_ = y;
    return moved || buttons != 0;
  }
 private:
  bool absolute_ = false;
  long x_ = 0, y_ = 0;
};

inline int ObservedIdleSeconds(uint64_t now, uint64_t keyboardMouse,
                               uint64_t dualsense, uint64_t xinput) {
  const auto last = std::max({keyboardMouse, dualsense, xinput});
  return static_cast<int>(std::min<uint64_t>((now >= last ? now - last : 0) / 1000, INT32_MAX));
}
