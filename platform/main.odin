package main

import "core:fmt"
import "core:os"


game_memory :: struct {
    input:         input_context,
    renderer:      renderer_context,
    code:          game_code,
    time:          f32,
    delta_time:    f32,
    initialized:   bool,
    running:       bool,
}

log_level :: enum {
    Debug,
    Info,
    Warn,
    Error,
    Fatal
}

memory: game_memory

main :: proc() {
    memory.time = 0
    code := &memory.code
    input := &memory.input
    
    setup_logging()

    memory.renderer.width = 1280
    memory.renderer.height = 720

    window := create_window(memory.renderer.width, memory.renderer.height)

    // Delete old .pdb files:
    old_pdbs, error := os.glob("bin/game?*.pdb")
    if error != nil do log(.Fatal, "Failed to search for old PDB files")
    for pdb_file in old_pdbs {
        error = os.remove(pdb_file)
        if error != nil do log(.Fatal, "Failed to remove old PDB files")
    }

    load_code(code)
    code.reload(&memory)
    code.initialize(&memory)

    log(.Debug, "Running!")

    memory.running = true
    last_counter: u64 = get_wall_clock()
    for memory.running {
        reset_input(input)
        process_messages(window, input)

        update_if_newer_code(&memory)

        memory.code.update(&memory)

        free_all(context.temp_allocator)
        clear(&time_records)

        end_counter := get_wall_clock()
        seconds_elapsed := get_seconds_elapsed(last_counter, end_counter)
        memory.time += seconds_elapsed
        memory.delta_time = seconds_elapsed
        last_counter = end_counter
        fmt.printf("FPS: %d\n", i32(1.0 / seconds_elapsed))
    }
}
