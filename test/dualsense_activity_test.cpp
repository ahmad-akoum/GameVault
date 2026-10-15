#include "../windows/runner/dualsense_activity.h"
#include <array>
#include <cassert>
#include <iostream>
int main() {
  for (int mode = 0; mode < 4; ++mode) {
    std::array<uint8_t, 78> r{};
    size_t size = mode == 0 ? 64 : mode == 1 ? 10 : 78;
    r[0] = mode == 2 ? 0x31 : 0x01;
    size_t a = mode == 2 ? 2 : 1, t = mode == 2 ? 6 : mode == 0 ? 5 : 8;
    size_t b = mode == 2 ? 9 : mode == 0 ? 8 : 5;
    for (size_t i = 0; i < 4; ++i) r[a+i] = 128;
    r[b] = 8;
    assert(!DualSenseActive(r.data(),size));
    for (size_t i = 0; i < 4; ++i) {
      r[a+i] = 152; assert(!DualSenseActive(r.data(),size));
      r[a+i] = 153; assert(DualSenseActive(r.data(),size));
      r[a+i] = 103; assert(DualSenseActive(r.data(),size)); r[a+i] = 128;
    }
    for (size_t i = 0; i < 2; ++i) {
      r[t+i] = 30; assert(!DualSenseActive(r.data(),size));
      r[t+i] = 31; assert(DualSenseActive(r.data(),size)); r[t+i] = 0;
    }
    for (int d = 0; d < 8; ++d) { r[b] = static_cast<uint8_t>(d); assert(DualSenseActive(r.data(),size)); }
    r[b] = 8;
    for (int bit = 4; bit < 8; ++bit) { r[b] = static_cast<uint8_t>(8 | (1 << bit)); assert(DualSenseActive(r.data(),size)); }
    r[b] = 8;
    for (int bit = 0; bit < 8; ++bit) { r[b+1] = static_cast<uint8_t>(1 << bit); assert(DualSenseActive(r.data(),size)); }
    r[b+1] = 0;
    r[b+2] = 0xfc; assert(!DualSenseActive(r.data(),size));
    assert(!DualSenseActive(r.data(),3));
    r[0] = 0xff; assert(!DualSenseActive(r.data(),size));
  }
  assert(!DualSenseActive(nullptr,0));
  std::cout << "DualSense neutral, drift, sticks, triggers, buttons, D-pad and malformed-report tests passed\n";
}
