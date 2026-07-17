package main

import "core:fmt"
import "core:os"


game_memory :: struct {
    input: input_context,
    renderer: renderer_context,
    code: game_code,
    window_width: u32,
    window_height: u32,
    initialized: bool,
}

log_level :: enum {
    Debug,
    Info,
    Warn,
    Error,
    Fatal
}

running: bool

main :: proc() {
    memory: game_memory
    code := &memory.code
    input := &memory.input
    setup_logging()

    memory.window_width = 1280
    memory.window_height = 720

    window := create_window(memory.window_width, memory.window_height)

    // Delete old .pdb files:
    old_pdbs, error := os.glob("bin/game?*.pdb")
    if error != nil do log(.Fatal, "Failed to search for old PDB files")
    for pdb_file in old_pdbs {
        error := os.remove(pdb_file)
        if error != nil do log(.Fatal, "Failed to remove old PDB files")
    }

    load_code(code)
    code.initialize(&memory)

    log(.Debug, "Running!")

    running = true
    last_counter: u64 = get_wall_clock()
    for running {
        reset_input(input)
        process_messages(window, input)

        update_if_newer_code(&memory)

        memory.code.update(&memory)

        free_all(context.temp_allocator)
        clear(&time_records)

        end_counter := get_wall_clock()
        seconds_elapsed := get_seconds_elapsed(last_counter, end_counter)
        last_counter = end_counter
        fmt.printf("FPS: %d\n", i32(1.0 / seconds_elapsed))
    }
}
