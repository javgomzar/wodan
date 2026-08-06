package asset

import "core:mem"
import "core:log"
import "core:slice"


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

serialize_string :: proc(memory: []byte, s: string) -> int {
    size := get_serialized_size_string(s)
    dump_to_memory(memory, u32(len(s)))
    bytes_copied := copy(memory[4:], s)
    assert(bytes_copied + 4 == size)
    return size
}

deserialize_string :: proc(memory: []byte) -> string {
    length := extract_from_memory(memory, u32)
    return string(memory[4:4+length])
}

get_serialized_size_slice :: proc(s: $T/[]$E) -> int {
    slice_size := slice.size(s)
    return size_of(u32) + slice_size
}

serialize_slice :: proc(memory: []byte, s: $T/[]$E) -> int {
    block := memory
    size := get_serialized_size_slice(s)
    length := u32(len(s))
    dump_to_memory(block, length)
    copied := copy(block[4:size], slice.to_bytes(s))
    assert(copied + 4 == size)
    return size
}

deserialize_slice :: proc(memory: []byte, $T: typeid/[]$E) -> []E {
    length := extract_from_memory(memory, u32)
    start := cast([^]E)raw_data(memory[4:])
    return start[:length]
}

widen_to_u32 :: proc(out: []u32, src: [^]$T, count: int) {
    for i in 0..<count {
        out[i] = u32(src[i])
    }
}


get_serialized_size_primitive :: proc(primitive: Primitive) -> int {
    size: int

    size += size_of(Topology)
    size += get_serialized_size_slice(primitive.indices)
    size += get_serialized_size_slice(primitive.positions)
    size += get_serialized_size_slice(primitive.attributes)

    return size
}

serialize_primitive :: proc(memory: []byte, primitive: Primitive) -> int {
    size := get_serialized_size_primitive(primitive)

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
    
    return size
}

deserialize_primitive :: proc(memory: []byte) -> (Primitive, int) {
    result: Primitive

    result.topology = extract_from_memory(memory, Topology)
    block := memory[size_of(Topology):]
    
    indices := deserialize_slice(block, []u32)
    result.indices = make([]u32, len(indices))
    copy(result.indices, indices)
    indices_size := get_serialized_size_slice(result.indices)
    block = block[indices_size:]

    positions := deserialize_slice(block, []Vertex_Position)
    result.positions = make([]Vertex_Position, len(positions))
    copy(result.positions, positions)
    positions_size := get_serialized_size_slice(result.positions)
    block = block[positions_size:]

    attributes := deserialize_slice(block, []Vertex_Attributes)
    result.attributes = make([]Vertex_Attributes, len(attributes))
    copy(result.attributes, attributes)
    attributes_size := get_serialized_size_slice(result.attributes)
    
    return result, size_of(Topology) + indices_size + positions_size + attributes_size
}

get_serialized_size_mesh :: proc(mesh: Mesh) -> int {
    size: int

    size += get_serialized_size_string(mesh.name)
    // primitive count (u32)
    size += 4
    for primitive in mesh.primitives {
        size += get_serialized_size_primitive(primitive)
    }

    return size
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

deserialize_mesh :: proc(memory: []byte) -> (Mesh, int) {
    result: Mesh
    result.name = deserialize_string(memory)
    string_size := get_serialized_size_string(result.name)
    block := memory[string_size:]
    n_primitives := extract_from_memory(block, u32)
    block = block[4:]
    result.primitives = make([]Primitive, n_primitives)
    primitives_size: int
    for index in 0..<n_primitives {
        result_primitive, size := deserialize_primitive(block)
        result.primitives[index] = result_primitive
        block = block[size:]
        primitives_size += size
    }
    return result, string_size + 4 + primitives_size
}
