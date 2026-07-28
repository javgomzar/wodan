package common

import "core:math"
import "core:math/linalg"
import "core:mem/virtual"
import "core:mem"
import "core:log"


Primitive :: enum int {
    Point =          0,
    Lines =          1,
    Line_Loop =      2,
    Line_Strip =     3,
    Triangles =      4,
    Triangle_Strip = 5,
    Triangle_Fan =   6,
}

Camera :: struct {
    position: [3]f32,
    angle:    f32,
    pitch:    f32,
    distance: f32,
}

get_camera_basis :: proc(angle: f32, pitch: f32) -> matrix[3, 3]f32 {
    cosA := math.cos(angle * math.RAD_PER_DEG)
    sinA := math.sin(angle * math.RAD_PER_DEG)
    cosP := math.cos(pitch * math.RAD_PER_DEG)
    sinP := math.sin(pitch * math.RAD_PER_DEG)

    return {
                cosA,   0.0,        -sinA,
        -sinA * sinP,  cosP, -cosA * sinP,
        -sinA * cosP, -sinP, -cosA * cosP,
    }
}

get_view_matrix :: proc(basis: matrix[3, 3]f32, distance: f32, position: [3]f32) -> matrix[4, 4]f32 {
    t_basis := linalg.transpose(basis)

    translation := [3]f32{0, 0, distance} - position * basis
    result := linalg.matrix4_from_matrix3(t_basis)
    return result
}

Sort_Key :: distinct f32

Render_Entry :: struct {
    key:      Sort_Key,
    pipeline: Shader_Pipeline_Id,
}

Render_Group :: struct {
    width:    u32,
    height:   u32,
    arena:    virtual.Arena,
    commands: [dynamic]Render_Entry,
}

initialize_render_group :: proc(group: ^Render_Group, width: u32, height: u32) {
    group.width, group.height = width, height
    error := virtual.arena_init_static(&group.arena, 64 * mem.Kilobyte)
    if error != nil do log.fatal("Failed to reserve memory for render group arena")

    group.commands = make([dynamic]Render_Entry, virtual.arena_allocator(&group.arena))
}

add_entry :: proc(group: ^Render_Group, key: Sort_Key, pipeline: Shader_Pipeline_Id) {
    
}