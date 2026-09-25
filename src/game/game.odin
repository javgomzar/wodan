package game

import "core:log"
import "core:math"
import "core:math/linalg"
import "../common"
import "../asset"


@(export)
initialize_game_state :: proc(memory: ^Game_Memory) {
    start := common.get_wall_clock()
    
    asset_manager := &memory.asset_manager
    asset.initialize_manager(asset_manager)
    
    // Add assets here
    asset.add_asset(asset_manager, &asset_manager.catalog.animation, "file/asset/animation/animation.ass",
        "file/asset/animation/Standard_Walking.glb",
        force_process = true
    )
    
    end := common.get_wall_clock()
    log.info("Loaded assets in", 1000.0*common.get_seconds_elapsed(start, end), "milliseconds")

    start = common.get_wall_clock()
    initialize_renderer(asset_manager, &memory.renderer, &memory.render_group)
    end = common.get_wall_clock()
    log.info("Initialized renderer in", 1000.0*common.get_seconds_elapsed(start, end), "milliseconds")

    initialize_ui_context(memory)
    initialize_entity_manager(asset_manager, &memory.entity_manager)
    memory.initialized = true
}

@(export)
reload_game_state :: proc(memory: ^Game_Memory) {
    common.set_up_timing(&memory.time_records)
    initialize_shader_compiler(&memory.renderer.shader_compiler)
    reload_ui_context(memory)
}

@(export)
update_game_state :: proc(memory: ^Game_Memory) {
    render_group := &memory.render_group
    asset_manager := &memory.asset_manager
    input := &memory.input

    update_camera(&render_group.camera, input)
    push_sky(render_group)

    // Testing & debugging
    when ODIN_DEBUG {
        if memory.debug {
            grid_mesh := asset.get_mesh(asset_manager, asset_manager.catalog.system.meshes[0])
            push_mesh(
                render_group,
                grid_mesh,
                pipeline = .World_Line,
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
            push_text(
                render_group, 
                test_string, 
                100, 300, 100 - 30*math.cos(memory.time),
                font = asset.get_font(asset_manager, "BlackChancery")
            )
        }
    }

    update_ui(memory)
    update_entities(memory)

    // skeleton_id := asset_manager.catalog.animation.skeletons[0]
    // push_debug_skeleton(render_group, skeleton_id)

    send_render_text_commands(render_group)
    render(memory)
}