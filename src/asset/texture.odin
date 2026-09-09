package asset


Texture :: struct {
    id:        ID,
    width:     i32,
    height:    i32,
    channels:  i32,
    pixels:    []byte,
    link:      ^Texture,
}

get_serialized_size_texture :: proc(texture: ^Texture) -> int {
    return 3 * size_of(i32) + get_serialized_size_slice(texture.pixels)
}

serialize_texture :: proc(memory: []byte, texture: ^Texture) -> (size: int) {
    dump_to_memory(memory, texture.width)
    block := memory[size_of(i32):]
    size += size_of(i32)
    dump_to_memory(block, texture.height)
    block = block[size_of(i32):]
    size += size_of(i32)
    dump_to_memory(block, texture.channels)
    block = block[size_of(i32):]
    size += size_of(i32)
    size += serialize_slice(memory, texture.pixels)

    return
}

deserialize_texture :: proc(texture: ^Texture, memory: []byte) -> (size: int) {
    texture.width = extract_from_memory(memory, i32)
    block := memory[size_of(i32):]
    size += size_of(i32)
    texture.height = extract_from_memory(memory, i32)
    block = memory[size_of(i32):]
    size += size_of(i32)
    texture.channels = extract_from_memory(memory, i32)
    block = memory[size_of(i32):]
    size += size_of(i32)

    pixels_size: int
    texture.pixels, pixels_size = deserialize_slice(memory, []byte)
    size += pixels_size
    
    return 
}
