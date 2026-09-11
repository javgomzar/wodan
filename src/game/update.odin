package game

import "core:math/linalg"
import "../common"


normalize_angle :: proc(angle: f32) -> f32 {
    if angle >= 360.0 do return angle - 360.0
	else if angle < 0 do return angle + 360.0
	return angle;
}

update_camera :: proc(camera: ^Camera, input: ^common.Input_Context) {
    delta := input.mouse.cursor - input.mouse.last_cursor
    
    if input.mouse.middle_click.is_down {
        camera.angle -= 0.5 * delta.x;
        camera.pitch += 0.5 * delta.y;
    }
    else {
        if input.keyboard.key[.Up].is_down    do camera.pitch += 0.75
        if input.keyboard.key[.Down].is_down  do camera.pitch -= 0.75
        if input.keyboard.key[.Left].is_down  do camera.angle += 0.75
        if input.keyboard.key[.Right].is_down do camera.angle -= 0.75
    }

    if input.mouse.wheel > 0      do camera.distance /= 1.2
    else if input.mouse.wheel < 0 do camera.distance *= 1.2

    direction := linalg.Vector3f32{0, 0, 0}
    left := input.keyboard.key[.A].is_down
    right := input.keyboard.key[.D].is_down
    up := input.keyboard.key[.W].is_down
    down := input.keyboard.key[.S].is_down
    if left  do direction.x -= 1.0
    if right do direction.x += 1.0
    if up    do direction.z += 1.0
    if down  do direction.z -= 1.0

    if linalg.length(direction) > 0 {
        direction = linalg.normalize(direction)
        horizontal_basis := get_camera_basis(camera.angle, 0)
        direction = direction.x * linalg.Vector3f32{horizontal_basis[0, 0], horizontal_basis[0, 1], horizontal_basis[0, 2]} +
                    direction.z * linalg.Vector3f32{horizontal_basis[2, 0], horizontal_basis[2, 1], horizontal_basis[2, 2]}
    
        camera.position += 0.1 * direction
    }

    camera.angle = normalize_angle(camera.angle)
    camera.pitch = normalize_angle(camera.pitch)
}
