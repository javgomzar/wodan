package game

import "vendor:directx/dxc"
import "vendor:directx/d3d12"
import "vendor:directx/dxgi"
import w32 "core:sys/windows"
import "core:os"
import "core:mem"
import "core:time"
import "core:log"
import "core:strings"


Shader_Type :: enum {
    Vertex,
    Domain,
    Hull,
    Geometry,
    Pixel,
    Compute,
    Library,
}

shader_target := [Shader_Type]w32.wstring {
    .Vertex =   "vs_6_6",
    .Domain =   "ds_6_6",
    .Hull =     "hs_6_6",
    .Geometry = "gs_6_6",
    .Pixel =    "ps_6_6",
    .Compute =  "cs_6_6",
    .Library =  "lib_6_6",
}

Shader_ID :: enum {
    None = 0,

    Vertex_Passthrough,
    Vertex_Screen,
    Vertex_Screen_Attributes,
    Vertex_World,
    Vertex_Mesh,
    Vertex_Text,
    Vertex_Sky,

    Pixel_Color,
    Pixel_Mesh,
    Pixel_Texture,
    Pixel_Text_Cover,
    Pixel_Bezier_Exterior_Stencil,
    Pixel_Bezier_Interior_Stencil,
    Pixel_Bezier_Exterior_Color,
    Pixel_Bezier_Interior_Color,
    Pixel_Sky,
}

get_shader_path :: proc(id: Shader_ID) -> string {
    switch id {
        case .None:                          return ""

        case .Vertex_Screen:                 return "file/shader/HLSL/vertex/screen.vsh"
        case .Vertex_Screen_Attributes:      return "file/shader/HLSL/vertex/screen_attributes.vsh"
        case .Vertex_World:                  return "file/shader/HLSL/vertex/world.vsh"
        case .Vertex_Passthrough:            return "file/shader/HLSL/vertex/passthrough.vsh"
        case .Vertex_Mesh:                   return "file/shader/HLSL/vertex/mesh.vsh"
        case .Vertex_Text:                   return "file/shader/HLSL/vertex/text.vsh"
        case .Vertex_Sky:                    return "file/shader/HLSL/vertex/sky.vsh"

        case .Pixel_Color:                   return "file/shader/HLSL/pixel/color.psh"
        case .Pixel_Mesh:                    return "file/shader/HLSL/pixel/mesh.psh"
        case .Pixel_Texture:                 return "file/shader/HLSL/pixel/texture.psh"
        case .Pixel_Text_Cover:              return "file/shader/HLSL/pixel/cover.psh"
        case .Pixel_Bezier_Exterior_Stencil: return "file/shader/HLSL/pixel/bezier_exterior_stencil.psh"
        case .Pixel_Bezier_Interior_Stencil: return "file/shader/HLSL/pixel/bezier_interior_stencil.psh"
        case .Pixel_Bezier_Exterior_Color:   return "file/shader/HLSL/pixel/bezier_exterior_color.psh"
        case .Pixel_Bezier_Interior_Color:   return "file/shader/HLSL/pixel/bezier_interior_color.psh"
        case .Pixel_Sky:                     return "file/shader/HLSL/pixel/sky.psh"
    }
    return ""
}

Shader_Pipeline_ID :: enum {
// 2D
    Screen_Line,
    Screen_Triangle,
    Screen_Texture,
    Winding_Number,
    Text_Bezier_Exterior_Stencil,
    Text_Bezier_Interior_Stencil,
    Text_Bezier_Exterior_Color,
    Text_Bezier_Interior_Color,
    Text_Stencil,
    Text_Cover,
    Text_Clean_Stencil,

// 3D
    World_Line,
    Debug_Skeleton,
    Mesh,
    Sky,
}

Shader_Pipeline_Entry :: struct {
    primitive:      d3d12.PRIMITIVE_TOPOLOGY_TYPE,
    stage:          [Shader_Type]Shader_ID,
}

shader_pipeline_entries := [Shader_Pipeline_ID]Shader_Pipeline_Entry {
    .Screen_Line = {
        primitive = .LINE,
        stage = #partial {
            .Vertex = .Vertex_Screen,
            .Pixel = .Pixel_Color,
        },
    },
    .Screen_Triangle = {
        primitive = .TRIANGLE,
        stage = #partial {
            .Vertex = .Vertex_Screen,
            .Pixel = .Pixel_Color,
        }
    },
    .Screen_Texture = {
        primitive = .TRIANGLE,
        stage = #partial {
            .Vertex = .Vertex_Screen_Attributes,
            .Pixel = .Pixel_Texture,
        }
    },
    .Winding_Number = {
        primitive = .TRIANGLE,
        stage = #partial {
            .Vertex = .Vertex_Text,
        }
    },
    .Text_Bezier_Exterior_Stencil = {
        primitive = .TRIANGLE,
        stage = #partial {
            .Vertex = .Vertex_Text,
            .Pixel = .Pixel_Bezier_Exterior_Stencil,
        },
    },
    .Text_Bezier_Interior_Stencil = {
        primitive = .TRIANGLE,
        stage = #partial {
            .Vertex = .Vertex_Text,
            .Pixel = .Pixel_Bezier_Interior_Stencil,
        },
    },
    .Text_Bezier_Exterior_Color = {
        primitive = .TRIANGLE,
        stage = #partial {
            .Vertex = .Vertex_Text,
            .Pixel = .Pixel_Bezier_Exterior_Color,
        },
    },
    .Text_Bezier_Interior_Color = {
        primitive = .TRIANGLE,
        stage = #partial {
            .Vertex = .Vertex_Text,
            .Pixel = .Pixel_Bezier_Interior_Color,
        },
    },
    .Text_Stencil = {
        primitive = .TRIANGLE,
        stage = #partial {
            .Vertex = .Vertex_Text,
        },
    },
    .Text_Cover = {
        primitive = .TRIANGLE,
        stage = #partial {
            .Vertex = .Vertex_Text,
            .Pixel = .Pixel_Text_Cover,
        },
    },
    .Text_Clean_Stencil = {
        primitive = .TRIANGLE,
        stage = #partial {
            .Vertex = .Vertex_Text,
        }
    },

    .World_Line = {
        primitive = .LINE,
        stage = #partial {
            .Vertex = .Vertex_World,
            .Pixel = .Pixel_Color,
        },
    },
    .Debug_Skeleton = {
        primitive = .LINE,
        stage = #partial {
            .Vertex = .Vertex_World,
            .Pixel = .Pixel_Color,
        },
    },
    .Mesh = {
        primitive = .TRIANGLE,
        stage = #partial {
            .Vertex = .Vertex_Mesh,
            .Pixel = .Pixel_Mesh,
        },
    },
    .Sky = {
        primitive = .TRIANGLE,
        stage = #partial {
            .Vertex = .Vertex_Sky,
            .Pixel = .Pixel_Sky,
        },
    }
}

Constant_Buffer :: struct {
    buffer:        ^d3d12.IResource,
    mapped_memory: rawptr,
    type:          typeid,
}

Global_Constant_Buffer :: struct #align(16) {
    projection: matrix[4, 4]f32,
    view:       matrix[4, 4]f32,
    resolution: [2]f32,
    mouse:      [2]f32,
    last_mouse: [2]f32,
    time:       f32,
}

Light_Constant_Buffer :: struct #align(16) {
    direction:        [3]f32,
    pad0:             f32,
    color:            [3]f32,
    pad1:             f32,
    camera_position:  [3]f32,
    ambient:          f32,
    diffuse:          f32,
}

Constant_Buffer_ID :: enum {
    Global,
    Light,
}

constant_buffer_types := [Constant_Buffer_ID]typeid{
    .Global = Global_Constant_Buffer,
    .Light = Light_Constant_Buffer,
}

set_constant_buffer :: proc(renderer: ^Renderer_Context, value: ^$T) {
    for type, id in constant_buffer_types {
        if T == type {
            constant_buffer := renderer.constant_buffers[renderer.frame % N_BACK_BUFFERS][id]
            mem.copy(constant_buffer.mapped_memory, value, size_of(T))
            return
        }
    }
}

Per_Draw_Data :: struct #align(256) {
    transform:            matrix[4, 4]f32,
    normal:               matrix[4, 4]f32,
    material_color:       [4]f32,
    metallic:             f32,
    roughness:            f32,
    color_texture_index:  u32,
    normal_texture_index: u32,
    pbr_texture_index:   u32,
}

DXC_Shader :: struct {
    id:                Shader_ID,
    path:              string,
    type:              Shader_Type,
    last_modification: time.Time,
    reflection:        ^d3d12.IShaderReflection,
    layout:            d3d12.INPUT_LAYOUT_DESC,
    blob:              ^dxc.IBlob,
    bytecode:          d3d12.SHADER_BYTECODE,
}

DXC_Compiler :: struct {
    utils:           ^dxc.IUtils,
    compiler:        ^dxc.ICompiler3,
    include_handler: ^dxc.IIncludeHandler,
}

initialize_shader_compiler :: proc(compiler: ^DXC_Compiler) {
    hr := dxc.CreateInstance(dxc.Utils_CLSID, dxc.IUtils_UUID, cast(rawptr)&compiler.utils)
    if hr < 0 do log.fatal("Failed to create DirectX compiler utils object")

    hr = dxc.CreateInstance(dxc.Compiler_CLSID, dxc.ICompiler3_UUID, cast(rawptr)&compiler.compiler)
    if hr < 0 do log.fatal("Failed to create DirectX compiler object")

    hr = compiler.utils->CreateDefaultIncludeHandler(&compiler.include_handler)
    if hr < 0 do log.fatal("Failed to create DirectX compiler include handler")
}

initialize_shader :: proc(id: Shader_ID, shader_list: ^[Shader_ID]DXC_Shader) {
    shader := &shader_list[id]
    shader.id = id
    shader.path = strings.clone(get_shader_path(id))
    error: os.Error
    shader.last_modification, error = os.modification_time_by_path(shader.path)
    if error != nil do log.error("Failed to check modification time for file", shader.path)
    _, extension := os.split_filename(shader.path)
    switch extension {
        case "vsh":
            shader.type = .Vertex
        case "dsh":
            shader.type = .Domain
        case "hsh":
            shader.type = .Hull
        case "gsh":
            shader.type = .Geometry
        case "psh":
            shader.type = .Pixel
        case "csh":
            shader.type = .Compute
        case "libsh":
            shader.type = .Library
        case:
            log.fatal("Invalid file extension '.", extension, "' for shader ", shader.path, sep = "")
    }
}

compile_shader :: proc(compiler: ^DXC_Compiler, shader: ^DXC_Shader) -> bool {
    data, error := os.read_entire_file(shader.path, context.temp_allocator)
    if error != nil{
        log.error("Failed to read shader file", shader.path)
        return false
    }
    defer {
        shader.last_modification, error = os.modification_time_by_path(shader.path)
        if error != nil do log.error("Failed to check modification time for file", shader.path)
    }

    buffer := dxc.Buffer{
        Ptr = raw_data(data),
        Size = len(data),
        Encoding = dxc.CP_UTF8,
    }    

    args: ^dxc.ICompilerArgs
    source_name := w32.utf8_to_wstring(shader.path)
    arguments := []w32.wstring { "-I", "file/shader/HLSL", }
    hr := compiler.utils->BuildArguments(source_name, "main", shader_target[shader.type], raw_data(arguments), u32(len(arguments)), nil, 0, &args)
    if hr < 0 {
        log.error("Failed to build arguments for DXC Compiler")
        return false
    }
    defer args->Release()

    result: ^dxc.IResult
    hr = compiler.compiler->Compile(&buffer, args->GetArguments(), args->GetCount(), compiler.include_handler, dxc.IResult_UUID, &result)
    if hr < 0 {
        log.error("Failed to compile shader", shader.id)
        return false
    }
    defer result->Release()

    result->GetStatus(&hr)
    if hr < 0 {
        errors: ^dxc.IBlobUtf8
        result->GetOutput(.ERRORS, dxc.IBlobUtf8_UUID, cast(rawptr)&errors, nil)
        log.error(string(errors->GetStringPointer()))
        return false
    }

    hr = result->GetOutput(.OBJECT, dxc.IBlob_UUID, cast(rawptr)&shader.blob, nil)
    if hr < 0 {
        log.error("Failed to get DXC compiled shader object")
        return false
    }

    shader.bytecode = d3d12.SHADER_BYTECODE{
        BytecodeLength = shader.blob->GetBufferSize(),
        pShaderBytecode = shader.blob->GetBufferPointer(),
    }
    log.info("Shader", shader.id, "compiled correctly")

    // Shader reflection
    reflection_blob: ^dxc.IBlob
    hr = result->GetOutput(.REFLECTION, dxc.IBlob_UUID, &reflection_blob, nil)
    if hr < 0 do log.error("Failed to get reflection data for shader", shader.id)
    else {
        reflection_buffer := dxc.Buffer{
            Ptr = reflection_blob->GetBufferPointer(),
            Size = reflection_blob->GetBufferSize(),
            Encoding = 0,
        }

        hr = compiler.utils->CreateReflection(&reflection_buffer, d3d12.IShaderReflection_UUID, &shader.reflection)
        if hr < 0 {
            log.error("Failed to get reflection data for shader", shader.id)
            return true
        }
    }

    return true
}

update_if_newer_shader :: proc(compiler: ^DXC_Compiler, shader: ^DXC_Shader) -> bool {
    timestamp, error := os.modification_time_by_path(shader.path)
    if error != nil {
        log.error("Failed to check modification time for file", shader.path)
        return false
    }

    delta := time.diff(shader.last_modification, timestamp)
    if delta > 0 {
        temp_shader := shader^
        ok := compile_shader(compiler, &temp_shader)
        if ok {
            if shader.blob != nil {
                shader.blob->Release()
            }
            shader^ = temp_shader

            log.info("Shader", shader.id, "hot-reloaded")
        }
        shader.last_modification = timestamp
        return ok
    }

    return false
}

get_input_element :: proc(parameter: d3d12.SIGNATURE_PARAMETER_DESC) -> d3d12.INPUT_ELEMENT_DESC {
    format: dxgi.FORMAT
    component_count: u32 = 0
    for i: u32 = 0; i < 4; i += 1 {
        if (parameter.Mask & (1 << i)) > 0 do component_count += 1
    }
    switch parameter.ComponentType {
        case .FLOAT32:
            switch component_count {
                case 1: format = .R32_FLOAT
                case 2: format = .R32G32_FLOAT
                case 3: format = .R32G32B32_FLOAT
                case 4: format = .R32G32B32A32_FLOAT
            }
        case .UINT32:
            switch component_count {
                case 1: format = .R32_UINT
                case 2: format = .R32G32_UINT
                case 3: format = .R32G32B32_UINT
                case 4: format = .R32G32B32A32_UINT
            }
        case .SINT32:
            switch component_count {
                case 1: format = .R32_SINT
                case 2: format = .R32G32_SINT
                case 3: format = .R32G32B32_SINT
                case 4: format = .R32G32B32A32_SINT
            }
        case .UNKNOWN:
            switch component_count {
                case 1: format = .R32_TYPELESS
                case 2: format = .R32G32_TYPELESS
                case 3: format = .R32G32B32_TYPELESS
                case 4: format = .R32G32B32A32_TYPELESS
            }
    }
    
    name := string(parameter.SemanticName)

    input_slot: u32
    switch name {
        case "POSITION", "SV_VERTEXID", "SV_INSTANCEID":
            input_slot = 0
        case "NORMAL", "TEXCOORD", "COLOR":
            input_slot = 1
        case "JOINTS", "WEIGHTS":
            input_slot = 2
    }
    
    offset: u32
    switch name {
        case "POSITION", "NORMAL", "SV_VERTEXID", "SV_INSTANCEID", "JOINTS":
            offset = 0
        case "TEXCOORD":
            offset = 12
        case "COLOR":
            offset = 20
        case "WEIGHTS":
            offset = 16
        case:
            log.fatal("Invalid semantic name '", name, "'.", sep="")
    }

    return d3d12.INPUT_ELEMENT_DESC{
        SemanticName = parameter.SemanticName,
        SemanticIndex = parameter.SemanticIndex,
        InputSlot = input_slot,
        AlignedByteOffset = offset,
        Format = format,
        InputSlotClass = .PER_VERTEX_DATA,
    }
}

create_root_signature :: proc(renderer: ^Renderer_Context, n_srv_descriptors: u32) {
    srv_range := []d3d12.DESCRIPTOR_RANGE{
        {
            RangeType = .SRV,
            NumDescriptors = n_srv_descriptors,
            BaseShaderRegister = 0,
            RegisterSpace = 0,
            OffsetInDescriptorsFromTableStart = d3d12.DESCRIPTOR_RANGE_OFFSET_APPEND,
        },
    }

    static_sampler := []d3d12.STATIC_SAMPLER_DESC{
        {
            Filter = .MIN_MAG_MIP_LINEAR,
            AddressU = .WRAP,
            AddressV = .WRAP,
            AddressW = .WRAP,
            ComparisonFunc = .NEVER,
            MinLOD = 0.0,
            MaxLOD = d3d12.FLOAT32_MAX,
            ShaderRegister = 0,
            RegisterSpace = 0,
            ShaderVisibility = .PIXEL,
        },
    }

    root_params: []d3d12.ROOT_PARAMETER1 = {
        {   // Globals
            ParameterType = .CBV,
            Descriptor = {
                RegisterSpace = 0,
                ShaderRegister = 0,
            },
            ShaderVisibility = .ALL,
        },
        {   // Light
            ParameterType = .CBV,
            Descriptor = {
                RegisterSpace = 0,
                ShaderRegister = 1,
            },
            ShaderVisibility = .ALL,
        },
        {
            // Per draw data
            ParameterType = .CBV,
            Descriptor = {
                RegisterSpace = 0,
                ShaderRegister = 2,
            },
            ShaderVisibility = .ALL,
        },
        {
            // Glyph instances
            ParameterType = .SRV,
            Descriptor = {
                RegisterSpace = 0,
                ShaderRegister = 0,
            },
            ShaderVisibility = .ALL,
        },
        {
            // Glyph offsets
            ParameterType = .SRV,
            Descriptor = {
                RegisterSpace = 0,
                ShaderRegister = 1,
            },
            ShaderVisibility = .ALL,
        },
    }

    root_signature_desc := d3d12.VERSIONED_ROOT_SIGNATURE_DESC{
        Version = ._1_1,
        Desc_1_1 = {
            NumParameters = u32(len(root_params)),
            pParameters = &root_params[0],
            NumStaticSamplers = u32(len(static_sampler)),
            pStaticSamplers = &static_sampler[0],
            Flags = {
                .ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT,
                .CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED,
                .SAMPLER_HEAP_DIRECTLY_INDEXED,
            }
        },
    }

    signature_blob, error: ^d3d12.IBlob
    hr := d3d12.SerializeVersionedRootSignature(&root_signature_desc, &signature_blob, &error)
    if hr < 0 do log.fatal("Failed to serialize D3D12 root signature")
    hr = renderer.device->CreateRootSignature(
        0, 
        signature_blob->GetBufferPointer(), 
        signature_blob->GetBufferSize(), 
        d3d12.IRootSignature_UUID,
        (^rawptr)(&renderer.root_signature)
    )
    if hr < 0 do log.fatal("Failed to create D3D12 root signature")
    defer signature_blob->Release()
}

initialize_pipeline :: proc(id: Shader_Pipeline_ID, renderer: ^Renderer_Context) {
    entry := shader_pipeline_entries[id]
    pipeline := &renderer.shader_pipelines[id]
    
    shader_desc: d3d12.SHADER_DESC
    vertex_shader := &renderer.shaders[entry.stage[.Vertex]]
    vertex_shader.reflection->GetDesc(&shader_desc)
    
    input_layout: d3d12.INPUT_LAYOUT_DESC
    input_elements: [8]d3d12.INPUT_ELEMENT_DESC
    parameter: d3d12.SIGNATURE_PARAMETER_DESC
    for i in 0..<shader_desc.InputParameters {
        vertex_shader.reflection->GetInputParameterDesc(i, &parameter)
        input_elements[i] = get_input_element(parameter)
    }
    input_layout = d3d12.INPUT_LAYOUT_DESC{
        NumElements = shader_desc.InputParameters,
        pInputElementDescs = raw_data(input_elements[:]),
    }

    depth_stencil_desc: d3d12.DEPTH_STENCIL_DESC = {
        DepthEnable = w32.TRUE,
        StencilEnable = w32.FALSE,
        DepthWriteMask = .ALL,
        DepthFunc = .LESS,
    }

    #partial switch id {
        case .Debug_Skeleton:
            depth_stencil_desc.DepthEnable = w32.FALSE
        case .Winding_Number:
            depth_stencil_desc.DepthEnable = w32.FALSE
            depth_stencil_desc.StencilEnable = w32.TRUE
            depth_stencil_desc.StencilReadMask = 0xff
            depth_stencil_desc.StencilWriteMask = 0xff
            depth_stencil_desc.FrontFace = {
                StencilFunc = .ALWAYS,
                StencilPassOp = .INCR,
                StencilFailOp = .KEEP,
                StencilDepthFailOp = .KEEP,
            }
            depth_stencil_desc.BackFace = {
                StencilFunc = .ALWAYS,
                StencilPassOp = .DECR,
                StencilFailOp = .KEEP,
                StencilDepthFailOp = .KEEP,
            }
        case .Text_Bezier_Exterior_Stencil, .Text_Bezier_Interior_Stencil:
            depth_stencil_desc.DepthEnable = w32.FALSE
            depth_stencil_desc.StencilEnable = w32.TRUE
            depth_stencil_desc.StencilReadMask = 0xff
            depth_stencil_desc.StencilWriteMask = 0xff
            depth_stencil_desc.FrontFace = {
                StencilFunc = .ALWAYS,
                StencilPassOp = .ZERO,
                StencilFailOp = .KEEP,
                StencilDepthFailOp = .KEEP,
            }
            depth_stencil_desc.BackFace = {
                StencilFunc = .ALWAYS,
                StencilPassOp = .ZERO,
                StencilFailOp = .KEEP,
                StencilDepthFailOp = .KEEP,
            }
        case .Text_Bezier_Exterior_Color, .Text_Bezier_Interior_Color:
            depth_stencil_desc.DepthFunc = .ALWAYS
            depth_stencil_desc.DepthWriteMask = .ZERO
            depth_stencil_desc.StencilEnable = w32.TRUE
            depth_stencil_desc.StencilReadMask = 0xff
            depth_stencil_desc.StencilWriteMask = 0xff
            depth_stencil_desc.FrontFace = {
                StencilFunc = .EQUAL,
                StencilPassOp = .KEEP,
                StencilFailOp = .KEEP,
                StencilDepthFailOp = .KEEP,
            }
            depth_stencil_desc.BackFace = {
                StencilFunc = .EQUAL,
                StencilPassOp = .KEEP,
                StencilFailOp = .KEEP,
                StencilDepthFailOp = .KEEP,
            }
        case .Text_Stencil:
            depth_stencil_desc.DepthEnable = w32.FALSE
            depth_stencil_desc.StencilEnable = w32.TRUE
            depth_stencil_desc.StencilReadMask = 0xff
            depth_stencil_desc.StencilWriteMask = 0xff
            depth_stencil_desc.FrontFace = {
                StencilFunc = .ALWAYS,
                StencilPassOp = .INCR,
                StencilFailOp = .KEEP,
                StencilDepthFailOp = .KEEP,
            }
            depth_stencil_desc.BackFace = {
                StencilFunc = .ALWAYS,
                StencilPassOp = .INCR,
                StencilFailOp = .KEEP,
                StencilDepthFailOp = .KEEP,
            }
        case .Text_Cover:
            depth_stencil_desc.DepthFunc = .ALWAYS
            depth_stencil_desc.DepthWriteMask = .ZERO
            depth_stencil_desc.StencilEnable = w32.TRUE
            depth_stencil_desc.StencilReadMask = 0xff
            depth_stencil_desc.StencilWriteMask = 0xff
            depth_stencil_desc.FrontFace = {
                StencilFunc = .EQUAL,
                StencilPassOp = .KEEP,
                StencilFailOp = .KEEP,
                StencilDepthFailOp = .ZERO,
            }
            depth_stencil_desc.BackFace = {
                StencilFunc = .EQUAL,
                StencilPassOp = .KEEP,
                StencilFailOp = .KEEP,
                StencilDepthFailOp = .ZERO,
            }
        case .Text_Clean_Stencil: 
            depth_stencil_desc.DepthEnable = w32.FALSE
            depth_stencil_desc.StencilEnable = w32.TRUE
            depth_stencil_desc.StencilReadMask = 0xff
            depth_stencil_desc.StencilWriteMask = 0xff
            depth_stencil_desc.FrontFace = {
                StencilFunc = .ALWAYS,
                StencilPassOp = .ZERO,
                StencilFailOp = .ZERO,
                StencilDepthFailOp = .ZERO,
            }
            depth_stencil_desc.BackFace = {
                StencilFunc = .ALWAYS,
                StencilPassOp = .ZERO,
                StencilFailOp = .ZERO,
                StencilDepthFailOp = .ZERO,
            }
        case .Sky:
            depth_stencil_desc.DepthFunc = .LESS_EQUAL
    }

    pixel_shader := &renderer.shaders[entry.stage[.Pixel]]
    pipeline_desc := d3d12.GRAPHICS_PIPELINE_STATE_DESC{
        InputLayout = input_layout,
        PrimitiveTopologyType = entry.primitive,
        NumRenderTargets = 1,
        DSVFormat = .D24_UNORM_S8_UINT,
        SampleMask = max(u32),
        SampleDesc = {
            Count = N_MSAA_SAMPLES, 
            Quality = 0,
        },
        NodeMask = 0,
        pRootSignature = renderer.root_signature,
        BlendState = {
            AlphaToCoverageEnable = w32.FALSE,
            IndependentBlendEnable = w32.FALSE,
        },
        DepthStencilState = depth_stencil_desc,
        RasterizerState = {
            FillMode = .SOLID,
            CullMode = .NONE,
            FrontCounterClockwise = w32.FALSE,
            DepthBias = d3d12.DEFAULT_DEPTH_BIAS,
            DepthBiasClamp = d3d12.DEFAULT_DEPTH_BIAS_CLAMP,
            SlopeScaledDepthBias = d3d12.DEFAULT_SLOPE_SCALED_DEPTH_BIAS,
            DepthClipEnable = w32.TRUE,
            MultisampleEnable = w32.TRUE,
            AntialiasedLineEnable = w32.TRUE,
            ForcedSampleCount = 0,
            ConservativeRaster = .OFF,
        },
        VS = vertex_shader.bytecode,
        PS = pixel_shader.bytecode,
    }

    pipeline_desc.RTVFormats[0] = .R8G8B8A8_UNORM
    pipeline_desc.BlendState.RenderTarget[0] = {
        BlendEnable = w32.TRUE,
        LogicOpEnable = w32.FALSE,
        SrcBlend = .SRC_ALPHA,
        DestBlend = .INV_SRC_ALPHA,
        BlendOp = .ADD,
        SrcBlendAlpha = .ONE,
        DestBlendAlpha = .INV_SRC_ALPHA,
        BlendOpAlpha = .ADD,
        LogicOp = .NOOP,
        RenderTargetWriteMask = 0xf,
    }

    #partial switch id {
        case .Winding_Number, .Text_Stencil, .Text_Bezier_Exterior_Stencil, .Text_Bezier_Interior_Stencil, .Text_Clean_Stencil:
            pipeline_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0
    }

    hr := renderer.device->CreateGraphicsPipelineState(&pipeline_desc, d3d12.IPipelineState_UUID, (^rawptr)(pipeline))
    if hr < 0 do log.fatal("Failed to create pipeline state")
}