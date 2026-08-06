package asset

import "core:os"
import "core:log"
import vmem "core:mem/virtual"
import img "core:image"
import "core:image/png"
import "core:image/jpeg"
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

GLTF_Primitive_Mode :: enum {
    Point =          0,
    Line =           1,
    Line_Loop =      2,
    Line_Strip =     3,
    Triangles =      4,
    Triangle_Strip = 5,
    Triangle_Fan =   6,
}

GLTF_Primitive :: struct {
    mode:       Maybe(GLTF_Primitive_Mode),
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

GLTF_Base_Color_Texture :: struct {
    index: int,
}

GLTF_Material :: struct {
    name: string,
    pbrMetallicRoughness: struct {
        baseColorFactor:  Maybe([4]f32),
        baseColorTexture: Maybe(GLTF_Base_Color_Texture),
        metallicFactor:   f32,
        roughnessFactor:  f32,
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
    memory:     []byte,
}

GLTF_Texture :: struct {
    source: int,
    sampler: Maybe(int),
}

GLTF_Image :: struct {
    bufferView: int,
    mimeType: string,
}

GLTF_Asset :: struct {
    asset:       GLTF_Asset_Header,
    scene:       int,
    scenes:      []GLTF_Scene,
    nodes:       []GLTF_Node,
    materials:   []GLTF_Material,
    textures:    []GLTF_Texture,
    images:      []GLTF_Image,
    meshes:      []GLTF_Mesh,
    accessors:   []GLTF_Accessor,
    bufferViews: []GLTF_Buffer_View,
    buffers:     []GLTF_Buffer,
}

parse_gltf_json :: proc(memory: []byte) -> GLTF_Asset {
    gltf_asset: GLTF_Asset
    err := json.unmarshal(memory, &gltf_asset, json.DEFAULT_SPECIFICATION, context.temp_allocator)
    if err != nil do log.fatal("Failed to unmarshal a GLTF_Asset struct from JSON")
    return gltf_asset
}

import_glb_asset :: proc(path: string, load_context: ^Load_Context) {
    arena: vmem.Arena
    error := vmem.arena_init_growing(&arena)
    if error != nil do log.fatal("Failed to initialize memory arena for GLB asset", path)
    allocator := vmem.arena_allocator(&arena)

    data, os_error := os.read_entire_file(path, allocator)
    if os_error != nil do log.fatal("Failed to read file", path)

    pointer := data

    header := extract_from_memory(pointer, GLB_Header)
    assert(header.magic == 0x46546c67)
    pointer = pointer[size_of(header):]

    json_chunk := extract_from_memory(pointer, GLTF_Chunk_Header)
    assert(json_chunk.type == .JSON)
    pointer = pointer[size_of(json_chunk):]

    gltf_asset := parse_gltf_json(pointer[:json_chunk.length])
    pointer = pointer[json_chunk.length:]

    bin_chunk := extract_from_memory(pointer, GLTF_Chunk_Header)
    assert(bin_chunk.type == .BIN)
    pointer = pointer[size_of(bin_chunk):]
    gltf_asset.buffers[0].memory = pointer

    // Load meshes
    for mesh in gltf_asset.meshes {
        game_mesh := Mesh{
            name = mesh.name,
            primitives = make([]Primitive, len(mesh.primitives)),
        }

        for primitive, index in mesh.primitives {
            game_primitive := &game_mesh.primitives[index]

            if mode, mode_ok := primitive.mode.?; mode_ok {
                switch mode {
                    case .Point:                         game_primitive.topology = .Point
                    case .Line:                          game_primitive.topology = .Line
                    case .Line_Loop, .Line_Strip:        game_primitive.topology = .Line_Strip
                    case .Triangles:                     game_primitive.topology = .Triangle
                    case .Triangle_Strip, .Triangle_Fan: game_primitive.topology = .Triangle_Strip
                }
            }
            else do game_primitive.topology = .Triangle

            if indices, indices_ok := primitive.indices.?; indices_ok {
                accessor := gltf_asset.accessors[indices]
                assert(accessor.type == "SCALAR")

                bufferview := gltf_asset.bufferViews[accessor.bufferView]
                pointer := raw_data(gltf_asset.buffers[bufferview.buffer].memory[bufferview.byteOffset + accessor.byteOffset:])
                
                game_primitive.indices = make([]u32, accessor.count)
                switch accessor.componentType {
                    case .S8:  widen_to_u32(game_primitive.indices, cast([^]i8)pointer, accessor.count)
                    case .U8:  widen_to_u32(game_primitive.indices, cast([^]u8)pointer, accessor.count)
                    case .S16: widen_to_u32(game_primitive.indices, cast([^]i16)pointer, accessor.count)
                    case .U16: widen_to_u32(game_primitive.indices, cast([^]u16)pointer, accessor.count)
                    case .U32: copy(game_primitive.indices, ([^]u32)(pointer)[:accessor.count])
                    case .F32: log.fatal("Invalid type f32 for mesh indices")
                }
            }
            
            for key, value in primitive.attributes {
                accessor := gltf_asset.accessors[value]

                switch key {
                    case "POSITION", "NORMAL": assert(accessor.componentType == .F32 && accessor.type == "VEC3")
                    case "COLOR_0":            assert(accessor.componentType == .F32 && (accessor.type == "VEC3" || accessor.type == "VEC4"))
                    case "TEXCOORD_0":         assert(accessor.componentType == .F32 && accessor.type == "VEC2")
                    case:
                        log.warn("Skipping unknown mesh primitive attribute", key)
                        continue
                }
                
                bufferview := gltf_asset.bufferViews[accessor.bufferView]
                pointer := gltf_asset.buffers[bufferview.buffer].memory[bufferview.byteOffset + accessor.byteOffset:]

                n_components := get_accessor_type_components(accessor.type)
                byte_stride, byte_stride_ok := bufferview.byteStride.?
                if !byte_stride_ok {
                    byte_stride = n_components * get_component_type_size(.F32)
                }

                if key == "POSITION" {
                    game_primitive.positions = make([]Vertex_Position, accessor.count)
                    for i in 0..<accessor.count {
                        vector := cast([^]f32)raw_data(pointer[i*byte_stride:])
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
                                vector := cast([^]f32)raw_data(pointer[i*byte_stride:])
                                game_primitive.attributes[i].normal  = { vector[0], vector[1], vector[2] }
                            }
                        case key == "TEXCOORD_0":
                            for i in 0..<accessor.count {
                                vector := cast([^]f32)raw_data(pointer[i*byte_stride:])
                                game_primitive.attributes[i].texture = { vector[0], vector[1] }
                            }
                        case key == "COLOR_0":
                            for i in 0..<accessor.count {
                                vector := cast([^]f32)raw_data(pointer[i*byte_stride:])
                                game_primitive.attributes[i].color   = { vector[0], vector[1], vector[2], vector[3] }
                            }
                    }
                }
            }

            _, ok := primitive.attributes["COLOR_0"]
            if !ok {
                for &attribute in game_primitive.attributes {
                    attribute.color = {1, 1, 1, 1}
                }
            }
        }
        append(&load_context.meshes, game_mesh)
    }

    // Load materials
    for material in gltf_asset.materials {
        base_color, ok := material.pbrMetallicRoughness.baseColorFactor.?
        if !ok do base_color = {1, 1, 1, 1}
        append(&load_context.materials, Material{
            name       = material.name,
            base_color = base_color,
            metallic   = material.pbrMetallicRoughness.metallicFactor,
            roughness  = material.pbrMetallicRoughness.roughnessFactor,
        })
    }

    // Load images
    for gltf_image in gltf_asset.images {
        bufferview := gltf_asset.bufferViews[gltf_image.bufferView]
        pointer := gltf_asset.buffers[bufferview.buffer].memory[bufferview.byteOffset:]
        image: ^img.Image
        error: img.Error
        switch gltf_image.mimeType {
            case "image/jpeg":
                image, error = jpeg.load_from_bytes(pointer)
            case "image/png":
                image, error = png.load_from_bytes(pointer)
            case:
                log.warn("Skipping unknown image mime type", gltf_image.mimeType)
                continue
        }
        append(&load_context.textures, Texture{ image = image, })
    }

    vmem.arena_destroy(&arena)
}
