package common

import "core:mem"
import "core:log"
import "base:runtime"


Game_Mesh_Primitive :: struct {
    topology:   Primitive,
    indices:    []u32,
    positions:  []f32,
    attributes: []f32,
}

Game_Mesh :: struct {
    name:       string,
    primitives: []Game_Mesh_Primitive,
}

get_serialized_size_primitive :: proc(primitive: Game_Mesh_Primitive) -> int {
    size: int

    size += size_of(Primitive)
    size += get_serialized_size_slice(primitive.indices)
    size += get_serialized_size_slice(primitive.positions)
    size += get_serialized_size_slice(primitive.attributes)

    return size
}

serialize_primitive :: proc(memory: []byte, primitive: Game_Mesh_Primitive) -> int {
    size := get_serialized_size_primitive(primitive)

    dump_to_memory(memory, primitive.topology)
    block := memory[size_of(primitive.topology):]
    bytes_written := serialize_slice(block, primitive.indices)
    block = block[bytes_written:]
    bytes_written = serialize_slice(block, primitive.positions)
    block = block[bytes_written:]
    bytes_written = serialize_slice(block, primitive.attributes)
    
    return size
}

deserialize_primitive :: proc(memory: []byte) -> (Game_Mesh_Primitive, int) {
    result: Game_Mesh_Primitive
    result.topology = extract_from_memory(memory, Primitive)
    block := memory[size_of(Primitive):]
    result.indices = deserialize_slice(block, []u32)
    indices_size := get_serialized_size_slice(result.indices)
    block = block[indices_size:]
    result.positions = deserialize_slice(block, []f32)
    positions_size := get_serialized_size_slice(result.positions)
    block = block[positions_size:]
    result.attributes = deserialize_slice(block, []f32)
    attributes_size := get_serialized_size_slice(result.attributes)
    return result, size_of(Primitive) + indices_size + positions_size + attributes_size
}

get_serialized_size_mesh :: proc(mesh: Game_Mesh) -> int {
    size: int

    size += get_serialized_size_string(mesh.name)
    // primitive count (u32)
    size += 4
    for primitive in mesh.primitives {
        size += get_serialized_size_primitive(primitive)
    }

    return size
}

serialize_mesh :: proc(allocator: mem.Allocator, mesh: Game_Mesh) {
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

deserialize_mesh :: proc(memory: []byte) -> (Game_Mesh, int) {
    result: Game_Mesh
    result.name = deserialize_string(memory)
    string_size := get_serialized_size_string(result.name)
    block := memory[string_size:]
    n_primitives := extract_from_memory(block, u32)
    block = block[4:]
    result.primitives = make([]Game_Mesh_Primitive, n_primitives)
    primitives_size: int
    for i in 0..<n_primitives {
        size: int
        result.primitives[i], size = deserialize_primitive(block)
        block = block[size:]
        primitives_size += size
    }
    return result, string_size + 4 + primitives_size
}
