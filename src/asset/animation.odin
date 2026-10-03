package asset

import "core:log"
import "core:math"
import "core:math/linalg"
import "core:container/pool"


Joint_Pose :: struct {
    translation:  [3]f32,
    rotation:     linalg.Quaternionf32,
    scale:        [3]f32,
}

Joint_ID :: distinct i32

Joint :: struct {
    id:           Joint_ID,
    name:         string,
    parent:       Joint_ID,
    inverse_bind: matrix[4, 4]f32,
    rest_pose:    matrix[4, 4]f32,
    local_pose:   Joint_Pose,
}

get_serialized_size_joint :: proc(joint: Joint) -> (size: int) {
    size += get_serialized_size_string(joint.name)
    size += 2 * size_of(Joint_ID)
    size += 32 * size_of(f32)
    size += size_of(Joint_Pose)
    return
}

serialize_joint :: proc(memory: []byte, joint: Joint) -> (size: int) {
    block := memory

    dump_to_memory(block, joint.id)
    size += size_of(joint.id)
    block = block[size_of(joint.id):]
    
    name_size := serialize_string(block, joint.name)
    size += name_size
    block = block[name_size:]

    dump_to_memory(block, joint.parent)
    size += size_of(joint.parent)
    block = block[size_of(joint.parent):]

    inverse_bind_size := serialize_matrix(block, joint.inverse_bind)
    size += inverse_bind_size
    block = block[inverse_bind_size:]

    rest_pose_size := serialize_matrix(block, joint.rest_pose)
    size += rest_pose_size
    block = block[rest_pose_size:]

    dump_to_memory(block, joint.local_pose)
    size += size_of(joint.local_pose)
    block = block[size_of(joint.local_pose):]

    return
}

deserialize_joint :: proc(joint: ^Joint, memory: []byte) -> (size: int) {
    block := memory

    joint.id = extract_from_memory(block, Joint_ID)
    size += size_of(joint.id)
    block = block[size_of(joint.id):]

    name_size: int
    joint.name, name_size = deserialize_string(block)
    size += name_size
    block = block[name_size:]

    joint.parent = extract_from_memory(block, Joint_ID)
    size += size_of(joint.parent)
    block = block[size_of(joint.parent):]

    matrix_size := deserialize_matrix(&joint.inverse_bind, block)
    size += matrix_size
    block = block[matrix_size:]

    matrix_size = deserialize_matrix(&joint.rest_pose, block)
    size += matrix_size
    block = block[matrix_size:]

    joint.local_pose = extract_from_memory(block, Joint_Pose)
    size += size_of(joint.local_pose)
    block = block[size_of(joint.local_pose):]

    return
}

Skeleton :: struct {
    id:               ID,
    root_joint:       Joint_ID,
    joints:           []Joint,
    global_transform: matrix[4, 4]f32,
    link:             ^Skeleton,
}

add_skeleton :: proc(manager: ^Manager) -> ^Skeleton {
    skeleton, error := pool.get(&manager.pools.skeleton)
    if error != nil do log.fatal("Failed to allocate skeleton asset.")
    skeleton.id = create_id(manager)
    manager.items.skeleton[skeleton.id] = skeleton
    return skeleton
}

get_skeleton :: proc(manager: ^Manager, id: ID) -> ^Skeleton {
    if id in manager.items.skeleton {
        return manager.items.skeleton[id]
    }
    return nil
}

get_serialized_size_skeleton :: proc(skeleton: ^Skeleton) -> (size: int) {
    size += size_of(skeleton.root_joint)
    size += size_of(u32)
    for joint in skeleton.joints {
        size += get_serialized_size_joint(joint)
    }
    return
}

serialize_skeleton :: proc(memory: []byte, skeleton: ^Skeleton) -> (size: int) {
    block := memory
    dump_to_memory(block, skeleton.root_joint)
    size += size_of(skeleton.root_joint)
    block = block[size_of(skeleton.root_joint):]

    dump_to_memory(block, u32(len(skeleton.joints)))
    size += size_of(u32)
    block = block[size_of(u32):]
    for joint in skeleton.joints {
        joint_size := serialize_joint(block, joint)
        size += joint_size
        block = block[joint_size:]
    }

    return
}

deserialize_skeleton :: proc(skeleton: ^Skeleton, memory: []byte) -> (size: int) {
    block := memory
    skeleton.root_joint = extract_from_memory(block, Joint_ID)
    size += size_of(Joint_ID)
    block = block[size_of(Joint_ID):]

    n_joints := extract_from_memory(block, u32)
    size += size_of(u32)
    block = block[size_of(u32):]
    skeleton.joints = make([]Joint, n_joints)
    for &joint in skeleton.joints {
        joint_size := deserialize_joint(&joint, block)
        size += joint_size
        block = block[joint_size:]
    }

    return
}

Animation_Target :: enum {
    Translation,
    Rotation,
    Scale,
    Weights,
}

Animation_Interpolation :: enum {
    Linear,
    Step,
    CubicSpline,
}

Animation_Channel :: struct {
    joint:         Joint_ID,
    target:        Animation_Target,
    interpolation: Animation_Interpolation,
    min_time:      f32,
    max_time:      f32,
    input:         []f32,
    output:        []f32,
}

get_serialized_size_animation_channel :: proc(channel: ^Animation_Channel) -> (size: int) {
    size += size_of(channel.joint)
    size += size_of(channel.target)
    size += size_of(channel.interpolation)
    size += size_of(channel.min_time)
    size += size_of(channel.max_time)
    size += get_serialized_size_slice(channel.input)
    size += get_serialized_size_slice(channel.output)
    return
}

serialize_animation_channel :: proc(memory: []byte, channel: ^Animation_Channel) -> (size: int) {
    block := memory

    dump_to_memory(block, channel.joint)
    size += size_of(channel.joint)
    block = block[size_of(channel.joint):]

    dump_to_memory(block, channel.target)
    size += size_of(channel.target)
    block = block[size_of(channel.target):]

    dump_to_memory(block, channel.interpolation)
    size += size_of(channel.interpolation)
    block = block[size_of(channel.interpolation):]

    dump_to_memory(block, channel.min_time)
    size += size_of(channel.min_time)
    block = block[size_of(channel.min_time):]

    dump_to_memory(block, channel.max_time)
    size += size_of(channel.max_time)
    block = block[size_of(channel.max_time):]

    input_size := serialize_slice(block, channel.input)
    size += input_size
    block = block[input_size:]

    output_size := serialize_slice(block, channel.output)
    size += output_size
    block = block[output_size:]

    return
}

deserialize_animation_channel :: proc(memory: []byte, channel: ^Animation_Channel) -> (size: int) {
    block := memory

    channel.joint = extract_from_memory(block, Joint_ID)
    size += size_of(Joint_ID)
    block = block[size_of(Joint_ID):]

    channel.target = extract_from_memory(block, Animation_Target)
    size += size_of(Animation_Target)
    block = block[size_of(Animation_Target):]

    channel.interpolation = extract_from_memory(block, Animation_Interpolation)
    size += size_of(Animation_Interpolation)
    block = block[size_of(Animation_Interpolation):]

    channel.min_time = extract_from_memory(block, f32)
    size += size_of(f32)
    block = block[size_of(f32):]

    channel.max_time = extract_from_memory(block, f32)
    size += size_of(f32)
    block = block[size_of(f32):]

    input_size: int
    channel.input, input_size = deserialize_slice(block, []f32)
    size += input_size
    block = block[input_size:]

    output_size: int
    channel.output, output_size = deserialize_slice(block, []f32)
    size += output_size
    block = block[output_size:]

    return
}

Animation :: struct {
    id:       ID,
    name:     string,
    skeleton: ID,
    duration: f32,
    channels: []Animation_Channel,
}

add_animation :: proc(manager: ^Manager) -> ^Animation {
    animation, error := pool.get(&manager.pools.animation)
    if error != nil do log.fatal("Failed to allocate animation asset.")
    animation.id = create_id(manager)
    manager.items.animation[animation.id] = animation
    return animation
}

get_animation :: proc(manager: ^Manager, id: ID) -> ^Animation {
    if id in manager.items.animation {
        return manager.items.animation[id]
    }
    return nil
}

get_serialized_size_animation :: proc(animation: ^Animation) -> (size: int) {
    size += get_serialized_size_string(animation.name)
    size += size_of(u32) // skeleton index
    size += size_of(u32) // len(channels)
    for &channel in animation.channels {
        size += get_serialized_size_animation_channel(&channel)
    }
    return
}

serialize_animation :: proc(memory: []byte, animation: ^Animation, skeleton_id_to_index: map[ID]u32) -> (size: int) {
    block := memory
    
    name_size := serialize_string(block, animation.name)
    size += name_size
    block = block[name_size:]

    dump_to_memory(block, skeleton_id_to_index[animation.skeleton])
    size += size_of(u32)
    block = block[size_of(u32):]

    dump_to_memory(block, u32(len(animation.channels)))
    size += size_of(u32)
    block = block[size_of(u32):]
    
    for &channel in animation.channels {
        channel_size := serialize_animation_channel(block, &channel)
        size += channel_size
        block = block[channel_size:]
    }

    return
}

deserialize_animation :: proc(animation: ^Animation, memory: []byte, skeletons: []ID) -> (size: int) {
    block := memory

    name_size: int
    animation.name, name_size = deserialize_string(block)
    size += name_size
    block = block[name_size:]

    skeleton_index := extract_from_memory(block, u32)
    animation.skeleton = skeletons[skeleton_index]
    size += size_of(u32)
    block = block[size_of(u32):]

    n_channels := extract_from_memory(block, u32)
    animation.channels = make([]Animation_Channel, n_channels)
    size += size_of(u32)
    block = block[size_of(u32):]

    max_time: f32 = 0
    for &channel in animation.channels {
        channel_size := deserialize_animation_channel(block, &channel)
        size += channel_size
        block = block[channel_size:]

        max_time = max(max_time, channel.max_time)
    }

    return
}

Animator_Loop :: enum {
    Repeat,
    Stop,
    Accumulate,
}

Animator :: struct {
    time:      f32,
    animation: ^Animation,
    skeleton:  ^Skeleton,
    loop:      Animator_Loop,
    indices:   []int,
    poses:     []Joint_Pose,
    transform: []matrix[4,4]f32,
    active:    bool,
}

start_animator :: proc(animator: ^Animator, skeleton: ^Skeleton, animation: ^Animation, loop: Animator_Loop = .Repeat) {
    animator.time = 0
    animator.animation = animation
    animator.skeleton = skeleton
    animator.loop = loop
    if len(animator.indices) > 0 {
        delete(animator.indices)
    }
    animator.indices = make([]int, len(animation.channels))
    if len(animator.poses) > 0 {
        delete(animator.poses)
    }
    animator.poses = make([]Joint_Pose, len(skeleton.joints))
    for &pose in animator.poses {
        pose.translation = 0
        pose.rotation = 1
        pose.scale = 1
    }
    animator.transform = make([]matrix[4,4]f32, len(skeleton.joints))
    animator.active = true
}

update_animator :: proc(animator: ^Animator, dt: f32) {
    if animator.active {
        animator.time += dt
        if animator.time > animator.animation.duration {
            switch animator.loop {
                case .Stop:
                    animator.time = animator.animation.duration
                case .Repeat, .Accumulate:
                    animator.time = math.mod(animator.time, animator.animation.duration)
            }
        }
    }
    
    for &channel, index in animator.animation.channels {
        current_index := &animator.indices[index]
        interpolation_mode := channel.interpolation
        clamp_start := animator.time <= channel.min_time
        clamp_end := animator.time >= channel.max_time
        if !(clamp_start || clamp_end) {
            last_time := channel.input[current_index^]
            for animator.time <= last_time {
                current_index^ -= 1
                last_time = channel.input[current_index^]
            }
            if current_index^ >= len(channel.input) - 1 {
                clamp_end = true
            }
            else {
                next_time := channel.input[current_index^ + 1]
                for animator.time >= next_time {
                    current_index^ += 1
                    last_time = channel.input[current_index^]
                    next_time = channel.input[current_index^ + 1]
                }
            }
        }
        if clamp_start || clamp_end {
            interpolation_mode = .Step
            current_index^ = clamp_end ? len(channel.input) - 1 : 0
        }
        last_index := current_index^

        // Compute interpolation
        value := [4]f32{}
        last_value := [4]f32{}
        components := channel.target == .Rotation ? 4 : 3
        last_output := channel.output[components*last_index:components*(last_index+1)]
        for i in 0..<components {
            last_value[i] = last_output[i]
        }

        switch interpolation_mode {
            case .Step:
                value = last_value
            case .Linear:
                last_time := channel.input[last_index]
                next_time := channel.input[last_index+1]
                t := (animator.time - last_time) / (next_time - last_time)
                next_value := [4]f32{}
                next_output := channel.output[components*(last_index+1):components*(last_index+2)]
                for i in 0..<components {
                    next_value[i] = next_output[i]
                }

                if channel.target == .Rotation {
                    last_rotation := quaternion(x=last_value[0], y=last_value[1], z=last_value[2], w=last_value[3])

                    next_rotation := quaternion(x=next_value[0], y=next_value[1], z=next_value[2], w=next_value[3])
                    slerp_rotation := linalg.quaternion_slerp(last_rotation, next_rotation, t)
                    value = {slerp_rotation.x, slerp_rotation.y, slerp_rotation.z, slerp_rotation.w}
                }
                else {
                    value = (1 - t) * last_value + t * next_value
                }
            case .CubicSpline:
                log.fatal("Not implemented")
            case:
                log.fatal("Invalid animation interpolation mode", channel.interpolation)
        }
    
        pose := &animator.poses[channel.joint]
        switch channel.target {
            case .Translation:
                pose.translation = value.xyz
            case .Rotation:
                pose.rotation = quaternion(x = value[0], y = value[1], z = value[2], w = value[3])
            case .Scale:
                pose.scale = value.xyz
            case .Weights:
                log.fatal("Not implemented")
            case:
                log.fatal("Invalid channel target", channel.target)
        }
    }
}
