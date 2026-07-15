package main

import w32 "core:sys/windows"
import "core:fmt"
import "core:time"
import "core:os"


EVENT_ALL_ACCESS :: w32.DWORD(0x1F0003)

create_window :: proc(width: u32, height: u32) -> w32.HWND {
    instance := w32.HINSTANCE(w32.GetModuleHandleW(nil))

    wclassname := cstring16("WIN32PLATFORMLAYER")

    wcex := w32.WNDCLASSW{
        style = w32.CS_HREDRAW | w32.CS_VREDRAW,
        lpfnWndProc = win_proc,
        cbClsExtra = 0,
        cbWndExtra = 0,
        hInstance = instance,
        lpszClassName = wclassname,
        // hIcon = LoadIcon(hInstance, MAKEINTRESOURCE(IDI_WIN32PLATFORMLAYER)),
        // hCursor = LoadCursor(nullptr, IDC_ARROW),
        // hbrBackground = (HBRUSH)(COLOR_WINDOW + 1),
        // lpszMenuName = 0, // MAKEINTRESOURCEW(IDC_TESTPROJECT),
        // hIconSm = LoadIcon(wcex.hInstance, MAKEINTRESOURCE(IDI_SMALL))
    }

    w32.RegisterClassW(&wcex)
    window: w32.HWND = w32.CreateWindowW(wclassname, wclassname, w32.WS_OVERLAPPEDWINDOW, 0, 0, 100, 100, nil, nil, instance, nil)

    startup_info: w32.STARTUPINFOW
    w32.GetStartupInfoW(&startup_info)
    nCmdShow: i32 = w32.SW_SHOWDEFAULT
    if startup_info.dwFlags & w32.STARTF_USESHOWWINDOW != 0 {
        nCmdShow = i32(startup_info.wShowWindow)
    }
    
    screen_width := w32.GetSystemMetrics(w32.SM_CXSCREEN)
    screen_height := w32.GetSystemMetrics(w32.SM_CYSCREEN)

    window_width := (w32.INT)(width)
    window_height := (w32.INT)(height)

    // This code starts the window centered
    X := (screen_width / 2) - (window_width / 2)
    Y := (screen_height / 2) - (window_height / 2)

    Result: w32.BOOL = w32.MoveWindow(window, X, Y, window_width, window_height, w32.FALSE)
    Result = w32.ShowWindow(window, nCmdShow)
    Result = w32.UpdateWindow(window)

    return window
}

win_proc :: proc "stdcall" (window: w32.HWND, message: w32.UINT, wparam: w32.WPARAM, lparam: w32.LPARAM) -> w32.LRESULT {
    switch message {
        case w32.WM_DESTROY:
            global_memory.running = false
            w32.PostQuitMessage(0)
    }
    return w32.DefWindowProcW(window, message, wparam, lparam)
}

console: w32.HANDLE

setup_logging :: proc() {
    result := w32.AllocConsole()
    console = w32.CreateFileW(
        w32.utf8_to_wstring("CONOUT$"),
        w32.GENERIC_READ | w32.GENERIC_WRITE,
        w32.FILE_SHARE_READ | w32.FILE_SHARE_WRITE,
        nil,
        w32.OPEN_EXISTING,
        0,
        nil
    )
    console_mode: w32.DWORD
    w32.GetConsoleMode(console, &console_mode)
    w32.SetConsoleMode(console, console_mode | w32.ENABLE_VIRTUAL_TERMINAL_PROCESSING)
}

level_color := [log_level]w32.WORD {
    .Debug = w32.FOREGROUND_GREEN | w32.FOREGROUND_BLUE,
    .Info = w32.FOREGROUND_GREEN | w32.FOREGROUND_BLUE,
    .Warn = w32.FOREGROUND_RED | w32.FOREGROUND_GREEN,
    .Error = w32.FOREGROUND_RED,
    .Fatal = w32.FOREGROUND_RED | w32.FOREGROUND_INTENSITY
}

level_string := [log_level]string {
    .Debug = "[DEBUG] ",
    .Info  = "[INFO]  ",
    .Warn  = "[WARN]  ",
    .Error = "[ERROR] ",
    .Fatal = "[FATAL] "
}

log :: proc(level: log_level, message: string) {
    now := time.now()

    year, month, day := time.date(now)
    hour, minute, second := time.clock(now)

    date_time := fmt.tprintf("%d-%02d-%02d %02d:%02d:%02d ", year, month, day, hour, minute, second)
    wdate_time := w32.utf8_to_wstring(date_time)
    
    result := w32.SetConsoleTextAttribute(console, w32.FOREGROUND_RED | w32.FOREGROUND_GREEN | w32.FOREGROUND_BLUE)
    result = w32.WriteConsoleW(console, rawptr(wdate_time), 22, nil, nil)

    w32.SetConsoleTextAttribute(console, level_color[level])
    wlevel := w32.utf8_to_wstring(level_string[level])
    result = w32.WriteConsoleW(console, rawptr(wlevel), 8, nil, nil)

    result = w32.SetConsoleTextAttribute(console, w32.FOREGROUND_RED | w32.FOREGROUND_GREEN | w32.FOREGROUND_BLUE)
    wmessage := w32.utf8_to_wstring(message)
    result = w32.WriteConsoleW(console, rawptr(wmessage), u32(len(message)), nil, nil)

    wline_break := w32.utf8_to_wstring("\n")
    result = w32.WriteConsoleW(console, rawptr(wline_break), 1, nil, nil)

    if level == .Fatal {
        os.exit(1)
    }
}

process_messages :: proc(window: w32.HWND, input: ^game_input) {
    msg: w32.MSG
    for w32.PeekMessageW(&msg, window, 0, 0, w32.PM_REMOVE) {
        switch msg.message {
            case w32.WM_LBUTTONDOWN:
                press_button(&input.mouse.left_click)
            case w32.WM_LBUTTONUP:
                lift_button(&input.mouse.left_click)
            case w32.WM_MBUTTONDOWN:
                press_button(&input.mouse.middle_click)
            case w32.WM_MBUTTONUP:
                lift_button(&input.mouse.middle_click)
            case w32.WM_RBUTTONDOWN:
                press_button(&input.mouse.right_click)
            case w32.WM_RBUTTONUP:
                lift_button(&input.mouse.right_click)
            case w32.WM_MOUSEWHEEL:
                input.mouse.wheel = w32.GET_WHEEL_DELTA_WPARAM(msg.wParam)

            case w32.WM_KEYDOWN, w32.WM_SYSKEYDOWN:
                was_down := (msg.lParam & (1 << 30)) != 0
                if was_down {
                    continue
                }
                
                vk_code := msg.wParam
                switch vk_code {
                    case w32.VK_0:
                        press_button(&input.keyboard.key[.Zero])
                    case w32.VK_1:
                        press_button(&input.keyboard.key[.One])
                    case w32.VK_2:
                        press_button(&input.keyboard.key[.Two])
                    case w32.VK_3:
                        press_button(&input.keyboard.key[.Three])
                    case w32.VK_4:
                        press_button(&input.keyboard.key[.Four])
                    case w32.VK_5:
                        press_button(&input.keyboard.key[.Five])
                    case w32.VK_6:
                        press_button(&input.keyboard.key[.Six])
                    case w32.VK_7:
                        press_button(&input.keyboard.key[.Seven])
                    case w32.VK_8:
                        press_button(&input.keyboard.key[.Eight])
                    case w32.VK_9:
                        press_button(&input.keyboard.key[.Nine])
                    case w32.VK_A:
                        press_button(&input.keyboard.key[.A])
                    case w32.VK_B:
                        press_button(&input.keyboard.key[.B])
                    case w32.VK_C:
                        press_button(&input.keyboard.key[.C])
                    case w32.VK_D:
                        press_button(&input.keyboard.key[.D])
                    case w32.VK_E:
                        press_button(&input.keyboard.key[.E])
                    case w32.VK_F:
                        press_button(&input.keyboard.key[.F])
                    case w32.VK_G:
                        press_button(&input.keyboard.key[.G])
                    case w32.VK_H:
                        press_button(&input.keyboard.key[.H])
                    case w32.VK_I:
                        press_button(&input.keyboard.key[.I])
                    case w32.VK_J:
                        press_button(&input.keyboard.key[.J])
                    case w32.VK_K:
                        press_button(&input.keyboard.key[.K])
                    case w32.VK_L:
                        press_button(&input.keyboard.key[.L])
                    case w32.VK_M:
                        press_button(&input.keyboard.key[.M])
                    case w32.VK_N:
                        press_button(&input.keyboard.key[.N])
                    case w32.VK_O:
                        press_button(&input.keyboard.key[.O])
                    case w32.VK_P:
                        press_button(&input.keyboard.key[.P])
                    case w32.VK_Q:
                        press_button(&input.keyboard.key[.Q])
                    case w32.VK_R:
                        press_button(&input.keyboard.key[.R])
                    case w32.VK_S:
                        press_button(&input.keyboard.key[.S])
                    case w32.VK_T:
                        press_button(&input.keyboard.key[.T])
                    case w32.VK_U:
                        press_button(&input.keyboard.key[.U])
                    case w32.VK_V:
                        press_button(&input.keyboard.key[.V])
                    case w32.VK_W:
                        press_button(&input.keyboard.key[.W])
                    case w32.VK_X:
                        press_button(&input.keyboard.key[.X])
                    case w32.VK_Y:
                        press_button(&input.keyboard.key[.Y])
                    case w32.VK_Z:
                        press_button(&input.keyboard.key[.Z])
                    case w32.VK_LEFT:
                        press_button(&input.keyboard.key[.Left])
                    case w32.VK_RIGHT:
                        press_button(&input.keyboard.key[.Right])
                    case w32.VK_UP:
                        press_button(&input.keyboard.key[.Up])
                    case w32.VK_DOWN:
                        press_button(&input.keyboard.key[.Down])
                    case w32.VK_ESCAPE:
                        press_button(&input.keyboard.key[.Escape])
                    case w32.VK_SPACE:
                        press_button(&input.keyboard.key[.Space])
                    case w32.VK_RETURN:
                        press_button(&input.keyboard.key[.Enter])
                    case w32.VK_CONTROL:
                        press_button(&input.keyboard.key[.Control])
                    case w32.VK_MENU:
                        press_button(&input.keyboard.key[.Alt])
                    case w32.VK_F1:
                        press_button(&input.keyboard.key[.F1])
                    case w32.VK_F2:
                        press_button(&input.keyboard.key[.F2])
                    case w32.VK_F3:
                        press_button(&input.keyboard.key[.F3])
                    case w32.VK_F4:
                        press_button(&input.keyboard.key[.F4])
                    case w32.VK_F5:
                        press_button(&input.keyboard.key[.F5])
                    case w32.VK_F6:
                        press_button(&input.keyboard.key[.F6])
                    case w32.VK_F7:
                        press_button(&input.keyboard.key[.F7])
                    case w32.VK_F8:
                        press_button(&input.keyboard.key[.F8])
                    case w32.VK_F9:
                        press_button(&input.keyboard.key[.F9])
                    case w32.VK_F10:
                        press_button(&input.keyboard.key[.F10])
                    case w32.VK_F11:
                        press_button(&input.keyboard.key[.F11])
                    case w32.VK_F12:
                        press_button(&input.keyboard.key[.F12])
                    case w32.VK_PRIOR:
                        press_button(&input.keyboard.key[.PageUp])
                    case w32.VK_NEXT:
                        press_button(&input.keyboard.key[.PageDown])
                    case w32.VK_SHIFT:
                        press_button(&input.keyboard.key[.Shift])
                }

            case w32.WM_KEYUP, w32.WM_SYSKEYUP:
                vk_code := msg.wParam
                switch vk_code {
                    case w32.VK_0:
                        lift_button(&input.keyboard.key[.Zero])
                    case w32.VK_1:
                        lift_button(&input.keyboard.key[.One])
                    case w32.VK_2:
                        lift_button(&input.keyboard.key[.Two])
                    case w32.VK_3:
                        lift_button(&input.keyboard.key[.Three])
                    case w32.VK_4:
                        lift_button(&input.keyboard.key[.Four])
                    case w32.VK_5:
                        lift_button(&input.keyboard.key[.Five])
                    case w32.VK_6:
                        lift_button(&input.keyboard.key[.Six])
                    case w32.VK_7:
                        lift_button(&input.keyboard.key[.Seven])
                    case w32.VK_8:
                        lift_button(&input.keyboard.key[.Eight])
                    case w32.VK_9:
                        lift_button(&input.keyboard.key[.Nine])
                    case w32.VK_A:
                        lift_button(&input.keyboard.key[.A])
                    case w32.VK_B:
                        lift_button(&input.keyboard.key[.B])
                    case w32.VK_C:
                        lift_button(&input.keyboard.key[.C])
                    case w32.VK_D:
                        lift_button(&input.keyboard.key[.D])
                    case w32.VK_E:
                        lift_button(&input.keyboard.key[.E])
                    case w32.VK_F:
                        lift_button(&input.keyboard.key[.F])
                    case w32.VK_G:
                        lift_button(&input.keyboard.key[.G])
                    case w32.VK_H:
                        lift_button(&input.keyboard.key[.H])
                    case w32.VK_I:
                        lift_button(&input.keyboard.key[.I])
                    case w32.VK_J:
                        lift_button(&input.keyboard.key[.J])
                    case w32.VK_K:
                        lift_button(&input.keyboard.key[.K])
                    case w32.VK_L:
                        lift_button(&input.keyboard.key[.L])
                    case w32.VK_M:
                        lift_button(&input.keyboard.key[.M])
                    case w32.VK_N:
                        lift_button(&input.keyboard.key[.N])
                    case w32.VK_O:
                        lift_button(&input.keyboard.key[.O])
                    case w32.VK_P:
                        lift_button(&input.keyboard.key[.P])
                    case w32.VK_Q:
                        lift_button(&input.keyboard.key[.Q])
                    case w32.VK_R:
                        lift_button(&input.keyboard.key[.R])
                    case w32.VK_S:
                        lift_button(&input.keyboard.key[.S])
                    case w32.VK_T:
                        lift_button(&input.keyboard.key[.T])
                    case w32.VK_U:
                        lift_button(&input.keyboard.key[.U])
                    case w32.VK_V:
                        lift_button(&input.keyboard.key[.V])
                    case w32.VK_W:
                        lift_button(&input.keyboard.key[.W])
                    case w32.VK_X:
                        lift_button(&input.keyboard.key[.X])
                    case w32.VK_Y:
                        lift_button(&input.keyboard.key[.Y])
                    case w32.VK_Z:
                        lift_button(&input.keyboard.key[.Z])
                    case w32.VK_LEFT:
                        lift_button(&input.keyboard.key[.Left])
                    case w32.VK_RIGHT:
                        lift_button(&input.keyboard.key[.Right])
                    case w32.VK_UP:
                        lift_button(&input.keyboard.key[.Up])
                    case w32.VK_DOWN:
                        lift_button(&input.keyboard.key[.Down])
                    case w32.VK_ESCAPE:
                        lift_button(&input.keyboard.key[.Escape])
                    case w32.VK_SPACE:
                        lift_button(&input.keyboard.key[.Space])
                    case w32.VK_RETURN:
                        lift_button(&input.keyboard.key[.Enter])
                    case w32.VK_CONTROL:
                        lift_button(&input.keyboard.key[.Control])
                    case w32.VK_MENU:
                        lift_button(&input.keyboard.key[.Alt])
                    case w32.VK_F1:
                        lift_button(&input.keyboard.key[.F1])
                    case w32.VK_F2:
                        lift_button(&input.keyboard.key[.F2])
                    case w32.VK_F3:
                        lift_button(&input.keyboard.key[.F3])
                    case w32.VK_F4:
                        lift_button(&input.keyboard.key[.F4])
                    case w32.VK_F5:
                        lift_button(&input.keyboard.key[.F5])
                    case w32.VK_F6:
                        lift_button(&input.keyboard.key[.F6])
                    case w32.VK_F7:
                        lift_button(&input.keyboard.key[.F7])
                    case w32.VK_F8:
                        lift_button(&input.keyboard.key[.F8])
                    case w32.VK_F9:
                        lift_button(&input.keyboard.key[.F9])
                    case w32.VK_F10:
                        lift_button(&input.keyboard.key[.F10])
                    case w32.VK_F11:
                        lift_button(&input.keyboard.key[.F11])
                    case w32.VK_F12:
                        lift_button(&input.keyboard.key[.F12])
                    case w32.VK_PRIOR:
                        lift_button(&input.keyboard.key[.PageUp])
                    case w32.VK_NEXT:
                        lift_button(&input.keyboard.key[.PageDown])
                    case w32.VK_SHIFT:
                        lift_button(&input.keyboard.key[.Shift])
                }
            case:
                w32.TranslateMessage(&msg)
                w32.DispatchMessageW(&msg)
        }
    }
}