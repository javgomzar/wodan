package common

import "core:mem"
import "core:log"
import "core:math/linalg"
import w32 "core:sys/windows"
import "vendor:directx/d3d12"
import "vendor:directx/dxgi"
import "../asset"


when ODIN_OS == .Windows {

N_BACK_BUFFERS  :: 3
N_MSAA_SAMPLES  :: 4

D3D12_Frame_Context :: struct {
    command_alloc: ^d3d12.ICommandAllocator,
    fence_value:   u64,
}

D3D12_get_primitive_topology :: proc(primitive: asset.Topology) -> d3d12.PRIMITIVE_TOPOLOGY {
    switch primitive {
        case .Point:          return .POINTLIST
        case .Line:           return .LINELIST
        case .Line_Strip:     return .LINESTRIP
        case .Triangle:       return .TRIANGLELIST
        case .Triangle_Strip: return .TRIANGLESTRIP
        case:
            log.fatal("Invalid primitive topology", primitive)
    }
    return .POINTLIST
}

create_buffer :: proc(device: ^d3d12.IDevice, size: u32) -> ^d3d12.IResource {
    assert(size > 0)

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
    if hr < 0 do log.fatal("Failed to create D3D12 generic buffer")

    return upload_buffer
}

RING_BUFFER_SIZE :: mem.Megabyte

D3D12_Ring_Buffer :: struct {
    using resource: ^d3d12.IResource,
    offset:         int,
    mapped:         rawptr,
}

allocate_from_ring_buffer :: proc(buffer: ^D3D12_Ring_Buffer, data: Per_Draw_Data) -> d3d12.GPU_VIRTUAL_ADDRESS {
    assert(buffer.offset + size_of(Per_Draw_Data) < RING_BUFFER_SIZE)
    pointer := ([^]byte)(buffer.mapped)[buffer.offset:]
    asset.dump_to_memory(pointer[:256], data)
    offset := u64(buffer.offset)
    buffer.offset += 256
    return buffer->GetGPUVirtualAddress() + offset
}

D3D12_Descriptor_Heap :: struct {
    heap:             ^d3d12.IDescriptorHeap,
    descriptor_size:  u32,
    descriptor_count: uint,
}

get_descriptor_heap_element :: proc(heap: ^D3D12_Descriptor_Heap, index: uint) -> d3d12.CPU_DESCRIPTOR_HANDLE {
    if index > heap.descriptor_count do log.fatal("Attempted to access descriptor heap beyond its length")
    handle: d3d12.CPU_DESCRIPTOR_HANDLE
    heap.heap->GetCPUDescriptorHandleForHeapStart(&handle)
    handle.ptr += index * uint(heap.descriptor_size)
    return handle
}

create_render_target_views :: proc(renderer: ^Renderer_Context) {
    rtv_handle, dsv_handle: d3d12.CPU_DESCRIPTOR_HANDLE
    renderer.rtv_heap.heap->GetCPUDescriptorHandleForHeapStart(&rtv_handle)
    renderer.dsv_heap.heap->GetCPUDescriptorHandleForHeapStart(&dsv_handle)
    
    // MSAA target
    renderer.device->CreateRenderTargetView(renderer.msaa_target, nil, rtv_handle)
    rtv_handle.ptr += uint(renderer.rtv_heap.descriptor_size)
    renderer.rtv_heap.descriptor_count += 1
    
    renderer.device->CreateDepthStencilView(renderer.msaa_depth_stencil, nil, dsv_handle)
    dsv_handle.ptr += uint(renderer.dsv_heap.descriptor_size)
    renderer.dsv_heap.descriptor_count += 1

    for i in 0..<N_BACK_BUFFERS {
        hr := renderer.swap_chain->GetBuffer(u32(i), d3d12.IResource_UUID, (^rawptr)(&renderer.render_targets[i]))
        if hr < 0 do log.fatal("Failed to get swap chain buffers")
        renderer.device->CreateRenderTargetView(renderer.render_targets[i], nil, rtv_handle)
        rtv_handle.ptr += uint(renderer.rtv_heap.descriptor_size)
        renderer.rtv_heap.descriptor_count += 1
    }

    renderer.device->CreateDepthStencilView(renderer.depth_stencil, nil, dsv_handle)
    dsv_handle.ptr += uint(renderer.dsv_heap.descriptor_size)
    renderer.dsv_heap.descriptor_count += 1
}

Renderer_Context :: struct {
    frame:                      u64,
    window:                     w32.HWND,
    device:                     ^d3d12.IDevice,
    fence:                      ^d3d12.IFence,
    fence_event:                w32.HANDLE,
    swap_chain:                 ^dxgi.ISwapChain1,
    viewport:                   d3d12.VIEWPORT,
    scissor_rect:               d3d12.RECT,
    command_queue:              ^d3d12.ICommandQueue,
    command_list:               ^d3d12.IGraphicsCommandList,
    frame_context:              [N_BACK_BUFFERS]D3D12_Frame_Context,
    rtv_heap:                   D3D12_Descriptor_Heap,
    dsv_heap:                   D3D12_Descriptor_Heap,
    srv_heap:                   D3D12_Descriptor_Heap,
    sampler_heap:               D3D12_Descriptor_Heap,
    render_targets:             [N_BACK_BUFFERS]^d3d12.IResource,
    depth_stencil:              ^d3d12.IResource,
    msaa_target:                ^d3d12.IResource,
    msaa_depth_stencil:         ^d3d12.IResource,
    static_position_buffer:     ^d3d12.IResource,
    static_attribute_buffer:    ^d3d12.IResource,
    static_index_buffer:        ^d3d12.IResource,
    dynamic_position_buffer:    ^d3d12.IResource,
    dynamic_attribute_buffer:   ^d3d12.IResource,
    dynamic_index_buffer:       ^d3d12.IResource,
    text_buffer:                ^d3d12.IResource,
    root_signature:             ^d3d12.IRootSignature,
    shader_compiler:            DXC_Compiler,
    shaders:                    [Shader_ID]DXC_Shader,
    shader_pipelines:           [Shader_Pipeline_ID]^d3d12.IPipelineState,
    constant_buffers:           [N_BACK_BUFFERS][Constant_Buffer_ID]Constant_Buffer,
    ring_buffers:               [N_BACK_BUFFERS]D3D12_Ring_Buffer,
}

EVENT_ALL_ACCESS :: w32.DWORD(0x1F0003)

initialize_renderer :: proc(
    asset_manager: ^asset.Manager,
    renderer: ^Renderer_Context,
    render_group: ^Render_Group,
) {
    hr: w32.HRESULT
    renderer.window = w32.GetActiveWindow()

    factory: ^dxgi.IFactory4
    flags: dxgi.CREATE_FACTORY

    renderer.fence_event = w32.CreateEventExW(nil, "GPU fence", 0, EVENT_ALL_ACCESS)

    // Activate debug layer
    when ODIN_DEBUG {
        debug_controller: ^d3d12.IDebug
        hr = d3d12.GetDebugInterface(d3d12.IDebug_UUID, (^rawptr)(&debug_controller))
        if hr < 0 do log.fatal("Failed to activate D3D12 debug interface")
        debug_controller->EnableDebugLayer()
        debug_controller->Release()
        flags |= {.DEBUG}
    }

    hr = dxgi.CreateDXGIFactory2(flags, dxgi.IFactory4_UUID, (^rawptr)(&factory))
    if hr < 0 do log.fatal("Failed to create DXGI Factory.")
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

    if adapter == nil do log.fatal("No D3D12-capable hardware adapter found")
    defer adapter->Release()

	hr = d3d12.CreateDevice((^dxgi.IUnknown)(adapter), ._12_0, d3d12.IDevice_UUID, (^rawptr)(&renderer.device))
	if hr < 0 do log.fatal("Failed to create D3D12 device")

    renderer.device->CreateFence(0, {}, d3d12.IFence_UUID, (^rawptr)(&renderer.fence))

    queue_desc := d3d12.COMMAND_QUEUE_DESC{ Type = .DIRECT, NodeMask = 0, }
    hr = renderer.device->CreateCommandQueue(
        &queue_desc, 
        d3d12.ICommandQueue_UUID, 
        (^rawptr)(&renderer.command_queue)
    )
    if hr < 0 do log.fatal("Failed to create D3D12 command queue")

    for &frame in renderer.frame_context {
        hr = renderer.device->CreateCommandAllocator(
            .DIRECT, 
            d3d12.ICommandAllocator_UUID, 
            (^rawptr)(&frame.command_alloc)
        )
        if hr < 0 {
            log.fatal("Failed to create D3D12 command allocator")
        }
    }

    texture_upload_alloc: ^d3d12.ICommandAllocator
    hr = renderer.device->CreateCommandAllocator(
        .DIRECT, 
        d3d12.ICommandAllocator_UUID, 
        (^rawptr)(&texture_upload_alloc)
    )

    texture_barriers: [dynamic]d3d12.RESOURCE_BARRIER
    defer delete(texture_barriers)

    texture_upload_fence: ^d3d12.IFence
    renderer.device->CreateFence(0, {}, d3d12.IFence_UUID, cast(^rawptr)&texture_upload_fence)
    texture_upload_fence_event := w32.CreateEventW(nil, false, false, nil)
    
    hr = renderer.device->CreateCommandList(
        0,
        .DIRECT,
        texture_upload_alloc,
        nil,
        d3d12.IGraphicsCommandList_UUID,
        (^rawptr)(&renderer.command_list)
    )
    if hr < 0 do log.fatal("Failed to create D3D12 command list")

    swap_chain_desc := dxgi.SWAP_CHAIN_DESC1{
        Width = render_group.width,
        Height = render_group.height,
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
    if hr < 0 do log.fatal("Failed to create DXGI swap chain")

    output: ^dxgi.IOutput
    renderer.swap_chain->GetContainingOutput(&output)

    output_desc: dxgi.OUTPUT_DESC
    output->GetDesc(&output_desc)

    renderer.viewport = {
        TopLeftX = 0.0,
        TopLeftY = 0.0,
        Width = f32(render_group.width),
        Height = f32(render_group.height),
        MinDepth = 0.0,
        MaxDepth = 1.0
    }

    renderer.scissor_rect = {
        left = 0,
        top = 0,
        right = i32(render_group.width),
        bottom = i32(render_group.height),
    }

    // n_modes: u32
    // output->GetDisplayModeList(.R8G8B8A8_UNORM, {}, &n_modes, nil)
    // modes := make([]dxgi.MODE_DESC, n_modes)
    // defer delete(modes)
    // output->GetDisplayModeList(.R8G8B8A8_UNORM, {}, &n_modes, raw_data(modes))
    // for mode in modes {
    //     fmt.printf("%d x %d : %.2f Hz\n", mode.Width, mode.Height, f32(mode.RefreshRate.Numerator) / f32(mode.RefreshRate.Denominator))
    // }

    // Render target views
    rtv_heap_desc := d3d12.DESCRIPTOR_HEAP_DESC{
        NumDescriptors = N_BACK_BUFFERS + 1,
        Type           = .RTV,
        Flags          = {},
    }
    hr = renderer.device->CreateDescriptorHeap(
        &rtv_heap_desc, 
        d3d12.IDescriptorHeap_UUID, 
        (^rawptr)(&renderer.rtv_heap.heap)
    )
    if hr < 0 do log.fatal("Failed to create RTV descriptor heap")
    renderer.rtv_heap.descriptor_size = renderer.device->GetDescriptorHandleIncrementSize(.RTV)

    // Depth-stencil views
    dsv_heap_desc := d3d12.DESCRIPTOR_HEAP_DESC{
        NumDescriptors = 2,
        Type           = .DSV,
        Flags          = {},
    }
    hr = renderer.device->CreateDescriptorHeap(
        &dsv_heap_desc, 
        d3d12.IDescriptorHeap_UUID, 
        (^rawptr)(&renderer.dsv_heap)
    )
    if hr < 0 do log.fatal("Failed to create DSV descriptor heap")
    renderer.dsv_heap.descriptor_size = renderer.device->GetDescriptorHandleIncrementSize(.DSV)

    depth_clear := d3d12.CLEAR_VALUE{
        Format = .D24_UNORM_S8_UINT,
        DepthStencil = {
            Depth = 1.0,
            Stencil = 0,
        },
    }

    resource_desc := d3d12.RESOURCE_DESC{
        Dimension = .TEXTURE2D,
        Format = .D24_UNORM_S8_UINT,
        Width = u64(render_group.width),
        Height = render_group.height,
        Alignment = 0,
        DepthOrArraySize = 1,
        MipLevels = 1,
        SampleDesc = {
            Count = 1,
            Quality = 0,
        },
        Layout = .UNKNOWN,
        Flags = {.ALLOW_DEPTH_STENCIL}
    }

    heap_props := d3d12.HEAP_PROPERTIES{ Type = .DEFAULT }
    hr = renderer.device->CreateCommittedResource(
        &heap_props, 
        {}, 
        &resource_desc, 
        { .DEPTH_WRITE }, 
        &depth_clear, 
        d3d12.IResource_UUID, 
        (^rawptr)(&renderer.depth_stencil)
    )
    if hr < 0 do log.fatal("Failed to create depth stencil buffer")

    // MSAA render target
    // Checking anti-aliasing support
    ms_quality_levels := d3d12.FEATURE_DATA_MULTISAMPLE_QUALITY_LEVELS{
        Format = .R8G8B8A8_UNORM,
        SampleCount = N_MSAA_SAMPLES,
    }
    renderer.device->CheckFeatureSupport(.MULTISAMPLE_QUALITY_LEVELS, &ms_quality_levels, size_of(d3d12.FEATURE_DATA_MULTISAMPLE_QUALITY_LEVELS))
    assert(ms_quality_levels.NumQualityLevels > 0)

    msaa_desc := d3d12.RESOURCE_DESC{
        Dimension = .TEXTURE2D,
        Format = .R8G8B8A8_UNORM,
        Width = u64(render_group.width),
        Height = render_group.height,
        DepthOrArraySize = 1,
        MipLevels = 1,
        SampleDesc = {
            Count = N_MSAA_SAMPLES,
            Quality = 0,
        },
        Flags = { .ALLOW_RENDER_TARGET, },
    }

    msaa_target_clear := d3d12.CLEAR_VALUE{
        Format = .R8G8B8A8_UNORM,
        Color = { 0, 0, 0, 0 },
    }

    msaa_heap_props := d3d12.HEAP_PROPERTIES{ Type = .DEFAULT, }
    renderer.device->CreateCommittedResource(
        &msaa_heap_props,
        {},
        &msaa_desc,
        { .RESOLVE_SOURCE },
        &msaa_target_clear,
        d3d12.IResource_UUID,
        cast(^rawptr)&renderer.msaa_target
    )

    msaa_depth_desc := d3d12.RESOURCE_DESC{
        Dimension = .TEXTURE2D,
        Format = .D24_UNORM_S8_UINT,
        Width = u64(render_group.width),
        Height = render_group.height,
        DepthOrArraySize = 1,
        MipLevels = 1,
        SampleDesc = {
            Count = N_MSAA_SAMPLES,
            Quality = 0,
        },
        Flags = { .ALLOW_DEPTH_STENCIL },
    }

    renderer.device->CreateCommittedResource(
        &msaa_heap_props,
        {},
        &msaa_depth_desc,
        { .DEPTH_WRITE },
        &depth_clear,
        d3d12.IResource_UUID,
        cast(^rawptr)&renderer.msaa_depth_stencil
    )
    
    create_render_target_views(renderer)

    // Shader resource views
    n_textures: u32 = 1
    for asset in asset_manager.assets {
        n_textures += u32(len(asset.textures))
    }

    srv_handle: d3d12.CPU_DESCRIPTOR_HANDLE
    srv_heap_desc := d3d12.DESCRIPTOR_HEAP_DESC{
        NumDescriptors = n_textures,
        Type           = .CBV_SRV_UAV,
        Flags          = {.SHADER_VISIBLE}
    }
    hr = renderer.device->CreateDescriptorHeap(
        &srv_heap_desc,
        d3d12.IDescriptorHeap_UUID,
        (^rawptr)(&renderer.srv_heap)
    )
    if hr < 0 do log.fatal("Failed to create SRV descriptor heap")
    renderer.srv_heap.descriptor_size = renderer.device->GetDescriptorHandleIncrementSize(.CBV_SRV_UAV)
    renderer.srv_heap.heap->GetCPUDescriptorHandleForHeapStart(&srv_handle)

    nil_srv := d3d12.SHADER_RESOURCE_VIEW_DESC{
        Format = .R8G8B8A8_UNORM,
        ViewDimension = .TEXTURE2D,
        Shader4ComponentMapping = d3d12.DEFAULT_SHADER_4_COMPONENT_MAPPING,
        Texture2D = {
            MipLevels = 1,
        },
    }
    renderer.device->CreateShaderResourceView(nil, &nil_srv, srv_handle)
    srv_handle.ptr += uint(renderer.srv_heap.descriptor_size)
    renderer.srv_heap.descriptor_count += 1

    // Samplers
    sampler_handle: d3d12.CPU_DESCRIPTOR_HANDLE
    sampler_heap_desc := d3d12.DESCRIPTOR_HEAP_DESC{
        NumDescriptors = 1,
        Type           = .SAMPLER,
        Flags          = {.SHADER_VISIBLE}
    }
    hr = renderer.device->CreateDescriptorHeap(
        &sampler_heap_desc,
        d3d12.IDescriptorHeap_UUID,
        (^rawptr)(&renderer.sampler_heap)
    )
    if hr < 0 do log.fatal("Failed to create sampler descriptor heap")
    renderer.sampler_heap.descriptor_size = renderer.device->GetDescriptorHandleIncrementSize(.SAMPLER)
    renderer.sampler_heap.heap->GetCPUDescriptorHandleForHeapStart(&sampler_handle)

    static_sampler := d3d12.SAMPLER_DESC{
        Filter = .MIN_MAG_MIP_LINEAR,
        AddressU = .WRAP,
        AddressV = .WRAP,
        AddressW = .WRAP,
        ComparisonFunc = .NEVER,
        MinLOD = 0.0,
        MaxLOD = d3d12.FLOAT32_MAX,
    }
    renderer.device->CreateSampler(&static_sampler, sampler_handle)
    sampler_handle.ptr += uint(renderer.sampler_heap.descriptor_size)
    renderer.sampler_heap.descriptor_count += 1

    // Vertex buffers
    position_count: u32
    attribute_count: u32
    index_count: u32

    // Meshes
    for asset in asset_manager.assets[1:] {
        for mesh in asset.meshes {
            for primitive in mesh.primitives {
                position_count += u32(len(primitive.positions))
                attribute_count += u32(len(primitive.attributes)) 
                index_count += u32(len(primitive.indices))
            }
        }
    }

    renderer.static_position_buffer = create_buffer(renderer.device, position_count * size_of(asset.Vertex_Position))
    renderer.static_attribute_buffer = create_buffer(renderer.device, attribute_count * size_of(asset.Vertex_Attributes))
    if index_count > 0 {
        renderer.static_index_buffer = create_buffer(renderer.device, index_count * size_of(u32))
    }

    mapped_position: rawptr = nil
    mapped_attribute: rawptr = nil
    mapped_index: rawptr = nil
    read_range := d3d12.RANGE{0, 0}

    hr = renderer.static_position_buffer->Map(0, &read_range, &mapped_position)
    if hr < 0 do log.fatal("Failed to map D3D12 static position buffer")

    hr = renderer.static_attribute_buffer->Map(0, &read_range, &mapped_attribute)
    if hr < 0 do log.fatal("Failed to map D3D12 static attribute buffer")
    
    hr = renderer.static_index_buffer->Map(0, &read_range, &mapped_index)
    if hr < 0 do log.fatal("Failed to map D3D12 static index buffer")

    position_offset: int
    attribute_offset: int
    index_offset: int
    position_ptr := cast([^]asset.Vertex_Position)mapped_position
    attribute_ptr := cast([^]asset.Vertex_Attributes)mapped_attribute
    index_ptr := cast([^]u32)mapped_index

    for asset in asset_manager.assets[1:] {
        for mesh in asset.meshes {
            for &primitive in mesh.primitives {
                if n_indices := len(primitive.indices); n_indices > 0 {
                    copy(index_ptr[:n_indices], primitive.indices)
                    index_ptr = index_ptr[n_indices:]
                    primitive.index_offset = index_offset
                    index_offset += n_indices
                }

                n_positions := len(primitive.positions)
                if n_positions == 0 do log.fatal("Mesh has 0 positions")
                copy(position_ptr[:n_positions], primitive.positions)
                position_ptr = position_ptr[n_positions:]
                primitive.position_offset = position_offset
                position_offset += n_positions

                if n_attributes := len(primitive.attributes); n_attributes > 0 {
                    copy(attribute_ptr[:n_attributes], primitive.attributes)
                    attribute_ptr = attribute_ptr[n_attributes:]
                    primitive.attribute_offset = attribute_offset
                    attribute_offset += n_attributes
                }
            }
        }

        // Textures
        for &texture in asset.textures {
            append(&texture_barriers, create_texture(renderer, &texture, &srv_handle))
        }
    }
    
    renderer.static_position_buffer->Unmap(0, nil)
    renderer.static_attribute_buffer->Unmap(0, nil)
    renderer.static_index_buffer->Unmap(0, nil)

    renderer.command_list->ResourceBarrier(u32(len(texture_barriers)), raw_data(texture_barriers))
    cmd_lists := []^d3d12.ICommandList{
        renderer.command_list,
    }
    renderer.command_list->Close()
    renderer.command_queue->ExecuteCommandLists(1, &cmd_lists[0])
    renderer.command_queue->Signal(texture_upload_fence, 1)

    if texture_upload_fence->GetCompletedValue() < 1 {
        texture_upload_fence->SetEventOnCompletion(1, texture_upload_fence_event)
        w32.WaitForSingleObject(texture_upload_fence_event, w32.INFINITE)
    }

    // Dynamic vertex buffers
    render_group.positions.capacity = 4096
    renderer.dynamic_position_buffer = create_buffer(renderer.device, u32(render_group.positions.capacity * size_of(asset.Vertex_Position)))
    dynamic_positions: rawptr
    hr = renderer.dynamic_position_buffer->Map(0, &read_range, &dynamic_positions)
    if hr < 0 do log.fatal("Failed to map D3D12 dynamic position buffer")
    render_group.positions.memory = cast([^]asset.Vertex_Position)dynamic_positions

    render_group.attributes.capacity = 4096
    renderer.dynamic_attribute_buffer = create_buffer(renderer.device, u32(render_group.attributes.capacity * size_of(asset.Vertex_Attributes)))
    dynamic_attributes: rawptr
    hr = renderer.dynamic_attribute_buffer->Map(0, &read_range, &dynamic_attributes)
    if hr < 0 do log.fatal("Failed to map D3D12 dynamic attributes buffer")
    render_group.attributes.memory = cast([^]asset.Vertex_Attributes)dynamic_attributes
    
    render_group.indices.capacity = 4096
    renderer.dynamic_index_buffer = create_buffer(renderer.device, u32(render_group.indices.capacity * size_of(u32)))
    dynamic_indices: rawptr
    hr = renderer.dynamic_index_buffer->Map(0, &read_range, &dynamic_indices)
    if hr < 0 do log.fatal("Failed to map D3D12 dynamic index buffer")
    render_group.indices.memory = cast([^]u32)dynamic_indices

    render_group.text_vertices.capacity = 4096
    renderer.text_buffer = create_buffer(renderer.device, u32(render_group.text_vertices.capacity * size_of(asset.Vertex_Text)))
    dynamic_text_vertices: rawptr
    hr = renderer.text_buffer->Map(0, &read_range, &dynamic_text_vertices)
    if hr < 0 do log.fatal("Failed to map D3D12 dynamic text vertices buffer")
    render_group.text_vertices.memory = cast([^]asset.Vertex_Text)dynamic_text_vertices

    // Constant buffers
    for i in 0..<N_BACK_BUFFERS {
        for id in Constant_Buffer_ID {
            constant_buffer := &renderer.constant_buffers[i][id]
            constant_buffer.type = constant_buffer_types[id]
            size := mem.align_forward_int(size_of(constant_buffer.type), 256)
            constant_buffer.buffer = create_buffer(renderer.device, u32(size))
            read_range := d3d12.RANGE{0, 0}
            constant_buffer.buffer->Map(0, &read_range, &constant_buffer.mapped_memory)
        }
    }

    // Per draw data
    heap_properties := d3d12.HEAP_PROPERTIES{ Type = .UPLOAD, }
    heap_desc := d3d12.RESOURCE_DESC{
        Dimension = .BUFFER,
        Alignment = 0,
        Width = mem.Megabyte,
        Height = 1,
        DepthOrArraySize = 1,
        MipLevels = 1,
        Format = .UNKNOWN,
        Layout = .ROW_MAJOR,
        SampleDesc = {
            Count = 1,
            Quality = 0,
        },
    }
    for &ring_buffer in renderer.ring_buffers {
        renderer.device->CreateCommittedResource(
            &heap_properties, 
            {}, 
            &heap_desc, 
            d3d12.RESOURCE_STATE_GENERIC_READ, 
            nil, 
            d3d12.IResource_UUID, 
            (^rawptr)(&ring_buffer.resource)
        )

        read_range := d3d12.RANGE{0, 0}
        hr = ring_buffer->Map(0, &read_range, &ring_buffer.mapped)
        if hr < 0 {
            log.fatal("Failed to map D3D12 ring buffer")
        }
    }

    // Shaders
    initialize_shader_compiler(&renderer.shader_compiler)

    for id in Shader_ID {
        if id == .None do continue
        initialize_shader(id, &renderer.shaders)
        compile_shader(&renderer.shader_compiler, &renderer.shaders[id])
    }

    // Pipelines
    create_root_signature(renderer, n_textures)
    for id in Shader_Pipeline_ID {
        initialize_pipeline(id, renderer)
    }

    renderer.frame = 0
}

create_texture :: proc(renderer: ^Renderer_Context, texture: ^asset.Texture, srv_handle: ^d3d12.CPU_DESCRIPTOR_HANDLE) -> d3d12.RESOURCE_BARRIER {
    format: dxgi.FORMAT
    switch texture.image.depth {
        case 8:
            switch texture.image.channels {
                case 1:    format = .R8_UNORM
                case 2:    format = .R8G8_UNORM
                case 3, 4: format = .R8G8B8A8_UNORM
            }
        case 16:
            switch texture.image.channels {
                case 1:    format = .R16_UNORM
                case 2:    format = .R16G16_UNORM
                case 3, 4: format = .R16G16B16A16_UNORM
            }
        case:
            log.fatal("Unsupported pixel bit depth:", texture.image.depth)
    }
    texture_desc := d3d12.RESOURCE_DESC{
        Dimension = .TEXTURE2D,
        Width = u64(texture.image.width),
        Height = u32(texture.image.height),
        DepthOrArraySize = 1,
        MipLevels = 1,
        Format = format,
        SampleDesc = { Count = 1, Quality = 0 },
        Layout = .UNKNOWN,
        Flags = {},
    }
    heap_props := d3d12.HEAP_PROPERTIES{ Type = .DEFAULT, }
    texture_buffer: ^d3d12.IResource
    hr := renderer.device->CreateCommittedResource(
        &heap_props,
        {},
        &texture_desc,
        { .COPY_DEST },
        nil,
        d3d12.IResource_UUID,
        (^rawptr)(&texture_buffer)
    )
    if hr < 0 do log.fatal("Failed to create texture resource")
    
    upload_buffer_size: u64
    subresource_footprint: d3d12.PLACED_SUBRESOURCE_FOOTPRINT
    n_rows: u32
    dst_pitch: u64
    renderer.device->GetCopyableFootprints(&texture_desc, 0, 1, 0, &subresource_footprint, &n_rows, &dst_pitch, &upload_buffer_size)

    upload_heap_props := d3d12.HEAP_PROPERTIES{ Type = .UPLOAD, }
    upload_desc := d3d12.RESOURCE_DESC{
        Dimension = .BUFFER,
        Width = upload_buffer_size,
        Height = 1,
        DepthOrArraySize = 1,
        MipLevels = 1,
        Format = .UNKNOWN,
        SampleDesc = { Count = 1, Quality = 0, },
        Layout = .ROW_MAJOR,
        Flags = {},
    }

    upload_buffer: ^d3d12.IResource
    renderer.device->CreateCommittedResource(
        &upload_heap_props,
        {},
        &upload_desc,
        d3d12.RESOURCE_STATE_GENERIC_READ,
        nil,
        d3d12.IResource_UUID,
        (^rawptr)(&upload_buffer)
    )

    mapped_memory: rawptr
    read_range := d3d12.RANGE{0, 0}
    upload_buffer->Map(0, &read_range, &mapped_memory)
    dst_mem := ([^]byte)(mapped_memory)
    src_mem := texture.image.pixels.buf[:]
    src_pitch := texture.image.width * texture.image.channels * texture.image.depth / 8

    if texture.image.channels == 3 {
        pixel_bytes := asset.get_bytes_per_pixel(texture.image)
        for row in 0..<n_rows {
            row_dst := dst_mem
            for col in 0..<texture.image.height {
                copy(row_dst[:pixel_bytes], src_mem[:pixel_bytes])
                row_dst = row_dst[4 * texture.image.depth / 8:]
                src_mem = src_mem[pixel_bytes:]
            }
            dst_mem = dst_mem[subresource_footprint.Footprint.RowPitch:]
        }
    }
    else {
        for row in 0..<n_rows {
            copy(dst_mem[:src_pitch], src_mem[:src_pitch])
            dst_mem = dst_mem[dst_pitch:]
            src_mem = src_mem[src_pitch:]
        }
    }

    upload_buffer->Unmap(0, nil)

    dst := d3d12.TEXTURE_COPY_LOCATION{
        Type = .SUBRESOURCE_INDEX,
        pResource = texture_buffer,
        SubresourceIndex = 0,
    }

    src := d3d12.TEXTURE_COPY_LOCATION{
        Type = .PLACED_FOOTPRINT,
        pResource = upload_buffer,
        PlacedFootprint = subresource_footprint,
    }

    renderer.command_list->CopyTextureRegion(&dst, 0, 0, 0, &src, nil)

    srv_desc := d3d12.SHADER_RESOURCE_VIEW_DESC{
        Format = format,
        ViewDimension = .TEXTURE2D,
        Shader4ComponentMapping = d3d12.DEFAULT_SHADER_4_COMPONENT_MAPPING,
        Texture2D = {
            MipLevels = 1,
            MostDetailedMip = 0,
        },
    }
    renderer.device->CreateShaderResourceView(texture_buffer, &srv_desc, srv_handle^)
    texture.gpu_index = renderer.srv_heap.descriptor_count
    srv_handle.ptr += uint(renderer.srv_heap.descriptor_size)
    renderer.srv_heap.descriptor_count += 1

    return {
        Type = .TRANSITION,
        Transition = {
            pResource = texture_buffer,
            StateBefore = {.COPY_DEST},
            StateAfter = {.PIXEL_SHADER_RESOURCE},
            Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
        },
    }
}

handle_resize :: proc(renderer: ^Renderer_Context, render_group: ^Render_Group) {
    screen_rect: w32.RECT
    w32.GetClientRect(renderer.window, &screen_rect)

    new_width := u32(screen_rect.right - screen_rect.left)
    new_height := u32(screen_rect.bottom - screen_rect.top)

    if new_width != render_group.width || new_height != render_group.height {
        render_group.width = new_width
        render_group.height = new_height
        
        // Wait for GPU to finish
        for &frame_context in renderer.frame_context {
            next_fence_value := frame_context.fence_value + 1
            renderer.command_queue->Signal(renderer.fence, next_fence_value)
            if renderer.fence->GetCompletedValue() < next_fence_value {
                renderer.fence->SetEventOnCompletion(next_fence_value, renderer.fence_event)
                w32.WaitForSingleObject(renderer.fence_event, w32.INFINITE)
            }
        }

        swap_chain_desc: dxgi.SWAP_CHAIN_DESC
        renderer.swap_chain->GetDesc(&swap_chain_desc)
        hr := renderer.swap_chain->ResizeBuffers(
            N_BACK_BUFFERS,
            new_width,
            new_height,
            swap_chain_desc.BufferDesc.Format,
            swap_chain_desc.Flags,
        )

        create_render_target_views(renderer)

        renderer.viewport.Width = f32(new_width)
        renderer.viewport.Height = f32(new_height)
        renderer.scissor_rect.right = i32(new_width)
        renderer.scissor_rect.bottom = i32(new_height)

        log.debug("Window resized to", new_width, "x", new_height)
    }
}

render :: proc(memory: ^Game_Memory) {
    renderer := &memory.renderer
    group := &memory.render_group
    input := &memory.input
    frame_index := renderer.frame % N_BACK_BUFFERS
    frame_context := &renderer.frame_context[frame_index]
    ring_buffer := &renderer.ring_buffers[frame_index]

    // Shader hot-reloading
    updated: [Shader_ID]bool
    for id in Shader_ID {
        if id == .None do continue
        updated[id] = update_if_newer_shader(&renderer.shader_compiler, &renderer.shaders[id])
    }

    for entry, pipeline_id in shader_pipeline_entries {
        for stage_id in entry.stage {
            if updated[stage_id] {
                initialize_pipeline(pipeline_id, renderer)
            }
        }
    }

    if renderer.fence->GetCompletedValue() < frame_context.fence_value {
        renderer.fence->SetEventOnCompletion(renderer.frame, renderer.fence_event)
        w32.WaitForSingleObject(renderer.fence_event, w32.INFINITE)
    }

    frame_context.command_alloc->Reset()
    renderer.command_list->Reset(frame_context.command_alloc, nil)

    renderer.command_list->RSSetViewports(1, &renderer.viewport)
    renderer.command_list->RSSetScissorRects(1, &renderer.scissor_rect)

    render_target_barrier := d3d12.RESOURCE_BARRIER{
        Type = .TRANSITION,
        Flags = {},
        Transition = {
            pResource = renderer.msaa_target,
            Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
            StateBefore = { .RESOLVE_SOURCE },
            StateAfter = { .RENDER_TARGET, },
        },
    }
    renderer.command_list->ResourceBarrier(1, &render_target_barrier)

    ring_buffer.offset = 0

    // Global constant buffer
    global_cb := Global_Constant_Buffer{
        projection = get_projection_matrix(f32(group.width), f32(group.height)),
        view = get_view_matrix(group.camera.angle, group.camera.pitch, group.camera.distance, group.camera.position),
        resolution = {f32(group.width), f32(group.height)},
        mouse = input.mouse.cursor,
        last_mouse = input.mouse.last_cursor,
    }
    set_constant_buffer(renderer, &global_cb)

    light_cb := Light_Constant_Buffer{
        direction = group.light.direction,
        color = group.light.color,
        camera_position = group.camera.position + group.camera.distance * radial_vector(group.camera.angle, group.camera.pitch),
        ambient = group.light.ambient,
        diffuse = group.light.diffuse,
    }
    set_constant_buffer(renderer, &light_cb)

    heaps := []^d3d12.IDescriptorHeap{
        renderer.srv_heap.heap,
        renderer.sampler_heap.heap,
    }
    renderer.command_list->SetDescriptorHeaps(2, raw_data(heaps))

    rtv_handle := get_descriptor_heap_element(&renderer.rtv_heap, 0)
    dsv_handle := get_descriptor_heap_element(&renderer.dsv_heap, 0)
    renderer.command_list->OMSetRenderTargets(1, &rtv_handle, false, &dsv_handle)
    renderer.command_list->SetGraphicsRootSignature(renderer.root_signature)
    global := renderer.constant_buffers[frame_index][.Global]
    light := renderer.constant_buffers[frame_index][.Light]
    renderer.command_list->SetGraphicsRootConstantBufferView(0, global.buffer->GetGPUVirtualAddress())
    renderer.command_list->SetGraphicsRootConstantBufferView(1, light.buffer->GetGPUVirtualAddress())

    clear_color := [4]f32{ 0, 0, 0, 0}
    renderer.command_list->ClearRenderTargetView(rtv_handle, &clear_color, 0, nil)
    renderer.command_list->ClearDepthStencilView(dsv_handle, { .DEPTH, .STENCIL }, 1.0, 0, 0, nil)

    for entry in group.commands {
        pipeline := renderer.shader_pipelines[entry.pipeline]

        per_draw_data := Per_Draw_Data{
            transform = linalg.transpose(entry.transform),
            normal = linalg.matrix4_from_matrix3(linalg.inverse(linalg.matrix3_from_matrix4(entry.transform))),
            material_color = entry.color,
        }
        if entry.texture != nil {
            per_draw_data.color_texture_index = u32(entry.texture.gpu_index)
        }
        if entry.material != nil {
            per_draw_data.material_color = entry.material.base_color * entry.color
            per_draw_data.metallic = entry.material.metallic
            per_draw_data.roughness = entry.material.roughness
        }
        per_draw_data_address := allocate_from_ring_buffer(ring_buffer, per_draw_data)
        renderer.command_list->SetGraphicsRootConstantBufferView(2, per_draw_data_address)
        renderer.command_list->SetPipelineState(pipeline)
        topology := D3D12_get_primitive_topology(entry.topology)
        renderer.command_list->IASetPrimitiveTopology(topology)

        n_buffers: u32 = 1
        positions_address: d3d12.GPU_VIRTUAL_ADDRESS
        indices_address: d3d12.GPU_VIRTUAL_ADDRESS
        extra_address: d3d12.GPU_VIRTUAL_ADDRESS
        extra_size: int
        extra_stride: int
        if entry.dynamic_buffer {
            positions_address = renderer.dynamic_position_buffer->GetGPUVirtualAddress() + 
                u64(entry.positions.offset * size_of(asset.Vertex_Position))
            if entry.attributes.count > 0 {
                n_buffers = 2
                extra_address = renderer.dynamic_attribute_buffer->GetGPUVirtualAddress() + 
                    u64(entry.attributes.offset * size_of(asset.Vertex_Attributes))
                extra_size = entry.attributes.count * size_of(asset.Vertex_Attributes)
                extra_stride = size_of(asset.Vertex_Attributes)
            }
            else if entry.text_vertices.count > 0 {
                n_buffers = 2
                extra_address = renderer.dynamic_attribute_buffer->GetGPUVirtualAddress() + 
                    u64(entry.text_vertices.offset * size_of(asset.Vertex_Text))
                extra_size = entry.text_vertices.count * size_of(asset.Vertex_Text)
                extra_stride = size_of(asset.Vertex_Text)
            }

            if entry.indices.count > 0 {
                indices_address = renderer.dynamic_index_buffer->GetGPUVirtualAddress() + 
                    u64(entry.indices.offset * size_of(u32))
            }
        }
        else {
            positions_address = renderer.static_position_buffer->GetGPUVirtualAddress() + 
                u64(entry.positions.offset * size_of(asset.Vertex_Position))
            if entry.attributes.count > 0 {
                n_buffers = 2
                extra_address = renderer.static_attribute_buffer->GetGPUVirtualAddress() + 
                    u64(entry.attributes.offset * size_of(asset.Vertex_Attributes))
                extra_size = entry.attributes.count * size_of(asset.Vertex_Attributes)
                extra_stride = size_of(asset.Vertex_Attributes)
            }

            if entry.indices.count > 0 {
                indices_address = renderer.static_index_buffer->GetGPUVirtualAddress() + 
                    u64(entry.indices.offset * size_of(u32))
            }
        }
        
        vertex_buffers := []d3d12.VERTEX_BUFFER_VIEW{
            {
                BufferLocation = positions_address,
                SizeInBytes = u32(entry.positions.count * size_of(asset.Vertex_Position)),
                StrideInBytes = size_of(asset.Vertex_Position),
            },
            {
                BufferLocation = extra_address,
                    SizeInBytes = u32(entry.attributes.count * size_of(asset.Vertex_Attributes)),
                    StrideInBytes = size_of(asset.Vertex_Attributes),
            },
        }
        
        renderer.command_list->IASetVertexBuffers(0, n_buffers, raw_data(vertex_buffers))

        if entry.indices.count > 0 {
            index_buffer_view := d3d12.INDEX_BUFFER_VIEW{
                BufferLocation = indices_address,
                Format = .R32_UINT,
                SizeInBytes = u32(entry.indices.count * size_of(u32)),
            }
            renderer.command_list->IASetIndexBuffer(&index_buffer_view)
            renderer.command_list->DrawIndexedInstanced(u32(entry.indices.count), 1, 0, 0, 0)
        }
        else {
            renderer.command_list->DrawInstanced(u32(entry.positions.count), 1, 0, 0)
        }
    }

    back_buffer := renderer.render_targets[frame_index]
    resolve_barriers := []d3d12.RESOURCE_BARRIER{
        {
            Type = .TRANSITION,
            Transition = {
                pResource = renderer.msaa_target,
                Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
                StateBefore = { .RENDER_TARGET },
                StateAfter = { .RESOLVE_SOURCE },
            },
        },
        {
            Type = .TRANSITION,
            Transition = {
                pResource = back_buffer,
                Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
                StateBefore = d3d12.RESOURCE_STATE_PRESENT,
                StateAfter = { .RESOLVE_DEST },
            },
        },
    }
    renderer.command_list->ResourceBarrier(2, raw_data(resolve_barriers))

    renderer.command_list->ResolveSubresource(
        back_buffer, 0,
        renderer.msaa_target, 0,
        .R8G8B8A8_UNORM
    )

    present_barrier := d3d12.RESOURCE_BARRIER{
        Type = .TRANSITION,
        Transition = {
            pResource = back_buffer,
            Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
            StateBefore = { .RESOLVE_DEST },
            StateAfter = d3d12.RESOURCE_STATE_PRESENT,
        },
    }
    renderer.command_list->ResourceBarrier(1, &present_barrier)

    renderer.command_list->Close()

    list := []^d3d12.ICommandList{
        renderer.command_list
    }
    renderer.command_queue->ExecuteCommandLists(1, raw_data(list))

    renderer.swap_chain->Present(0, {})
    renderer.frame += 1
    frame_context.fence_value = renderer.frame

    hr := renderer.command_queue->Signal(renderer.fence, renderer.frame)
    if hr < 0 do log.fatal("Failed to signal fence")

    asset.clear_vertex_buffer(&group.positions)
    asset.clear_vertex_buffer(&group.attributes)
    asset.clear_vertex_buffer(&group.indices)
    asset.clear_vertex_buffer(&group.text_vertices)
}

}