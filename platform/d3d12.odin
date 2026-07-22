package main

import w32 "core:sys/windows"
import "vendor:directx/d3d12"
import "vendor:directx/dxgi"
import "core:math"
import "core:mem"
import "base:runtime"


when ODIN_OS == .Windows {

N_BACK_BUFFERS  :: 3
N_DEPTH_BUFFERS :: 1

d3d12_frame_context :: struct {
    command_alloc: ^d3d12.ICommandAllocator,
    fence_value:   u64,
}

renderer_context :: struct {
    frame:               u64,
    width:               u32,
    height:              u32,
    camera:              game_camera,
    window:              w32.HWND,
    device:              ^d3d12.IDevice,
    fence:               ^d3d12.IFence,
    fence_event:         w32.HANDLE,
    swap_chain:          ^dxgi.ISwapChain1,
    command_queue:       ^d3d12.ICommandQueue,
    command_list:        ^d3d12.IGraphicsCommandList,
    pipeline:            ^d3d12.IPipelineState,
    root_signature:      ^d3d12.IRootSignature,
    frame_context:       [N_BACK_BUFFERS]d3d12_frame_context,
    rtv_heap:            ^d3d12.IDescriptorHeap,
    dsv_heap:            ^d3d12.IDescriptorHeap,
    rtv_descriptor_size: u32,
    dsv_descriptor_size: u32,
    render_targets:      [N_BACK_BUFFERS]^d3d12.IResource,
    depth_stencils:      [N_DEPTH_BUFFERS]^d3d12.IResource,
    position_buffer:     d3d12.VERTEX_BUFFER_VIEW,
    attribute_buffer:    d3d12.VERTEX_BUFFER_VIEW,
    shader_compiler:     dxc_compiler,
    shaders:             [shader_id]dxc_shader,
    global_buffers:      [N_BACK_BUFFERS]^d3d12.IResource,
    global_mapped:       [N_BACK_BUFFERS]rawptr,
}

initialize_renderer :: proc(renderer: ^renderer_context) {
    hr: w32.HRESULT
    renderer.window = w32.GetActiveWindow()

    factory: ^dxgi.IFactory4
    flags: dxgi.CREATE_FACTORY

    renderer.fence_event = w32.CreateEventExW(nil, "GPU fence", 0, EVENT_ALL_ACCESS)

    // Activate debug layer
    when ODIN_DEBUG {
        debug_controller: ^d3d12.IDebug
        hr = d3d12.GetDebugInterface(d3d12.IDebug_UUID, (^rawptr)(&debug_controller))
        if hr >= 0 {
            debug_controller->EnableDebugLayer()
            debug_controller->Release()
        }
        flags |= {.DEBUG}
    }

    hr = dxgi.CreateDXGIFactory2(flags, dxgi.IFactory4_UUID, (^rawptr)(&factory))
    if hr < 0 {
        log(.Fatal, "Failed to create DXGI Factory.")
    }
    defer factory->Release()

    adapter: ^dxgi.IAdapter1
    DXGI_ERROR_NOT_FOUND :: dxgi.HRESULT(-142213123)

    for i: u32 = 0; factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND; i += 1 {
        desc: dxgi.ADAPTER_DESC1
        adapter->GetDesc1(&desc)

        if dxgi.ADAPTER_FLAG.SOFTWARE in desc.Flags {
            adapter->Release()
            continue // skip software adapter
        }

        if d3d12.CreateDevice((^dxgi.IUnknown)(adapter), ._12_0, d3d12.IDevice_UUID, nil) >= 0 {
            break
        }

        adapter->Release()
        adapter = nil
    }

    if adapter == nil {
        log(.Fatal, "No D3D12-capable hardware adapter found")
    }
    defer adapter->Release()

	hr = d3d12.CreateDevice((^dxgi.IUnknown)(adapter), ._12_0, d3d12.IDevice_UUID, (^rawptr)(&renderer.device))
	if hr < 0 {
		log(.Fatal, "Failed to create D3D12 device")
	}

    renderer.device->CreateFence(0, {}, d3d12.IFence_UUID, (^rawptr)(&renderer.fence))

    queue_desc := d3d12.COMMAND_QUEUE_DESC{ Type = .DIRECT }
    hr = renderer.device->CreateCommandQueue(
        &queue_desc, 
        d3d12.ICommandQueue_UUID, 
        (^rawptr)(&renderer.command_queue)
    )
    if hr < 0 {
        log(.Fatal, "Failed to create D3D12 command queue")
    }

    for &frame in renderer.frame_context {
        hr = renderer.device->CreateCommandAllocator(
            .DIRECT, 
            d3d12.ICommandAllocator_UUID, 
            (^rawptr)(&frame.command_alloc)
        )
        if hr < 0 {
            log(.Fatal, "Failed to create D3D12 command allocator")
        }
    }
    
    hr = renderer.device->CreateCommandList(
        0, 
        .DIRECT, 
        renderer.frame_context[0].command_alloc, 
        nil, 
        d3d12.IGraphicsCommandList_UUID, 
        (^rawptr)(&renderer.command_list)
    )
    if hr < 0 {
        log(.Fatal, "Failed to create D3D12 command list")
    }

    swap_chain_desc := dxgi.SWAP_CHAIN_DESC1{
        Width = renderer.width,
        Height = renderer.height,
        Format = .R8G8B8A8_UNORM,
        Stereo = false,
        SampleDesc = {
            Count = 1,
            Quality = 0,
        },
        BufferUsage = {.RENDER_TARGET_OUTPUT},
        BufferCount = N_BACK_BUFFERS,
        Scaling = .STRETCH,
        SwapEffect = .FLIP_DISCARD,
        AlphaMode = .UNSPECIFIED,
        Flags = {.ALLOW_TEARING},
    }

    hr = factory->CreateSwapChainForHwnd(renderer.command_queue, renderer.window, &swap_chain_desc, nil, nil, &renderer.swap_chain)
    if hr < 0 {
        log(.Fatal, "Failed to create DXGI swap chain")
    }

    output: ^dxgi.IOutput
    renderer.swap_chain->GetContainingOutput(&output)

    output_desc: dxgi.OUTPUT_DESC
    output->GetDesc(&output_desc)

    // n_modes: u32
    // output->GetDisplayModeList(.R8G8B8A8_UNORM, {}, &n_modes, nil)
    // modes := make([]dxgi.MODE_DESC, n_modes)
    // defer delete(modes)
    // output->GetDisplayModeList(.R8G8B8A8_UNORM, {}, &n_modes, raw_data(modes))
    // for mode in modes {
    //     fmt.printf("%d x %d : %.2f Hz\n", mode.Width, mode.Height, f32(mode.RefreshRate.Numerator) / f32(mode.RefreshRate.Denominator))
    // }

    rtv_heap_desc := d3d12.DESCRIPTOR_HEAP_DESC{
        NumDescriptors = N_BACK_BUFFERS,
        Type           = .RTV,
        Flags          = {},
    }
    hr = renderer.device->CreateDescriptorHeap(
        &rtv_heap_desc, 
        d3d12.IDescriptorHeap_UUID, 
        (^rawptr)(&renderer.rtv_heap)
    )
    if hr < 0 {
        log(.Fatal, "Failed to create RTV descriptor heap")
    }
    renderer.rtv_descriptor_size = renderer.device->GetDescriptorHandleIncrementSize(.RTV)

    dsv_heap_desc := d3d12.DESCRIPTOR_HEAP_DESC{
        NumDescriptors = N_DEPTH_BUFFERS,
        Type           = .DSV,
        Flags          = {},
    }
    hr = renderer.device->CreateDescriptorHeap(
        &dsv_heap_desc, 
        d3d12.IDescriptorHeap_UUID, 
        (^rawptr)(&renderer.dsv_heap)
    )
    if hr < 0 {
        log(.Fatal, "Failed to create DSV descriptor heap")
    }
    renderer.dsv_descriptor_size = renderer.device->GetDescriptorHandleIncrementSize(.DSV)

    renderer.frame = 0
    rtv_handle: d3d12.CPU_DESCRIPTOR_HANDLE
    renderer.rtv_heap->GetCPUDescriptorHandleForHeapStart(&rtv_handle)
    for i in 0..<N_BACK_BUFFERS {
        hr = renderer.swap_chain->GetBuffer(u32(i), d3d12.IResource_UUID, (^rawptr)(&renderer.render_targets[i]))
        if hr < 0 {
            log(.Fatal, "Failed to get swap chain buffers")
        }
        renderer.device->CreateRenderTargetView(renderer.render_targets[i], nil, rtv_handle)
        rtv_handle.ptr += uint(renderer.rtv_descriptor_size)
    }

    dsv_handle: d3d12.CPU_DESCRIPTOR_HANDLE
    renderer.dsv_heap->GetCPUDescriptorHandleForHeapStart(&dsv_handle)
    for i in 0..<N_DEPTH_BUFFERS {
        resource_desc := d3d12.RESOURCE_DESC{
            Dimension = .TEXTURE2D,
            Alignment = 0,
            Width = u64(renderer.width),
            Height = renderer.height,
            DepthOrArraySize = 1,
            MipLevels = 1,
            Format = .D24_UNORM_S8_UINT,
            SampleDesc = {
                Count = 1,
                Quality = 0
            },
            Layout = .UNKNOWN,
            Flags = {.ALLOW_DEPTH_STENCIL}
        }

        clear := d3d12.CLEAR_VALUE{
            Format = .D24_UNORM_S8_UINT,
            DepthStencil = {
                Depth = 1.0,
                Stencil = 0
            },
        }

        heap_props := d3d12.HEAP_PROPERTIES{ Type = .DEFAULT }
        hr = renderer.device->CreateCommittedResource(
            &heap_props, 
            {}, 
            &resource_desc, 
            { .DEPTH_WRITE }, 
            &clear, 
            d3d12.IResource_UUID, 
            (^rawptr)(&renderer.depth_stencils[i])
        )
        if hr < 0 {
            log(.Fatal, "Failed to create depth stencil buffer")
        }

        renderer.device->CreateDepthStencilView(renderer.depth_stencils[i], nil, dsv_handle)
        dsv_handle.ptr += uint(renderer.dsv_descriptor_size)
    }

    // Vertex buffers
    renderer.position_buffer = create_vertex_buffer(renderer.device, 3, vertex_position, &triangle_positions)
    renderer.attribute_buffer = create_vertex_buffer(renderer.device, 3, vertex_attributes, &triangle_attributes)

    // Constant buffers
    for i in 0..<N_BACK_BUFFERS {
        size := mem.align_forward_int(size_of(global_constant_buffer), 256)
        renderer.global_buffers[i] = create_buffer(renderer.device, size)
        read_range := d3d12.RANGE{0, 0}
        renderer.global_buffers[i]->Map(0, &read_range, &renderer.global_mapped[i])
    }

    // Shaders
    initialize_shader_compiler(&renderer.shader_compiler)

    for id in shader_id {
        initialize_shader(id, &renderer.shaders)
        compile_shader(renderer.shader_compiler, &renderer.shaders[id])
    }

    root_params: []d3d12.ROOT_PARAMETER = {
        {
            ParameterType = .CBV,
            Descriptor = {
                RegisterSpace = 0,
                ShaderRegister = 0,
            },
            ShaderVisibility = .ALL,
        }
    }

    root_signature_desc := d3d12.ROOT_SIGNATURE_DESC{
        NumParameters = u32(len(root_params)),
        pParameters = raw_data(root_params),
        Flags = {.ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT},
    }

    signature, error: ^d3d12.IBlob
    hr = d3d12.SerializeRootSignature(&root_signature_desc, ._1, &signature, &error)
    if hr < 0 {
        log(.Fatal, "Failed to serialize D3D12 root signature")
    }
    hr = renderer.device->CreateRootSignature(
        0, 
        signature->GetBufferPointer(), 
        signature->GetBufferSize(), 
        d3d12.IRootSignature_UUID,
        (^rawptr)(&renderer.root_signature)
    )
    if hr < 0 {
        log(.Fatal, "Failed to create D3D12 root signature")
    }

    input_layout :: []d3d12.INPUT_ELEMENT_DESC{
        {
            SemanticName = "POSITION",
            SemanticIndex = 0,
            AlignedByteOffset = 0,
            Format = .R32G32B32_FLOAT,
            InputSlot = 0,
            InputSlotClass = .PER_VERTEX_DATA,
        },
        {
            SemanticName = "NORMAL",
            SemanticIndex = 0,
            AlignedByteOffset = 0,
            Format = .R32G32B32_FLOAT,
            InputSlot = 1,
            InputSlotClass = .PER_VERTEX_DATA,
        },
        {
            SemanticName = "TEXCOORD",
            SemanticIndex = 0,
            AlignedByteOffset = 12,
            Format = .R32G32_FLOAT,
            InputSlot = 1,
            InputSlotClass = .PER_VERTEX_DATA,
        },
        {
            SemanticName = "COLOR",
            SemanticIndex = 0,
            AlignedByteOffset = 20,
            Format = .R32G32B32A32_FLOAT,
            InputSlot = 1,
            InputSlotClass = .PER_VERTEX_DATA,
        },
    }

    input_layout_desc := d3d12.INPUT_LAYOUT_DESC{
        NumElements = u32(len(input_layout)),
        pInputElementDescs = raw_data(input_layout),
    }

    target_blend_desc := d3d12.RENDER_TARGET_BLEND_DESC {
        BlendEnable = w32.FALSE,
        LogicOpEnable = w32.FALSE,
        SrcBlend = .ONE,
        DestBlend = .ZERO,
        BlendOp = .ADD,
        SrcBlendAlpha = .ONE,
        DestBlendAlpha = .ZERO,
        BlendOpAlpha = .ADD,
        LogicOp = .NOOP,
        RenderTargetWriteMask = 0xf,
    }

    pipeline_desc := d3d12.GRAPHICS_PIPELINE_STATE_DESC{
        InputLayout = input_layout_desc,
        VS = renderer.shaders[.Vertex_Passthrough].bytecode,
        PS = renderer.shaders[.Pixel_Color].bytecode,
        PrimitiveTopologyType = .TRIANGLE,
        NumRenderTargets = 1,
        RTVFormats = {
            .R8G8B8A8_UNORM,
            .UNKNOWN,
            .UNKNOWN,
            .UNKNOWN,
            .UNKNOWN,
            .UNKNOWN,
            .UNKNOWN,
            .UNKNOWN,
        },
        DSVFormat = .UNKNOWN,
        SampleMask = max(u32),
        SampleDesc = {
            Count = 1,
            Quality = 0,            
        },
        NodeMask = 0,
        CachedPSO = {},
        Flags = {},
        pRootSignature = renderer.root_signature,
        BlendState = {
            AlphaToCoverageEnable = w32.FALSE,
            IndependentBlendEnable = w32.FALSE,
            RenderTarget = {
                target_blend_desc,
                target_blend_desc,
                target_blend_desc,
                target_blend_desc,
                target_blend_desc,
                target_blend_desc,
                target_blend_desc,
                target_blend_desc,
            }
        },
        DepthStencilState = {
            DepthEnable = w32.FALSE,
            StencilEnable = w32.FALSE,
        },
        RasterizerState = {
            FillMode = .SOLID,
            CullMode = .BACK,
            FrontCounterClockwise = w32.FALSE,
            DepthBias = d3d12.DEFAULT_DEPTH_BIAS,
            DepthBiasClamp = d3d12.DEFAULT_DEPTH_BIAS_CLAMP,
            SlopeScaledDepthBias = d3d12.DEFAULT_SLOPE_SCALED_DEPTH_BIAS,
            DepthClipEnable = w32.TRUE,
            MultisampleEnable = w32.FALSE,
            AntialiasedLineEnable = w32.FALSE,
            ForcedSampleCount = 0,
            ConservativeRaster = .OFF,
        },
    }
    renderer.device->CreateGraphicsPipelineState(&pipeline_desc, d3d12.IPipelineState_UUID, (^rawptr)(&renderer.pipeline))

    renderer.command_list->Close()
}

create_buffer :: proc(device: ^d3d12.IDevice, size: int, memory: rawptr = nil) -> ^d3d12.IResource {
    properties := d3d12.HEAP_PROPERTIES{
        Type = .UPLOAD,
        CPUPageProperty = .UNKNOWN,
        MemoryPoolPreference = .UNKNOWN,
        CreationNodeMask = 1,
        VisibleNodeMask = 1,
    }

    resource_desc := d3d12.RESOURCE_DESC{
        Dimension = .BUFFER,
        Alignment = 0,
        Width = u64(size),
        Height = 1,
        DepthOrArraySize = 1,
        MipLevels = 1,
        Format = .UNKNOWN,
        SampleDesc = {
            Count = 1,
            Quality = 0,
        },
        Layout = .ROW_MAJOR,
        Flags = {},
    }

    state: d3d12.RESOURCE_STATE
    upload_buffer: ^d3d12.IResource
    hr := device->CreateCommittedResource(&properties, {}, &resource_desc, d3d12.RESOURCE_STATE_GENERIC_READ, nil, d3d12.IResource_UUID, (^rawptr)(&upload_buffer))
    if hr < 0 {
        log(.Fatal, "Failed to create D3D12 generic buffer")
    }

    if memory != nil {
        mapped_data: rawptr = nil
        read_range := d3d12.RANGE{0, 0}

        hr = upload_buffer->Map(0, &read_range, &mapped_data)
        if hr < 0 {
            log(.Fatal, "Failed to map D3D12 generic buffer")
        }
        runtime.mem_copy(mapped_data, memory, size)
        upload_buffer->Unmap(0, nil)
    }

    return upload_buffer
}

create_vertex_buffer :: proc(device: ^d3d12.IDevice, n_vertices: int, $T: typeid, memory: rawptr = nil) -> d3d12.VERTEX_BUFFER_VIEW {
    buffer := create_buffer(device, n_vertices * size_of(T), memory)

    return d3d12.VERTEX_BUFFER_VIEW{
        BufferLocation = buffer->GetGPUVirtualAddress(),
        StrideInBytes = size_of(T),
        SizeInBytes = u32(n_vertices * size_of(T)),
    }
}

global_constant_buffer :: struct #align(16) {
    projection: matrix[4, 4]f32,
    view:       matrix[4, 4]f32,
    resolution: [2]f32,
    mouse:      [2]f32,
    last_mouse: [2]f32,
    time:       f32,
}

constant_buffer_id :: enum {
}

constant_buffer_types :: [constant_buffer_id]typeid {
}

set_constant_buffer :: proc(renderer: ^renderer_context, value: ^$T) {
    for type, id in constant_buffer_types {
        if T == type {
            read_range := d3d12.RANGE{0, 0}
            mapped_data: rawptr = nil
            renderer.constant_buffers[id]->Map(0, &read_range, &mapped_data)
            runtime.mem_copy(mapped_data, value, size_of(T))
            return
        }
    }
}

set_global_constant_buffer :: proc(renderer: ^renderer_context, value: ^global_constant_buffer) {
    runtime.mem_copy(renderer.global_mapped[renderer.frame % N_BACK_BUFFERS], value, size_of(global_constant_buffer))
}

render :: proc(memory: ^game_memory) {
    renderer := &memory.renderer
    frame_index := renderer.frame % N_BACK_BUFFERS
    frame_context := &renderer.frame_context[frame_index]

    if renderer.fence->GetCompletedValue() < frame_context.fence_value {
        renderer.fence->SetEventOnCompletion(renderer.frame, renderer.fence_event)
        w32.WaitForSingleObject(renderer.fence_event, w32.INFINITE)
    }

    frame_context.command_alloc->Reset()
    renderer.command_list->Reset(frame_context.command_alloc, nil)

    viewport := d3d12.VIEWPORT{
        TopLeftX = 0.0,
        TopLeftY = 0.0,
        Width = f32(renderer.width),
        Height = f32(renderer.height),
        MinDepth = 0.0,
        MaxDepth = 1.0
    }
    renderer.command_list->RSSetViewports(1, &viewport)

    scissor_rect :=  d3d12.RECT{
        left = 0,
        top = 0,
        right = i32(renderer.width),
        bottom = i32(renderer.height),
    }
    renderer.command_list->RSSetScissorRects(1, &scissor_rect)

    back_buffer := renderer.render_targets[frame_index]
    barrier := d3d12.RESOURCE_BARRIER{
        Type = .TRANSITION,
        Flags = {},
        Transition = {
            pResource = back_buffer,
            StateBefore = d3d12.RESOURCE_STATE_PRESENT,
            StateAfter = {.RENDER_TARGET},
            Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
        }
    }
    renderer.command_list->ResourceBarrier(1, &barrier)

    rtv_handle: d3d12.CPU_DESCRIPTOR_HANDLE
    rtv_descriptor_size := renderer.device->GetDescriptorHandleIncrementSize(.RTV)
    renderer.rtv_heap->GetCPUDescriptorHandleForHeapStart(&rtv_handle)
    rtv_handle.ptr += uint(frame_index) * uint(rtv_descriptor_size)
    dsv_handle: d3d12.CPU_DESCRIPTOR_HANDLE
    renderer.dsv_heap->GetCPUDescriptorHandleForHeapStart(&dsv_handle)

    // Global constant buffer
    global_cb := global_constant_buffer{
        resolution = {f32(renderer.width), f32(renderer.height)},
        mouse = memory.input.mouse.cursor,
        last_mouse = memory.input.mouse.cursor,
    }
    set_global_constant_buffer(renderer, &global_cb)

    renderer.command_list->SetGraphicsRootSignature(renderer.root_signature)
    renderer.command_list->SetGraphicsRootConstantBufferView(0, renderer.global_buffers[frame_index]->GetGPUVirtualAddress())

    renderer.command_list->SetPipelineState(renderer.pipeline)

    renderer.command_list->OMSetRenderTargets(1, &rtv_handle, false, &dsv_handle)

    clear_color := [4]f32{0.5 + 0.5*math.sin(f32(renderer.frame) / 100.0), 0.0, 0.5, 1.0}
    renderer.command_list->ClearRenderTargetView(rtv_handle, &clear_color, 0, nil)
    renderer.command_list->ClearDepthStencilView(dsv_handle, { .DEPTH, .STENCIL }, 1.0, 0, 0, nil)
    
    renderer.command_list->IASetPrimitiveTopology(.TRIANGLELIST)
    renderer.command_list->IASetVertexBuffers(0, 2, &renderer.position_buffer)
    renderer.command_list->DrawInstanced(3, 1, 0, 0)

    barrier = d3d12.RESOURCE_BARRIER{
        Type = .TRANSITION,
        Flags = {},
        Transition = {
            pResource = back_buffer,
            StateBefore = {.RENDER_TARGET},
            StateAfter = d3d12.RESOURCE_STATE_PRESENT,
            Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
        }
    }
    renderer.command_list->ResourceBarrier(1, &barrier)
    renderer.command_list->Close()

    list := []^d3d12.ICommandList{
        renderer.command_list
    }
    renderer.command_queue->ExecuteCommandLists(1, raw_data(list))

    renderer.swap_chain->Present(0, {})
    renderer.frame += 1
    frame_context.fence_value = renderer.frame

    hr := renderer.command_queue->Signal(renderer.fence, renderer.frame)
    if hr < 0 {
        log(.Fatal, "Failed to signal fence")
    }
}

}