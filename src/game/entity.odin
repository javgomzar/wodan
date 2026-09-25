package game

import "core:log"
import "core:math/linalg"
import "../asset"
import "../common"


ID :: distinct i64

Tag :: enum u64 {
    Render,
    Movable,
    Animated,
    Debug_Skeleton,
}

Tags :: bit_set[Tag]

Handle :: struct {
    index:      u32,
    generation: u32,
}

Entity :: struct {
    handle:     Handle,
    parent:     Handle,
    name:       string,
    tags:       Tags,
    position:   [3]f32,
    rotation:   linalg.Quaternionf32,
    scale:      [3]f32,
    velocity:   [3]f32,
    animator:   asset.Animator,
    mesh:       ^asset.Mesh,
    active:     bool,
}

MAX_ENTITIES :: 256

Entity_Manager :: struct {
    entities:   [MAX_ENTITIES]Entity,
    first_free: u32,
}

initialize_entity_manager :: proc(asset_manager: ^asset.Manager, manager: ^Entity_Manager) {
    manager.first_free = 1

    test_entity := create_entity(manager)
    test_entity.name = "Test entity"
    test_entity.tags = {.Render, .Animated, .Debug_Skeleton}
    test_entity.mesh = asset.get_mesh(asset_manager, asset_manager.catalog.animation.meshes[0])
    test_entity.animator.skeleton = asset.get_skeleton(asset_manager, asset_manager.catalog.animation.skeletons[0])
    test_entity.animator.animation = asset.get_animation(asset_manager, asset_manager.catalog.animation.animations[0])
}

create_entity :: proc(manager: ^Entity_Manager) -> ^Entity {
    result := &manager.entities[manager.first_free]
    result.handle.index = manager.first_free
    assert(!result.active)
    result.active = true

    // Default values
    result.position = 0
    result.velocity = 0
    result.rotation = 1
    result.scale = 1
    result.parent = {0, 0}

    next := result
    for next.active {
        // Search first free slot
        manager.first_free += 1
        next = &manager.entities[manager.first_free]
    }
    return result
}

get_entity :: proc(manager: ^Entity_Manager, handle: Handle) -> ^Entity {
    result := &manager.entities[handle.index]
    if result.handle.generation > handle.generation {
        log.error("Entity with handle", handle, "has been eliminated.")
        return nil
    }
    return result
}

release_entity :: proc(manager: ^Entity_Manager, handle: Handle) -> bool {
    entity := get_entity(manager, handle)
    if entity == nil || entity.handle.generation > handle.generation || !entity.active do return false
    entity.active = false
    entity.handle.generation += 1
    if handle.index < manager.first_free {
        manager.first_free = handle.index
    }
    return true
}

update_entities :: proc(memory: ^Game_Memory) {
    timer := common.start_timer(.Update_Entities)
    defer common.end_timer(timer)

    manager := &memory.entity_manager

    for &entity in manager.entities {
        if entity.active {
            if .Render in entity.tags {
                assert(entity.mesh != nil)
                push_mesh(
                    &memory.render_group,
                    entity.mesh,
                    .Mesh,
                    translation = entity.position,
                    rotation = entity.rotation,
                    scale = entity.scale,
                )
            }

            if .Debug_Skeleton in entity.tags {
                assert(entity.animator.skeleton != nil)
                push_debug_skeleton(&memory.render_group, entity.animator.skeleton)
            }
        }
    }
}
