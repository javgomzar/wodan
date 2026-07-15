package main


// monitor :: struct {
//     name: string,
//     width: u32,
//     height: u32,
// }

game_memory :: struct {
    // monitors: []monitor,
    input: game_input,
    running: bool,
}

global_memory: game_memory

log_level :: enum {
    Debug,
    Info,
    Warn,
    Error,
    Fatal
}

// log :: proc(level: log_level, message: string) {
//     fmt.printf()
// }

window_width: u32 = 1280
window_height: u32 = 720

main :: proc() {
    setup_logging()

    window := create_window(window_width, window_height)
    initiate_renderer(window, window_width, window_height)

    log(.Debug, "Running!")

    global_memory.running = true
    for global_memory.running {
        reset_input(&global_memory.input)
        process_messages(window, &global_memory.input)
        
        if global_memory.input.mouse.left_click.is_down {
            log(.Debug, "Click!")
        }

        render(f32(window_width), f32(window_height))

        free_all(context.temp_allocator)
    }
}
