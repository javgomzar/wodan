package asset

import "core:mem"
import "core:log"
import "core:slice"
import "core:strings"


extract_from_memory :: proc(memory: []byte, $T: typeid) -> T {
    result, ok := slice.to_type(memory, T)
    if !ok do log.fatal("Failed to extract type '", typeid_of(T), "' from memory", sep = "")
    return result
}

dump_to_memory :: proc(memory: []byte, data: $T) {
    dst := (^T)(raw_data(memory))
    dst^ = data
}

get_serialized_size_string :: proc(s: string) -> int {
    return size_of(u32) + len(s)
}

serialize_string :: proc(memory: []byte, s: string) -> (size: int) {
    size = get_serialized_size_string(s)
    dump_to_memory(memory, u32(len(s)))
    bytes_copied := copy(memory[4:], s)
    assert(bytes_copied + 4 == size)
    return
}

deserialize_string :: proc(memory: []byte) -> (result: string, size: int) {
    length := extract_from_memory(memory, u32)
    block := memory[size_of(u32):]
    size += size_of(u32)
    result = strings.clone(string(block[:length]))
    size += int(length)
    return
}

get_serialized_size_slice :: proc(s: $T/[]$E) -> (size: int) {
    size += size_of(u32)
    size += slice.size(s)
    return
}

serialize_slice :: proc(memory: []byte, s: $T/[]$E) -> (size: int) {
    block := memory
    size = get_serialized_size_slice(s)
    dump_to_memory(block, u32(len(s)))
    copied := copy(block[4:size], slice.to_bytes(s))
    assert(copied + 4 == size)
    return
}

deserialize_slice :: proc(memory: []byte, $T: typeid/[]$E) -> (result: []E, size: int) {
    length := extract_from_memory(memory, u32)
    size += size_of(u32)
    block := memory[size_of(u32):]
    result = make([]E, length)
    raw := cast([^]E)raw_data(block)
    copy(result, raw[:length])
    size += int(length) * size_of(E)
    return
}

widen_to_u32 :: proc(out: []u32, src: [^]$T, count: int) {
    for i in 0..<count {
        out[i] = u32(src[i])
    }
}

get_serialized_size_material :: proc(material: Material) -> int {
    return get_serialized_size_string(material.name) + 6 * size_of(f32)
}

serialize_material :: proc(allocator: mem.Allocator, material: Material) {
    size := get_serialized_size_material(material)
    block := make([]byte, size, allocator)

    name_size := serialize_string(block, material.name)
    block = block[name_size:]

    data := []f32{
        material.base_color[0],
        material.base_color[1],
        material.base_color[2],
        material.base_color[3],
        material.metallic,
        material.roughness,
    }
    copy(block, slice.to_bytes(data))
}

deserialize_material :: proc(memory: []byte) -> (result: Material, size: int) {
    name_size: int
    result.name, name_size = deserialize_string(memory)
    block := memory[name_size:]
    size += name_size
    
    result.base_color = extract_from_memory(block, [4]f32)
    color_size := size_of([4]f32)
    block = block[color_size:]
    size += color_size

    result.metallic = extract_from_memory(block, f32)
    metallic_size := size_of(f32)
    block = block[metallic_size:]
    size += metallic_size

    result.roughness = extract_from_memory(block, f32)
    roughness_size := size_of(f32)
    block = block[roughness_size:]
    size += roughness_size

    return
}

get_serialized_size_primitive :: proc(primitive: Primitive) -> (size: int) {
    size += size_of(Topology)
    size += get_serialized_size_slice(primitive.indices)
    size += get_serialized_size_slice(primitive.positions)
    size += get_serialized_size_slice(primitive.attributes)
    return
}

serialize_primitive :: proc(memory: []byte, primitive: Primitive) -> (size: int) {
    size = get_serialized_size_primitive(primitive)
    total_bytes_written: int
    dump_to_memory(memory, primitive.topology)
    total_bytes_written += 4
    block := memory[size_of(primitive.topology):]
    bytes_written := serialize_slice(block, primitive.indices)
    total_bytes_written += bytes_written
    block = block[bytes_written:]
    bytes_written = serialize_slice(block, primitive.positions)
    total_bytes_written += bytes_written
    block = block[bytes_written:]
    bytes_written = serialize_slice(block, primitive.attributes)
    total_bytes_written += bytes_written
    assert(size == total_bytes_written)
    return
}

deserialize_primitive :: proc(memory: []byte) -> (result: Primitive, size: int) {
    result.topology = extract_from_memory(memory, Topology)
    block := memory[size_of(Topology):]
    size += size_of(Topology)
    
    indices_size: int
    result.indices, indices_size = deserialize_slice(block, []u32)
    block = block[indices_size:]
    size += indices_size

    positions_size: int
    result.positions, positions_size = deserialize_slice(block, []Vertex_Position)
    block = block[positions_size:]
    size += positions_size

    attributes_size: int
    result.attributes, attributes_size = deserialize_slice(block, []Vertex_Attributes)
    block = block[attributes_size:]
    size += attributes_size
    return
}

get_serialized_size_mesh :: proc(mesh: Mesh) -> (size: int) {
    size += get_serialized_size_string(mesh.name)
    size += 4 // primitive count (u32)
    for primitive in mesh.primitives {
        size += get_serialized_size_primitive(primitive)
    }
    return
}

serialize_mesh :: proc(allocator: mem.Allocator, mesh: Mesh) {
    size := get_serialized_size_mesh(mesh)

    block := make([]byte, size, allocator)
    if len(block) == 0 {
        log.fatal("Failed to allocate mesh block.")
    }

    bytes_written := serialize_string(block, mesh.name)
    block = block[bytes_written:]
    dump_to_memory(block, u32(len(mesh.primitives)))
    block = block[4:]
    for primitive in mesh.primitives {
        bytes_written = serialize_primitive(block, primitive)
        block = block[bytes_written:]
    }
}

deserialize_mesh :: proc(memory: []byte) -> (result: Mesh, size: int) {
    name_size: int
    result.name, name_size = deserialize_string(memory)
    block := memory[name_size:]
    size += name_size

    n_primitives := extract_from_memory(block, u32)
    block = block[size_of(u32):]
    size += size_of(u32)

    result.primitives = make([]Primitive, n_primitives)
    for index in 0..<n_primitives {
        result_primitive, primitive_size := deserialize_primitive(block)
        result.primitives[index] = result_primitive
        block = block[primitive_size:]
        size += primitive_size
    }
    return
}

get_serialized_size_glyph_contour :: proc(contour: Glyph_Contour) -> int {
    return get_serialized_size_slice(contour.points)
}

serialize_glyph_contour :: proc(memory: []byte, contour: Glyph_Contour) -> int {
    return serialize_slice(memory, contour.points)
}

deserialize_glyph_contour :: proc(memory: []byte) -> (result: Glyph_Contour, size: int) {
    result.points, size = deserialize_slice(memory, []Glyph_Contour_Point)
    return 
}

get_serialized_size_glyph :: proc(glyph: Glyph) -> (size: int) {
    size += 8 * size_of(f32) + size_of(bool)
    if glyph.composite {
        size += get_serialized_size_slice(glyph.children)
    }
    else {
        size += size_of(u32) // contour count
        for contour in glyph.contours {
            size += get_serialized_size_glyph_contour(contour)
        }
    }
    return
}

serialize_glyph :: proc(memory: []byte, glyph: Glyph) -> (size: int) {
    dump_to_memory(memory, glyph.id)
    block := memory[size_of(glyph.id):]
    size += size_of(glyph.id)
    dump_to_memory(block, glyph.code)
    block = block[size_of(glyph.code):]
    size += size_of(glyph.code)
    dump_to_memory(block, glyph.min_x)
    block = block[size_of(glyph.min_x):]
    size += size_of(glyph.min_x)
    dump_to_memory(block, glyph.max_x)
    block = block[size_of(glyph.max_x):]
    size += size_of(glyph.max_x)
    dump_to_memory(block, glyph.min_y)
    block = block[size_of(glyph.min_y):]
    size += size_of(glyph.min_y)
    dump_to_memory(block, glyph.max_y)
    block = block[size_of(glyph.max_y):]
    size += size_of(glyph.max_y)
    dump_to_memory(block, glyph.advance)
    block = block[size_of(glyph.advance):]
    size += size_of(glyph.advance)
    dump_to_memory(block, glyph.left_side_bearing)
    block = block[size_of(glyph.left_side_bearing):]
    size += size_of(glyph.left_side_bearing)
    dump_to_memory(block, glyph.composite)
    block = block[size_of(glyph.composite):]
    size += size_of(glyph.composite)
    if glyph.composite {
        slice_size := serialize_slice(block, glyph.children)
        block = block[slice_size:]
        size += slice_size
    }
    else {
        dump_to_memory(block, u32(len(glyph.contours)))
        block = block[size_of(u32):]
        size += size_of(u32)
        for contour in glyph.contours {
            contour_size := serialize_glyph_contour(block, contour)
            block = block[contour_size:]
            size += contour_size
        }
    }
    expected_size := get_serialized_size_glyph(glyph)
    assert(size == expected_size)
    return
}

deserialize_glyph :: proc(memory: []byte) -> (result: Glyph, size: int) {
    result.id = extract_from_memory(memory, i32)
    block := memory[size_of(i32):]
    size += size_of(i32)
    result.code = extract_from_memory(block, i32)
    block = block[size_of(i32):]
    size += size_of(i32)
    result.min_x = extract_from_memory(block, f32)
    block = block[size_of(f32):]
    size += size_of(f32)
    result.max_x = extract_from_memory(block, f32)
    block = block[size_of(f32):]
    size += size_of(f32)
    result.min_y = extract_from_memory(block, f32)
    block = block[size_of(f32):]
    size += size_of(f32)
    result.max_y = extract_from_memory(block, f32)
    block = block[size_of(f32):]
    size += size_of(f32)
    result.advance = extract_from_memory(block, f32)
    block = block[size_of(f32):]
    size += size_of(f32)
    result.left_side_bearing = extract_from_memory(block, f32)
    block = block[size_of(f32):]
    size += size_of(f32)
    result.composite = extract_from_memory(block, bool)
    block = block[size_of(bool):]
    size += size_of(bool)
    if result.composite {
        children_size: int
        result.children, children_size = deserialize_slice(block, []Glyph_Composite_Record)
        size += get_serialized_size_slice(result.children)
    }
    else {
        n_contours := extract_from_memory(block, u32)
        block = block[size_of(u32):]
        size += size_of(u32)
        result.contours = make([]Glyph_Contour, n_contours)
        for i in 0..<n_contours {
            contour_size: int
            result.contours[i], contour_size = deserialize_glyph_contour(block)
            size += contour_size
            block = block[contour_size:]
            result.n_positions += len(result.contours[i].points)
        }
    }
    expected_size := get_serialized_size_glyph(result)
    assert(size == expected_size)
    return
}

get_serialized_size_font :: proc(font: Font) -> (size: int) {
    size += get_serialized_size_string(font.name)
    size += 2 * size_of(f32) // space advance and line jump
    size += 4 * size_of(f32) // min/max x, y
    size += size_of(f32)     // units per EM
    size += size_of(u32)     // glyph count
    for glyph in font.glyphs {
        size += get_serialized_size_glyph(glyph)
    }
    return
}

serialize_font :: proc(allocator: mem.Allocator, font: Font) {
    size := get_serialized_size_font(font)

    block := make([]byte, size, allocator)
    if len(block) == 0 {
        log.fatal("Failed to allocate mesh block.")
    }

    name_size := serialize_string(block, font.name)
    block = block[name_size:]
    dump_to_memory(block, font.space_advance)
    block = block[size_of(f32):]
    dump_to_memory(block, font.line_jump)
    block = block[size_of(f32):]
    dump_to_memory(block, font.min_x)
    block = block[size_of(f32):]
    dump_to_memory(block, font.max_x)
    block = block[size_of(f32):]
    dump_to_memory(block, font.min_y)
    block = block[size_of(f32):]
    dump_to_memory(block, font.max_y)
    block = block[size_of(f32):]
    dump_to_memory(block, font.units_per_em)
    block = block[size_of(f32):]

    dump_to_memory(block, u32(len(font.glyphs)))
    block = block[size_of(u32):]
    for glyph in font.glyphs {
        glyph_size := serialize_glyph(block, glyph)
        block = block[glyph_size:]
    }
}

deserialize_font :: proc(memory: []byte) -> (result: Font, size: int) {
    name_size: int
    result.name, name_size = deserialize_string(memory)
    block := memory[name_size:]
    size += name_size

    result.space_advance = extract_from_memory(block, f32)
    block = block[size_of(f32):]
    size += size_of(f32)
    result.line_jump = extract_from_memory(block, f32)
    block = block[size_of(f32):]
    size += size_of(f32)
    result.min_x = extract_from_memory(block, f32)
    block = block[size_of(f32):]
    size += size_of(f32)
    result.max_x = extract_from_memory(block, f32)
    block = block[size_of(f32):]
    size += size_of(f32)
    result.min_y = extract_from_memory(block, f32)
    block = block[size_of(f32):]
    size += size_of(f32)
    result.max_y = extract_from_memory(block, f32)
    block = block[size_of(f32):]
    size += size_of(f32)
    result.units_per_em = extract_from_memory(block, f32)
    block = block[size_of(f32):]
    size += size_of(f32)

    n_glyphs := extract_from_memory(block, u32)
    block = block[size_of(u32):]
    size += size_of(u32)
    result.glyphs = make([]Glyph, n_glyphs)
    for &glyph in result.glyphs {
        glyph_size: int
        glyph, glyph_size = deserialize_glyph(block)
        block = block[glyph_size:]
        size += glyph_size
    }
    return
}
