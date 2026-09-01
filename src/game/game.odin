package game

import "core:log"
import "core:math"
import "../common"
import "../asset"


@(export)
initialize_game_state :: proc(memory: ^common.Game_Memory) {
    common.set_up_timing(&memory.time_records)
    start := common.get_wall_clock()
    
    asset_manager := &memory.asset_manager
    asset.initialize_manager(asset_manager)

    // System assets
    system_asset := &asset_manager.assets[asset_manager.system_asset_id]
    asset.add_file(system_asset, "file/asset/system/grid.glb")
    asset.add_file(system_asset, "file/asset/system/rgb_triangle.glb")
    asset.add_file(system_asset, "file/asset/system/body_pro.glb")
    //asset.add_file(system_asset, "file/asset/animation/Standard_Walking.glb")
    
    // Add assets here

    for &game_asset in memory.asset_manager.assets[1:] {
        if game_asset.processing {
            asset.import_asset_files(&game_asset)
            asset.write(&game_asset)
            game_asset.processing = false
        }
        else do asset.load(&game_asset)
    }

    common.initialize_renderer(&memory.asset_manager, &memory.renderer, &memory.render_group)
    common.initialize_ui_context(memory)
    memory.initialized = true

    end := common.get_wall_clock()
    log.info("Loaded assets in", 1000.0*common.get_seconds_elapsed(start, end), "milliseconds")
}

@(export)
reload_game_state :: proc(memory: ^common.Game_Memory) {
    common.set_up_timing(&memory.time_records)
    common.initialize_shader_compiler(&memory.renderer.shader_compiler)
    common.initialize_ui_context(memory)
}

@(export)
update_game_state :: proc(memory: ^common.Game_Memory) {
    render_group := &memory.render_group
    asset_manager := &memory.asset_manager
    system_asset := &asset_manager.assets[asset_manager.system_asset_id]
    input := &memory.input

    update_camera(&render_group.camera, input)
    common.push_sky(render_group)

    // Testing & debugging
    when ODIN_DEBUG {
        if memory.debug {
            grid := asset.get_mesh_by_name(system_asset, "Grid")
            material := &asset_manager.assets[1].materials[0]
            common.push_mesh(
                render_group, 
                grid, 
                material = material,
                pipeline = .Grid,
                scale = {10, 10, 10},
                color = {1, 1, 1, 0.4},
            )
        }

        if input.keyboard.key[.Control].is_down && input.keyboard.key[.T].just_pressed {
            memory.testing = !memory.testing
            if memory.testing {
                log.debug("Activating testing")
            }
            else {
                log.debug("Deactivating testing")
            }
        }
    
        if memory.testing {
            test_string := "!\"#$%&'()*+,-./0123456789:;<=>?@\nABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`\nabcdefghijklmnopqrstuvwxyz{|}~"
            common.push_text(
                render_group, 
                test_string, 
                100, 300, 100 - 30*math.cos(memory.time),
                font = asset.get_font(asset_manager, "BlackChancery")
            )
        }
    }

    common.update_ui(memory)

    // body := asset.get_mesh_by_name(system_asset, "Mesh")
    // common.push_mesh(render_group, body, .Mesh, scale = {1, 1, -1})

    common.send_render_text_commands(render_group)
    common.render(memory)
}