package test

import "core:testing"
import "core:slice"
import "core:os"
import "../asset"


@(test)
test_serialization_string :: proc(^testing.T) {
    test_string: string = "This is a test string."

    size := asset.get_serialized_size_string(test_string)
    block := make([]byte, size, context.temp_allocator)

    bytes_written := asset.serialize_string(block, test_string)
    result_string := asset.deserialize_string(block)

    assert(test_string == result_string)
}

@(test)
test_serialization_slice :: proc(^testing.T) {
    numbers: []int = { 1, 2, 3 }
    size := asset.get_serialized_size_slice(numbers)

    block := make([]byte, size, context.temp_allocator)

    bytes_written := asset.serialize_slice(block, numbers)
    result := asset.deserialize_slice(block, []int)

    for i in 0..<len(numbers) {
        actual := result[i]
        expected := numbers[i]
        assert(actual == expected)
    }
}

test_asset_loading :: proc(manager: ^asset.Manager, path: string, import_files: []string) {
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

    assert(len(test_asset.meshes) == len(loaded_asset.meshes))
    assert(len(test_asset.materials) == len(loaded_asset.materials))
    assert(len(test_asset.images) == len(loaded_asset.images))

    for mesh, m_index in test_asset.meshes {
        loaded_mesh := loaded_asset.meshes[m_index]
        assert(mesh.name == loaded_mesh.name)
        for primitive, p_index in mesh.primitives {
            loaded_primitive := loaded_mesh.primitives[p_index]
            assert(primitive.topology == loaded_primitive.topology)
            assert(slice.equal(primitive.positions, loaded_primitive.positions))
            assert(slice.equal(primitive.indices, loaded_primitive.indices))
            assert(slice.equal(primitive.attributes, loaded_primitive.attributes))
        }
    }

    for material, m_index in test_asset.materials {
        loaded_material := loaded_asset.materials[m_index]
        assert(material.name == loaded_material.name)
        assert(material.base_color == loaded_material.base_color)
        assert(material.metallic == loaded_material.metallic)
        assert(material.roughness == loaded_material.roughness)
    }

    for image, i_index in test_asset.images {
        loaded_image := loaded_asset.images[i_index]
        assert(image.width == loaded_image.width)
        assert(image.height == loaded_image.height)
        assert(image.depth == loaded_image.depth)
        assert(image.channels == loaded_image.channels)
        assert(slice.equal(image.pixels.buf[:], loaded_image.pixels.buf[:]))
    }

    asset.release(&loaded_asset)
}

@(test)
test_asset_loading_box :: proc(T: ^testing.T) {
    manager: asset.Manager
    asset.initialize_manager(&manager)

    test_asset_loading(&manager, "file/asset/test/box.ass", {
        "D:/TestAssets/glTF-Sample-Assets-main/Models/Box/glTF-Binary/Box.glb",
        "D:/TestAssets/glTF-Sample-Assets-main/Models/BoxTextured/glTF-Binary/BoxTextured.glb",
    })

    asset.release_assets(&manager)
}
