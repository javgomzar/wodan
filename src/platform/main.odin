package main

import "core:fmt"
import "core:os"
import "core:log"
import "core:mem"
import w32 "core:sys/windows"
import "../common"


memory: common.Game_Memory

win_proc :: proc "stdcall" (window: w32.HWND, message: w32.UINT, wparam: w32.WPARAM, lparam: w32.LPARAM) -> w32.LRESULT {
    switch message {
        case w32.WM_CLOSE, w32.WM_DESTROY:
            memory.running = false
            w32.PostQuitMessage(0)
    }
    return w32.DefWindowProcW(window, message, wparam, lparam)
}

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
    window: w32.HWND = w32.CreateWindowW(
        wclassname, 
        wclassname, 
        w32.WS_POPUP | w32.WS_VISIBLE, 
        0, 0, 
        i32(width), i32(height),
        nil, nil, 
        instance, nil,
    )

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

    w32.QueryPerformanceFrequency(&common.performance_frequency)

    return window
}

main :: proc() {
    when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

    memory.time = 0
    code := &memory.code
    input := &memory.input
    
    context.logger = common.create_logger()

    // Delete old .pdb files:
    old_pdbs, error := os.glob("bin/game?*.pdb")
    if error != nil do log.fatal("Failed to search for old PDB files")
    for pdb_file in old_pdbs {
        error = os.remove(pdb_file)
        if error != nil do log.fatal("Failed to remove old PDB files")
    }

    common.initialize_render_group(&memory.render_group, 1280, 720)
    window := create_window(memory.render_group.width, memory.render_group.height)

    common.load_code(code)
    code.reload(&memory)
    code.initialize(&memory)

    log.debug("Running!")

    memory.running = true
    last_counter: u64 = common.get_wall_clock()
    for memory.running {
        common.reset_input(input)
        common.process_messages(window, input)

        if input.keyboard.key[.Alt].is_down && input.keyboard.key[.F4].is_down do break

        common.update_if_newer_code(&memory)
        common.handle_resize(&memory.renderer, &memory.render_group)

        memory.code.update(&memory)

        free_all(context.temp_allocator)
        clear(&common.time_records)
        clear(&memory.render_group.commands)

        end_counter := common.get_wall_clock()
        seconds_elapsed := common.get_seconds_elapsed(last_counter, end_counter)
        memory.time += seconds_elapsed
        memory.delta_time = seconds_elapsed
        last_counter = end_counter
        fmt.printf("FPS: %d\n", i32(1.0 / seconds_elapsed))
    }
}
