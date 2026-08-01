package common

import "core:log"
import "core:slice"
import "base:runtime"


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
    size := get_serialized_size_slice(s)
    length := u32(len(s))
    dump_to_memory(memory, length)
    copied := copy(memory[4:], slice.to_bytes(s))
    assert(copied + 4 == size)
    return size
}

deserialize_slice :: proc(memory: []byte, $T: typeid/[]$E) -> []E {
    length := extract_from_memory(memory, u32)
    start := cast([^]E)raw_data(memory[4:])
    return start[:length]
}
