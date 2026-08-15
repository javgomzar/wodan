package common

import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:mem/virtual"
import "../asset"


Camera :: struct {
    position: linalg.Vector3f32,
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

get_view_matrix :: proc(angle: f32, pitch: f32, distance: f32, position: [3]f32) -> matrix[4, 4]f32 {
    basis := get_camera_basis(angle, pitch)
    t_basis := linalg.transpose(basis)

    translation := [3]f32{0, 0, distance} - basis * position
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

Render_Entry :: struct {
    key:              Sort_Key,
    topology:         asset.Topology,
    pipeline:         Shader_Pipeline_ID,
    positions:        asset.Vertex_Buffer_Entry(asset.Vertex_Position),
    attributes:       asset.Vertex_Buffer_Entry(asset.Vertex_Attributes),
    text_vertices:    asset.Vertex_Buffer_Entry(asset.Vertex_Text),
    indices:          asset.Vertex_Buffer_Entry(u32),
    transform:        matrix[4, 4]f32,
    font:             ^asset.Font,
    material:         ^asset.Material,
    texture:          ^asset.Texture,
    dynamic_buffer:   bool,
}

Render_Group :: struct {
    asset_manager: ^asset.Manager,
    width:         u32,
    height:        u32,
    arena:         virtual.Arena,
    camera:        Camera,
    light:         Render_Light,
    positions:     asset.Vertex_Buffer(asset.Vertex_Position),
    attributes:    asset.Vertex_Buffer(asset.Vertex_Attributes),
    text_vertices: asset.Vertex_Buffer(asset.Vertex_Text),
    indices:       asset.Vertex_Buffer(u32),
    commands:      [dynamic]Render_Entry,
}

initialize_render_group :: proc(group: ^Render_Group, asset_manager: ^asset.Manager, width: u32, height: u32) {
    group.asset_manager = asset_manager
    group.width, group.height = width, height
    error := virtual.arena_init_growing(&group.arena, 64 * mem.Kilobyte)
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

add_entry :: proc(
    group: ^Render_Group,
    topology: asset.Topology,
    pipeline: Shader_Pipeline_ID,
    dynamic_buffer: bool,
    key: Sort_Key = 0,
    transform: matrix[4, 4]f32 = 1,
    material: ^asset.Material = nil,
    texture: ^asset.Texture = nil,
) -> ^Render_Entry {
    entry := Render_Entry{
        topology = topology,
        key = key,
        pipeline = pipeline,
        transform = transform,
        material = material,
        texture = texture,
        dynamic_buffer = dynamic_buffer,
    }
    
    append(&group.commands, entry)
    return &group.commands[len(group.commands) - 1]
}

push_rect :: proc(
    group: ^Render_Group,
    left: f32, top: f32,
    width: f32, height: f32,
    texture: ^asset.Texture = nil, 
    color: [4]f32 = {1, 1, 1, 1}
) {
    entry := add_entry(group,
        topology = .Triangle_Strip,
        pipeline = .Text_Pipeline,
        dynamic_buffer = true,
        texture = texture,
    )

    entry.positions = asset.push_vertices(&group.positions, 4)
    vertices := entry.positions.memory
    vertices[0] = { left, top, 0 }
    vertices[1] = { left + width, top, 0 }
    vertices[2] = { left, top + height, 0 }
    vertices[3] = { left + width, top + height, 0 }

    entry.attributes = asset.push_vertices(&group.attributes, 4)
    attributes := entry.attributes.memory
    attributes[0] = { color = color, texture = {0, 1} }
    attributes[1] = { color = color, texture = {1, 1} } 
    attributes[2] = { color = color, texture = {0, 0} } 
    attributes[3] = { color = color, texture = {1, 0} }
}

push_triangle :: proc(
    group: ^Render_Group,
    triangle: Triangle2,
    color: [4]f32 = {1, 1, 1, 1},
) {
    entry := add_entry(group,
        topology = .Triangle,
        pipeline = .Text_Pipeline,
        dynamic_buffer = true,
    )

    entry.positions = asset.push_vertices(&group.positions, 3)
    vertices := entry.positions.memory
    vertices[0] = { triangle[0].x, triangle[0].y, 0 }
    vertices[1] = { triangle[1].x, triangle[1].y, 0 }
    vertices[2] = { triangle[2].x, triangle[2].y, 0 }

    entry.attributes = asset.push_vertices(&group.attributes, 3)
    attributes := entry.attributes.memory
    attributes[0] = { color = color }
    attributes[1] = { color = color }
    attributes[2] = { color = color }
}

push_mesh :: proc(
    group:       ^Render_Group,
    mesh:        ^asset.Mesh,
    pipeline:    Shader_Pipeline_ID,
    material:    ^asset.Material = nil,
    texture:     ^asset.Texture = nil,
    translation: linalg.Vector3f32 = 0,
    rotation:    linalg.Quaternionf32 = 1,
    scale:       linalg.Vector3f32 = 1,
    outline:     bool = false,
) {
    for primitive in mesh.primitives {
        entry := add_entry(group,
            topology = primitive.topology,
            pipeline = pipeline,
            dynamic_buffer = false,
            transform = linalg.matrix4_from_trs_f32(translation, rotation, scale),
            material = material,
            texture = texture,
        )

        entry.positions = asset.static_vertices(len(primitive.positions), primitive.position_offset, asset.Vertex_Position)
        if len(primitive.indices) > 0 {
            entry.indices = asset.static_vertices(len(primitive.indices), primitive.index_offset, u32)
        }
        if len(primitive.attributes) > 0 {
            entry.attributes = asset.static_vertices(len(primitive.attributes), primitive.attribute_offset, asset.Vertex_Attributes)
        }
    }
}

push_text :: proc(
    group: ^Render_Group,
    text: string,
    left: f32, bottom: f32,
    points: f32,
    font_name: string = "DejaVuSansMono",
    color: [4]f32 = {1, 1, 1, 1},
) {
    font := asset.get_font_by_name(group.asset_manager, font_name)
    pen := [2]f32{left, bottom}

    DPI :: 96
    size := points * (DPI / 72.0) / font.units_per_em
    for i in 0..<len(text) {
        char := text[i]

        if char == '\n' {
            pen.x = left
            pen.y += size * font.line_jump
            continue
        }

        if char == ' ' {
            pen.x += size * font.space_advance
            continue
        }

        index, ok := font.code_to_index[i32(char)]
        if !ok do index = 0
        glyph := font.glyphs[index]
        push_rect(group,
            pen.x - 0.5 * size * glyph.left, pen.y - size * glyph.top, size * glyph.width, size * glyph.height, color = color
        )

        pen.x += size * glyph.width
    }
}
