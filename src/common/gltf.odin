package common

import "core:os"
import "core:log"
import "core:mem"
import "core:encoding/json"


GLB_Header :: struct {
    magic:   u32,
    version: u32,
    length:  u32,
}

GLTF_Chunk_Type :: enum u32 {
    JSON = 0x4E4F534A,
    BIN  = 0x004E4942,
}

GLTF_Chunk_Header :: struct {
    length: u32,
    type:   GLTF_Chunk_Type,
}

GLTF_Asset_Header :: struct {
    generator: string,
    version:   string,
}

GLTF_Node :: struct {
    children:    []int,
    transform:   [16]f32 `json:"matrix"`,
    rotation:    [4]f32,
    scale:       [3]f32,
    translation: [3]f32,
    mesh:        int,
}

GLTF_Scene :: struct {
    nodes: []int,
}

GLTF_Primitive :: struct {
    mode:       Primitive,
    attributes: map[string]int,
    indices:    Maybe(int),
    material:   Maybe(int),
}

GLTF_Mesh :: struct {
    name: string,
    primitives: []GLTF_Primitive,
}

GLTF_Component_Type :: enum u32 {
    S8  = 5120,
    U8  = 5121,
    S16 = 5122,
    U16 = 5123,
    U32 = 5125,
    F32 = 5126,
}

GLTF_Accessor :: struct {
    bufferView:    int,
    byteOffset:    int,
    componentType: GLTF_Component_Type,
    count:         int,
    type:          string,
    min:           []f32,
    max:           []f32,
}

get_accessor_type_components :: proc(type: string) -> int {
    switch type {
        case "SCALAR": return 1
        case "VEC2":   return 2
        case "VEC3":   return 3
        case "VEC4":   return 4
        case "MAT2":   return 4
        case "MAT3":   return 9
        case "MAT4":   return 16
    }
    return 0
}

get_component_type_size :: proc(component_type: GLTF_Component_Type) -> int {
    switch component_type {
        case .S8, .U8:   return 1
        case .S16, .U16: return 2
        case .F32, .U32: return 4
    }
    return 0
}

get_component_type_id :: proc(component_type: GLTF_Component_Type) -> typeid {
    switch component_type {
        case .S8:  return i8
        case .U8:  return u8
        case .S16: return i16
        case .U16: return u16
        case .F32: return f32
        case .U32: return u32
    }
    return nil
}

GLTF_Material :: struct {
    name: string,
    pbrMetallicRoughness: struct {
        baseColorFactor: [4]f32,
        metallicFactor:  f32,
        roughnessFactor: f32,
    },
    emissive_factor: [3]f32,
}

GLTF_Buffer_View :: struct {
    buffer:     int,
    byteOffset: int,
    byteLength: int,
    byteStride: Maybe(int),
    target:     int,
}

GLTF_Buffer :: struct {
    byteLength: int,
    memory:     rawptr,
}

GLTF_Asset :: struct {
    asset:       GLTF_Asset_Header,
    scene:       int,
    scenes:      []GLTF_Scene,
    nodes:       []GLTF_Node,
    materials:   []GLTF_Material,
    meshes:      []GLTF_Mesh,
    accessors:   []GLTF_Accessor,
    bufferViews: []GLTF_Buffer_View,
    buffers:     []GLTF_Buffer,
}

read_glb_asset :: proc(path: string) -> ^GLTF_Asset {
    data, os_error := os.read_entire_file(path, context.temp_allocator)
    if os_error != nil do log.fatal("Failed to read file", path)

    pointer := data

    header := extract_from_memory(pointer, GLB_Header)
    assert(header.magic == 0x46546c67)
    pointer = pointer[size_of(header):]

    json_chunk := extract_from_memory(pointer, GLTF_Chunk_Header)
    assert(json_chunk.type == .JSON)
    pointer = pointer[size_of(json_chunk):]

    glb_asset := new(GLTF_Asset)
    err := json.unmarshal(pointer[:json_chunk.length], glb_asset, json.DEFAULT_SPECIFICATION, context.temp_allocator)
    if err != nil do log.fatal("Failed to unmarshal a GLTF_Asset struct from JSON")
    pointer = pointer[json_chunk.length:]

    bin_chunk := extract_from_memory(pointer, GLTF_Chunk_Header)
    assert(bin_chunk.type == .BIN)
    pointer = pointer[size_of(bin_chunk):]
    glb_asset.buffers[0].memory = raw_data(pointer)

    return glb_asset
}

compute_needed_memory_glb :: proc(asset: ^GLTF_Asset) -> int {
    total_size: int
    for mesh in asset.meshes {
        total_size += get_serialized_size_string(mesh.name)
        total_size += 4              // primitive count (u32)
        for primitive in mesh.primitives {
            total_size += size_of(Primitive)
            indices, ok := primitive.indices.?
            if ok {
                accessor := asset.accessors[indices]
                total_size += 4 + accessor.count * size_of(u32)
            }

            positions := asset.accessors[primitive.attributes["POSITION"]]
            total_size += 4 + positions.count * size_of(Vertex_Position)

            attributes: []string = {"NORMAL", "TEXCOORD_0", "COLOR_0"}
            attributes_count: int
            for attribute in attributes {
                accessor_index, exists := primitive.attributes[attribute]
                if exists {
                    attributes_count = asset.accessors[accessor_index].count
                    assert(attributes_count == positions.count)
                    break
                }
            }
            total_size += 4 + attributes_count * size_of(Vertex_Attributes)
        }
    }

    for material in asset.materials {
        total_size += get_serialized_size_string(material.name)
        total_size += 6 * size_of(f32)
    }

    return total_size
}

widen_to_u32 :: proc(out: []u32, src: [^]$T, count: int) {
    for i in 0..<count {
        out[i] = u32(src[i])
    }
}

load_glb_asset :: proc(allocator: mem.Allocator, glb_asset: ^GLTF_Asset) {
    for mesh in glb_asset.meshes {
        game_mesh: Game_Mesh
        game_mesh.name = mesh.name
        game_mesh.primitives = make([]Game_Mesh_Primitive, len(mesh.primitives))
        defer delete(game_mesh.primitives)
        for primitive, index in mesh.primitives {
            game_primitive := &game_mesh.primitives[index]
            game_primitive.topology = primitive.mode
            indices, ok := primitive.indices.?
            if ok {
                accessor := glb_asset.accessors[indices]
                assert(accessor.type == "SCALAR")

                bufferview := glb_asset.bufferViews[accessor.bufferView]
                pointer := cast([^]byte)glb_asset.buffers[bufferview.buffer].memory
                start := pointer[bufferview.byteOffset + accessor.byteOffset:]
                
                game_primitive.indices = make([]u32, accessor.count)
                switch accessor.componentType {
                    case .S8:  widen_to_u32(game_primitive.indices, ([^]i8)(start), accessor.count)
                    case .U8:  widen_to_u32(game_primitive.indices, ([^]u8)(start), accessor.count)
                    case .S16: widen_to_u32(game_primitive.indices, ([^]i16)(start), accessor.count)
                    case .U16: widen_to_u32(game_primitive.indices, ([^]u16)(start), accessor.count)
                    case .U32: copy(game_primitive.indices, ([^]u32)(start)[:accessor.count])
                    case .F32: log.fatal("Invalid type f32 for mesh indices")
                }
            }
            
            for key, value in primitive.attributes {
                accessor := glb_asset.accessors[value]

                switch key {
                    case "POSITION", "NORMAL": assert(accessor.componentType == .F32 && accessor.type == "VEC3")
                    case "COLOR_0":            assert(accessor.componentType == .F32 && (accessor.type == "VEC3" || accessor.type == "VEC4"))
                    case "TEXCOORD_0":         assert(accessor.componentType == .F32 && accessor.type == "VEC2")
                    case:
                        log.warn("Skipping unknown mesh primitive attribute", key)
                        continue
                }
                
                bufferview := glb_asset.bufferViews[accessor.bufferView]
                pointer := cast([^]byte)glb_asset.buffers[bufferview.buffer].memory
                src := pointer[bufferview.byteOffset + accessor.byteOffset:]

                n_components := get_accessor_type_components(accessor.type)
                byte_stride: int
                byte_stride, ok = bufferview.byteStride.?
                if !ok {
                    byte_stride = n_components * get_component_type_size(.F32)
                }

                if key == "POSITION" {
                    game_primitive.positions = make([]Vertex_Position, accessor.count)
                    for i in 0..<accessor.count {
                        vector := cast([^]f32)src[i*byte_stride:]
                        game_primitive.positions[i] = { vector[0], vector[1], vector[2] }
                    }
                }
                else {
                    if len(game_primitive.attributes) == 0 {
                        game_primitive.attributes = make([]Vertex_Attributes, accessor.count)
                    }

                    switch {
                        case key == "NORMAL": 
                            for i in 0..<accessor.count {
                                vector := cast([^]f32)src[i*byte_stride:]
                                game_primitive.attributes[i].normal  = { vector[0], vector[1], vector[2] }
                            }
                        case key == "TEXCOORD_0":
                            for i in 0..<accessor.count {
                                vector := cast([^]f32)src[i*byte_stride:]
                                game_primitive.attributes[i].texture = { vector[0], vector[1] }
                            }
                        case key == "COLOR_0":
                            for i in 0..<accessor.count {
                                vector := cast([^]f32)src[i*byte_stride:]
                                game_primitive.attributes[i].color   = { vector[0], vector[1], vector[2], vector[3] }
                            }
                    }
                }
            }
        }
        serialize_mesh(allocator, game_mesh)
        for game_primitive in game_mesh.primitives {
            delete(game_primitive.indices)
            delete(game_primitive.attributes)
        }
    }

    for material in glb_asset.materials {
        game_material := Game_Material{
            name = material.name,
            base_color = material.pbrMetallicRoughness.baseColorFactor,
            metallicity = material.pbrMetallicRoughness.metallicFactor,
            roughness = material.pbrMetallicRoughness.roughnessFactor,
        }
        
        serialize_material(allocator, game_material)
    }
}