package main

import "core:math"
import "core:math/linalg"


game_camera :: struct {
    position: [3]f32,
    angle:    f32,
    pitch:    f32,
    distance: f32,
}

get_camera_basis :: proc(angle: f32, pitch: f32) -> matrix[3, 3]f32 {
    cosA := math.cos(angle * math.RAD_PER_DEG)
    sinA := math.sin(angle * math.RAD_PER_DEG)
    cosP := math.cos(pitch * math.RAD_PER_DEG)
    sinP := math.sin(pitch * math.RAD_PER_DEG)

    return {
                cosA,   0.0,        -sinA,
        -sinA * sinP,  cosP, -cosA * sinP,
        -sinA * cosP, -sinP, -cosA * cosP,
    }
}

get_view_matrix :: proc(basis: matrix[3, 3]f32, distance: f32, position: [3]f32) -> matrix[4, 4]f32 {
    t_basis := linalg.transpose(basis)

    translation := [3]f32{0, 0, distance} - position * basis
    result := linalg.matrix4_from_matrix3(t_basis)
    return result
}

