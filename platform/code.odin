package main

import "core:os"
import "core:dynlib"
import "core:time"
import "core:io"


game_code :: struct {
    library:    dynlib.Library,
    initialize: proc(memory: ^game_memory),
    reload:     proc(memory: ^game_memory),
    update:     proc(memory: ^game_memory),
    timestamp:  time.Time,
}

source_dll_path :: "bin/game.dll"
temp_dll_path :: "bin/game_temp.dll"

load_code :: proc(code: ^game_code) {
    error := os.copy_file(temp_dll_path, source_dll_path)
    for error == io.Error.Permission_Denied {
        error = os.copy_file(temp_dll_path, source_dll_path)
    }
    if error != nil {
        log(.Fatal, "Failed to copy DLL file")
    }
    
    ok: bool
    code.library, ok = dynlib.load_library(temp_dll_path)
    if ok {
        fun: rawptr
        fun, ok = dynlib.symbol_address(code.library, "initialize_game_state")
        if ok do code.initialize = cast(proc(memory: ^game_memory))(fun)

        fun, ok = dynlib.symbol_address(code.library, "reload_game_state")
        if ok do code.reload = cast(proc(memory: ^game_memory))(fun)

        fun, ok = dynlib.symbol_address(code.library, "update_game_state")
        if ok do code.update = cast(proc(memory: ^game_memory))(fun)

        code.timestamp, error = os.modification_time_by_path(source_dll_path)
        if error != nil do log(.Fatal, "Failed to check modification time for source DLL")
    }
    else do log(.Fatal, "Game code couldn't be loaded.")
}

update_if_newer_code :: proc(memory: ^game_memory) {
    code := &memory.code
    timestamp, error := os.modification_time_by_path(source_dll_path)
    if error != nil {
        log(.Error, "Failed to check modification time for source DLL")
        return
    }

    delta := time.diff(code.timestamp, timestamp)
    if delta > 0 {
        ok := dynlib.unload_library(code.library)
        if !ok do log(.Fatal, "Failed to unload game code library")

        matches: []string
        matches, error = os.glob("bin/game*.pdb")

        load_code(code)
        log(.Info, "Code has been reloaded")
        code.reload(memory)
    }
}