package game

import "../platform"

@(export)
initialize_game_state :: proc(memory: ^platform.game_memory) {
    platform.initiate_renderer(&memory.renderer, memory.window_width, memory.window_height)
    memory.initialized = true
}

@(export)
reload_game_state :: proc(memory: ^platform.game_memory) {
    platform.setup_logging()
}

@(export)
update_game_state :: proc(memory: ^platform.game_memory) {
    // Main game loop
    
    platform.render(&memory.renderer)
}