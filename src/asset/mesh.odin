package asset

import "core:slice"


Topology :: enum u32 {
    Point,
    Line,
    Line_Strip,
    Triangle,
    Triangle_Strip,
}

Material :: struct {
    id:             ID,
    name:           string,
    base_color:     [4]f32,
    metallic:       f32,
    roughness:      f32,
    emissive:       [3]f32,
    specular:       f32,
    texture: struct {
        color:    ID,
        normal:   ID,
        pbr:      ID,
        emissive: ID,
        specular: ID,
    },
    link: ^Material,
}

default_material := Material{
    name       = "Default",
    base_color = {0.5, 0.5, 0.5, 1.0},
    metallic   = 1.0,
    roughness  = 1.0,
}

get_default_material :: proc(color: [4]f32 = {0.5, 0.5, 0.5, 1.0}, texture: ID = 0) -> (result: Material) {
    result = default_material
    result.base_color = color
    result.texture.color = texture
    return
}

get_serialized_size_material :: proc(material: ^Material) -> (size: int) {
    size += get_serialized_size_string(material.name)
    size += 4 * size_of(f32) // base color
    size += size_of(f32)     // metallic
    size += size_of(f32)     // roughness
    size += 3 * size_of(f32) // emissive
    size += size_of(f32)     // specular
    size += size_of(u32)     // color texture
    size += size_of(u32)     // normal texture
    size += size_of(u32)     // pbr texture
    size += size_of(u32)     // emissive texture
    size += size_of(u32)     // specular texture
    return
}

serialize_material :: proc(memory: []byte, material: ^Material, texture_id_to_index: map[ID]u32) -> int {
    name_size := serialize_string(memory, material.name)
    block := memory[name_size:]

    float_data := []f32{
        material.base_color[0],
        material.base_color[1],
        material.base_color[2],
        material.base_color[3],
        material.metallic,
        material.roughness,
        material.emissive[0],
        material.emissive[1],
        material.emissive[2],
        material.specular,
    }

    textures := []u32{
        texture_id_to_index[material.texture.color],
        texture_id_to_index[material.texture.normal],
        texture_id_to_index[material.texture.pbr],
        texture_id_to_index[material.texture.emissive],
        texture_id_to_index[material.texture.specular],
    }

    float_data_bytes := slice.to_bytes(float_data)
    copy(block, float_data_bytes)
    block = block[len(float_data_bytes):]
    copy(block, slice.to_bytes(textures))

    return name_size + len(float_data) * size_of(f32) + len(textures) * size_of(u32)
}

deserialize_material :: proc(material: ^Material, memory: []byte, textures: []ID) -> (size: int) {
    name_size: int
    material.name, name_size = deserialize_string(memory)
    block := memory[name_size:]
    size += name_size
    
    material.base_color = extract_from_memory(block, [4]f32)
    color_size := size_of([4]f32)
    block = block[color_size:]
    size += color_size

    material.metallic = extract_from_memory(block, f32)
    metallic_size := size_of(f32)
    block = block[metallic_size:]
    size += metallic_size

    material.roughness = extract_from_memory(block, f32)
    roughness_size := size_of(f32)
    block = block[roughness_size:]
    size += roughness_size

    material.emissive = extract_from_memory(block, [3]f32)
    emissive_size := 3 * size_of(f32)
    block = block[emissive_size:]
    size += emissive_size

    material.specular = extract_from_memory(block, f32)
    specular_size := size_of(f32)
    block = block[specular_size:]
    size += specular_size

    texture_id_size := size_of(u32)
    color_texture_index := extract_from_memory(block, u32)
    if color_texture_index != 0 {
        material.texture.color = textures[color_texture_index - 1]
    }
    block = block[texture_id_size:]
    size += texture_id_size

    normal_texture_index := extract_from_memory(block, u32)
    if normal_texture_index != 0 {
        material.texture.normal = textures[normal_texture_index - 1]
    }
    block = block[texture_id_size:]
    size += texture_id_size

    pbr_texture_index := extract_from_memory(block, u32)
    if pbr_texture_index != 0 {
        material.texture.pbr = textures[pbr_texture_index - 1]
    }
    block = block[texture_id_size:]
    size += texture_id_size

    emissive_texture_index := extract_from_memory(block, u32)
    if emissive_texture_index != 0 {
        material.texture.emissive = textures[emissive_texture_index - 1]
    }
    block = block[texture_id_size:]
    size += texture_id_size

    specular_texture_index := extract_from_memory(block, u32)
    if specular_texture_index != 0 {
        material.texture.specular = textures[specular_texture_index - 1]
    }
    block = block[texture_id_size:]
    size += texture_id_size

    return
}

Primitive :: struct {
    topology:         Topology,
    indices:          []u32,
    positions:        []Vertex_Position,
    attributes:       []Vertex_Attributes,
    joints:           []Vertex_Joint,
    material:         ID,
    position_offset:  int,
    attribute_offset: int,
    index_offset:     int,
}


get_serialized_size_primitive :: proc(primitive: Primitive) -> (size: int) {
    size += size_of(Topology)
    size += size_of(u32)
    size += get_serialized_size_slice(primitive.indices)
    size += get_serialized_size_slice(primitive.positions)
    size += get_serialized_size_slice(primitive.attributes)
    size += get_serialized_size_slice(primitive.joints)
    return
}

serialize_primitive :: proc(memory: []byte, primitive: Primitive, material_id_to_index: map[ID]u32) -> (size: int) {
    block := memory
    dump_to_memory(memory, primitive.topology)
    size += size_of(Topology)
    block = block[size_of(Topology):]

    dump_to_memory(block, material_id_to_index[primitive.material])
    size += size_of(u32)
    block = block[size_of(u32):]

    indices_size := serialize_slice(block, primitive.indices)
    size += indices_size
    block = block[indices_size:]

    positions_size := serialize_slice(block, primitive.positions)
    size += positions_size
    block = block[positions_size:]

    attributes_size := serialize_slice(block, primitive.attributes)
    size += attributes_size
    block = block[attributes_size:]

    joints_size := serialize_slice(block, primitive.joints)
    size += joints_size
    block = block[joints_size:]

    return
}

deserialize_primitive :: proc(primitive: ^Primitive, memory: []byte, materials: []ID) -> (size: int) {
    primitive.topology = extract_from_memory(memory, Topology)
    block := memory[size_of(Topology):]
    size += size_of(Topology)

    material_id := extract_from_memory(block, u32)
    if material_id != 0 {
        primitive.material = materials[material_id - 1]
    }
    block = block[size_of(u32):]
    size += size_of(u32)
    
    indices_size: int
    primitive.indices, indices_size = deserialize_slice(block, []u32)
    block = block[indices_size:]
    size += indices_size

    positions_size: int
    primitive.positions, positions_size = deserialize_slice(block, []Vertex_Position)
    block = block[positions_size:]
    size += positions_size

    attributes_size: int
    primitive.attributes, attributes_size = deserialize_slice(block, []Vertex_Attributes)
    block = block[attributes_size:]
    size += attributes_size

    joints_size: int
    primitive.joints, joints_size = deserialize_slice(block, []Vertex_Joint)
    block = block[joints_size:]
    size += joints_size

    return
}

Mesh :: struct {
    id:         ID,
    name:       string,
    link:       ^Mesh,
    primitives: []Primitive,
}

get_serialized_size_mesh :: proc(mesh: ^Mesh) -> (size: int) {
    size += get_serialized_size_string(mesh.name)
    size += 4 // primitive count (u32)
    for primitive in mesh.primitives {
        size += get_serialized_size_primitive(primitive)
    }
    return
}

serialize_mesh :: proc(memory: []byte, mesh: ^Mesh, material_id_to_index: map[ID]u32) -> (size: int) {
    name_size := serialize_string(memory, mesh.name)
    block := memory[name_size:]
    size += name_size
    dump_to_memory(block, u32(len(mesh.primitives)))
    block = block[4:]
    size += 4
    for primitive in mesh.primitives {
        primitive_size := serialize_primitive(block, primitive, material_id_to_index)
        block = block[primitive_size:]
        size += primitive_size
    }
    return
}

deserialize_mesh :: proc(mesh: ^Mesh, memory: []byte, materials: []ID) -> (size: int) {
    materials := materials
    name_size: int
    mesh.name, name_size = deserialize_string(memory)
    block := memory[name_size:]
    size += name_size

    n_primitives := extract_from_memory(block, u32)
    block = block[size_of(u32):]
    size += size_of(u32)

    mesh.primitives = make([]Primitive, n_primitives)
    for &primitive in mesh.primitives {
        primitive_size := deserialize_primitive(&primitive, block, materials)
        block = block[primitive_size:]
        size += primitive_size
    }
    return
}

release_mesh :: proc(mesh: ^Mesh) {
    delete(mesh.name)
    for primitive in mesh.primitives {
        if len(primitive.positions) > 0  do delete(primitive.positions)
        if len(primitive.indices) > 0    do delete(primitive.indices)
        if len(primitive.attributes) > 0 do delete(primitive.attributes)
        if len(primitive.joints) > 0     do delete(primitive.joints)
    }
    delete(mesh.primitives)
}

Joint_ID :: distinct i32

Joint :: struct {
    id:           Joint_ID,
    name:         string,
    parent:       Joint_ID,
    inverse_bind: matrix[4, 4]f32,
    local_bind:   matrix[4, 4]f32,
    global_bind:  matrix[4, 4]f32,
}

Skeleton :: struct {
    id:          ID,
    joints:      []Joint,
    root_joints: []Joint_ID,
    link:        ^Skeleton,
}
