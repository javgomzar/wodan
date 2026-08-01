package test

import "../common"
import "core:mem"
import "core:testing"
import "core:slice"


@(test)
test_serialization_string :: proc(^testing.T) {
    test_string: string = "This is a test string."

    size := common.get_serialized_size_string(test_string)
    block := make([]byte, size, context.temp_allocator)

    bytes_written := common.serialize_string(block, test_string)
    result_string := common.deserialize_string(block)

    assert(test_string == result_string)
}

@(test)
test_serialization_slice :: proc(^testing.T) {
    numbers: []int = { 1, 2, 3 }
    size := common.get_serialized_size_slice(numbers)

    block := make([]byte, size, context.temp_allocator)

    bytes_written := common.serialize_slice(block, numbers)
    result := common.deserialize_slice(block, []int)

    for i in 0..<len(numbers) {
        actual := result[i]
        expected := numbers[i]
        assert(actual == expected)
    }
}