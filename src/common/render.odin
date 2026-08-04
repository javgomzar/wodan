package common

import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:mem/virtual"
import "../asset"


Camera :: struct {
    position: [3]f32,
    angle:    f32,
    pitch:    f32,
    distance: f32,
}

radial_vector :: proc(angle: f32, pitch: f32) -> [3]f32 {
    cosA := math.cos(angle * math.RAD_PER_DEG);
    sinA := math.sin(angle * math.RAD_PER_DEG);
    cosP := math.cos(pitch * math.RAD_PER_DEG);
    sinP := math.sin(pitch * math.RAD_PER_DEG);
    return { sinA * cosP, sinP, cosA * cosP }
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
    result[3, 0] = translation.x
    result[3, 1] = translation.y
    result[3, 2] = translation.z
    return result
}

get_projection_matrix :: proc(Width: f32, Height: f32) -> matrix[4, 4]f32 {
    s_x: f32 = 1.0
    s_y: f32 = Width / Height
    s_z: f32 = 1.0
    
    return {
        s_x, 0.0, 0.0, 0.0,
        0.0, s_y, 0.0, 0.0,
        0.0, 0.0, 1.0, s_z,
        0.0, 0.0,-1.0, 0.0,
    }
}

Render_Light :: struct {
    direction:        [3]f32,
    color:            [3]f32,
    ambient:          f32,
    diffuse:          f32,
}

Sort_Key :: distinct f32

Render_Entry_Type :: enum {
    Clear,
    Mesh,
}

Render_Entry :: struct {
    type:             Render_Entry_Type,
    key:              Sort_Key,
    topology:         asset.Topology,
    position_offset:  int,
    position_count:   int,
    attribute_offset: int,
    attribute_count:  int,
    index_offset:     int,
    index_count:      int,
    pipeline:         Shader_Pipeline_ID,
    material:         ^asset.Material,
    color:            [4]f32,
}

Render_Group :: struct {
    width:    u32,
    height:   u32,
    arena:    virtual.Arena,
    camera:   Camera,
    light:    Render_Light,
    commands: [dynamic]Render_Entry,
}

initialize_render_group :: proc(group: ^Render_Group, width: u32, height: u32) {
    group.width, group.height = width, height
    error := virtual.arena_init_static(&group.arena, 64 * mem.Kilobyte)
    if error != nil do log.fatal("Failed to reserve memory for render group arena")

    group.commands = make([dynamic]Render_Entry, virtual.arena_allocator(&group.arena))

    group.camera.angle = 45.0
    group.camera.pitch = 45.0
    group.camera.distance = 10.0

    group.light = {
        color = { 1.0, 1.0, 1.0, },
        direction = linalg.normalize([3]f32{ -0.5, -1, 1 }),
        ambient = 0.5,
        diffuse = 0.5,
    }
}

add_entry :: proc(group: ^Render_Group, entry: Render_Entry) -> ^Render_Entry {
    append(&group.commands, entry)
    return &group.commands[len(group.commands) - 1]
}

push_clear :: proc(group: ^Render_Group, color: [3]f32) {
    entry := add_entry(group, { type = .Clear, pipeline = .Test_Pipeline })
    entry.color.rgb = color
}

push_mesh :: proc(
    group:    ^Render_Group,
    mesh:     ^asset.Mesh,
    material: ^asset.Material,
    pipeline: Shader_Pipeline_ID,
    outline:  bool = false,
) {
    for primitive in mesh.primitives {
        add_entry(group, {
            type = .Mesh,
            material = material,
            topology = primitive.topology,
            pipeline = pipeline,
            index_count = len(primitive.indices),
            index_offset = primitive.index_offset,
            position_count = len(primitive.positions),
            position_offset = primitive.position_offset,
            attribute_count = len(primitive.attributes),
            attribute_offset = primitive.attribute_offset,
        })
    }
}
