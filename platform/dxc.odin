package main

import "vendor:directx/dxc"
import "vendor:directx/d3d12"
import w32 "core:sys/windows"
import "core:path/filepath"
import "core:fmt"
import "core:os"


dxc_compiler :: struct {
    utils:           ^dxc.IUtils,
    compiler:        ^dxc.ICompiler3,
    include_handler: ^dxc.IIncludeHandler,
}

shader_id :: enum {
    Vertex_Screen,
    Vertex_Passthrough,
    Pixel_Color,
}

dxc_shader :: struct {
    id:       shader_id,
    path:     string,
    target:   w32.wstring,
    blob:     ^dxc.IBlob,
    bytecode: d3d12.SHADER_BYTECODE,
}

shader_paths := [shader_id]string {
    .Vertex_Screen =      "assets/shaders/HLSL/vertex/screen.vsh",
    .Vertex_Passthrough = "assets/shaders/HLSL/vertex/passthrough.vsh",
    .Pixel_Color =        "assets/shaders/HLSL/pixel/color.psh",
}

initialize_shader_compiler :: proc(compiler: ^dxc_compiler) {
    hr := dxc.CreateInstance(dxc.Utils_CLSID, dxc.IUtils_UUID, cast(rawptr)&compiler.utils)
    if hr < 0 {
        log(.Fatal, "Failed to create DirectX compiler utils object")
    }

    hr = dxc.CreateInstance(dxc.Compiler_CLSID, dxc.ICompiler3_UUID, cast(rawptr)&compiler.compiler)
    if hr < 0 {
        log(.Fatal, "Failed to create DirectX compiler object")
    }

    hr = compiler.utils->CreateDefaultIncludeHandler(&compiler.include_handler)
    if hr < 0 {
        log(.Fatal, "Failed to create DirectX compiler include handler")
    }
}

initialize_shader :: proc(id: shader_id, shader_list: ^[shader_id]dxc_shader) {
    shader := &shader_list[id]
    shader.id = id
    shader.path = shader_paths[id]
    extension := filepath.ext(shader.path)
    switch extension {
        case ".vsh":
            shader.target = "vs_6_0"
        case ".psh":
            shader.target = "ps_6_0"
        case ".dsh":
            shader.target = "ds_6_0"
        case ".hsh":
            shader.target = "hs_6_0"
        case ".gsh":
            shader.target = "gs_6_0"
        case ".csh":
            shader.target = "cs_6_0"
        case ".libsh":
            shader.target = "lib_6_0"
        case:
            log(.Fatal, fmt.tprintf("Invalid file extension %s", extension))
    }
}

compile_shader :: proc(compiler: dxc_compiler, shader: ^dxc_shader) -> bool {
    data, error := os.read_entire_file(shader.path, context.temp_allocator)
    if error != nil{
        log(.Error, fmt.tprintf("Failed to read shader file `%s`", shader.path))
        return false
    }

    buffer := dxc.Buffer{
        Ptr = raw_data(data),
        Size = len(data),
        Encoding = dxc.CP_UTF8,
    }    

    args: ^dxc.ICompilerArgs
    hr := compiler.utils->BuildArguments(nil, "main", shader.target, nil, 0, nil, 0, &args)
    if hr < 0 {
        log(.Error, "Failed to build arguments for DXC Compiler")
        return false
    }
    defer args->Release()

    result: ^dxc.IResult
    hr = compiler.compiler->Compile(&buffer, args->GetArguments(), args->GetCount(), compiler.include_handler, dxc.IResult_UUID, &result)
    if hr < 0 {
        log(.Error, fmt.tprintf("Failed to compile shader %s", shader.path))
        return false
    }
    defer result->Release()

    result->GetStatus(&hr)
    if hr < 0 {
        errors: ^dxc.IBlobUtf8
        result->GetOutput(.ERRORS, dxc.IBlobUtf8_UUID, cast(rawptr)&errors, nil)
        log(.Error, string(errors->GetStringPointer()))
        return false
    }

    hr = result->GetOutput(.OBJECT, dxc.IBlob_UUID, cast(rawptr)&shader.blob, nil)
    if hr < 0 {
        log(.Error, "Failed to get DXC compiled shader object")
        return false
    }

    shader.bytecode = d3d12.SHADER_BYTECODE{
        BytecodeLength = shader.blob->GetBufferSize(),
        pShaderBytecode = shader.blob->GetBufferPointer(),
    }
    log(.Info, fmt.tprintf("Shader .%s compiled correctly", shader.id))
    return true
}