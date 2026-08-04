package asset

import "core:mem"
import "core:log"
import "core:slice"
import "core:bytes"
import img "core:image"


extract_from_memory :: proc(memory: []byte, $T: typeid) -> T {
    result, ok := slice.to_type(memory, T)
    if !ok do log.fatal("Failed to extract type '", typeid_of(T), "' from memory", sep = "")
    return result
}

dump_to_memory :: proc(memory: []byte, data: $T) {
    dst := (^T)(raw_data(memory))
    dst^ = data
}

get_serialized_size_string :: proc(s: string) -> int {
    return size_of(u32) + len(s)
}

serialize_string :: proc(memory: []byte, s: string) -> int {
    size := get_serialized_size_string(s)
    dump_to_memory(memory, u32(len(s)))
    bytes_copied := copy(memory[4:], s)
    assert(bytes_copied + 4 == size)
    return size
}

deserialize_string :: proc(memory: []byte) -> string {
    length := extract_from_memory(memory, u32)
    return string(memory[4:4+length])
}

get_serialized_size_slice :: proc(s: $T/[]$E) -> int {
    slice_size := slice.size(s)
    return size_of(u32) + slice_size
}

serialize_slice :: proc(memory: []byte, s: $T/[]$E) -> int {
    block := memory
    size := get_serialized_size_slice(s)
    length := u32(len(s))
    dump_to_memory(block, length)
    copied := copy(block[4:size], slice.to_bytes(s))
    assert(copied + 4 == size)
    return size
}

deserialize_slice :: proc(memory: []byte, $T: typeid/[]$E) -> []E {
    length := extract_from_memory(memory, u32)
    start := cast([^]E)raw_data(memory[4:])
    return start[:length]
}

widen_to_u32 :: proc(out: []u32, src: [^]$T, count: int) {
    for i in 0..<count {
        out[i] = u32(src[i])
    }
}

get_serialized_size_image :: proc(image: ^img.Image) -> int {
    return 4 * size_of(int) + image.width * image.height * image.depth * image.channels / 8
}

serialize_image :: proc(allocator: mem.Allocator, image: ^img.Image) -> int {
    size := get_serialized_size_image(image)
    block := make([]byte, size, allocator)

    dump_to_memory(block, image.width)
    block = block[size_of(int):]
    dump_to_memory(block, image.height)
    block = block[size_of(int):]
    dump_to_memory(block, image.channels)
    block = block[size_of(int):]
    dump_to_memory(block, image.depth)
    block = block[size_of(int):]
    pixels_size := image.width * image.height * image.depth * image.channels / 8

    copy(block[:pixels_size], image.pixels.buf[:])

    return size
}

deserialize_image :: proc(memory: []byte) -> (^img.Image, int) {
    result := new(img.Image)
    header := slice.reinterpret([]int, memory[:4*size_of(int)])
    result^ = {
        width    = header[0],
        height   = header[1],
        channels = header[2],
        depth    = header[3],
    }
    block := memory[4*size_of(int):]
    pixels_size := result.width * result.height * result.depth * result.channels / 8
    bytes.buffer_init(&result.pixels, block[:pixels_size])

    return result, get_serialized_size_image(result)
}
