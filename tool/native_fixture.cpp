// Harmless native integration fixture: a visible window that exits after 12s.
#include <windows.h>
LRESULT CALLBACK FixtureProc(HWND window, UINT message, WPARAM w, LPARAM l) {
  if (message == WM_TIMER) { DestroyWindow(window); return 0; }
  if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
  return DefWindowProc(window,message,w,l);
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,PWSTR,int) {
  WNDCLASS wc{};wc.lpfnWndProc=FixtureProc;wc.hInstance=instance;wc.lpszClassName=L"GameVaultNativeFixture";
  RegisterClass(&wc);
  HWND window=CreateWindow(wc.lpszClassName,L"GameVault native test fixture",WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,500,260,nullptr,nullptr,instance,nullptr);
  ShowWindow(window,SW_SHOW);SetForegroundWindow(window);SetTimer(window,1,12000,nullptr);
  MSG message{};while(GetMessage(&message,nullptr,0,0)>0){TranslateMessage(&message);DispatchMessage(&message);}return 0;
}
