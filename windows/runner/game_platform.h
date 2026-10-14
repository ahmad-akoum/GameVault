#pragma once
#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>

class GamePlatform {
 public:
  explicit GamePlatform(flutter::BinaryMessenger* messenger);
 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
