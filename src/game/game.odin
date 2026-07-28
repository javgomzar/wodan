package game

import "../common"

@(export)
initialize_game_state :: proc(memory: ^common.Game_Memory) {
    common.initialize_renderer(&memory.renderer, memory.render_group.width, memory.render_group.height)
    memory.initialized = true
}

@(export)
reload_game_state :: proc(memory: ^common.Game_Memory) {

}

@(export)
update_game_state :: proc(memory: ^common.Game_Memory) {
    // Main game loop
    
    common.render(memory)
}