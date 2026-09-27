package asset

import "core:log"


Vertex_Position :: distinct [3]f32

Vertex_Attributes :: struct #align(16) {
    normal:  [3]f32,
    texture: [2]f32,
    color:   [4]f32,
}

Vertex_Text :: struct {
    pen:   [2]f32,
    depth: f32,
    size:  f32,
    color: [4]f32,
}

Vertex_Joint :: struct {
    joints:  [4]u32,
    weights: [4]f32,
}

Vertex_Buffer :: struct($T: typeid) {
    capacity: int,
    count: int,
    memory: [^]T,
}

Vertex_Buffer_Entry :: struct($T: typeid) {
    count: int,
    offset: int,
    memory: []T,
}

static_vertices :: proc(count: int, offset: int, $T: typeid) -> (result: Vertex_Buffer_Entry(T)) {
    return Vertex_Buffer_Entry(T){
        count = count, offset = offset, memory = {},
    }
}

push_vertices :: proc(buffer: ^Vertex_Buffer($T), count: int) -> (result: Vertex_Buffer_Entry(T)) {
    if buffer.count + count >= buffer.capacity {
        log.fatal("Buffer", typeid_of(T), "overflowing its capacity")
    }
    result.count = count
    result.offset = buffer.count
    result.memory = buffer.memory[buffer.count:buffer.count + count]
    buffer.count += count
    return
}

clear_vertex_buffer :: proc(buffer: ^Vertex_Buffer($T)) {
    buffer.count = 0
}
