package common

import w32 "core:sys/windows"
import "vendor:directx/d3d12"
import "vendor:directx/dxgi"
import "core:slice"
import "core:mem"
import "core:log"


when ODIN_OS == .Windows {

N_BACK_BUFFERS  :: 3
N_DEPTH_BUFFERS :: 1

D3D12_Frame_Context :: struct {
    command_alloc: ^d3d12.ICommandAllocator,
    fence_value:   u64,
}

D3D12_get_primitive_topology :: proc(primitive: Primitive) -> d3d12.PRIMITIVE_TOPOLOGY {
    switch primitive {
        case .Point:          return .POINTLIST
        case .Lines:          return .LINELIST
        case .Line_Loop:      return .LINESTRIP
        case .Line_Strip:     return .LINESTRIP
        case .Triangles:      return .TRIANGLELIST
        case .Triangle_Strip: return .TRIANGLESTRIP
        case .Triangle_Fan:   return .TRIANGLESTRIP
        case:
            log.fatal("Invalid primitive topology", primitive)
    }
    return .POINTLIST
}

constant_buffer_id :: enum {
    Global
}

Renderer_Context :: struct {
    frame:               u64,
    window:              w32.HWND,
    device:              ^d3d12.IDevice,
    fence:               ^d3d12.IFence,
    fence_event:         w32.HANDLE,
    swap_chain:          ^dxgi.ISwapChain1,
    command_queue:       ^d3d12.ICommandQueue,
    command_list:        ^d3d12.IGraphicsCommandList,
    frame_context:       [N_BACK_BUFFERS]D3D12_Frame_Context,
    rtv_heap:            ^d3d12.IDescriptorHeap,
    dsv_heap:            ^d3d12.IDescriptorHeap,
    rtv_descriptor_size: u32,
    dsv_descriptor_size: u32,
    render_targets:      [N_BACK_BUFFERS]^d3d12.IResource,
    depth_stencils:      [N_DEPTH_BUFFERS]^d3d12.IResource,
    position_buffer:     ^d3d12.IResource,
    attribute_buffer:    ^d3d12.IResource,
    index_buffer:        ^d3d12.IResource,
    shader_compiler:     DXC_Compiler,
    shaders:             [Shader_Id]DXC_Shader,
    shader_pipelines:    [Shader_Pipeline_Id]Shader_Pipeline,
    constant_buffers:    [N_BACK_BUFFERS][Constant_Buffer_Id]Constant_Buffer,
}

EVENT_ALL_ACCESS :: w32.DWORD(0x1F0003)

initialize_renderer :: proc(asset_manager: ^Game_Asset_Manager, renderer: ^Renderer_Context, width: u32, height: u32) {
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
        log.fatal("Failed to create DXGI Factory.")
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
        log.fatal("No D3D12-capable hardware adapter found")
    }
    defer adapter->Release()

	hr = d3d12.CreateDevice((^dxgi.IUnknown)(adapter), ._12_0, d3d12.IDevice_UUID, (^rawptr)(&renderer.device))
	if hr < 0 {
		log.fatal("Failed to create D3D12 device")
	}

    renderer.device->CreateFence(0, {}, d3d12.IFence_UUID, (^rawptr)(&renderer.fence))

    queue_desc := d3d12.COMMAND_QUEUE_DESC{ Type = .DIRECT, NodeMask = 0, }
    hr = renderer.device->CreateCommandQueue(
        &queue_desc, 
        d3d12.ICommandQueue_UUID, 
        (^rawptr)(&renderer.command_queue)
    )
    if hr < 0 {
        log.fatal("Failed to create D3D12 command queue")
    }

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
    
    hr = renderer.device->CreateCommandList(
        0, 
        .DIRECT, 
        renderer.frame_context[0].command_alloc, 
        nil, 
        d3d12.IGraphicsCommandList_UUID, 
        (^rawptr)(&renderer.command_list)
    )
    if hr < 0 {
        log.fatal("Failed to create D3D12 command list")
    }

    swap_chain_desc := dxgi.SWAP_CHAIN_DESC1{
        Width = width,
        Height = height,
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
        log.fatal("Failed to create DXGI swap chain")
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
        log.fatal("Failed to create RTV descriptor heap")
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
        log.fatal("Failed to create DSV descriptor heap")
    }
    renderer.dsv_descriptor_size = renderer.device->GetDescriptorHandleIncrementSize(.DSV)

    renderer.frame = 0
    rtv_handle: d3d12.CPU_DESCRIPTOR_HANDLE
    renderer.rtv_heap->GetCPUDescriptorHandleForHeapStart(&rtv_handle)
    for i in 0..<N_BACK_BUFFERS {
        hr = renderer.swap_chain->GetBuffer(u32(i), d3d12.IResource_UUID, (^rawptr)(&renderer.render_targets[i]))
        if hr < 0 {
            log.fatal("Failed to get swap chain buffers")
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
            Width = u64(width),
            Height = height,
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
            log.fatal("Failed to create depth stencil buffer")
        }

        renderer.device->CreateDepthStencilView(renderer.depth_stencils[i], nil, dsv_handle)
        dsv_handle.ptr += uint(renderer.dsv_descriptor_size)
    }

    // Vertex buffers
    position_count: u32
    attribute_count: u32
    index_count: u32

    // RGB triangle
    position_count += 3
    attribute_count += 3

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

    renderer.position_buffer = create_buffer(renderer.device, position_count * size_of(Vertex_Position))
    renderer.attribute_buffer = create_buffer(renderer.device, attribute_count * size_of(Vertex_Attributes))
    renderer.index_buffer = create_buffer(renderer.device, index_count * size_of(u32))

    mapped_position: rawptr = nil
    mapped_attribute: rawptr = nil
    mapped_index: rawptr = nil
    read_range := d3d12.RANGE{0, 0}
    
    if hr = renderer.position_buffer->Map(0, &read_range, &mapped_position);   hr < 0 do log.fatal("Failed to map D3D12 position buffer")
    if hr = renderer.attribute_buffer->Map(0, &read_range, &mapped_attribute); hr < 0 do log.fatal("Failed to map D3D12 attribute buffer")
    if hr = renderer.index_buffer->Map(0, &read_range, &mapped_index);         hr < 0 do log.fatal("Failed to map D3D12 index buffer")

    position_offset: int
    attribute_offset: int
    index_offset: int
    position_ptr := cast([^]Vertex_Position)mapped_position
    attribute_ptr := cast([^]Vertex_Attributes)mapped_attribute
    index_ptr := cast([^]u32)mapped_index

    // RGB triangle
    copy(position_ptr[:3], triangle_positions[:])
    position_ptr = position_ptr[3:]
    position_offset += 3

    copy(attribute_ptr[:3], triangle_attributes[:])
    attribute_ptr = attribute_ptr[3:]
    attribute_offset += 3

    // Meshes
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
    }
    
    renderer.position_buffer->Unmap(0, nil)
    renderer.attribute_buffer->Unmap(0, nil)
    renderer.index_buffer->Unmap(0, nil)

    // Constant buffers
    for i in 0..<N_BACK_BUFFERS {
        for id in Constant_Buffer_Id {
            constant_buffer := &renderer.constant_buffers[i][id]
            constant_buffer.type = constant_buffer_types[id]
            size := mem.align_forward_int(size_of(constant_buffer.type), 256)
            constant_buffer.buffer = create_buffer(renderer.device, u32(size))
            read_range := d3d12.RANGE{0, 0}
            constant_buffer.buffer->Map(0, &read_range, &constant_buffer.mapped_memory)
        }
    }

    // Shaders
    initialize_shader_compiler(&renderer.shader_compiler)

    for id in Shader_Id {
        if id == .None do continue
        initialize_shader(id, &renderer.shaders)
        compile_shader(&renderer.shader_compiler, &renderer.shaders[id])
    }

    // Pipelines
    for &pipeline, id in renderer.shader_pipelines {
        initialize_pipeline(id, renderer)
    }

    renderer.command_list->Close()
}

create_buffer :: proc(device: ^d3d12.IDevice, size: u32, memory: rawptr = nil) -> ^d3d12.IResource {
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
        log.fatal("Failed to create D3D12 generic buffer")
    }

    if memory != nil {
        mapped_data: rawptr = nil
        read_range := d3d12.RANGE{0, 0}

        hr = upload_buffer->Map(0, &read_range, &mapped_data)
        if hr < 0 {
            log.fatal("Failed to map D3D12 generic buffer")
        }
        mem.copy(mapped_data, memory, int(size))
        upload_buffer->Unmap(0, nil)
    }

    return upload_buffer
}

render :: proc(memory: ^Game_Memory) {
    renderer := &memory.renderer
    group := &memory.render_group
    input := &memory.input
    frame_index := renderer.frame % N_BACK_BUFFERS
    frame_context := &renderer.frame_context[frame_index]

    // Shader hot-reloading
    updated: [Shader_Id]bool
    for id in Shader_Id {
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

    viewport := d3d12.VIEWPORT{
        TopLeftX = 0.0,
        TopLeftY = 0.0,
        Width = f32(group.width),
        Height = f32(group.height),
        MinDepth = 0.0,
        MaxDepth = 1.0
    }
    renderer.command_list->RSSetViewports(1, &viewport)

    scissor_rect :=  d3d12.RECT{
        left = 0,
        top = 0,
        right = i32(group.width),
        bottom = i32(group.height),
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
    global_cb := Global_Constant_Buffer{
        projection = get_projection_matrix(f32(group.width), f32(group.height)),
        view = get_view_matrix(get_camera_basis(group.camera.angle, group.camera.pitch), group.camera.distance, group.camera.position),
        resolution = {f32(group.width), f32(group.height)},
        mouse = input.mouse.cursor,
        last_mouse = input.mouse.last_cursor,
    }
    set_constant_buffer(renderer, &global_cb)

    transform_cb := Transform_Constant_Buffer{
        transform = 1,
        normal = 1,
    }
    set_constant_buffer(renderer, &transform_cb)

    renderer.command_list->OMSetRenderTargets(1, &rtv_handle, false, &dsv_handle)
    
    for entry in group.commands {
        switch entry.type {
            case .Clear:
                color := [4]f32{ entry.color.r, entry.color.g, entry.color.b, 1.0}
                renderer.command_list->ClearRenderTargetView(rtv_handle, &color, 0, nil)
                renderer.command_list->ClearDepthStencilView(dsv_handle, { .DEPTH, .STENCIL }, 1.0, 0, 0, nil)
            case .Mesh:
                pipeline := &renderer.shader_pipelines[entry.pipeline]
                renderer.command_list->SetGraphicsRootSignature(pipeline.root_signature)

                #partial switch entry.pipeline {
                    case .Mesh_Pipeline:
                        global := renderer.constant_buffers[frame_index][.Global]
                        renderer.command_list->SetGraphicsRootConstantBufferView(0, global.buffer->GetGPUVirtualAddress())
                        transform := renderer.constant_buffers[frame_index][.Transform]
                        renderer.command_list->SetGraphicsRootConstantBufferView(1, transform.buffer->GetGPUVirtualAddress())
                }

                // renderer.command_list->SetGraphicsRootConstantBufferView(0, renderer.global_buffers[frame_index]->GetGPUVirtualAddress())
                renderer.command_list->SetPipelineState(pipeline.state)
                primitive := D3D12_get_primitive_topology(entry.primitive)
                renderer.command_list->IASetPrimitiveTopology(primitive)
                
                n_buffers: u32 = 1
                vertex_buffers := []d3d12.VERTEX_BUFFER_VIEW{
                    {
                        BufferLocation = renderer.position_buffer->GetGPUVirtualAddress() + u64(entry.position_offset * size_of(Vertex_Position)),
                        SizeInBytes = u32(entry.position_count * size_of(Vertex_Position)),
                        StrideInBytes = size_of(Vertex_Position),
                    },
                    {
                        BufferLocation = renderer.attribute_buffer->GetGPUVirtualAddress() + u64(entry.attribute_offset * size_of(Vertex_Attributes)),
                        SizeInBytes = u32(entry.attribute_count * size_of(Vertex_Attributes)),
                        StrideInBytes = size_of(Vertex_Attributes),
                    },
                }

                if entry.attribute_count > 0 {
                    n_buffers = 2
                }
                renderer.command_list->IASetVertexBuffers(0, n_buffers, raw_data(vertex_buffers))

                if entry.index_count > 0 {
                    index_buffer_view := d3d12.INDEX_BUFFER_VIEW{
                        BufferLocation = renderer.index_buffer->GetGPUVirtualAddress() + u64(entry.index_offset * size_of(u32)),
                        Format = .R32_UINT,
                        SizeInBytes = u32(entry.index_count * size_of(u32)),
                    }
                    renderer.command_list->IASetIndexBuffer(&index_buffer_view)
                    renderer.command_list->DrawIndexedInstanced(u32(entry.index_count), 1, 0, 0, 0)
                }
                else {
                    renderer.command_list->DrawInstanced(u32(entry.position_count), 1, 0, 0)
                }
        }
    }

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
        log.fatal("Failed to signal fence")
    }
}

}