package test

import "core:testing"
import "core:slice"
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

@(test)
test_serialization_matrix :: proc(t: ^testing.T) {
    mat: matrix[4,6]f32 = {
        1, 2, 3, 4, 5, 6,
       -1,-2,-3,-4,-5,-6,
        0,-0, 9, 9, 9, 1E-60,
        9, 9, 9, 9, 9, 1E60,
    }

    expected_size := asset.get_serialized_size_matrix(mat)
    memory := make([]byte, expected_size)
    defer delete(memory)
    
    bytes_written := asset.serialize_matrix(memory, mat)
    testing.expect(t, expected_size == bytes_written)
    
    loaded_mat: matrix[4,6]f32
    loaded_size := asset.deserialize_matrix(&loaded_mat, memory)
    testing.expect(t, loaded_size == expected_size)
    testing.expect(t, mat == loaded_mat)
}

@(test)
test_serialization_material :: proc(t: ^testing.T) {
    material: asset.Material = asset.default_material
    material.name = "Test"

    expected_size := asset.get_serialized_size_material(&material)
    memory := make([]byte, expected_size)
    defer delete(memory)

    texture_id_to_index := make(map[asset.ID]u32)
    defer delete(texture_id_to_index)
    texture_id_to_index[0] = 0

    write_size := asset.serialize_material(memory, &material, texture_id_to_index)
    testing.expect(t, expected_size == write_size)

    deserialized_material: asset.Material
    read_size := asset.deserialize_material(&deserialized_material, memory, {})
    testing.expect(t, write_size == read_size)

    testing.expect(t, material.base_color == deserialized_material.base_color)
    testing.expect(t, material.metallic == deserialized_material.metallic)
    testing.expect(t, material.roughness == deserialized_material.roughness)
    testing.expect(t, material.emissive == deserialized_material.emissive)
    testing.expect(t, material.specular == deserialized_material.specular)

    delete(deserialized_material.name)
}

@(test)
test_serialization_mesh :: proc(t: ^testing.T) {
    mesh: asset.Mesh
    mesh.name = "Test"

    positions := [3]asset.Vertex_Position{
        {0, 0, 0},
        {0, 1, 0},
        {0, 0, 1},
    }

    attributes := [3]asset.Vertex_Attributes{
        {
            color = {1, 0, 0, 1},
            normal = {1, 0, 0},
            texture = {0, 0},
        },
        {
            color = {0, 1, 0, 1},
            normal = {0, 1, 0},
            texture = {0, 1},
        },
        {
            color = {0, 0, 1, 1},
            normal = {0, 0, 1},
            texture = {1, 0},
        },
    }

    joints := [3]asset.Vertex_Joint{
        {
            joints = {0, 1, 2, 3},
            weights = {1, 0, 0, 0},
        },
        {
            joints = {0, 1, 2, 3},
            weights = {0, 1, 0, 0},
        },
        {
            joints = {0, 1, 2, 3},
            weights = {0, 0, 1, 0},
        },
    }

    indices := [3]u32{0, 1, 2}

    primitives := [2]asset.Primitive{
        {
            topology = .Triangle,
            positions = positions[:],
            attributes = attributes[:],
            joints = joints[:],
            indices = indices[:],
        },
        {
            topology = .Triangle_Strip,
            positions = positions[:],
            attributes = attributes[:],
            joints = joints[:],
            indices = indices[:],
        },
    }

    mesh.primitives = primitives[:]

    expected_size := asset.get_serialized_size_mesh(&mesh)
    block := make([]byte, expected_size)
    defer delete(block)

    material_id_to_index := make(map[asset.ID]u32)
    defer delete(material_id_to_index)
    material_id_to_index[0] = 0

    write_size := asset.serialize_mesh(block, &mesh, material_id_to_index)
    testing.expect(t, expected_size == write_size)

    deserialized_mesh: asset.Mesh
    read_size := asset.deserialize_mesh(&deserialized_mesh, block, {})
    testing.expect(t, write_size == read_size)

    testing.expect(t, mesh.name == deserialized_mesh.name)
    testing.expect(t, len(mesh.primitives) == len(deserialized_mesh.primitives))
    for primitive, index in mesh.primitives {
        deserialized_primitive := deserialized_mesh.primitives[index]
        testing.expect(t, primitive.topology == deserialized_primitive.topology)
        testing.expect(t, slice.equal(primitive.positions, deserialized_primitive.positions))
        testing.expect(t, slice.equal(primitive.indices, deserialized_primitive.indices))
        testing.expect(t, slice.equal(primitive.attributes, deserialized_primitive.attributes))
        testing.expect(t, slice.equal(primitive.joints, deserialized_primitive.joints))
    }

    asset.release_mesh(&deserialized_mesh)
}

@(test)
test_serialization_skeleton :: proc(t: ^testing.T) {
    skeleton := asset.Skeleton{
        id = 1,
        root_joint = 0,
        joints = {
            {
                id = 0,
                name = "Joint 0",
                parent = -1,
                inverse_bind = 1,
                rest_pose = 1,
                local_pose = {
                    translation = 0,
                    rotation = 1,
                    scale = 1,
                },
            },
            {
                id = 1,
                name = "Joint 1",
                parent = 0,
                inverse_bind = 1,
                rest_pose = 1,
                local_pose = {
                    translation = {0, 1, 0},
                    rotation = 1,
                    scale = 1,
                },
            },
        },
    }
    
    expected_size := asset.get_serialized_size_skeleton(&skeleton)
    memory := make([]byte, expected_size)
    defer delete(memory)
    
    bytes_written := asset.serialize_skeleton(memory, &skeleton)
    testing.expect(t, expected_size == bytes_written)

    loaded_skeleton: asset.Skeleton 
    asset.deserialize_skeleton(&loaded_skeleton, memory)
    defer delete(loaded_skeleton.joints)
    testing.expect(t, skeleton.root_joint == loaded_skeleton.root_joint)
    testing.expect(t, len(skeleton.joints) == len(loaded_skeleton.joints))
    for joint, index in skeleton.joints {
        loaded_joint := loaded_skeleton.joints[index]
        testing.expect(t, joint.id == loaded_joint.id)
        testing.expect(t, joint.name == loaded_joint.name)
        delete(loaded_joint.name)
        testing.expect(t, joint.parent == loaded_joint.parent)
        testing.expect(t, joint.inverse_bind == loaded_joint.inverse_bind)
        testing.expect(t, joint.rest_pose == loaded_joint.rest_pose)
        testing.expect(t, joint.local_pose == loaded_joint.local_pose)
    }
}

@(test)
test_serialization_animation :: proc(t: ^testing.T) {
    animation: asset.Animation = {
        name = "Test Animation",
        skeleton = 1,
        channels = {
            {
                joint = 0,
                target = .Translation,
                interpolation = .CubicSpline,
                min_time = 0,
                max_time = 1,
                input = {0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1},
                output = {
                    0, 0, 0,
                    0.1, 0.1, 0.1,
                    0.2, 0.2, 0.2,
                    0.3, 0.3, 0.3,
                    0.4, 0.4, 0.4,
                    0.5, 0.5, 0.5,
                    0.6, 0.6, 0.6,
                    0.7, 0.7, 0.7,
                    0.8, 0.8, 0.8,
                    0.9, 0.9, 0.9,
                    1.0, 1.0, 1.0,
                },
            },
            {
                joint = 1,
                target = .Rotation,
                interpolation = .Linear,
                min_time = 0,
                max_time = 1,
                input = {0, 0.5, 1},
                output = {
                    0, 0, 0, 1,
                    1, 0, 0, 0,
                    0, 1, 0, 0,
                }
            }
        },
    }

    skeleton_id_to_index: map[asset.ID]u32
    defer delete(skeleton_id_to_index)
    skeleton_id_to_index[1] = 0

    expected_size := asset.get_serialized_size_animation(&animation)
    memory := make([]byte, expected_size)
    defer delete(memory)
    bytes_written := asset.serialize_animation(memory, &animation, skeleton_id_to_index)
    testing.expect(t, expected_size == bytes_written)
    loaded_animation: asset.Animation
    loaded_size := asset.deserialize_animation(&loaded_animation, memory, {1})
    testing.expect(t, expected_size == loaded_size)

    testing.expect(t, animation.name == loaded_animation.name)
    delete(loaded_animation.name)
    testing.expect(t, animation.skeleton == loaded_animation.skeleton)
    for channel, index in animation.channels {
        loaded_channel := loaded_animation.channels[index]
        testing.expect(t, channel.joint == loaded_channel.joint)
        testing.expect(t, channel.target == loaded_channel.target)
        testing.expect(t, channel.interpolation == loaded_channel.interpolation)
        testing.expect(t, channel.min_time == loaded_channel.min_time)
        testing.expect(t, channel.max_time == loaded_channel.max_time)
        testing.expect(t, slice.equal(channel.input, loaded_channel.input))
        delete(loaded_channel.input)
        testing.expect(t, slice.equal(channel.output, loaded_channel.output))
        delete(loaded_channel.output)
    }
    delete(loaded_animation.channels)
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
