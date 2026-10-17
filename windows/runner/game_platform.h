#pragma once
#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>
#include <windows.h>
#include <unordered_map>
#include "input_activity.h"

class GamePlatform {
 public:
  explicit GamePlatform(flutter::BinaryMessenger* messenger, HWND window);
  ~GamePlatform();
  void HandleInput(UINT message, LPARAM data);
 private:
  HWND window_;
  bool registered_ = false;
  ULONGLONG last_dualsense_ = 0;
  ULONGLONG last_keyboard_mouse_ = 0, last_xinput_ = 0;
  std::array<ControllerActivity, 4> xinput_activity_;
  std::unordered_map<HANDLE, ControllerActivity> dualsense_activity_;
  std::unordered_map<HANDLE, MouseActivity> mouse_activity_;
  int IdleSeconds();
  std::unordered_map<HANDLE, bool> devices_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
