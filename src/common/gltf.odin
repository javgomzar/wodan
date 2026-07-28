package common

import "core:os"
import "core:encoding/json"


glb_header :: struct {
    magic:   u32,
    version: u32,
    length:  u32,
}

gltf_chunk_type :: enum u32 {
    JSON = 0x4E4F534A,
    BIN  = 0x004E4942,
}

gltf_chunk_header :: struct {
    length: u32,
    type:   gltf_chunk_type,
}

gltf_asset_header :: struct {
    generator: string,
    version:   string,
}

gltf_node :: struct {
    children:    []int,
    transform:   [16]f32 `json:"matrix"`,
    rotation:    [4]f32,
    scale:       [3]f32,
    translation: [3]f32,
    mesh:        int,
}

gltf_scene :: struct {
    nodes: []int,
}

gltf_primitive :: struct {
    attributes: map[string]int,
    indices:    int,
    mode:       int,
    material:   int,
}

gltf_mesh :: struct {
    name: string,
    primitives: []gltf_primitive,
}

gltf_component_type :: enum u32 {
    S8  = 5120,
    U8  = 5121,
    S16 = 5122,
    U16 = 5123,
    U32 = 5125,
    F32 = 5126,
}

gltf_accessor :: struct {
    bufferView:    int,
    byteOffset:    int,
    componentType: gltf_component_type,
    count:         int,
    type:          string,
    min:           []f32,
    max:           []f32,
}

gltf_material :: struct {
    name: string,
    pbrMetallicRoughness: struct {
        baseColorFactor: [4]f32,
        metallicFactor:  f32,
        roughnessFactor: f32,
    }
}

gltf_buffer_view :: struct {
    buffer:     int,
    byteOffset: int,
    byteLength: int,
    byteStride: int,
    target:     int,
}

gltf_buffer :: struct {
    byteLength: int,
}

gltf_asset :: struct {
    asset:       gltf_asset_header,
    scene:       int,
    scenes:      []gltf_scene,
    nodes:       []gltf_node,
    meshes:      []gltf_mesh,
    accessors:   []gltf_accessor,
    bufferViews: []gltf_buffer_view,
    buffers:     []gltf_buffer,
}

extract_from_memory :: proc(memory: ^[]byte, $T: typeid) -> T {
    result := (^T)(raw_data(memory^))^
    memory^ = memory^[size_of(T):]
    return result
}

process_gltf_mesh :: proc(mesh: gltf_mesh) -> Game_Mesh {
    result: Game_Mesh

    

    return result
}

load_glb_asset :: proc(path: string, asset: ^game_asset) -> bool {
    data, os_error := os.read_entire_file(path, context.temp_allocator)
    if os_error != nil do return false

    pointer := data

    header := extract_from_memory(&pointer, glb_header)
    assert(header.magic == 0x46546c67)

    json_chunk := extract_from_memory(&pointer, gltf_chunk_header)
    assert(json_chunk.type == .JSON)

    glb_asset: gltf_asset
    err := json.unmarshal(pointer[:json_chunk.length], &glb_asset, json.DEFAULT_SPECIFICATION, context.temp_allocator)
    if err != nil do return false
    pointer = pointer[json_chunk.length:]

    if len(pointer) == 0 do return true

    bin_chunk := extract_from_memory(&pointer, gltf_chunk_header)
    assert(bin_chunk.type == .BIN)
    bin_data := pointer

    for mesh in glb_asset.meshes {

    }

    return true
}
