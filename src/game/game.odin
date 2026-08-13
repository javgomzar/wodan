package game

import "core:log"
import "../common"
import "../asset"


@(export)
initialize_game_state :: proc(memory: ^common.Game_Memory) {
    common.set_up_timing(&memory.time_records)
    timer := common.start_timer(.Asset_Loading)
    defer common.end_timer(timer)
    
    asset_manager := &memory.asset_manager
    asset.initialize_manager(asset_manager)

    // System assets
    system_asset := &asset_manager.assets[asset_manager.system_asset_id]
    asset.add_file(system_asset, "file/asset/system/DejaVuSans.ttf")
    asset.add_file(system_asset, "file/asset/system/DejaVuSansMono.ttf")
    asset.add_file(system_asset, "file/asset/system/grid.glb")
    asset.add_file(system_asset, "file/asset/system/rgb_triangle.glb")
    asset.add_file(system_asset, "D:/TestAssets/glTF-Sample-Assets-main/Models/BoxTexturedNonPowerOfTwo/glTF-Binary/BoxTexturedNonPowerOfTwo.glb")
    
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
    memory.initialized = true
}

@(export)
reload_game_state :: proc(memory: ^common.Game_Memory) {
    common.set_up_timing(&memory.time_records)
}

@(export)
update_game_state :: proc(memory: ^common.Game_Memory) {
    render_group := &memory.render_group
    asset_manager := &memory.asset_manager
    system_asset := &asset_manager.assets[asset_manager.system_asset_id]
    input := &memory.input

    // Testing & debugging
    when ODIN_DEBUG {
        if memory.debug {
            grid := asset.get_mesh_by_name(system_asset, "Grid")
            material := &asset_manager.assets[1].materials[0]
            common.push_mesh(
                render_group, 
                grid, 
                material = material,
                pipeline = .Grid_Pipeline,
                scale = {10, 10, 10}
            )
        }

        if input.keyboard.key[.Control].is_down && input.keyboard.key[.T].just_pressed {
            memory.testing = !memory.testing
            log.debug("Activating testing")
        }
    
        if memory.testing {
            rect := common.Rect{200, 200, 200, 200}

            @(static) triangle := common.Triangle2{
                {600, 600},
                {500, 600},
                {600, 500},
            }
            
            if input.mouse.left_click.is_down {
                triangle[2] = common.Point2(input.mouse.cursor)
            }

            color: [4]f32 = common.intersect_rect_with_triangle(rect, triangle) ? {0, 1, 0, 1} : {1, 0, 0, 1}
            common.push_rect(render_group, rect.left, rect.top, rect.width, rect.height, color = {1, 1, 1, 1})
            common.push_triangle(render_group, triangle, color = color)
        }
    }

    update_camera(&render_group.camera, input)

    if input.keyboard.key[.F1].just_pressed {
        memory.debug = !memory.debug
        if memory.debug do log.debug("Debug mode on")
    }

    cube := asset.get_mesh_by_name(system_asset, "Mesh")
    material := &system_asset.materials[1]
    texture := &system_asset.textures[0]
    common.push_mesh(render_group, cube, .Mesh_Pipeline, material, texture, scale = {1, -1, 1})

    common.push_text(render_group, "This is a test string !", 300, 300, 42)

    common.render(memory)

    common.print_timers()
    common.clear_time_records()
}