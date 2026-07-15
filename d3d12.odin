package main

import w32 "core:sys/windows"
import "vendor:directx/d3d12"
import "vendor:directx/dxgi"
import "core:math"


N_BACK_BUFFERS  :: 3
N_DEPTH_BUFFERS :: 1

d3d12_renderer_context :: struct {
    device:              ^d3d12.IDevice,
    fence:               ^d3d12.IFence,
    swap_chain:          ^dxgi.ISwapChain1,
    command_queue:       ^d3d12.ICommandQueue,
    command_alloc:       ^d3d12.ICommandAllocator,
    command_list:        ^d3d12.IGraphicsCommandList,
    rtv_heap:            ^d3d12.IDescriptorHeap,
    dsv_heap:            ^d3d12.IDescriptorHeap,
    rtv_descriptor_size: u32,
    dsv_descriptor_size: u32,
    render_targets:      [N_BACK_BUFFERS]^d3d12.IResource,
    depth_stencils:      [N_DEPTH_BUFFERS]^d3d12.IResource,
    frame:               u64,
}

@(private="file")
renderer_context: d3d12_renderer_context

initiate_renderer :: proc(window: w32.HWND, width: u32, height: u32) {
    hr: w32.HRESULT

    factory: ^dxgi.IFactory4
    flags: dxgi.CREATE_FACTORY

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

	hr = d3d12.CreateDevice((^dxgi.IUnknown)(adapter), ._12_0, d3d12.IDevice_UUID, (^rawptr)(&renderer_context.device))
	if hr < 0 {
		log(.Fatal, "Failed to create D3D12 device")
	}

    renderer_context.device->CreateFence(0, {}, d3d12.IFence_UUID, (^rawptr)(&renderer_context.fence))

    queue_desc := d3d12.COMMAND_QUEUE_DESC{ Type = .DIRECT }
    hr = renderer_context.device->CreateCommandQueue(
        &queue_desc, 
        d3d12.ICommandQueue_UUID, 
        (^rawptr)(&renderer_context.command_queue)
    )
    if hr < 0 {
        log(.Fatal, "Failed to create D3D12 command queue")
    }

    hr = renderer_context.device->CreateCommandAllocator(
        .DIRECT, 
        d3d12.ICommandAllocator_UUID, 
        (^rawptr)(&renderer_context.command_alloc)
    )
    if hr < 0 {
        log(.Fatal, "Failed to create D3D12 command queue")
    }
    
    hr = renderer_context.device->CreateCommandList(
        0, 
        .DIRECT, 
        renderer_context.command_alloc, 
        nil, 
        d3d12.IGraphicsCommandList_UUID, 
        (^rawptr)(&renderer_context.command_list)
    )
    if hr < 0 {
        log(.Fatal, "Failed to create D3D12 command list")
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

    hr = factory->CreateSwapChainForHwnd(renderer_context.command_queue, window, &swap_chain_desc, nil, nil, &renderer_context.swap_chain)
    if hr < 0 {
        log(.Fatal, "Failed to create DXGI swap chain")
    }

    rtv_heap_desc := d3d12.DESCRIPTOR_HEAP_DESC{
        NumDescriptors = N_BACK_BUFFERS,
        Type           = .RTV,
        Flags          = {},
    }
    hr = renderer_context.device->CreateDescriptorHeap(
        &rtv_heap_desc, 
        d3d12.IDescriptorHeap_UUID, 
        (^rawptr)(&renderer_context.rtv_heap)
    )
    if hr < 0 {
        log(.Fatal, "Failed to create RTV descriptor heap")
    }
    renderer_context.rtv_descriptor_size = renderer_context.device->GetDescriptorHandleIncrementSize(.RTV)

    dsv_heap_desc := d3d12.DESCRIPTOR_HEAP_DESC{
        NumDescriptors = N_DEPTH_BUFFERS,
        Type           = .DSV,
        Flags          = {},
    }
    hr = renderer_context.device->CreateDescriptorHeap(
        &dsv_heap_desc, 
        d3d12.IDescriptorHeap_UUID, 
        (^rawptr)(&renderer_context.dsv_heap)
    )
    if hr < 0 {
        log(.Fatal, "Failed to create DSV descriptor heap")
    }
    renderer_context.dsv_descriptor_size = renderer_context.device->GetDescriptorHandleIncrementSize(.DSV)

    renderer_context.frame = 0
    rtv_handle: d3d12.CPU_DESCRIPTOR_HANDLE
    renderer_context.rtv_heap->GetCPUDescriptorHandleForHeapStart(&rtv_handle)
    for i in 0..<N_BACK_BUFFERS {
        hr = renderer_context.swap_chain->GetBuffer(u32(i), d3d12.IResource_UUID, (^rawptr)(&renderer_context.render_targets[i]))
        if hr < 0 {
            log(.Fatal, "Failed to get swap chain buffers")
        }
        renderer_context.device->CreateRenderTargetView(renderer_context.render_targets[i], nil, rtv_handle)
        rtv_handle.ptr += uint(renderer_context.rtv_descriptor_size)
    }

    dsv_handle: d3d12.CPU_DESCRIPTOR_HANDLE
    renderer_context.dsv_heap->GetCPUDescriptorHandleForHeapStart(&dsv_handle)
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
        hr = renderer_context.device->CreateCommittedResource(
            &heap_props, 
            {}, 
            &resource_desc, 
            { .DEPTH_WRITE }, 
            &clear, 
            d3d12.IResource_UUID, 
            (^rawptr)(&renderer_context.depth_stencils[i])
        )
        if hr < 0 {
            log(.Fatal, "Failed to create depth stencil buffer")
        }

        renderer_context.device->CreateDepthStencilView(renderer_context.depth_stencils[i], nil, dsv_handle)
        dsv_handle.ptr += uint(renderer_context.dsv_descriptor_size)
    }

    renderer_context.command_list->Close()
}

render :: proc(width: f32, height: f32) {
    renderer_context.command_alloc->Reset()
    renderer_context.command_list->Reset(renderer_context.command_alloc, nil)

    viewport := d3d12.VIEWPORT{
        TopLeftX = 0.0,
        TopLeftY = 0.0,
        Width = width,
        Height = height,
        MinDepth = 0.0,
        MaxDepth = 1.0
    }
    renderer_context.command_list->RSSetViewports(1, &viewport)

    scissor_rect :=  d3d12.RECT{
        left = 0,
        top = 0,
        right = i32(width),
        bottom = i32(height),
    }
    renderer_context.command_list->RSSetScissorRects(1, &scissor_rect)

    back_buffer := renderer_context.render_targets[renderer_context.frame % N_BACK_BUFFERS]
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
    renderer_context.command_list->ResourceBarrier(1, &barrier)

    rtv_handle: d3d12.CPU_DESCRIPTOR_HANDLE
    rtv_descriptor_size := renderer_context.device->GetDescriptorHandleIncrementSize(.RTV)
    renderer_context.rtv_heap->GetCPUDescriptorHandleForHeapStart(&rtv_handle)
    rtv_handle.ptr += uint(renderer_context.frame % N_BACK_BUFFERS) * uint(rtv_descriptor_size)
    dsv_handle: d3d12.CPU_DESCRIPTOR_HANDLE
    renderer_context.dsv_heap->GetCPUDescriptorHandleForHeapStart(&dsv_handle)

    clear_color := [4]f32{0.5 + 0.5*math.sin(f32(renderer_context.frame) / 100.0), 0.0, 0.5, 1.0}
    renderer_context.command_list->ClearRenderTargetView(rtv_handle, &clear_color, 0, nil)
    renderer_context.command_list->ClearDepthStencilView(dsv_handle, { .DEPTH, .STENCIL }, 1.0, 0, 0, nil)
    
    renderer_context.command_list->OMSetRenderTargets(1, &rtv_handle, false, &dsv_handle)

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
    renderer_context.command_list->ResourceBarrier(1, &barrier)
    renderer_context.command_list->Close()

    list := []^d3d12.ICommandList{
        renderer_context.command_list
    }
    renderer_context.command_queue->ExecuteCommandLists(1, raw_data(list))

    renderer_context.swap_chain->Present(0, {})
    renderer_context.frame += 1

    hr := renderer_context.command_queue->Signal(renderer_context.fence, renderer_context.frame)
    if hr < 0 {
        log(.Fatal, "Failed to signal fence")
    }

    if renderer_context.fence->GetCompletedValue() < renderer_context.frame {
        hevent := w32.CreateEventExW(nil, "GPU fence", 0, EVENT_ALL_ACCESS)
        renderer_context.fence->SetEventOnCompletion(renderer_context.frame, hevent)
        w32.WaitForSingleObject(hevent, w32.INFINITE)
        w32.CloseHandle(hevent)
    }
}