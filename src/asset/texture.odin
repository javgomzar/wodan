package asset

import "core:mem"
import "core:slice"
import "core:bytes"
import img "core:image"


Texture :: struct {
    id:        ID,
    image:     ^img.Image,
    link:      ^Texture,
}

get_bytes_per_pixel :: proc(image: ^img.Image) -> int {
    return image.channels * image.depth / 8
}

get_serialized_size_image :: proc(image: ^img.Image) -> int {
    return 4 * size_of(int) + image.width * image.height * get_bytes_per_pixel(image)
}

serialize_image :: proc(memory: []byte, image: ^img.Image) -> (size: int) {
    dump_to_memory(memory, image.width)
    block := memory[size_of(int):]
    size += size_of(int)
    dump_to_memory(block, image.height)
    block = block[size_of(int):]
    size += size_of(int)
    dump_to_memory(block, image.channels)
    block = block[size_of(int):]
    size += size_of(int)
    dump_to_memory(block, image.depth)
    block = block[size_of(int):]
    size += size_of(int)
    
    pixels_size := image.width * image.height * get_bytes_per_pixel(image)
    copy(block[:pixels_size], image.pixels.buf[:])
    size += pixels_size

    return
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
    pixels_size := result.width * result.height * get_bytes_per_pixel(result)
    bytes.buffer_init(&result.pixels, block[:pixels_size])

    return result, get_serialized_size_image(result)
}
