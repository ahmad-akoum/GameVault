#pragma once
#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>
#include <windows.h>
#include <unordered_map>

class GamePlatform {
 public:
  explicit GamePlatform(flutter::BinaryMessenger* messenger, HWND window);
  ~GamePlatform();
  void HandleInput(UINT message, LPARAM data);
 private:
  HWND window_;
  bool registered_ = false;
  ULONGLONG last_dualsense_ = 0;
  std::unordered_map<HANDLE, bool> devices_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
