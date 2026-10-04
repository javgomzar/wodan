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
}

MAX_ENTITIES :: 256

Entity_Manager :: struct {
    entities:   [MAX_ENTITIES]Entity,
    occupied:   [MAX_ENTITIES]bool,
    first_free: u32,
}

initialize_entity_manager :: proc(asset_manager: ^asset.Manager, manager: ^Entity_Manager) {
    manager.first_free = 1

    // Test entity for animation
    test_entity := create_entity(manager)
    test_entity.name = "Test entity"
    test_entity.tags = {.Render, .Animated }
    test_entity.mesh = asset.get_mesh(asset_manager, asset_manager.catalog.animation.meshes[0])
    skeleton := asset.get_skeleton(asset_manager, asset_manager.catalog.animation.skeletons[0])
    animation := asset.get_animation(asset_manager, asset_manager.catalog.animation.animations[0])
    asset.start_animator(&test_entity.animator, skeleton, animation)
}

create_entity :: proc(manager: ^Entity_Manager) -> ^Entity {
    assert(!manager.occupied[manager.first_free])
    result := &manager.entities[manager.first_free]
    result.handle.index = manager.first_free
    manager.occupied[manager.first_free] = true

    // Default values
    result.position = 0
    result.velocity = 0
    result.rotation = 1
    result.scale = 1
    result.parent = {0, 0}

    for manager.occupied[manager.first_free] {
        // Search first free slot
        manager.first_free += 1
    }
    return result
}

get_entity :: proc(manager: ^Entity_Manager, handle: Handle) -> ^Entity {
    if manager.occupied[handle.index] {
        result := &manager.entities[handle.index]
        if result.handle.generation > handle.generation {
            log.error("Entity with handle", handle, "has been eliminated.")
            return nil
        }
        return result
    }
    log.error("Handle", handle, "corresponds to an empty slot.")
    return nil
}

release_entity :: proc(manager: ^Entity_Manager, handle: Handle) -> bool {
    entity := get_entity(manager, handle)
    if entity == nil || entity.handle.generation > handle.generation || !manager.occupied[handle.index] do return false
    manager.occupied[handle.index] = false
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

    for i in 0..<MAX_ENTITIES {
        if !manager.occupied[i] {
            continue
        }

        entity := &manager.entities[i]

        if .Render in entity.tags {
            assert(entity.mesh != nil)
            animator := .Animated in entity.tags ? &entity.animator : nil
            push_mesh(
                &memory.render_group,
                entity.mesh,
                .Mesh,
                translation = entity.position,
                rotation = entity.rotation,
                scale = entity.scale,
                animator = animator,
            )
        }

        if .Debug_Skeleton in entity.tags {
            assert(entity.animator.skeleton != nil)
            push_debug_skeleton(&memory.render_group, entity.animator.skeleton, entity.animator.poses)
        }

        if .Animated in entity.tags {
            asset.update_animator(&entity.animator, memory.delta_time)
        }
    }
}
