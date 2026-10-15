#pragma once
#include <cstddef>
#include <cstdint>
#include <cstdlib>

// Original activity-only parser for standard DualSense (054c:0ce6).
// Report layouts: USB 01/64, Bluetooth simple 01/10 (may be padded),
// Bluetooth enhanced 31/78. No feature/output reports or mode changes.
inline bool DualSenseActive(const uint8_t* report, size_t size) {
  if (!report || size == 0) return false;
  size_t axes, buttons, triggers;
  if (report[0] == 0x31 && size == 78) {
    axes = 2; triggers = 6; buttons = 9;
  } else if (report[0] == 0x01 && size == 64) {
    axes = 1; triggers = 5; buttons = 8;
  } else if (report[0] == 0x01 && (size == 10 || size == 78)) {
    axes = 1; buttons = 5; triggers = 8;
  } else {
    return false; // Unknown reports must never manufacture activity.
  }
  for (size_t i = 0; i < 4; ++i) {
    if (std::abs(static_cast<int>(report[axes + i]) - 128) > 24) return true;
  }
  if (report[triggers] > 30 || report[triggers + 1] > 30) return true;
  return (report[buttons] & 0xf0) != 0 || (report[buttons] & 0x0f) < 8 ||
      report[buttons + 1] != 0 || (report[buttons + 2] & 0x03) != 0;
}
