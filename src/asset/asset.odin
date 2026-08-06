package asset

import "core:os"
import "core:mem"
import "core:log"
import "core:time"
import img "core:image"
import "core:image/png"
import "core:image/jpeg"


ID :: distinct u32

Import_File_Format :: enum {
    GLB,
    JPEG,
    PNG,
    WAV,
}

Import_File :: struct {
    info:       os.File_Info,
    format:     Import_File_Format,
    content:    []byte,
}

File_Header :: struct {
    magic_number:   u32,
    mesh_count:     u32,
    material_count: u32,
    texture_count:  u32,
}

Asset :: struct {
    id:           ID,
    file_info:    os.File_Info,
    import_files: [dynamic]Import_File,
    meshes:       []Mesh,
    materials:    []Material,
    textures:     []Texture,
    // fonts:        []Font,
    // text:         []Text,
    processing:   bool,
}

Manager :: struct {
    next_asset_id:    ID,
    system_asset_id : ID,
    assets:           [dynamic]Asset,
}

add_asset :: proc(manager: ^Manager, path: string, force_process: bool = false) -> ^Asset {
    asset: Asset
    asset.id = manager.next_asset_id
    if os.exists(path) {
        error: os.Error
        asset.file_info, error = os.stat(path, context.allocator)
        asset.processing = force_process
    }
    else {
        asset.file_info.fullpath = path
        asset.processing = true
    }
    append(&manager.assets, asset)
    manager.next_asset_id += 1
    return &manager.assets[len(manager.assets) - 1]
}

add_file :: proc(asset: ^Asset, path: string) {
    import_file: Import_File
    error: os.Error
    if !os.exists(path) {
        log.error("Failed to add file ", path, " to asset ", asset.file_info.fullpath, ": File doesn't exist", sep = "")
        return
    }
    import_file.info, error = os.stat(path, context.allocator)
    append(&asset.import_files, import_file)
    
    if !asset.processing && time.diff(asset.file_info.modification_time, import_file.info.modification_time) > 0 {
        asset.processing = true
    }

    _, ext := os.split_filename(path)
    switch ext {
        case "glb":  import_file.format = .GLB
        case "jpeg": import_file.format = .JPEG
        case "png":  import_file.format = .PNG
        case "wav":  import_file.format = .WAV
        case:
            log.fatal("Invalid format '.", ext, "'", sep = "")
    }
}

Load_Context :: struct {
    meshes:    [dynamic]Mesh,
    materials: [dynamic]Material,
    textures:  [dynamic]Texture,
}

import_asset_files :: proc(asset: ^Asset) {
    load_context: Load_Context
    defer delete(load_context.meshes)
    defer delete(load_context.materials)
    defer delete(load_context.textures)

    for &file in asset.import_files {
        switch file.format {
            case .GLB:
                import_glb_asset(file.info.fullpath, &load_context)
            case .PNG:
                image, error := png.load_from_file(file.info.fullpath)
                append(&load_context.textures, Texture{ image = image, })
            case .JPEG:
                image, error := jpeg.load_from_file(file.info.fullpath)
                append(&load_context.textures, Texture{ image = image, })
            case .WAV:
                log.fatal("Asset file loading with extension", file.format, "hasn't been implemented yet")
            case:
                log.fatal("Invalid asset file extension '.", file.format, "'", sep = "")
        }
    }

    asset.meshes = make([]Mesh, len(load_context.meshes))
    copy(asset.meshes, load_context.meshes[:])

    asset.materials = make([]Material, len(load_context.materials))
    copy(asset.materials, load_context.materials[:])

    asset.textures  = make([]Texture, len(load_context.textures))
    copy(asset.textures, load_context.textures[:])
}

write :: proc(asset: ^Asset) {
    total_size := size_of(File_Header)

    for mesh in asset.meshes {
        total_size += get_serialized_size_mesh(mesh)
    }

    for material in asset.materials {
        total_size += get_serialized_size_material(material)
    }

    for texture in asset.textures {
        total_size += get_serialized_size_image(texture.image)
    }

    block, error := make([]byte, total_size, context.allocator)
    if error != nil do log.fatal("Failed to allocate arena for asset processing")
    defer delete(block)

    arena: mem.Arena
    mem.arena_init(&arena, block)
    allocator := mem.arena_allocator(&arena)

    header := new(File_Header, allocator)
    header^ = {
        magic_number = 0xffaaaacc,
        mesh_count = u32(len(asset.meshes)),
        material_count = u32(len(asset.materials)),
        texture_count = u32(len(asset.textures)),
    }

    for mesh in asset.meshes {
        serialize_mesh(allocator, mesh)
    }

    for material in asset.materials {
        serialize_material(allocator, material)
    }

    for texture in asset.textures {
        serialize_image(allocator, texture.image)
    }

    assert(arena.offset == int(total_size))

    write_error := os.write_entire_file(asset.file_info.fullpath, block)
    if write_error != nil do log.fatal("Failed to write asset file", asset.file_info.fullpath)

    log.info("Asset", asset.file_info.fullpath, "was successfully written")
}

load :: proc(asset: ^Asset) {
    path := asset.file_info.fullpath
    data, error := os.read_entire_file(path, context.allocator)
    defer delete(data)
    if error != nil {
        log.fatal("Failed to read asset file", path)
    }

    header := cast(^File_Header)raw_data(data)
    assert(header.magic_number == 0xffaaaacc)
    block := data[size_of(File_Header):]

    asset.meshes = make([]Mesh, header.mesh_count)
    asset.materials = make([]Material, header.material_count)
    asset.textures = make([]Texture, header.texture_count)
    for &mesh in asset.meshes {
        size: int
        mesh, size = deserialize_mesh(block)
        block = block[size:]
    }

    for &material in asset.materials {
        size: int
        material, size = deserialize_material(block)
        block = block[size:]
    }

    for &texture in asset.textures {
        image, size := deserialize_image(block)
        texture.image = image
        block = block[size:]
    }

    log.info("Loaded asset file", path)
}

release :: proc(asset: ^Asset) {
    for import_file in asset.import_files {
        os.file_info_delete(import_file.info, context.allocator)
    }
    if len(asset.import_files) > 0 do delete(asset.import_files)
    for mesh in asset.meshes {
        for primitive in mesh.primitives {
            if len(primitive.positions) > 0  do delete(primitive.positions)
            if len(primitive.indices) > 0    do delete(primitive.indices)
            if len(primitive.attributes) > 0 do delete(primitive.attributes)
        }
        delete(mesh.primitives)
    }
    if len(asset.meshes) > 0 do delete(asset.meshes)
    if len(asset.materials) > 0 do delete(asset.materials)
    for texture in asset.textures {
        img.destroy(texture.image)
    }
    if len(asset.textures) > 0 do delete(asset.textures)
    os.file_info_delete(asset.file_info, context.allocator)
}

release_assets :: proc(manager: ^Manager) {
    for &asset in manager.assets[1:] {
        release(&asset)
    }
    delete(manager.assets)
}

initialize_manager :: proc(manager: ^Manager) {
    // empty asset for id 0
    add_asset(manager, "")

    system_asset := add_asset(manager, "file/asset/system.ass", force_process = true)
    manager.system_asset_id = system_asset.id
}
