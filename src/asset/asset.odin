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
    TTF,
    WAV,
}

Import_File :: struct {
    info:       os.File_Info,
    format:     Import_File_Format,
}

File_Header :: struct {
    magic_number:   u32,
    font_count:     u32,
    mesh_count:     u32,
    material_count: u32,
    texture_count:  u32,
}

Asset :: struct {
    id:           ID,
    language:     Language,
    file_info:    os.File_Info,
    import_files: [dynamic]Import_File,
    fonts:        []Font,
    meshes:       []Mesh,
    materials:    []Material,
    textures:     []Texture,
    // text:         []Text,
    processing:   bool,
    released:     bool,
}

Catalog :: struct {
    debug_font: ^Font,
}

Manager :: struct {
    next_asset_id:    ID,
    system_asset_id:  ID,
    language:         Language,
    catalog:          Catalog,
    assets:           [dynamic]Asset,
}

add_asset :: proc(manager: ^Manager, path: string, force_process: bool = false) -> ^Asset {
    asset: Asset
    asset.id = manager.next_asset_id
    asset.language = manager.language
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
    
    if !asset.processing && time.diff(asset.file_info.modification_time, import_file.info.modification_time) > 0 {
        asset.processing = true
    }

    _, ext := os.split_filename(path)
    switch ext {
        case "glb":  import_file.format = .GLB
        case "jpeg": import_file.format = .JPEG
        case "png":  import_file.format = .PNG
        case "wav":  import_file.format = .WAV
        case "ttf":  import_file.format = .TTF
        case:
            log.fatal("Invalid format '.", ext, "'", sep = "")
    }

    append(&asset.import_files, import_file)
}

Load_Context :: struct {
    fonts:     [dynamic]Font,
    meshes:    [dynamic]Mesh,
    materials: [dynamic]Material,
    textures:  [dynamic]Texture,
}

import_asset_files :: proc(asset: ^Asset) {
    load_context: Load_Context
    defer delete(load_context.fonts)
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
            case .TTF:
                font := import_ttf(file.info.fullpath, asset.language)
                append(&load_context.fonts, font)
            case .WAV:
                log.fatal("Asset file loading with extension", file.format, "hasn't been implemented yet")
            case:
                log.fatal("Invalid asset file extension '.", file.format, "'", sep = "")
        }
    }

    asset.fonts = make([]Font, len(load_context.fonts))
    copy(asset.fonts, load_context.fonts[:])

    asset.meshes = make([]Mesh, len(load_context.meshes))
    copy(asset.meshes, load_context.meshes[:])

    asset.materials = make([]Material, len(load_context.materials))
    copy(asset.materials, load_context.materials[:])

    asset.textures  = make([]Texture, len(load_context.textures))
    copy(asset.textures, load_context.textures[:])
}

write :: proc(asset: ^Asset) {
    total_size := size_of(File_Header)

    for font in asset.fonts {
        total_size += get_serialized_size_font(font)
    }

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
        font_count = u32(len(asset.fonts)),
        mesh_count = u32(len(asset.meshes)),
        material_count = u32(len(asset.materials)),
        texture_count = u32(len(asset.textures)),
    }

    for font in asset.fonts {
        serialize_font(allocator, font)
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

    asset.fonts = make([]Font, header.font_count)
    asset.meshes = make([]Mesh, header.mesh_count)
    asset.materials = make([]Material, header.material_count)
    asset.textures = make([]Texture, header.texture_count)

    for &font in asset.fonts {
        size: int
        font, size = deserialize_font(block)
        block = block[size:]
    }

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

    asset.released = false
}

release :: proc(asset: ^Asset) {
    if asset.released {
        log.warn("Skipping release of already released asset.")
        return
    }

    // Import files
    for import_file in asset.import_files do os.file_info_delete(import_file.info, context.allocator)
    if len(asset.import_files) > 0 do delete(asset.import_files)

    // Fonts
    for font in asset.fonts {
        delete(font.name)
        for glyph in font.glyphs {
            for contour in glyph.contours {
                delete(contour.points)
            }
            delete(glyph.contours)
        }
        delete(font.glyphs)
        delete(font.code_to_index)
        delete(font.glyph_id_to_index)
    }
    if len(asset.fonts) > 0 do delete(asset.fonts)

    // Meshes
    for mesh in asset.meshes {
        delete(mesh.name)
        for primitive in mesh.primitives {
            if len(primitive.positions) > 0  do delete(primitive.positions)
            if len(primitive.indices) > 0    do delete(primitive.indices)
            if len(primitive.attributes) > 0 do delete(primitive.attributes)
        }
        delete(mesh.primitives)
    }
    if len(asset.meshes) > 0 do delete(asset.meshes)

    // Materials
    for material in asset.materials {
        delete(material.name)
    }
    if len(asset.materials) > 0 do delete(asset.materials)

    // Textures
    for texture in asset.textures do img.destroy(texture.image)
    if len(asset.textures) > 0 do delete(asset.textures)

    os.file_info_delete(asset.file_info, context.allocator)

    asset.released = true
}

release_assets :: proc(manager: ^Manager) {
    for &asset in manager.assets[1:] {
        release(&asset)
    }
    delete(manager.assets)
}

get_mesh_by_name :: proc(asset: ^Asset, name: string) -> ^Mesh {
    result: ^Mesh = nil
    for &mesh in asset.meshes {
        if mesh.name == name {
            result = &mesh
            break
        }
    }
    return result
}

get_font_by_name :: proc(manager: ^Manager, name: string) -> ^Font {
    for asset in manager.assets[1:] {
        for &font in asset.fonts {
            if font.name == name {
                return &font
            }
        }
    }
    return nil
}

initialize_manager :: proc(manager: ^Manager) {
    manager.language = .English
    
    // empty asset for id 0
    add_asset(manager, "")

    system_asset := add_asset(manager, "file/asset/system/system.ass", force_process = true)
    manager.system_asset_id = system_asset.id
}
