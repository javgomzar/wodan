package game

import "core:os"
import "core:dynlib"
import "core:time"
import "core:io"
import "core:log"
import "../asset"
import "../common"


Game_Memory :: struct {
    input:         common.Input_Context,
    ui_context:    UI_Context,
    renderer:      Renderer_Context,
    render_group:  Render_Group,
    asset_manager: asset.Manager,
    code:          Game_Code,
    time_records:  [common.Time_Record_ID]common.Time_Record,
    time:          f32,
    delta_time:    f32,
    initialized:   bool,
    running:       bool,
    testing:       bool,
    debug:         bool,
}

Game_Code :: struct {
    library:    dynlib.Library,
    initialize: proc(memory: ^Game_Memory),
    reload:     proc(memory: ^Game_Memory),
    update:     proc(memory: ^Game_Memory),
    timestamp:  time.Time,
}

source_dll_path :: "bin/game.dll"
temp_dll_path :: "bin/game_temp.dll"

load_code :: proc(code: ^Game_Code) {
    error := os.copy_file(temp_dll_path, source_dll_path)
    for error == io.Error.Permission_Denied {
        error = os.copy_file(temp_dll_path, source_dll_path)
    }
    if error != nil {
        log.fatal("Failed to copy DLL file")
    }
    
    ok: bool
    code.library, ok = dynlib.load_library(temp_dll_path)
    if ok {
        fun: rawptr
        fun, ok = dynlib.symbol_address(code.library, "initialize_game_state")
        if ok do code.initialize = cast(proc(memory: ^Game_Memory))(fun)

        fun, ok = dynlib.symbol_address(code.library, "reload_game_state")
        if ok do code.reload = cast(proc(memory: ^Game_Memory))(fun)

        fun, ok = dynlib.symbol_address(code.library, "update_game_state")
        if ok do code.update = cast(proc(memory: ^Game_Memory))(fun)

        code.timestamp, error = os.modification_time_by_path(source_dll_path)
        if error != nil do log.fatal("Failed to check modification time for source DLL")
    }
    else do log.fatal("Game code couldn't be loaded.")
}

update_if_newer_code :: proc(memory: ^Game_Memory) {
    code := &memory.code
    timestamp, error := os.modification_time_by_path(source_dll_path)
    if error != nil {
        log.error("Failed to check modification time for source DLL")
        return
    }

    delta := time.diff(code.timestamp, timestamp)
    if delta > 0 {
        ok := dynlib.unload_library(code.library)
        if !ok do log.fatal("Failed to unload game code library")

        load_code(code)
        log.info("Code has been reloaded")
        code.reload(memory)
    }
}