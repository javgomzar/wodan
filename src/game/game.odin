package game

import "core:math"
import "../common"

@(export)
initialize_game_state :: proc(memory: ^common.Game_Memory) {
    common.initialize_asset_manager(&memory.asset_manager)
    common.initialize_renderer(&memory.asset_manager, &memory.renderer, memory.render_group.width, memory.render_group.height)
    memory.initialized = true
}

@(export)
reload_game_state :: proc(memory: ^common.Game_Memory) {

}

@(export)
update_game_state :: proc(memory: ^common.Game_Memory) {
    render_group := &memory.render_group
    asset_manager := &memory.asset_manager
    input := &memory.input

    // Testing
    if memory.testing {
    
    }
    
    // Main game loop
    clear_color := [3]f32{0.5 + 0.5*math.sin(f32(memory.renderer.frame) / 100.0), 0.0, 0.5}
    common.push_clear(render_group, clear_color)
    // common.push_rgb_triangle(render_group)

    update_camera(&render_group.camera, input)

    mesh := &asset_manager.assets[1].meshes[0]
    common.push_mesh(render_group, mesh)

    common.render(memory)
}