package common

import "core:mem"
import "core:slice"


Game_Material :: struct {
    name: string,
    base_color: [4]f32,
    metallicity: f32,
    roughness: f32,
}

get_serialized_size_material :: proc(material: Game_Material) -> int {
    return get_serialized_size_string(material.name) + 6 * size_of(f32)
}

serialize_material :: proc(allocator: mem.Allocator, material: Game_Material) {
    size := get_serialized_size_material(material)
    block := make([]byte, size, allocator)

    name_size := serialize_string(block, material.name)
    block = block[name_size:]

    data := []f32{
        material.base_color[0],
        material.base_color[1],
        material.base_color[2],
        material.base_color[3],
        material.metallicity,
        material.roughness,
    }
    copy(block, slice.to_bytes(data))
}

deserialize_material :: proc(memory: []byte) -> (Game_Material, int) {
    material: Game_Material
    material.name = deserialize_string(memory)
    name_size := get_serialized_size_string(material.name)
    block := memory[name_size:]
    mem.copy(&material.base_color, raw_data(block), 6 * size_of(f32))

    return material, name_size + 6 * size_of(f32)
}
