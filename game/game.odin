package game

import "../platform"

@(export)
initialize_game_state :: proc(memory: ^platform.game_memory) {
    platform.initialize_renderer(&memory.renderer)
    memory.initialized = true
}

@(export)
reload_game_state :: proc(memory: ^platform.game_memory) {
    platform.setup_logging()
}

@(export)
update_game_state :: proc(memory: ^platform.game_memory) {
    // Main game loop
    
    platform.render(memory)
}