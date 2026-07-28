package common

import "core:os"
import "core:fmt"
import "core:time"
import "core:log"


Game_Mesh :: struct {
    name:        string,
    indices:     []u32,
    positions:   []Vertex_Position,
    attributes:  []Vertex_Attributes,
}

game_asset_id :: distinct u32

game_asset :: struct {
    id:           game_asset_id,
    file:         os.File_Info,
    import_files: [dynamic]os.File_Info,
    meshes:       []Game_Mesh,
    // textures:     []game_textures,
    // fonts:        []game_font,
    // text:         []game_text,
    memory:       rawptr,
    processing:   bool,
}

Game_Asset_Manager :: struct {
    next_asset_id: game_asset_id,
    assets: [dynamic]game_asset,
}

load_asset :: proc(asset: ^game_asset) {
    // TODO
}

add_asset :: proc(manager: ^Game_Asset_Manager, path: string) -> game_asset_id {
    asset: game_asset
    asset.id = manager.next_asset_id
    if os.exists(path) {
        error: os.Error
        asset.file, error = os.stat(path, context.allocator)
    }
    else {
        asset.file.fullpath = path
        asset.processing = true
    }
    append(&manager.assets, asset)
    manager.next_asset_id += 1
    return asset.id
}

add_file :: proc(manager: ^Game_Asset_Manager, id: game_asset_id, path: string) {
    asset := &manager.assets[id]
    if !os.exists(path) {
        log.fatal("Failed to add file ", path, " to asset ", asset.file.fullpath, ": File doesn't exist", sep = "")
    }
    file_info, error := os.stat(path, context.allocator)
    append(&asset.import_files, file_info)
    if !asset.processing && time.diff(asset.file.modification_time, file_info.modification_time) > 0 {
        asset.processing = true
    }
}

process_asset :: proc(asset: ^game_asset) {
    for file in asset.import_files {
        _, ext := os.split_filename(file.name)
        switch ext {
            case "glb":
                load_glb_asset(file.fullpath, asset)
            case:
                log.fatal("Invalid asset extension '.", ext, "'", sep = "")
        }
    }

    free_all(context.temp_allocator)
}

initialize_asset_manager :: proc(manager: ^Game_Asset_Manager) {
    // empty asset for id 0
    add_asset(manager, "")

    box_asset_id := add_asset(manager, "file/asset/test_asset.ass")
    add_file(manager, box_asset_id, "D:/TestAssets/glTF-Sample-Assets-main/Models/Box/glTF-Binary/Box.glb")

    // Asset processing and loading
    for &asset in manager.assets {
        if asset.processing {
            process_asset(&asset)
        }
        load_asset(&asset)
    }
}
