package asset

import "core:os"
import "core:log"
import "core:time"
import "core:slice"
import "core:container/pool"
import stbi "vendor:stb/image"


ID :: distinct u32

File_Header :: struct {
    magic_number:   u32,
    mesh_count:     u32,
    material_count: u32,
    texture_count:  u32,
}

read_file_header :: proc(memory: []byte) -> (result: File_Header, ok: bool) {
    header := cast(^File_Header)raw_data(memory)
    ok = header.magic_number == 0xffaaaacc
    result = header^
    return
}

Asset :: struct {
    path:         string,
    meshes:       []ID,
    materials:    []ID,
    textures:     []ID,
    skeletons:    []ID,
    // text:         []ID,
    link:         ^Asset,
}

Catalog :: struct {
    system:    Asset,
    animation: Asset,
}

Manager :: struct {
    next_id:  ID,
    language: Language,
    fonts:    map[string]Font,
    catalog:  Catalog,
    pools: struct {
        mesh:     pool.Pool(Mesh),
        texture:  pool.Pool(Texture),
        material: pool.Pool(Material),
        skeleton: pool.Pool(Skeleton),
    },
    items: struct {
        mesh:     map[ID]^Mesh,
        texture:  map[ID]^Texture,
        material: map[ID]^Material,
        skeleton: map[ID]^Skeleton,
    }
}

create_id :: proc(manager: ^Manager) -> ID {
    defer manager.next_id += 1
    return manager.next_id
}

add_asset :: proc(manager: ^Manager, asset: ^Asset, path: string, files: ..string, force_process: bool = false) {
    asset.path = path
    process := force_process
    if os.exists(path) {
        file_info, error := os.stat(path, context.temp_allocator)
        
        for import_file in files {
            if !os.exists(import_file) {
                log.error("Failed to add file ", import_file, " to asset ", path, ": File doesn't exist.", sep = "")
                continue
            }
            import_file_info, error := os.stat(path, context.temp_allocator)
            
            if time.diff(file_info.modification_time, import_file_info.modification_time) > 0 {
                process = true
            }
        }
    }
    else {
        process = true
    }

    if process {
        meshes    := make([dynamic]ID)
        materials := make([dynamic]ID)
        textures  := make([dynamic]ID)
        skeletons := make([dynamic]ID)
        defer delete(meshes)
        defer delete(materials)
        defer delete(textures)
        defer delete(skeletons)

        for import_file in files {
            _, ext := os.split_filename(import_file)
            switch ext {
                case "glb":
                    import_meshes, import_materials, import_textures, import_skeletons := import_glb_asset(manager, import_file)
                    append(&meshes, ..import_meshes[:])
                    append(&materials, ..import_materials[:])
                    append(&textures, ..import_textures[:])
                    append(&skeletons, ..import_skeletons[:])
                    delete(import_meshes)
                    delete(import_materials)
                    delete(import_textures)
                    delete(import_skeletons)
                case "jpeg", "png":
                    texture := add_texture(manager)
                    pixels := stbi.load(cstring(raw_data(import_file)), &texture.width, &texture.height, &texture.channels, 0)
                    texture.pixels = make([]byte, texture.width * texture.height * texture.channels)
                    copy(texture.pixels, pixels[:len(texture.pixels)])
                    stbi.image_free(pixels)
                    append(&textures, texture.id)
                case "wav":
                    log.error("Asset file loading with extension", ext, "hasn't been implemented yet")
                case:
                    log.fatal("Invalid format '.", ext, "' for asset file.", sep = "")
            }
        }

        asset.meshes = make([]ID, len(meshes))
        copy(asset.meshes, meshes[:])

        asset.materials = make([]ID, len(materials))
        copy(asset.materials, materials[:])

        asset.textures = make([]ID, len(textures))
        copy(asset.textures, textures[:])

        asset.skeletons = make([]ID, len(skeletons))
        copy(asset.skeletons, skeletons[:])

        write(manager, asset)
    }
    else {
        load(manager, asset, path)
    }
}

add_mesh :: proc(manager: ^Manager) -> ^Mesh {
    mesh, error := pool.get(&manager.pools.mesh)
    if error != nil do log.fatal("Failed to allocate mesh asset.")
    mesh.id = create_id(manager)
    manager.items.mesh[mesh.id] = mesh
    return mesh
}

get_mesh :: proc(manager: ^Manager, id: ID) -> ^Mesh {
    if id in manager.items.mesh {
        return manager.items.mesh[id]
    }
    return nil
}

add_texture :: proc(manager: ^Manager) -> ^Texture {
    texture, error := pool.get(&manager.pools.texture)
    if error != nil do log.fatal("Failed to allocate texture asset.")
    texture.id = create_id(manager)
    manager.items.texture[texture.id] = texture
    return texture
}

get_texture :: proc(manager: ^Manager, id: ID) -> ^Texture {
    if id in manager.items.texture {
        return manager.items.texture[id]
    }
    return nil
}

add_material :: proc(manager: ^Manager) -> ^Material {
    material, error := pool.get(&manager.pools.material)
    if error != nil do log.fatal("Failed to allocate material asset.")
    material.id = create_id(manager)
    manager.items.material[material.id] = material
    return material
}

get_material :: proc(manager: ^Manager, id: ID) -> ^Material {
    if id in manager.items.material {
        return manager.items.material[id]
    }
    return nil
}

add_skeleton :: proc(manager: ^Manager) -> ^Skeleton {
    skeleton, error := pool.get(&manager.pools.skeleton)
    if error != nil do log.fatal("Failed to allocate skeleton asset.")
    skeleton.id = create_id(manager)
    manager.items.skeleton[skeleton.id] = skeleton
    return skeleton
}

get_skeleton :: proc(manager: ^Manager, id: ID) -> ^Skeleton {
    if id in manager.items.skeleton {
        return manager.items.skeleton[id]
    }
    return nil
}

write :: proc(manager: ^Manager, asset: ^Asset) {
    total_size := size_of(File_Header)

    material_id_to_index := make(map[ID]u32)
    defer delete(material_id_to_index)
    material_id_to_index[0] = 0

    texture_id_to_index := make(map[ID]u32)
    defer delete(texture_id_to_index)
    texture_id_to_index[0] = 0

    for id, index in asset.textures {
        texture := get_texture(manager, id)
        if texture == nil {
            log.error("Failed to find asset texture with ID ", id, " when writing asset file ", asset.path, ".", sep="")
        }
        total_size += get_serialized_size_texture(texture)
        texture_id_to_index[id] = u32(index+1)
    }

    for id, index in asset.materials {
        material := get_material(manager, id)
        if material == nil {
            log.error("Failed to find asset material with ID", id, "when writing asset file.")
        }
        else {
            total_size += get_serialized_size_material(material)
            material_id_to_index[id] = u32(index+1)
        }
    }

    for id in asset.meshes {
        mesh := get_mesh(manager, id)
        if mesh == nil {
            log.error("Failed to find asset mesh with ID", id, "when writing asset file.")
        }
        else {
            total_size += get_serialized_size_mesh(mesh)
        }
    }

    memory, error := make([]byte, total_size, context.allocator)
    if error != nil do log.fatal("Failed to allocate arena for asset processing")
    defer delete(memory)

    block := memory
    dump_to_memory(block, File_Header{
        magic_number = 0xffaaaacc,
        mesh_count = u32(len(asset.meshes)),
        material_count = u32(len(asset.materials)),
        texture_count = u32(len(asset.textures)),
    })
    block = block[size_of(File_Header):]

    for id in asset.textures {
        texture := get_texture(manager, id)
        size := serialize_texture(block, texture)
        block = block[size:]
    }

    for id in asset.materials {
        material := get_material(manager, id)
        size := serialize_material(block, material, texture_id_to_index)
        block = block[size:]
    }

    for id in asset.meshes {
        mesh := get_mesh(manager, id)
        size := serialize_mesh(block, mesh, material_id_to_index)
        block = block[size:]
    }

    write_error := os.write_entire_file(asset.path, memory)
    if write_error != nil do log.fatal("Failed to write asset file", asset.path)
    else                  do log.info("Asset", asset.path, "was successfully written")
}

load :: proc(manager: ^Manager, asset: ^Asset, path: string) {
    data, error := os.read_entire_file(path, context.allocator)
    defer delete(data)
    if error != nil {
        log.error("Failed to read asset file", path)
        return
    }

    header, ok := read_file_header(data)
    if !ok {
        log.error("Asset file at ", path, " is corrupt. Skipping load.")
        return
    }
    block := data[size_of(File_Header):]

    if header.texture_count > 0 {
        asset.textures = make([]ID, header.texture_count)
    }
    if header.material_count > 0 {
        asset.materials = make([]ID, header.material_count)
    }
    if header.mesh_count > 0 {
        asset.meshes = make([]ID, header.mesh_count)
    }

    for &id in asset.textures {
        texture := add_texture(manager)
        id = texture.id
        size := deserialize_texture(texture, block)
        block = block[size:]
    }

    for &id in asset.materials {
        material := add_material(manager)
        id = material.id
        size := deserialize_material(material, block, asset.textures)
        block = block[size:]
    }

    for &id in asset.meshes {
        mesh := add_mesh(manager)
        id = mesh.id
        size := deserialize_mesh(mesh, block, asset.materials)
        block = block[size:]
    }

    log.info("Loaded asset file", path)
}

release :: proc(manager: ^Manager, asset: ^Asset) {
    // Meshes
    for id in asset.meshes {
        mesh := get_mesh(manager, id)
        release_mesh(mesh)
    }

    // Materials
    for id in asset.materials {
        material := get_material(manager, id)
        delete(material.name)
    }

    // Textures
    for id in asset.textures {
        texture := get_texture(manager, id)
        delete(texture.pixels)
    }
}

get_font :: proc(manager: ^Manager, name: string) -> ^Font {
    if name not_in manager.fonts {
        log.fatal("Failed to find '", name, "' font. Available fonts: ", slice.map_keys(manager.fonts), sep="")
        return &manager.fonts["DejaVuSansMono"]
    }
    return &manager.fonts[name]
}

initialize_manager :: proc(manager: ^Manager) {
    manager.language = .English

    error_mesh := pool.init(&manager.pools.mesh, "link")
    error_material := pool.init(&manager.pools.material, "link")
    error_texture := pool.init(&manager.pools.texture, "link")
    if error_mesh != nil || error_material != nil || error_texture != nil {
        log.fatal("Failed to initialize asset manager pools.")
    }
    manager.next_id = 1
    
    add_font(manager, "DejaVuSansMono")
    add_font(manager, "DejaVuSans")
    add_font(manager, "BlackChancery")

    add_asset(manager, &manager.catalog.system, "file/asset/system/system.ass", 
        "file/asset/system/grid.glb",
        "file/asset/system/empty.png",
        force_process = true
    )
}
