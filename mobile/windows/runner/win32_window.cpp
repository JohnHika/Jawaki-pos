#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include <algorithm>
#include <cstdint>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

// The smallest client area (logical pixels) the window can be dragged to.
// Narrower than this the app would fall back to its phone layout.
constexpr int kMinClientWidth = 900;
constexpr int kMinClientHeight = 560;

// Where the last window size and position are kept (per Windows user).
constexpr wchar_t kPlacementKey[] = L"Software\\ArcheAxon\\Counterbase\\Window";
constexpr wchar_t kPlacementValue[] = L"Placement";

// All 32-bit fields so there is no padding to worry about.
struct SavedPlacement {
  uint32_t version;                  // 1
  int32_t left, top, right, bottom;  // restored rectangle, screen pixels
  uint32_t dpi;                      // window DPI when it was captured
  uint32_t maximized;                // 0 or 1
};

// Windows build number, or 0 when it cannot be read.
DWORD WindowsBuildNumber() {
  static const DWORD build = [] {
    using RtlGetVersionFn = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    auto fn = ntdll ? reinterpret_cast<RtlGetVersionFn>(
                          GetProcAddress(ntdll, "RtlGetVersion"))
                    : nullptr;
    RTL_OSVERSIONINFOW info{};
    info.dwOSVersionInfoSize = sizeof(info);
    return (fn && fn(&info) == 0) ? info.dwBuildNumber : 0UL;
  }();
  return build;
}

// Smallest outer window size that still leaves the minimum client area at the
// window's DPI, capped to the monitor's work area so a small screen is never
// forced to scroll off the desktop.
POINT MinTrackSize(HWND hwnd) {
  UINT dpi = GetDpiForWindow(hwnd);
  if (dpi == 0) {
    dpi = 96;
  }
  const double scale = dpi / 96.0;
  RECT frame{0, 0, Scale(kMinClientWidth, scale),
             Scale(kMinClientHeight, scale)};
  AdjustWindowRectExForDpi(
      &frame, static_cast<DWORD>(GetWindowLongPtr(hwnd, GWL_STYLE)), FALSE,
      static_cast<DWORD>(GetWindowLongPtr(hwnd, GWL_EXSTYLE)), dpi);
  LONG width = frame.right - frame.left;
  LONG height = frame.bottom - frame.top;
  MONITORINFO info{sizeof(info)};
  if (GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                     &info)) {
    width = std::min<LONG>(width, info.rcWork.right - info.rcWork.left);
    height = std::min<LONG>(height, info.rcWork.bottom - info.rcWork.top);
  }
  return {width, height};
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  // Restore the last size and position before the Flutter view is created, so
  // it starts at its final size.
  ApplyInitialPlacement(window);

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_,
                    start_maximized_ ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      const POINT minimum = MinTrackSize(hwnd);
      info->ptMinTrackSize.x = minimum.x;
      info->ptMinTrackSize.y = minimum.y;
      return 0;
    }

    case WM_EXITSIZEMOVE:
      // After a drag or resize: cheap protection if the app is later killed.
      SavePlacement(hwnd);
      return 0;

    case WM_DESTROY:
      // Not WM_CLOSE: Flutter's lifecycle handling can hold a close back.
      SavePlacement(hwnd);
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      if (wparam == SIZE_MAXIMIZED) {
        maximized_ = true;
      } else if (wparam == SIZE_RESTORED) {
        maximized_ = false;
        RememberNormalBounds(hwnd);
      }
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      if (!title_bar_themed_) {
        UpdateTheme(hwnd);
      }
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}

void Win32Window::ApplyTitleBarTheme(bool dark, COLORREF caption,
                                     COLORREF text, COLORREF border) {
  HWND hwnd = window_handle_;
  if (!hwnd) {
    return;
  }
  // From here on the app, not the system accent colour, decides the frame.
  title_bar_themed_ = true;
  const DWORD build = WindowsBuildNumber();
  if (build >= 17763) {  // Windows 10 1809 and later
    const BOOL use_dark = dark ? TRUE : FALSE;
    DwmSetWindowAttribute(hwnd, build >= 18985 ? 20 : 19, &use_dark,
                          sizeof(use_dark));
  }
  if (build >= 22000) {  // Windows 11: colour attributes exist
    constexpr DWORD kBorderColor = 34;
    constexpr DWORD kCaptionColor = 35;
    constexpr DWORD kTextColor = 36;
    DwmSetWindowAttribute(hwnd, kCaptionColor, &caption, sizeof(caption));
    DwmSetWindowAttribute(hwnd, kTextColor, &text, sizeof(text));
    DwmSetWindowAttribute(hwnd, kBorderColor, &border, sizeof(border));
  }
}

void Win32Window::RememberNormalBounds(HWND hwnd) {
  // A maximised or minimised window reports the wrong rectangle.
  if (IsZoomed(hwnd) || IsIconic(hwnd)) {
    return;
  }
  GetWindowRect(hwnd, &normal_rect_);
  normal_dpi_ = GetDpiForWindow(hwnd);
}

void Win32Window::SavePlacement(HWND hwnd) {
  RememberNormalBounds(hwnd);
  if (normal_rect_.right <= normal_rect_.left ||
      normal_rect_.bottom <= normal_rect_.top) {
    return;
  }
  SavedPlacement saved{1,
                       normal_rect_.left,
                       normal_rect_.top,
                       normal_rect_.right,
                       normal_rect_.bottom,
                       normal_dpi_ ? normal_dpi_ : 96u,
                       (maximized_ || IsZoomed(hwnd)) ? 1u : 0u};
  RegSetKeyValueW(HKEY_CURRENT_USER, kPlacementKey, kPlacementValue,
                  REG_BINARY, &saved, sizeof(saved));
}

void Win32Window::ApplyInitialPlacement(HWND hwnd) {
  // Start from what Create() just made, then prefer the saved rectangle.
  RECT target{};
  GetWindowRect(hwnd, &target);
  UINT target_dpi = GetDpiForWindow(hwnd);
  if (target_dpi == 0) {
    target_dpi = 96;
  }

  SavedPlacement saved{};
  DWORD size = sizeof(saved);
  if (RegGetValueW(HKEY_CURRENT_USER, kPlacementKey, kPlacementValue,
                   RRF_RT_REG_BINARY, nullptr, &saved,
                   &size) == ERROR_SUCCESS &&
      size == sizeof(saved) && saved.version == 1 && saved.dpi != 0) {
    const RECT remembered{saved.left, saved.top, saved.right, saved.bottom};
    // Ignore it if that monitor is no longer connected.
    if (MonitorFromRect(&remembered, MONITOR_DEFAULTTONULL) != nullptr) {
      target = remembered;
      target_dpi = saved.dpi;
      start_maximized_ = saved.maximized != 0;
    }
  }

  HMONITOR monitor = MonitorFromRect(&target, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{sizeof(info)};
  if (!GetMonitorInfo(monitor, &info)) {
    return;
  }
  // Keep the logical size if the monitor's scale changed since the save.
  const UINT monitor_dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const double ratio = monitor_dpi / static_cast<double>(target_dpi);
  const double monitor_scale = monitor_dpi / 96.0;
  const LONG work_width = info.rcWork.right - info.rcWork.left;
  const LONG work_height = info.rcWork.bottom - info.rcWork.top;
  const LONG min_width =
      std::min<LONG>(work_width, Scale(kMinClientWidth, monitor_scale));
  const LONG min_height =
      std::min<LONG>(work_height, Scale(kMinClientHeight, monitor_scale));
  const LONG width = std::clamp<LONG>(Scale(target.right - target.left, ratio),
                                      min_width, work_width);
  const LONG height = std::clamp<LONG>(
      Scale(target.bottom - target.top, ratio), min_height, work_height);
  const LONG x = std::clamp<LONG>(target.left, info.rcWork.left,
                                  info.rcWork.right - width);
  const LONG y = std::clamp<LONG>(target.top, info.rcWork.top,
                                  info.rcWork.bottom - height);

  // A move to a monitor with another DPI triggers WM_DPICHANGED, which applies
  // Windows' suggested rectangle; the second call restores the intended size.
  for (int i = 0; i < 2; ++i) {
    SetWindowPos(hwnd, nullptr, x, y, width, height,
                 SWP_NOZORDER | SWP_NOACTIVATE);
  }
  normal_rect_ = RECT{x, y, x + width, y + height};
  normal_dpi_ = monitor_dpi;
}
