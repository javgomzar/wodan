package asset

import "core:log"
import "core:slice"
import "core:strings"


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

serialize_string :: proc(memory: []byte, s: string) -> (size: int) {
    size = get_serialized_size_string(s)
    dump_to_memory(memory, u32(len(s)))
    bytes_copied := copy(memory[4:], s)
    assert(bytes_copied + 4 == size)
    return
}

deserialize_string :: proc(memory: []byte) -> (result: string, size: int) {
    length := extract_from_memory(memory, u32)
    block := memory[size_of(u32):]
    size += size_of(u32)
    result = strings.clone(string(block[:length]))
    size += int(length)
    return
}

get_serialized_size_slice :: proc(s: $T/[]$E) -> (size: int) {
    size += size_of(u32)
    size += slice.size(s)
    return
}

serialize_slice :: proc(memory: []byte, s: $T/[]$E) -> (size: int) {
    size = get_serialized_size_slice(s)
    length := u32(len(s))
    dump_to_memory(memory, length)
    if length > 0 {
        copied := copy(memory[4:size], slice.to_bytes(s))
        assert(copied + 4 == size)
    }
    return
}

deserialize_slice :: proc(memory: []byte, $T: typeid/[]$E) -> (result: []E, size: int) {
    length := extract_from_memory(memory, u32)
    size += size_of(u32)
    block := memory[size_of(u32):]
    result = make([]E, length)
    raw := cast([^]E)raw_data(block)
    copy(result, raw[:length])
    size += int(length) * size_of(E)
    return
}

widen_to_u32 :: proc(out: []u32, src: [^]$T, count: int) {
    for i in 0..<count {
        out[i] = u32(src[i])
    }
}
