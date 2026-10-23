#include "game_platform.h"
#include "dualsense_activity.h"
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <tlhelp32.h>
#include <xinput.h>
#include <algorithm>
#include <cwctype>
#include <set>
#include <string>
#include <stdexcept>
#include <vector>

namespace {
using V = flutter::EncodableValue;
using M = flutter::EncodableMap;
using L = flutter::EncodableList;
std::wstring Wide(const std::string& text) {
  if (text.empty()) return {};
  int length = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring out(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), length);
  return out;
}
std::wstring Normalize(std::wstring path) {
  std::transform(path.begin(), path.end(), path.begin(), [](wchar_t c) { return c == L'/' ? L'\\' : static_cast<wchar_t>(towlower(c)); });
  while (!path.empty() && path.back() == L'\\') path.pop_back();
  return path;
}
const V* Field(const M& map, const char* key) {
  auto it = map.find(V(key)); return it == map.end() ? nullptr : &it->second;
}
std::string Text(const M& map, const char* key) {
  auto v = Field(map, key); auto s = v ? std::get_if<std::string>(v) : nullptr;
  return s ? *s : "";
}
int64_t Number(const M& map, const char* key) {
  auto v = Field(map,key);
  if (!v) return 0;
  if (auto n = std::get_if<int32_t>(v)) return *n;
  if (auto n = std::get_if<int64_t>(v)) return *n;
  return 0;
}
bool Helper(const std::wstring& path) {
  auto name = path.substr(path.find_last_of(L'\\') + 1);
  for (const auto word : {L"launcher", L"crash", L"unins", L"setup", L"installer", L"updater", L"redist", L"anticheat", L"cef", L"webhelper"}) {
    if (name.find(word) != std::wstring::npos) return true;
  }
  return name == L"steam.exe" || name == L"gamevault.exe";
}
BOOL CALLBACK VisibleWindow(HWND window, LPARAM data) {
  if (IsWindowVisible(window) && GetWindow(window, GW_OWNER) == nullptr) {
    DWORD pid = 0; GetWindowThreadProcessId(window, &pid);
    reinterpret_cast<std::set<DWORD>*>(data)->insert(pid);
  }
  return TRUE;
}
struct Process { DWORD pid; std::wstring path; std::string token; bool visible; };
L Snapshot(const L& games) {
  if (games.empty()) return {};
  std::set<DWORD> visible;
  EnumWindows(VisibleWindow, reinterpret_cast<LPARAM>(&visible));
  DWORD foreground = 0; GetWindowThreadProcessId(GetForegroundWindow(), &foreground);
  std::vector<Process> processes;
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) throw std::runtime_error("Process snapshot unavailable");
  PROCESSENTRY32 entry{}; entry.dwSize = sizeof(entry);
  if (Process32First(snapshot,&entry)) do {
    HANDLE handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, entry.th32ProcessID);
    if (!handle) continue;  // Protected processes are never elevated or bypassed.
    wchar_t buffer[32768]; DWORD size = 32768;
    FILETIME created{}, exited{}, kernel{}, user{};
    if (QueryFullProcessImageName(handle,0,buffer,&size) && GetProcessTimes(handle,&created,&exited,&kernel,&user)) {
      auto path = Normalize(std::wstring(buffer,size));
      ULARGE_INTEGER timestamp{}; timestamp.LowPart = created.dwLowDateTime; timestamp.HighPart = created.dwHighDateTime;
      processes.push_back({entry.th32ProcessID,path,std::to_string(entry.th32ProcessID) + ":" + std::to_string(timestamp.QuadPart),visible.count(entry.th32ProcessID) != 0});
    }
    CloseHandle(handle);
  } while (Process32Next(snapshot,&entry));
  CloseHandle(snapshot);
  L result;
  for (const auto& value : games) {
    const auto* g = std::get_if<M>(&value); if (!g) continue;
    auto root = Normalize(Wide(Text(*g,"root")));
    auto exact = Normalize(Wide(Text(*g,"executable")));
    L tokens; bool focused = false;
    for (const auto& process : processes) {
      bool match = !exact.empty() ? process.path == exact :
        root.size() > 3 && process.path.compare(0,root.size()+1,root+L"\\") == 0 && process.visible && !Helper(process.path);
      // One process can belong to only one game. Prefer an explicit path, then
      // the most specific installation root; equal matches remain untracked.
      if (match) {
        const auto score = exact.empty() ? root.size() : static_cast<size_t>(65536);
        for (const auto& other_value : games) {
          const auto* other = std::get_if<M>(&other_value);
          if (!other || Number(*other,"id") == Number(*g,"id")) continue;
          auto other_exact = Normalize(Wide(Text(*other,"executable")));
          auto other_root = Normalize(Wide(Text(*other,"root")));
          bool other_match = !other_exact.empty() ? process.path == other_exact :
            other_root.size() > 3 && process.path.compare(0,other_root.size()+1,other_root+L"\\") == 0 && process.visible && !Helper(process.path);
          const auto other_score = other_exact.empty() ? other_root.size() : static_cast<size_t>(65536);
          if (other_match && other_score >= score) { match = false; break; }
        }
      }
      if (match) {
        tokens.emplace_back(process.token);
        focused = focused || process.pid == foreground;
      }
    }
    result.emplace_back(M{{V("id"),V(Number(*g,"id"))},{V("processes"),V(tokens)},{V("focused"),V(focused)}});
  }
  return result;
}
}

int GamePlatform::IdleSeconds() {
  if (!registered_) throw std::runtime_error("Physical input observation unavailable");
  const auto now = GetTickCount64();
  for (DWORD index = 0; index < XUSER_MAX_COUNT; ++index) {
    XINPUT_STATE state{};
    if (XInputGetState(index, &state) == ERROR_SUCCESS) {
      const auto& g = state.Gamepad;
      ControllerSample sample;
      sample.buttons = g.wButtons;
      sample.axes = {g.sThumbLX, g.sThumbLY, g.sThumbRX, g.sThumbRY};
      sample.triggers = {g.bLeftTrigger, g.bRightTrigger};
      if (xinput_activity_[index].Observe(sample,
          {XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE,
           XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE, XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE},
          1024, XINPUT_GAMEPAD_TRIGGER_THRESHOLD, 4)) last_xinput_ = now;
    } else {
      xinput_activity_[index].Reset();
    }
  }
  return ObservedIdleSeconds(now, last_keyboard_mouse_, last_dualsense_, last_xinput_);
}

GamePlatform::GamePlatform(flutter::BinaryMessenger* messenger, HWND window) : window_(window) {
  last_keyboard_mouse_ = GetTickCount64();
  RAWINPUTDEVICE devices[] = {
      {0x01, 0x05, RIDEV_INPUTSINK | RIDEV_DEVNOTIFY, window_},
      {0x01, 0x06, RIDEV_INPUTSINK | RIDEV_DEVNOTIFY, window_},
      {0x01, 0x02, RIDEV_INPUTSINK | RIDEV_DEVNOTIFY, window_}};
  registered_ = RegisterRawInputDevices(devices, 3, sizeof(RAWINPUTDEVICE)) != FALSE;
  channel_ = std::make_unique<flutter::MethodChannel<V>>(messenger,"gamevault/windows",&flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const flutter::MethodCall<V>& call, std::unique_ptr<flutter::MethodResult<V>> result) {
    const auto* args = call.arguments() ? std::get_if<M>(call.arguments()) : nullptr;
    if (!args) { result->Error("invalid_arguments","Expected game parameters"); return; }
    try {
      if (call.method_name() == "appVersion") {
        result->Success(V(FLUTTER_VERSION));
      } else if (call.method_name() == "steamStarted") {
        HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (snapshot == INVALID_HANDLE_VALUE) { result->Error("process_unavailable", "Steam status unavailable"); return; }
        PROCESSENTRY32 entry{}; entry.dwSize = sizeof(entry);
        int64_t started = 0;
        if (Process32First(snapshot, &entry)) do {
          if (_wcsicmp(entry.szExeFile, L"steam.exe") != 0) continue;
          HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, entry.th32ProcessID);
          if (!process) continue;
          FILETIME created{}, exited{}, kernel{}, user{};
          if (GetProcessTimes(process, &created, &exited, &kernel, &user)) {
            ULARGE_INTEGER ticks{}; ticks.LowPart = created.dwLowDateTime; ticks.HighPart = created.dwHighDateTime;
            const int64_t time = static_cast<int64_t>(ticks.QuadPart / 10000) - 11644473600000LL;
            if (!started || time < started) started = time;
          }
          CloseHandle(process);
        } while (Process32Next(snapshot, &entry));
        CloseHandle(snapshot);
        if (started) result->Success(V(started)); else result->Success();
      } else if (call.method_name() == "sample") {
        const auto* value = Field(*args,"games"); const auto* games = value ? std::get_if<L>(value) : nullptr;
        if (!games) { result->Error("invalid_arguments","Missing game list"); return; }
        result->Success(V(M{{V("games"),V(Snapshot(*games))},{V("idleSeconds"),V(IdleSeconds())}}));
      } else if (call.method_name() == "openLocation") {
        const auto path = Wide(Text(*args,"path"));
        if (path.size() < 3 || GetFileAttributes(path.c_str()) == INVALID_FILE_ATTRIBUTES) {
          result->Error("missing_location", "Location is unavailable"); return;
        }
        const auto* selected = Field(*args, "select");
        const bool select = selected && std::holds_alternative<bool>(*selected) && std::get<bool>(*selected);
        // Shell API accepts a file selection without constructing shell commands.
        PIDLIST_ABSOLUTE item = nullptr;
        const HRESULT parsed = SHParseDisplayName(path.c_str(), nullptr, &item, 0, nullptr);
        if (FAILED(parsed)) { result->Error("location_failed", "Location could not be resolved"); return; }
        HRESULT opened = select ? SHOpenFolderAndSelectItems(item, 0, nullptr, 0) : E_FAIL;
        CoTaskMemFree(item);
        if (!select || FAILED(opened)) {
          const auto folder = select ? path.substr(0, path.find_last_of(L"\\/")) : path;
          const auto status = reinterpret_cast<INT_PTR>(ShellExecute(nullptr, L"open", folder.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
          if (status <= 32) { result->Error("location_failed", "Folder could not be opened"); return; }
        }
        result->Success();
      } else if (call.method_name() == "launch" || call.method_name() == "openWeb" || call.method_name() == "openSteam") {
        std::wstring target, directory;
        if (call.method_name() == "openWeb") {
          target = Wide(Text(*args,"url"));
          if (target.rfind(L"https://",0) != 0) { result->Error("invalid_url","HTTPS required"); return; }
        } else if (Number(*args,"steamId") > 0) {
          target = (call.method_name() == "openSteam" ? L"steam://nav/games/details/" : L"steam://rungameid/") + std::to_wstring(Number(*args,"steamId"));
        } else {
          target = Wide(Text(*args,"executable"));
          auto normalized = Normalize(target);
          if (normalized.size() < 7 || normalized.substr(normalized.size()-4) != L".exe" || GetFileAttributes(target.c_str()) == INVALID_FILE_ATTRIBUTES) {
            result->Error("missing_executable","Executable not found"); return;
          }
          directory = target.substr(0,target.find_last_of(L"\\/"));
        }
        auto status = reinterpret_cast<INT_PTR>(ShellExecute(nullptr,L"open",target.c_str(),nullptr,directory.empty() ? nullptr : directory.c_str(),SW_SHOWNORMAL));
        if (status <= 32) result->Error("launch_failed","Windows could not open the game or link (code " + std::to_string(status) + ")");
        else result->Success();
      } else result->NotImplemented();
    } catch (const std::exception& e) { result->Error("platform_error",e.what()); }
  });
}

GamePlatform::~GamePlatform() {
  if (registered_) {
    RAWINPUTDEVICE devices[] = {{0x01, 0x05, RIDEV_REMOVE, nullptr},
        {0x01, 0x06, RIDEV_REMOVE, nullptr}, {0x01, 0x02, RIDEV_REMOVE, nullptr}};
    RegisterRawInputDevices(devices, 3, sizeof(RAWINPUTDEVICE));
  }
}

void GamePlatform::HandleInput(UINT message, LPARAM data) {
  if (message == WM_INPUT_DEVICE_CHANGE) {
    const auto device = reinterpret_cast<HANDLE>(data);
    devices_.erase(device);
    dualsense_activity_.erase(device);
    mouse_activity_.erase(device);
    return;
  }
  if (message != WM_INPUT || !registered_) return;
  UINT size = 0;
  auto handle = reinterpret_cast<HRAWINPUT>(data);
  if (GetRawInputData(handle, RID_INPUT, nullptr, &size, sizeof(RAWINPUTHEADER)) != 0 ||
      size < sizeof(RAWINPUTHEADER) || size > 65536) return;
  std::vector<BYTE> bytes(size);
  if (GetRawInputData(handle, RID_INPUT, bytes.data(), &size, sizeof(RAWINPUTHEADER)) != size) return;
  const auto* input = reinterpret_cast<const RAWINPUT*>(bytes.data());
  // Synthetic cursor recentering/SendInput must not refresh physical idle time.
  if (!input->header.hDevice) return;
  if (input->header.dwType == RIM_TYPEKEYBOARD && size >= offsetof(RAWINPUT, data) + sizeof(RAWKEYBOARD)) {
    if (input->data.keyboard.VKey != 255) last_keyboard_mouse_ = GetTickCount64();
    return;
  }
  if (input->header.dwType == RIM_TYPEMOUSE && size >= offsetof(RAWINPUT, data) + sizeof(RAWMOUSE)) {
    const auto& mouse = input->data.mouse;
    if (mouse_activity_[input->header.hDevice].Observe(
        (mouse.usFlags & MOUSE_MOVE_ABSOLUTE) != 0, mouse.lLastX, mouse.lLastY,
        mouse.usButtonFlags)) last_keyboard_mouse_ = GetTickCount64();
    return;
  }
  if (input->header.dwType != RIM_TYPEHID || size < offsetof(RAWINPUT, data.hid.bRawData)) return;
  auto found = devices_.find(input->header.hDevice);
  if (found == devices_.end()) {
    RID_DEVICE_INFO info{}; info.cbSize = sizeof(info); UINT length = sizeof(info);
    bool supported = GetRawInputDeviceInfo(input->header.hDevice, RIDI_DEVICEINFO, &info, &length) != UINT(-1) &&
        info.dwType == RIM_TYPEHID && info.hid.dwVendorId == 0x054c && info.hid.dwProductId == 0x0ce6;
    found = devices_.emplace(input->header.hDevice, supported).first;
  }
  if (!found->second) return;
  const auto& hid = input->data.hid;
  const size_t available = size - offsetof(RAWINPUT, data.hid.bRawData);
  if (!hid.dwSizeHid || hid.dwCount > available / hid.dwSizeHid) return;
  for (DWORD i = 0; i < hid.dwCount; ++i) {
    ControllerSample sample;
    if (DecodeDualSense(hid.bRawData + static_cast<size_t>(i) * hid.dwSizeHid, hid.dwSizeHid, sample) &&
        dualsense_activity_[input->header.hDevice].Observe(sample, {24,24,24,24}, 4, 30, 4)) {
      last_dualsense_ = GetTickCount64();
      // Process every report in a batch so the device anchor stays current.
    }
  }
}
