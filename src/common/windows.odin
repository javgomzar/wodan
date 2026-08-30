package common

import w32 "core:sys/windows"
import "core:dynlib"
import "core:fmt"
import "core:time"
import "core:os"
import "core:log"
import "../common"


when ODIN_OS == .Windows {

performance_frequency: w32.LARGE_INTEGER

query_performance_frequency :: proc() {
    w32.QueryPerformanceFrequency(&common.performance_frequency)
}

get_wall_clock :: proc() -> u64 {
    result: w32.LARGE_INTEGER
    w32.QueryPerformanceCounter(&result)
    return u64(result)
}

get_seconds_elapsed :: proc(start: u64, end: u64) -> f32 {
    elapsed := end - start
    return f32(elapsed) / f32(performance_frequency)
}

Log_Data :: struct {
    console: w32.HANDLE,
}

create_logger :: proc() -> log.Logger {
    result := w32.AllocConsole()
    assert(result == w32.TRUE)

    log_data := new(Log_Data)
    log_data.console = w32.CreateFileW(
        w32.utf8_to_wstring("CONOUT$"),
        w32.GENERIC_READ | w32.GENERIC_WRITE,
        w32.FILE_SHARE_READ | w32.FILE_SHARE_WRITE,
        nil,
        w32.OPEN_EXISTING,
        0,
        nil
    )

    console_mode: w32.DWORD
    w32.GetConsoleMode(log_data.console, &console_mode)
    w32.SetConsoleMode(log_data.console, console_mode | w32.ENABLE_VIRTUAL_TERMINAL_PROCESSING)

    return log.Logger{
        procedure = game_log,
        data = log_data,
        lowest_level = .Debug,
        options = log.Default_Console_Logger_Opts,
    }
}

log_level_color :: proc(level: log.Level) -> w32.WORD {
    switch level {
        case .Debug:    return w32.FOREGROUND_GREEN | w32.FOREGROUND_BLUE
        case .Info:     return w32.FOREGROUND_GREEN | w32.FOREGROUND_BLUE
        case .Warning:  return w32.FOREGROUND_RED | w32.FOREGROUND_GREEN
        case .Error:    return w32.FOREGROUND_RED | w32.FOREGROUND_INTENSITY
        case .Fatal:    return w32.FOREGROUND_RED 
    }
    return 0
}

log_level_string :: proc(level: log.Level) -> string {
    switch level {
        case .Debug:   return "[DEBUG] "
        case .Info:    return "[INFO]  "
        case .Warning: return "[WARN]  "
        case .Error:   return "[ERROR] "
        case .Fatal:   return "[FATAL] "
    }
    return "?INVALID"
}

game_log :: proc(data: rawptr, level: log.Level, text: string, options: log.Options, location := #caller_location) {
    log_data := (^Log_Data)(data)
    
    now := time.now()

    year, month, day := time.date(now)
    hour, minute, second := time.clock(now)

    date_time := fmt.tprintf("%d-%02d-%02d %02d:%02d:%02d ", year, month, day, hour, minute, second)
    wdate_time := w32.utf8_to_wstring(date_time)
    
    result := w32.SetConsoleTextAttribute(log_data.console, w32.FOREGROUND_RED | w32.FOREGROUND_GREEN | w32.FOREGROUND_BLUE)
    result = w32.WriteConsoleW(log_data.console, rawptr(wdate_time), 22, nil, nil)

    w32.SetConsoleTextAttribute(log_data.console, log_level_color(level))
    wlevel := w32.utf8_to_wstring(log_level_string(level))
    result = w32.WriteConsoleW(log_data.console, rawptr(wlevel), 8, nil, nil)

    result = w32.SetConsoleTextAttribute(log_data.console, w32.FOREGROUND_RED | w32.FOREGROUND_GREEN | w32.FOREGROUND_BLUE)
    wmessage := w32.utf8_to_wstring(text)
    result = w32.WriteConsoleW(log_data.console, rawptr(wmessage), u32(len(text)), nil, nil)

    wline_break := w32.utf8_to_wstring("\n")
    result = w32.WriteConsoleW(log_data.console, rawptr(wline_break), 1, nil, nil)

    if level == .Fatal {
        os.exit(1)
    }
}

get_process_memory :: proc() -> (u64, bool) {
    GetProcessMemoryInfo_Proc :: proc "stdcall" (
        w32.HANDLE,
        rawptr,
        u32,
    ) -> w32.BOOL

    counters: [9]u64
    counters[0] = 72

    kernel32, ok_k32 := dynlib.load_library("kernel32.dll")
    if !ok_k32 {
        return 0, false
    }
    defer dynlib.unload_library(kernel32)

    address, ok := dynlib.symbol_address(
        kernel32,
        "K32GetProcessMemoryInfo",
    )
    if !ok {
        return 0, false
    }

    get_memory_info := transmute(GetProcessMemoryInfo_Proc)address
    result := get_memory_info(w32.GetCurrentProcess(), rawptr(&counters), 72)

    if !result {
        return 0, false
    }

    return counters[2], true
}

process_messages :: proc(window: w32.HWND, input: ^common.Input_Context) {
    pointer: w32.POINT
    w32.GetCursorPos(&pointer)
    w32.ScreenToClient(window, &pointer)
    
    input.mouse.cursor.x = f32(pointer.x)
    input.mouse.cursor.y = f32(pointer.y)
    
    msg: w32.MSG
    for w32.PeekMessageW(&msg, window, 0, 0, w32.PM_REMOVE) {
        switch msg.message {
            case w32.WM_LBUTTONDOWN:
                common.press_button(&input.mouse.left_click)
            case w32.WM_LBUTTONUP:
                common.lift_button(&input.mouse.left_click)
            case w32.WM_MBUTTONDOWN:
                common.press_button(&input.mouse.middle_click)
            case w32.WM_MBUTTONUP:
                common.lift_button(&input.mouse.middle_click)
            case w32.WM_RBUTTONDOWN:
                common.press_button(&input.mouse.right_click)
            case w32.WM_RBUTTONUP:
                common.lift_button(&input.mouse.right_click)
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
                        common.press_button(&input.keyboard.key[.Zero])
                    case w32.VK_1:
                        common.press_button(&input.keyboard.key[.One])
                    case w32.VK_2:
                        common.press_button(&input.keyboard.key[.Two])
                    case w32.VK_3:
                        common.press_button(&input.keyboard.key[.Three])
                    case w32.VK_4:
                        common.press_button(&input.keyboard.key[.Four])
                    case w32.VK_5:
                        common.press_button(&input.keyboard.key[.Five])
                    case w32.VK_6:
                        common.press_button(&input.keyboard.key[.Six])
                    case w32.VK_7:
                        common.press_button(&input.keyboard.key[.Seven])
                    case w32.VK_8:
                        common.press_button(&input.keyboard.key[.Eight])
                    case w32.VK_9:
                        common.press_button(&input.keyboard.key[.Nine])
                    case w32.VK_A:
                        common.press_button(&input.keyboard.key[.A])
                    case w32.VK_B:
                        common.press_button(&input.keyboard.key[.B])
                    case w32.VK_C:
                        common.press_button(&input.keyboard.key[.C])
                    case w32.VK_D:
                        common.press_button(&input.keyboard.key[.D])
                    case w32.VK_E:
                        common.press_button(&input.keyboard.key[.E])
                    case w32.VK_F:
                        common.press_button(&input.keyboard.key[.F])
                    case w32.VK_G:
                        common.press_button(&input.keyboard.key[.G])
                    case w32.VK_H:
                        common.press_button(&input.keyboard.key[.H])
                    case w32.VK_I:
                        common.press_button(&input.keyboard.key[.I])
                    case w32.VK_J:
                        common.press_button(&input.keyboard.key[.J])
                    case w32.VK_K:
                        common.press_button(&input.keyboard.key[.K])
                    case w32.VK_L:
                        common.press_button(&input.keyboard.key[.L])
                    case w32.VK_M:
                        common.press_button(&input.keyboard.key[.M])
                    case w32.VK_N:
                        common.press_button(&input.keyboard.key[.N])
                    case w32.VK_O:
                        common.press_button(&input.keyboard.key[.O])
                    case w32.VK_P:
                        common.press_button(&input.keyboard.key[.P])
                    case w32.VK_Q:
                        common.press_button(&input.keyboard.key[.Q])
                    case w32.VK_R:
                        common.press_button(&input.keyboard.key[.R])
                    case w32.VK_S:
                        common.press_button(&input.keyboard.key[.S])
                    case w32.VK_T:
                        common.press_button(&input.keyboard.key[.T])
                    case w32.VK_U:
                        common.press_button(&input.keyboard.key[.U])
                    case w32.VK_V:
                        common.press_button(&input.keyboard.key[.V])
                    case w32.VK_W:
                        common.press_button(&input.keyboard.key[.W])
                    case w32.VK_X:
                        common.press_button(&input.keyboard.key[.X])
                    case w32.VK_Y:
                        common.press_button(&input.keyboard.key[.Y])
                    case w32.VK_Z:
                        common.press_button(&input.keyboard.key[.Z])
                    case w32.VK_LEFT:
                        common.press_button(&input.keyboard.key[.Left])
                    case w32.VK_RIGHT:
                        common.press_button(&input.keyboard.key[.Right])
                    case w32.VK_UP:
                        common.press_button(&input.keyboard.key[.Up])
                    case w32.VK_DOWN:
                        common.press_button(&input.keyboard.key[.Down])
                    case w32.VK_ESCAPE:
                        common.press_button(&input.keyboard.key[.Escape])
                    case w32.VK_SPACE:
                        common.press_button(&input.keyboard.key[.Space])
                    case w32.VK_RETURN:
                        common.press_button(&input.keyboard.key[.Enter])
                    case w32.VK_CONTROL:
                        common.press_button(&input.keyboard.key[.Control])
                    case w32.VK_MENU:
                        common.press_button(&input.keyboard.key[.Alt])
                    case w32.VK_F1:
                        common.press_button(&input.keyboard.key[.F1])
                    case w32.VK_F2:
                        common.press_button(&input.keyboard.key[.F2])
                    case w32.VK_F3:
                        common.press_button(&input.keyboard.key[.F3])
                    case w32.VK_F4:
                        common.press_button(&input.keyboard.key[.F4])
                    case w32.VK_F5:
                        common.press_button(&input.keyboard.key[.F5])
                    case w32.VK_F6:
                        common.press_button(&input.keyboard.key[.F6])
                    case w32.VK_F7:
                        common.press_button(&input.keyboard.key[.F7])
                    case w32.VK_F8:
                        common.press_button(&input.keyboard.key[.F8])
                    case w32.VK_F9:
                        common.press_button(&input.keyboard.key[.F9])
                    case w32.VK_F10:
                        common.press_button(&input.keyboard.key[.F10])
                    case w32.VK_F11:
                        common.press_button(&input.keyboard.key[.F11])
                    case w32.VK_F12:
                        common.press_button(&input.keyboard.key[.F12])
                    case w32.VK_PRIOR:
                        common.press_button(&input.keyboard.key[.Page_Up])
                    case w32.VK_NEXT:
                        common.press_button(&input.keyboard.key[.Page_Down])
                    case w32.VK_SHIFT:
                        common.press_button(&input.keyboard.key[.Shift])
                }

            case w32.WM_KEYUP, w32.WM_SYSKEYUP:
                vk_code := msg.wParam
                switch vk_code {
                    case w32.VK_0:
                        common.lift_button(&input.keyboard.key[.Zero])
                    case w32.VK_1:
                        common.lift_button(&input.keyboard.key[.One])
                    case w32.VK_2:
                        common.lift_button(&input.keyboard.key[.Two])
                    case w32.VK_3:
                        common.lift_button(&input.keyboard.key[.Three])
                    case w32.VK_4:
                        common.lift_button(&input.keyboard.key[.Four])
                    case w32.VK_5:
                        common.lift_button(&input.keyboard.key[.Five])
                    case w32.VK_6:
                        common.lift_button(&input.keyboard.key[.Six])
                    case w32.VK_7:
                        common.lift_button(&input.keyboard.key[.Seven])
                    case w32.VK_8:
                        common.lift_button(&input.keyboard.key[.Eight])
                    case w32.VK_9:
                        common.lift_button(&input.keyboard.key[.Nine])
                    case w32.VK_A:
                        common.lift_button(&input.keyboard.key[.A])
                    case w32.VK_B:
                        common.lift_button(&input.keyboard.key[.B])
                    case w32.VK_C:
                        common.lift_button(&input.keyboard.key[.C])
                    case w32.VK_D:
                        common.lift_button(&input.keyboard.key[.D])
                    case w32.VK_E:
                        common.lift_button(&input.keyboard.key[.E])
                    case w32.VK_F:
                        common.lift_button(&input.keyboard.key[.F])
                    case w32.VK_G:
                        common.lift_button(&input.keyboard.key[.G])
                    case w32.VK_H:
                        common.lift_button(&input.keyboard.key[.H])
                    case w32.VK_I:
                        common.lift_button(&input.keyboard.key[.I])
                    case w32.VK_J:
                        common.lift_button(&input.keyboard.key[.J])
                    case w32.VK_K:
                        common.lift_button(&input.keyboard.key[.K])
                    case w32.VK_L:
                        common.lift_button(&input.keyboard.key[.L])
                    case w32.VK_M:
                        common.lift_button(&input.keyboard.key[.M])
                    case w32.VK_N:
                        common.lift_button(&input.keyboard.key[.N])
                    case w32.VK_O:
                        common.lift_button(&input.keyboard.key[.O])
                    case w32.VK_P:
                        common.lift_button(&input.keyboard.key[.P])
                    case w32.VK_Q:
                        common.lift_button(&input.keyboard.key[.Q])
                    case w32.VK_R:
                        common.lift_button(&input.keyboard.key[.R])
                    case w32.VK_S:
                        common.lift_button(&input.keyboard.key[.S])
                    case w32.VK_T:
                        common.lift_button(&input.keyboard.key[.T])
                    case w32.VK_U:
                        common.lift_button(&input.keyboard.key[.U])
                    case w32.VK_V:
                        common.lift_button(&input.keyboard.key[.V])
                    case w32.VK_W:
                        common.lift_button(&input.keyboard.key[.W])
                    case w32.VK_X:
                        common.lift_button(&input.keyboard.key[.X])
                    case w32.VK_Y:
                        common.lift_button(&input.keyboard.key[.Y])
                    case w32.VK_Z:
                        common.lift_button(&input.keyboard.key[.Z])
                    case w32.VK_LEFT:
                        common.lift_button(&input.keyboard.key[.Left])
                    case w32.VK_RIGHT:
                        common.lift_button(&input.keyboard.key[.Right])
                    case w32.VK_UP:
                        common.lift_button(&input.keyboard.key[.Up])
                    case w32.VK_DOWN:
                        common.lift_button(&input.keyboard.key[.Down])
                    case w32.VK_ESCAPE:
                        common.lift_button(&input.keyboard.key[.Escape])
                    case w32.VK_SPACE:
                        common.lift_button(&input.keyboard.key[.Space])
                    case w32.VK_RETURN:
                        common.lift_button(&input.keyboard.key[.Enter])
                    case w32.VK_CONTROL:
                        common.lift_button(&input.keyboard.key[.Control])
                    case w32.VK_MENU:
                        common.lift_button(&input.keyboard.key[.Alt])
                    case w32.VK_F1:
                        common.lift_button(&input.keyboard.key[.F1])
                    case w32.VK_F2:
                        common.lift_button(&input.keyboard.key[.F2])
                    case w32.VK_F3:
                        common.lift_button(&input.keyboard.key[.F3])
                    case w32.VK_F4:
                        common.lift_button(&input.keyboard.key[.F4])
                    case w32.VK_F5:
                        common.lift_button(&input.keyboard.key[.F5])
                    case w32.VK_F6:
                        common.lift_button(&input.keyboard.key[.F6])
                    case w32.VK_F7:
                        common.lift_button(&input.keyboard.key[.F7])
                    case w32.VK_F8:
                        common.lift_button(&input.keyboard.key[.F8])
                    case w32.VK_F9:
                        common.lift_button(&input.keyboard.key[.F9])
                    case w32.VK_F10:
                        common.lift_button(&input.keyboard.key[.F10])
                    case w32.VK_F11:
                        common.lift_button(&input.keyboard.key[.F11])
                    case w32.VK_F12:
                        common.lift_button(&input.keyboard.key[.F12])
                    case w32.VK_PRIOR:
                        common.lift_button(&input.keyboard.key[.Page_Up])
                    case w32.VK_NEXT:
                        common.lift_button(&input.keyboard.key[.Page_Down])
                    case w32.VK_SHIFT:
                        common.lift_button(&input.keyboard.key[.Shift])
                }
            case:
                w32.TranslateMessage(&msg)
                w32.DispatchMessageW(&msg)
        }
    }
}

}