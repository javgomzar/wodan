package common

import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:mem/virtual"
import "core:fmt"
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
    indices:          asset.Vertex_Buffer_Entry(u32),
    instances:        asset.Vertex_Buffer_Entry(u32),
    transform:        matrix[4, 4]f32,
    color:            [4]f32,
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
    text_offsets:  asset.Vertex_Buffer(u32),
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
    group:          ^Render_Group,
    topology:       asset.Topology,
    pipeline:       Shader_Pipeline_ID,
    dynamic_buffer: bool,
    key:            Sort_Key = 0,
    transform:      matrix[4, 4]f32 = 1,
    material:       ^asset.Material = nil,
    texture:        ^asset.Texture = nil,
    color:          [4]f32 = {1, 1, 1, 1},
) -> ^Render_Entry {
    entry := Render_Entry{
        topology = topology,
        key = key,
        pipeline = pipeline,
        transform = transform,
        material = material,
        texture = texture,
        dynamic_buffer = dynamic_buffer,
        color = color,
    }
    
    append(&group.commands, entry)
    return &group.commands[len(group.commands) - 1]
}

push_point :: proc(group: ^Render_Group, point: [2]f32, color: [4]f32 = {1, 1, 1, 1}) {
    push_rect(group, point.x, point.y, 2, 2, color = color)
}

push_segment :: proc(group: ^Render_Group, start: [2]f32, end: [2]f32, color: [4]f32 = {1, 1, 1, 1}) {
    entry := add_entry(group, 
        .Line,
        .Screen_Line,
        dynamic_buffer = true,
        color = color,
    )

    entry.positions = asset.push_vertices(&group.positions, 2)
    vertices := entry.positions.memory
    vertices[0] = {start.x, start.y, 0}
    vertices[1] = {end.x, end.y, 0}
}

push_rect :: proc(
    group: ^Render_Group,
    left: f32, top: f32,
    width: f32, height: f32,
    texture: ^asset.Texture = nil, 
    color: [4]f32 = {1, 1, 1, 1}
) {
    pipeline: Shader_Pipeline_ID = texture != nil ? .Screen_Texture : .Screen_Triangle
    entry := add_entry(group,
        topology = .Triangle_Strip,
        pipeline = pipeline,
        dynamic_buffer = true,
        texture = texture,
        color = color,
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

push_rect_outline :: proc(
    group: ^Render_Group,
    left: f32, top: f32,
    width: f32, height: f32,
    color: [4]f32 = {1, 1, 1, 1}
) {
    entry := add_entry(group,
        topology = .Line_Strip,
        pipeline = .Screen_Line,
        dynamic_buffer = true,
        color = color,
    )

    entry.positions = asset.push_vertices(&group.positions, 5)
    vertices := entry.positions.memory
    vertices[0] = { left, top, 0 }
    vertices[1] = { left + width, top, 0 }
    vertices[2] = { left + width, top + height, 0 }
    vertices[3] = { left, top + height, 0 }
    vertices[4] = { left, top, 0 }
}

push_triangle :: proc(
    group: ^Render_Group,
    p0: [2]f32,
    p1: [2]f32,
    p2: [2]f32,
    color: [4]f32 = {1, 1, 1, 1},
) {
    entry := add_entry(group,
        topology = .Triangle,
        pipeline = .Screen_Triangle,
        dynamic_buffer = true,
        color = color,
    )

    entry.positions = asset.push_vertices(&group.positions, 3)
    vertices := entry.positions.memory
    vertices[0] = { p0.x, p0.y, 0 }
    vertices[1] = { p1.x, p1.y, 0 }
    vertices[2] = { p2.x, p2.y, 0 }
}

push_triangle_fan :: proc(
    group: ^Render_Group, 
    pipeline: Shader_Pipeline_ID,
    vertices: [][2]f32,
    color: [4]f32 = {1, 1, 1, 1},
) {
    entry := add_entry(group, .Triangle, pipeline, true, color = color)

    entry.positions = asset.push_vertices(&group.positions, len(vertices))
    positions := entry.positions.memory
    for vertex, index in vertices {
        positions[index] = {vertex.x, vertex.y, 0}
    }

    entry.indices = asset.push_vertices(&group.indices, 3*(len(vertices) - 1))
    indices := entry.indices.memory
    for i in 0..<len(vertices)-2 {
        indices[3*i]     = 0;
        indices[3*i + 1] = u32(i+1);
        indices[3*i + 2] = u32(i+2);
    }
    indices[3*(len(vertices)-2)] = 0
    indices[3*(len(vertices)-2) + 1] = u32(len(vertices) - 1)
    indices[3*(len(vertices)-2) + 2] = 1
}

push_circle :: proc(
    group: ^Render_Group,
    center: [2]f32,
    radius: f32,
    color: [4]f32 = {1, 1, 1, 1},
) {
    vertices := make([][2]f32, 64)
    defer delete(vertices)
    vertices[0] = center
    for i in 1..<64 {
        vertices[i] = {
            center.x + radius * math.cos(math.TAU * f32(i) / 63.0),
            center.y + radius * math.sin(math.TAU * f32(i) / 63.0),
        }
    }
    push_triangle_fan(group, .Screen_Triangle, vertices, color)
}

push_mesh :: proc(
    group:       ^Render_Group,
    mesh:        ^asset.Mesh,
    pipeline:    Shader_Pipeline_ID,
    color:       [4]f32 = {1, 1, 1, 1},
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
            color = color,
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

DPI :: 96.0

push_text :: proc(
    group: ^Render_Group,
    text: string,
    pen_x: f32, pen_y: f32,
    points: f32,
    font: ^asset.Font,
    color: [4]f32 = {1, 1, 1, 1},
) {
    pen: [2]f32 = {pen_x, pen_y}

    size := points * (DPI / 72.0) / font.units_per_em
    for i in 0..<len(text) {
        char := text[i]

        if char == '\n' {
            pen.x = pen_x
            pen.y += size * font.line_jump
            continue
        }

        if char == ' ' {
            pen.x += size * font.space_advance
            continue
        }

        index, ok := font.code_to_index[i32(char)]
        if !ok do index = 0
        glyph := &font.glyphs[index]

        offset := u32(group.text_vertices.count)
        text_vertices := asset.push_vertices(&group.text_vertices, 1)
        text_vertices.memory[0] = {
            pen = pen,
            size = size,
            depth = 0,
            color = color,
        }
        append(&glyph.instances, offset)

        pen.x += size * glyph.advance
    }
}

send_render_text_commands :: proc(group: ^Render_Group) {
    for &game_asset in group.asset_manager.assets[1:] {
        for &font in game_asset.fonts {
            for &glyph in font.glyphs {
                if len(glyph.instances) > 0 {
                    glyph.instances_offset = group.text_offsets.count

                    instances := asset.push_vertices(&group.text_offsets, len(glyph.instances))
                    copy(instances.memory, glyph.instances[:])

                    positions := asset.static_vertices(glyph.n_positions, glyph.positions_offset, asset.Vertex_Position)

                    winding_number_pass := add_entry(group, .Triangle, .Winding_Number, false)
                    winding_number_pass.positions = positions
                    winding_number_pass.instances = instances
                    winding_number_pass.indices = asset.static_vertices(glyph.n_triangle_fan_indices, glyph.triangle_fan_offset, u32)

                    entry_cover := add_entry(group, .Triangle_Strip, .Text_Cover, true)
                    entry_cover.positions = asset.push_vertices(&group.positions, 4)
                    entry_cover.instances = instances
                    entry_cover_vertices := &entry_cover.positions.memory

                    glyph_width := glyph.max_x - glyph.min_x

                    entry_cover_vertices[0] = {glyph.min_x, glyph.max_y, 0}
                    entry_cover_vertices[1] = {glyph.max_x, glyph.max_y, 0}
                    entry_cover_vertices[2] = {glyph.min_x, glyph.min_y, 0}
                    entry_cover_vertices[3] = {glyph.max_x, glyph.min_y, 0}

                    if glyph.n_interior_bezier_indices + glyph.n_exterior_bezier_indices > 0 {
                        bezier_triangles_pass := add_entry(group, .Triangle, .Text_Stencil, false)
                        bezier_triangles_pass.positions = positions
                        bezier_triangles_pass.instances = instances
                        bezier_triangles_pass.indices = asset.static_vertices(
                            glyph.n_interior_bezier_indices + glyph.n_exterior_bezier_indices, glyph.interior_bezier_offset, u32)

                        if glyph.n_interior_bezier_indices > 0 {
                            bezier_interior_stencil_pass := add_entry(group, .Triangle, .Text_Bezier_Interior_Stencil, false)
                            bezier_interior_stencil_pass.positions = positions
                            bezier_interior_stencil_pass.instances = instances
                            bezier_interior_stencil_pass.indices = asset.static_vertices(glyph.n_interior_bezier_indices, glyph.interior_bezier_offset, u32)
                        }

                        if glyph.n_exterior_bezier_indices > 0 {
                            bezier_exterior_stencil_pass := add_entry(group, .Triangle, .Text_Bezier_Exterior_Stencil, false)
                            bezier_exterior_stencil_pass.positions = positions
                            bezier_exterior_stencil_pass.instances = instances
                            bezier_exterior_stencil_pass.indices = asset.static_vertices(glyph.n_exterior_bezier_indices, glyph.exterior_bezier_offset, u32)
                        }

                        if glyph.n_interior_bezier_indices > 0 {
                            bezier_interior_color_pass := add_entry(group, .Triangle, .Text_Bezier_Interior_Color, false)
                            bezier_interior_color_pass.positions = positions
                            bezier_interior_color_pass.instances = instances
                            bezier_interior_color_pass.indices = asset.static_vertices(glyph.n_interior_bezier_indices, glyph.interior_bezier_offset, u32)
                        }

                        if glyph.n_exterior_bezier_indices > 0 {
                            bezier_exterior_color_pass := add_entry(group, .Triangle, .Text_Bezier_Exterior_Color, false)
                            bezier_exterior_color_pass.positions = positions
                            bezier_exterior_color_pass.instances = instances
                            bezier_exterior_color_pass.indices = asset.static_vertices(glyph.n_exterior_bezier_indices, glyph.exterior_bezier_offset, u32)
                        }
                    }

                    entry_stencil_clean := add_entry(group, .Triangle_Strip, .Text_Clean_Stencil, true)
                    entry_stencil_clean.positions = entry_cover.positions
                    entry_stencil_clean.instances = instances

                    clear(&glyph.instances)
                }
            }
        }
    }
}

push_sky :: proc(group: ^Render_Group) {
    entry := add_entry(group, .Triangle, .Sky, true)

    entry.positions = asset.push_vertices(&group.positions, 8)
    vertices := entry.positions.memory
    vertices[0] = {-1.0, -1.0, -1.0}
    vertices[1] = { 1.0, -1.0, -1.0}
    vertices[2] = {-1.0, -1.0,  1.0}
    vertices[3] = { 1.0, -1.0,  1.0}
    vertices[4] = {-1.0,  1.0, -1.0}
    vertices[5] = { 1.0,  1.0, -1.0}
    vertices[6] = {-1.0,  1.0,  1.0}
    vertices[7] = { 1.0,  1.0,  1.0}

    entry.indices = asset.push_vertices(&group.indices, 36)
    indices := entry.indices.memory
    indices[0] = 0;  indices[1] = 1;  indices[2] = 2
    indices[3] = 1;  indices[4] = 2;  indices[5] = 3
    indices[6] = 0;  indices[7] = 1;  indices[8] = 4
    indices[9] = 1;  indices[10] = 4; indices[11] = 5
    indices[12] = 0; indices[13] = 2; indices[14] = 4
    indices[15] = 2; indices[16] = 4; indices[17] = 6
    indices[18] = 1; indices[19] = 3; indices[20] = 5
    indices[21] = 3; indices[22] = 5; indices[23] = 7
    indices[24] = 4; indices[25] = 5; indices[26] = 6
    indices[27] = 5; indices[28] = 6; indices[29] = 7
    indices[30] = 2; indices[31] = 6; indices[32] = 7
    indices[33] = 2; indices[34] = 7; indices[35] = 3
}

get_text_width :: proc(font: ^asset.Font, text: string, points: f32) -> (result: f32) {
    size := points * (DPI / 72.0) / font.units_per_em

    line_width: f32
    for char in text {
        if char == ' ' {
            line_width += size * font.space_advance
            continue
        }

        if char == '\n' {
            if line_width > result do result = line_width
            line_width = 0
            continue
        }

        line_width += size * asset.get_glyph(font, i32(char)).advance
    }

    if line_width > result do result = line_width
    return
}

get_text_rect :: proc(font: ^asset.Font, text: string, pen_x: f32, pen_y: f32, points: f32) -> (result: asset.Rect) {
    size := points * (DPI / 72.0) / font.units_per_em

    result.left = pen_x
    result.top = max(f32)

    line_width: f32
    nth_line: int
    line_min_y: f32
    for char in text {
        if char == ' ' {
            line_width += size * font.space_advance
            continue
        }

        if char == '\n' {
            if line_width > result.width do result.width = line_width
            line_width = 0
            line_min_y = 0
            nth_line += 1

            continue
        }

        glyph := asset.get_glyph(font, i32(char))
        line_width += size * glyph.advance
        line_min_y = min(line_min_y, size * glyph.min_y)
        
        if nth_line == 0 {
            result.top = min(result.top, pen_y - size * glyph.max_y)
        }
    }

    if line_width > result.width do result.width = line_width

    result.height = pen_y + size * (f32(nth_line) * font.line_jump - line_min_y) - result.top

    return
}

push_debug_overlay :: proc(group: ^Render_Group, time: f32, FPS: int) {
    font := group.asset_manager.catalog.debug_font
    pad := f32(10)
    points := f32(16)
    size := points * (DPI / 72.0) / font.units_per_em

    str := fmt.tprintf("FPS: %d\nTime: %f", FPS, time)
    rect := get_text_rect(font, str, 0, 0, points)
    
    push_text(group, str, pad, pad - rect.top, points, font)
    push_rect(group, 0, 0, rect.width + 2*pad, rect.height + 2*pad, color = {0.2, 0.2, 0.2, 0.5})
}