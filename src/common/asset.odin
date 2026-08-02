package common

import "core:os"
import "core:mem"
import "core:time"
import "core:log"
import "base:runtime"
import "core:slice"


Game_Asset_ID :: distinct u32

Game_Import_File_Format :: enum {
    GLB,
    JPEG,
    PNG,
    BMP,
    WAV,
}

Game_Import_File :: struct {
    info:       os.File_Info,
    format:     Game_Import_File_Format,
    extra_data: rawptr,
    write_size: int,
    content:    []byte,
}

Game_Asset_File_Header :: struct {
    magic_number:   u32,
    mesh_count:     u32,
    material_count: u32,
}

Game_Asset :: struct {
    id:           Game_Asset_ID,
    file_info:    os.File_Info,
    import_files: [dynamic]Game_Import_File,
    meshes:       []Game_Mesh,
    materials:    []Game_Material,
    // textures:     []Game_Textures,
    // fonts:        []Game_Font,
    // text:         []Game_Text,
    processing:   bool,
}

Game_Asset_Manager :: struct {
    next_asset_id: Game_Asset_ID,
    assets: [dynamic]Game_Asset,
}

add_asset :: proc(manager: ^Game_Asset_Manager, path: string, force_process: bool = false) -> Game_Asset_ID {
    asset: Game_Asset
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
    return asset.id
}

add_file :: proc(manager: ^Game_Asset_Manager, id: Game_Asset_ID, path: string) {
    asset := &manager.assets[id]
    if !os.exists(path) {
        log.fatal("Failed to add file ", path, " to asset ", asset.file_info.fullpath, ": File doesn't exist", sep = "")
    }
    import_file: Game_Import_File
    error: os.Error
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
        case "bmp":  import_file.format = .BMP
        case "wav":  import_file.format = .WAV
        case:
            log.fatal("Invalid format '.", ext, "'", sep = "")
    }
}

process_asset :: proc(asset: ^Game_Asset) {
    total_size: int

    // Asset header
    total_size += size_of(Game_Asset_File_Header)

    n_meshes, n_mesh_primitives: int
    n_materials: int

    for &file in asset.import_files {
        switch file.format {
            case .GLB:
                glb_asset := read_glb_asset(file.info.fullpath)
                file.extra_data = glb_asset

                n_meshes += len(glb_asset.meshes)
                for mesh in glb_asset.meshes {
                    n_mesh_primitives += len(mesh.primitives)
                }

                n_materials = len(glb_asset.materials)

                file.write_size = compute_needed_memory_glb(glb_asset)
            case .JPEG, .PNG, .BMP, .WAV:
                log.fatal("Asset file loading with extension", file.format, "hasn't been implemented yet")
            case:
                log.fatal("Invalid asset file extension '.", file.format, "'", sep = "")
        }

        total_size += file.write_size
    }

    block, error := make([]byte, total_size, context.allocator)
    defer delete(block)
    if error != nil do log.fatal("Failed to allocate arena for asset processing")
    arena: mem.Arena
    mem.arena_init(&arena, block)
    allocator := mem.arena_allocator(&arena)

    header := new(Game_Asset_File_Header, allocator)
    header.magic_number = 0xffaaaacc
    header.mesh_count = u32(n_meshes)
    header.material_count = u32(n_materials)

    for file in asset.import_files {
        switch file.format {
            case .GLB:
                glb_asset := (^GLTF_Asset)(file.extra_data)
                load_glb_asset(allocator, glb_asset)
                free(glb_asset)
            case .JPEG, .PNG, .BMP, .WAV:
                log.fatal("Asset file loading with extension", file.format, "hasn't been implemented yet")
        }
    }

    assert(arena.offset == int(total_size))

    write_error := os.write_entire_file(asset.file_info.fullpath, block)
    if write_error != nil do log.fatal("Failed to write asset file", asset.file_info.fullpath)

    log.info("Asset", asset.file_info.fullpath, "was successfully processed")

    free_all(context.temp_allocator)
}

load_asset :: proc(asset: ^Game_Asset) {
    path := asset.file_info.fullpath
    data, error := os.read_entire_file(path, context.allocator)
    if error != nil {
        log.fatal("Failed to read asset file", path)
    }

    header := cast(^Game_Asset_File_Header)raw_data(data)
    assert(header.magic_number == 0xffaaaacc)
    block := data[size_of(Game_Asset_File_Header):]

    asset.meshes = make([]Game_Mesh, header.mesh_count)
    asset.materials = make([]Game_Material, header.material_count)
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

    log.info("Asset read from file", path)
}

initialize_asset_manager :: proc(manager: ^Game_Asset_Manager) {
    // empty asset for id 0
    add_asset(manager, "")

    box_asset_id := add_asset(manager, "file/asset/test_asset.ass", force_process = true)
    add_file(manager, box_asset_id, "D:/TestAssets/glTF-Sample-Assets-main/Models/Box/glTF-Binary/Box.glb")

    // Asset processing and loading
    for &asset in manager.assets[1:] {
        if asset.processing {
            process_asset(&asset)
        }
        load_asset(&asset)
    }
}
