package test

import "core:testing"
import "core:slice"
import "core:os"
import "../asset"


@(test)
test_serialization_string :: proc(t: ^testing.T) {
    test_string: string = "This is a test string."

    expected_size := asset.get_serialized_size_string(test_string)
    block := make([]byte, expected_size, context.temp_allocator)

    bytes_written := asset.serialize_string(block, test_string)
    result_string, size := asset.deserialize_string(block)

    testing.expect(t, test_string == result_string)
    testing.expect(t, size == expected_size)
    delete(result_string)
}

@(test)
test_serialization_slice :: proc(t: ^testing.T) {
    numbers: []int = { 1, 2, 3 }
    expected_size := asset.get_serialized_size_slice(numbers)
    block := make([]byte, expected_size, context.temp_allocator)

    bytes_written := asset.serialize_slice(block, numbers)
    result, actual_size := asset.deserialize_slice(block, []int)
    testing.expect(t, expected_size == actual_size)

    for i in 0..<len(numbers) {
        actual := result[i]
        expected := numbers[i]
        testing.expect(t, actual == expected)
    }

    delete(result)
}

test_asset_loading :: proc(t: ^testing.T, manager: ^asset.Manager, path: string, import_files: []string) {
    test_asset := asset.add_asset(manager, path)

    for import_path in import_files {
        asset.add_file(test_asset, import_path)
    }

    asset.import_asset_files(test_asset)
    asset.write(test_asset)

    loaded_asset: asset.Asset
    error: os.Error
    loaded_asset.file_info, error = os.stat(path, context.allocator)
    asset.load(&loaded_asset)

    testing.expect(t, len(test_asset.meshes) == len(loaded_asset.meshes))
    testing.expect(t, len(test_asset.materials) == len(loaded_asset.materials))
    testing.expect(t, len(test_asset.textures) == len(loaded_asset.textures))

    for mesh, index in test_asset.meshes {
        loaded_mesh := loaded_asset.meshes[index]
        testing.expect(t, mesh.name == loaded_mesh.name)
        for primitive, p_index in mesh.primitives {
            loaded_primitive := loaded_mesh.primitives[p_index]
            testing.expect(t, primitive.topology == loaded_primitive.topology)
            testing.expect(t, slice.equal(primitive.positions, loaded_primitive.positions))
            testing.expect(t, slice.equal(primitive.indices, loaded_primitive.indices))
            testing.expect(t, slice.equal(primitive.attributes, loaded_primitive.attributes))
        }
    }

    for material, index in test_asset.materials {
        loaded_material := loaded_asset.materials[index]
        testing.expect(t, material.name == loaded_material.name)
        testing.expect(t, material.base_color == loaded_material.base_color)
        testing.expect(t, material.metallic == loaded_material.metallic)
        testing.expect(t, material.roughness == loaded_material.roughness)
    }

    for texture, index in test_asset.textures {
        image := texture.image
        loaded_image := loaded_asset.textures[index].image
        testing.expect(t, image.width == loaded_image.width)
        testing.expect(t, image.height == loaded_image.height)
        testing.expect(t, image.depth == loaded_image.depth)
        testing.expect(t, image.channels == loaded_image.channels)
        testing.expect(t, slice.equal(image.pixels.buf[:], loaded_image.pixels.buf[:]))
    }

    asset.release(&loaded_asset)
}

@(test)
test_asset_loading_box :: proc(t: ^testing.T) {
    manager: asset.Manager
    asset.initialize_manager(&manager)

    test_asset_loading(t, &manager, "file/asset/test/box.ass", {
        "D:/TestAssets/glTF-Sample-Assets-main/Models/Box/glTF-Binary/Box.glb",
        "D:/TestAssets/glTF-Sample-Assets-main/Models/BoxTextured/glTF-Binary/BoxTextured.glb",
    })

    asset.release_assets(&manager)
}

@(test)
test_separation :: proc(t: ^testing.T) {
    testing.expect_value(t, asset.separate_points({0, 1, 0}, {1, 0}, {-1, 0}), true)
    testing.expect_value(t, asset.separate_points({0, 0, 1}, {0, 1}, {0, -1}), true)
    testing.expect_value(t, asset.separate_points({0, 1, 1}, {1, 1}, {-1, -1}), true)
    testing.expect_value(t, asset.separate_points({0, 1, -1}, {1, -1}, {-1, 1}), true)
    testing.expect_value(t, asset.separate_points({0, 1, 0}, {0, 1}, {0, -1}), false)
    testing.expect_value(t, asset.separate_points({-2, 0, 1}, {0, 1}, {0, 3}), true)
    testing.expect_value(t, asset.separate_points({1, 0, 1}, {0, 1}, {0, 3}), false)
}
