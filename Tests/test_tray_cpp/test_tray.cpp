// Minimal C++ tray icon test - uses Shell_NotifyIcon directly with NOTIFYICON_VERSION_4
// Compile with: cl /EHsc test_tray.cpp shell32.lib user32.lib

#define UNICODE
#define _UNICODE
#include <windows.h>
#include <shellapi.h>

#define WM_TRAYICON (WM_USER + 1)
#define ID_TRAY_EXIT 1001

NOTIFYICONDATAW nid = {};
HMENU hMenu = NULL;

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_TRAYICON:
            if (lParam == WM_RBUTTONUP) {
                POINT pt;
                GetCursorPos(&pt);
                SetForegroundWindow(hwnd);
                TrackPopupMenu(hMenu, TPM_BOTTOMALIGN | TPM_LEFTALIGN, pt.x, pt.y, 0, hwnd, NULL);
            }
            break;
        case WM_COMMAND:
            if (LOWORD(wParam) == ID_TRAY_EXIT) {
                Shell_NotifyIconW(NIM_DELETE, &nid);
                PostQuitMessage(0);
            }
            break;
        case WM_DESTROY:
            Shell_NotifyIconW(NIM_DELETE, &nid);
            PostQuitMessage(0);
            break;
        default:
            return DefWindowProcW(hwnd, msg, wParam, lParam);
    }
    return 0;
}

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE, LPWSTR, int) {
    // Register window class
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.lpszClassName = L"TestTrayIconClass";
    RegisterClassExW(&wc);

    // Create hidden window
    HWND hwnd = CreateWindowExW(0, L"TestTrayIconClass", L"Test Tray", 
        0, 0, 0, 0, 0, HWND_MESSAGE, NULL, hInstance, NULL);

    // Create context menu
    hMenu = CreatePopupMenu();
    AppendMenuW(hMenu, MF_STRING, ID_TRAY_EXIT, L"Exit");

    // Setup NOTIFYICONDATA with NOTIFYICON_VERSION_4
    nid.cbSize = sizeof(NOTIFYICONDATAW);  // 976 bytes on 64-bit Vista+
    nid.hWnd = hwnd;
    nid.uID = 1;
    nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
    nid.uCallbackMessage = WM_TRAYICON;
    nid.hIcon = LoadIconW(NULL, IDI_APPLICATION);  // Default app icon
    wcscpy_s(nid.szTip, L"C++ Test Tray Icon");

    // Add the icon
    Shell_NotifyIconW(NIM_ADD, &nid);

    // Set version to NOTIFYICON_VERSION_4
    nid.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &nid);

    // Message loop
    MSG msg;
    while (GetMessageW(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    DestroyMenu(hMenu);
    return 0;
}
