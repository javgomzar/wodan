package game

import "core:math"
import "../common"
import "../asset"


@(export)
initialize_game_state :: proc(memory: ^common.Game_Memory) {
    asset.initialize_manager(&memory.asset_manager)
    
    // Add assets here

    for &game_asset in memory.asset_manager.assets[1:] {
        if game_asset.processing {
            asset.import_asset_files(&game_asset)
            asset.write(&game_asset)
            game_asset.processing = false
        }
        else do asset.load(&game_asset)
    }

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

    update_camera(&render_group.camera, input)

    mesh := &asset_manager.assets[1].meshes[0]
    material := &asset_manager.assets[1].materials[0]
    common.push_mesh(render_group, mesh, material, .Test_Pipeline)

    common.render(memory)
}