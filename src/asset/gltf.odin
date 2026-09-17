package asset

import "core:os"
import "core:log"
import "core:strings"
import "core:slice"
import "core:math/linalg"
import vmem "core:mem/virtual"
import "core:encoding/json"
import stbi "vendor:stb/image"
import "../common"


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
    name:        string,
    children:    Maybe([]int),
    transform:   Maybe([16]f32) `json:"matrix"`,
    rotation:    Maybe([4]f32),
    scale:       Maybe([3]f32),
    translation: Maybe([3]f32),
    mesh:        Maybe(int),
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

GLTF_Material_Texture :: struct {
    index: int,
    texCoord: int,
}

GLTF_Material :: struct {
    name: string,
    pbrMetallicRoughness: struct {
        baseColorFactor:          Maybe([4]f32),
        baseColorTexture:         Maybe(GLTF_Material_Texture),
        metallicFactor:           Maybe(f32),
        roughnessFactor:          Maybe(f32),
        metallicRoughnessTexture: Maybe(GLTF_Material_Texture),
    },
    normalTexture: Maybe(struct {
        scale: int,
        index: int,
        texCoord: int,
    }),
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

GLTF_Animation_Channel :: struct {
    sampler: int,
    target: struct {
        node: int,
        path: string,
    },
}

GLTF_Sampler :: struct {
    input:         int,
    output:        int,
    interpolation: string,
}

GLTF_Animation :: struct {
    name:     string,
    channels: []GLTF_Animation_Channel,
    samplers: []GLTF_Sampler,
}

GLTF_Skin :: struct {
    name:                string,
    inverseBindMatrices: int,
    joints:              []int,
    skeleton:            Maybe(int),
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
    skins:       []GLTF_Skin,
    animations:  []GLTF_Animation,
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

import_glb_asset :: proc(manager: ^Manager, path: string) -> (
    meshes:    [dynamic]ID,
    materials: [dynamic]ID,
    textures:  [dynamic]ID,
    skeletons: [dynamic]ID,
) {
    path := path
    arena: vmem.Arena
    error := vmem.arena_init_growing(&arena)
    if error != nil do log.fatal("Failed to initialize memory arena for GLB asset", path)
    defer vmem.arena_destroy(&arena)
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

    n_images    := len(gltf_asset.images)
    n_materials := len(gltf_asset.materials)
    n_meshes    := len(gltf_asset.meshes)

    // Load textures
    if n_images > 0 {
        start_textures := common.get_wall_clock()
        for gltf_image in gltf_asset.images {
            bufferview := gltf_asset.bufferViews[gltf_image.bufferView]
            image_memory := gltf_asset.buffers[bufferview.buffer].memory[bufferview.byteOffset:]
            texture := add_texture(manager)
            pixels := stbi.load_from_memory(
                raw_data(image_memory),
                i32(bufferview.byteLength),
                &texture.width,
                &texture.height,
                &texture.channels,
                0
            )
            pixels_size := texture.width * texture.height * texture.channels
            texture.pixels = make([]byte, pixels_size)
            copy(texture.pixels, pixels[:pixels_size])
            stbi.image_free(pixels)
            append(&textures, texture.id)
        }
        end_textures := common.get_wall_clock()
        log.info("GLTF:", n_images, n_images > 1 ? "textures" : "texture", "loaded in",
            common.get_seconds_elapsed(start_textures, end_textures), "seconds."
        )
    }

    // Load materials
    if n_materials > 0 {
        start_materials := common.get_wall_clock()
        for gltf_material in gltf_asset.materials {
            material := add_material(manager)
            material.name = strings.clone(gltf_material.name)
    
            base_color, ok_color := gltf_material.pbrMetallicRoughness.baseColorFactor.?
            if !ok_color do base_color = {1, 1, 1, 1}
            material.base_color = base_color
            
            metallic, ok_metallic := gltf_material.pbrMetallicRoughness.metallicFactor.?
            if !ok_metallic do metallic = 1.0
            material.metallic = metallic
    
            roughness, ok_roughness := gltf_material.pbrMetallicRoughness.roughnessFactor.?
            if !ok_roughness do roughness = 1.0
            material.roughness = roughness
    
            base_color_texture, ok_base_color_texture := gltf_material.pbrMetallicRoughness.baseColorTexture.?
            normal_texture, ok_normal_texture         := gltf_material.normalTexture.?
            pbr_texture, ok_pbr_texture               := gltf_material.pbrMetallicRoughness.metallicRoughnessTexture.?
            if ok_base_color_texture || ok_normal_texture || ok_pbr_texture {
                if ok_base_color_texture {
                    image_index := gltf_asset.textures[base_color_texture.index].source
                    material.texture.color = textures[image_index]
                }
    
                if ok_normal_texture {
                    image_index := gltf_asset.textures[normal_texture.index].source
                    material.texture.normal = textures[image_index]
                }
    
                if ok_pbr_texture {
                    image_index := gltf_asset.textures[pbr_texture.index].source
                    material.texture.pbr = textures[image_index]
                }
            }
    
            append(&materials, material.id)
        }
        end_materials := common.get_wall_clock()
        log.info("GLTF:", n_materials, n_materials > 1? "materials" : "material", "loaded in", 
            common.get_seconds_elapsed(start_materials, end_materials), "seconds."
        )
    }

    if len(gltf_asset.animations) > 0 {
        // Load skins
        for skin in gltf_asset.skins {
            skeleton := add_skeleton(manager)
            skeleton.joints = make([]Joint, len(skin.joints))
            defer append(&skeletons, skeleton.id)

            node_index_to_joint_index := make(map[int]Joint_ID)
            defer delete(node_index_to_joint_index)

            // Build map node_index -> joint_index
            for node_index, joint_index in skin.joints {
                joint := &skeleton.joints[joint_index]
                joint.id = Joint_ID(joint_index)
                joint.parent = -1
                node_index_to_joint_index[node_index] = joint.id
            }
            
            // Build hierarchy
            for node_index, joint_index in skin.joints {
                gltf_joint := gltf_asset.nodes[node_index]
                joint := &skeleton.joints[joint_index]
                joint.name = strings.clone(gltf_joint.name)

                if children, ok := gltf_joint.children.?; ok {
                    for child in children {
                        child_joint := &skeleton.joints[node_index_to_joint_index[child]]
                        child_joint.parent = joint.id
                    }
                }
            }

            root_joints := make([dynamic]int)
            defer delete(root_joints)
            if root, ok := skin.skeleton.?; ok {
                if root not_in node_index_to_joint_index {
                    log.fatal("GLTF: Root joint is not in the skin joints.")
                }
                append(&root_joints, root)
            }
            else {
                for joint in skeleton.joints {
                    if joint.parent == -1 {
                        for node_id, joint_id in node_index_to_joint_index {
                            if joint.id == joint_id {
                                append(&root_joints, node_id)
                            }
                        }
                    }
                }
            }
            assert(len(root_joints) == 1, "More than one root joint present")
            skeleton.root_joint = node_index_to_joint_index[root_joints[0]]

            // Global transform for the skeleton
            global_translation := [3]f32{0, 0, 0}
            global_rotation: linalg.Quaternionf32 = 1
            global_scale := [3]f32{1, 1, 1}
            for node in gltf_asset.nodes {
                children, ok := node.children.?
                if ok && slice.contains(children, root_joints[0]) {
                    if translation, ok := node.translation.?; ok {
                        global_translation = {translation.x, -translation.z, -translation.y}
                    }

                    if rotation, ok := node.rotation.?; ok {
                        global_rotation = quaternion(x = -rotation[0], y = rotation[2], z = rotation[1], w = rotation[3])
                    }

                    if scale, ok := node.scale.?; ok {
                        global_scale = {scale.x, scale.z, scale.y}
                    }

                    break
                }
            }

            accessor := gltf_asset.accessors[skin.inverseBindMatrices]
            assert(accessor.componentType == .F32 && accessor.type == "MAT4" && accessor.count == len(skin.joints))
            bufferview := gltf_asset.bufferViews[accessor.bufferView]
            block := gltf_asset.buffers[bufferview.buffer].memory[bufferview.byteOffset + accessor.byteOffset:]
            matrices := cast([^]f32)raw_data(block)
            
            for node_index, joint_index in skin.joints {
                gltf_joint := gltf_asset.nodes[node_index]
                joint := &skeleton.joints[joint_index]
                joint.name = strings.clone(gltf_joint.name)
                joint.id = Joint_ID(joint_index)

                joint_rotation: linalg.Quaternionf32 = 1
                if rotation, ok := gltf_joint.rotation.?; ok {
                    joint_rotation = quaternion(x=-rotation[0], y=rotation[2], z=rotation[1], w=rotation[3])
                }

                joint_translation: [3]f32 = {0, 0, 0}
                if translation, ok := gltf_joint.translation.?; ok {
                    joint_translation = {translation.x, -translation.z, -translation.y}
                }

                joint_scale: [3]f32 = {1, 1, 1}
                if scale, ok := gltf_joint.scale.?; ok {
                    joint_scale = {scale.x, scale.z, scale.y}
                }

                transform := linalg.matrix4_from_trs_f32(joint_translation, joint_rotation, joint_scale)
                joint.local_bind = transform
            }

            for &joint, index in skeleton.joints {
                for i in 0..<4 {
                    for j in 0..<4 {
                        joint.inverse_bind[i, j] = matrices[4*i + j]
                    }
                }
                matrices = matrices[16:]
            }
        }

        // Load animations
        for animation in gltf_asset.animations {
            for channel in animation.channels {
                // TODO
            }            
        }
    }

    // Load meshes
    if n_meshes > 0 {
        start_meshes := common.get_wall_clock()
        for gltf_mesh in gltf_asset.meshes {
            mesh := add_mesh(manager)
            mesh.name = strings.clone(gltf_mesh.name)
            mesh.primitives = make([]Primitive, len(gltf_mesh.primitives))
    
            for gltf_primitive, primitive_index in gltf_mesh.primitives {
                primitive := &mesh.primitives[primitive_index]
    
                if material_index, material_ok := gltf_primitive.material.?; material_ok {
                    primitive.material = materials[material_index]
                }
    
                if mode, mode_ok := gltf_primitive.mode.?; mode_ok {
                    switch mode {
                        case .Point:                         primitive.topology = .Point
                        case .Line:                          primitive.topology = .Line
                        case .Line_Loop, .Line_Strip:        primitive.topology = .Line_Strip
                        case .Triangles:                     primitive.topology = .Triangle
                        case .Triangle_Strip, .Triangle_Fan: primitive.topology = .Triangle_Strip
                    }
                }
                else do primitive.topology = .Triangle
    
                if indices, indices_ok := gltf_primitive.indices.?; indices_ok {
                    accessor := gltf_asset.accessors[indices]
                    assert(accessor.type == "SCALAR")
    
                    bufferview := gltf_asset.bufferViews[accessor.bufferView]
                    pointer := raw_data(gltf_asset.buffers[bufferview.buffer].memory[bufferview.byteOffset + accessor.byteOffset:])
                    
                    primitive.indices = make([]u32, accessor.count)
                    switch accessor.componentType {
                        case .S8:  widen_to_u32(primitive.indices, cast([^]i8)pointer, accessor.count)
                        case .U8:  widen_to_u32(primitive.indices, cast([^]u8)pointer, accessor.count)
                        case .S16: widen_to_u32(primitive.indices, cast([^]i16)pointer, accessor.count)
                        case .U16: widen_to_u32(primitive.indices, cast([^]u16)pointer, accessor.count)
                        case .U32: copy(primitive.indices, ([^]u32)(pointer)[:accessor.count])
                        case .F32: log.fatal("Invalid type f32 for mesh indices")
                    }
                }
                
                for key, value in gltf_primitive.attributes {
                    accessor := gltf_asset.accessors[value]
    
                    switch key {
                        case "POSITION", "NORMAL": assert(accessor.componentType == .F32 && accessor.type == "VEC3")
                        case "COLOR_0":            assert(accessor.componentType == .F32 && (accessor.type == "VEC3" || accessor.type == "VEC4"))
                        case "TEXCOORD_0":         assert(accessor.componentType == .F32 && accessor.type == "VEC2")
                        case "JOINTS_0":           assert(accessor.componentType == .U8 && accessor.type == "VEC4")
                        case "WEIGHTS_0":          assert(accessor.componentType == .F32 && accessor.type == "VEC4")
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
                        primitive.positions = make([]Vertex_Position, accessor.count)
                        for i in 0..<accessor.count {
                            vector := cast([^]f32)raw_data(pointer[i*byte_stride:])
                            primitive.positions[i] = { vector[0], vector[1], vector[2] }
                        }
                    }
                    else {
                        if len(primitive.attributes) == 0 && (key == "NORMAL" || key == "TEXCOORD_0" || key == "COLOR_0") {
                            primitive.attributes = make([]Vertex_Attributes, accessor.count)
                        }
                        else if len(primitive.joints) == 0 && (key == "JOINTS_0" || key == "WEIGHTS_0") {
                            primitive.joints = make([]Vertex_Joint, accessor.count)
                        }
    
                        switch key {
                            case "NORMAL": 
                                for i in 0..<accessor.count {
                                    vector := cast([^]f32)raw_data(pointer[i*byte_stride:])
                                    primitive.attributes[i].normal = { vector[0], vector[1], vector[2] }
                                }
                            case "TEXCOORD_0":
                                for i in 0..<accessor.count {
                                    vector := cast([^]f32)raw_data(pointer[i*byte_stride:])
                                    primitive.attributes[i].texture = { vector[0], vector[1] }
                                }
                            case "COLOR_0":
                                for i in 0..<accessor.count {
                                    vector := cast([^]f32)raw_data(pointer[i*byte_stride:])
                                    primitive.attributes[i].color = { vector[0], vector[1], vector[2], vector[3] }
                                }
                            case "JOINTS_0":
                                for i in 0..<accessor.count {
                                    vector := cast([^]u8)raw_data(pointer[i*byte_stride:])
                                    primitive.joints[i].joints = { vector[0], vector[1], vector[2], vector[3] }
                                }
                            case "WEIGHTS_0":
                                for i in 0..<accessor.count {
                                    vector := cast([^]f32)raw_data(pointer[i*byte_stride:])
                                    primitive.joints[i].weights = { vector[0], vector[1], vector[2], vector[3] }
                                }
                        }
                    }
                }
    
                _, ok := gltf_primitive.attributes["COLOR_0"]
                if !ok {
                    for &attribute in primitive.attributes {
                        attribute.color = {1, 1, 1, 1}
                    }
                }
            }
            append(&meshes, mesh.id)
        }
        end_meshes := common.get_wall_clock()
        log.info("GLTF:", n_meshes, n_meshes > 1? "meshes" : "mesh", "loaded in", 
            common.get_seconds_elapsed(start_meshes, end_meshes), "seconds."
        )
    }

    return
}
