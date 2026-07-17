package game

import "../platform"

@(export)
initialize_game_state :: proc(memory: ^platform.game_memory) {
    platform.setup_logging()

    memory.initialized = true
}

@(export)
update_game_state :: proc(memory: ^platform.game_memory) {
    // Main game loop
}