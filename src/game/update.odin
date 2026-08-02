package game

import "../common"


update_camera :: proc(camera: ^common.Camera, input: ^common.Input_Context) {
    delta := input.mouse.cursor - input.mouse.last_cursor
    
    if (input.mouse.left_click.is_down) {
        camera.angle -= 0.5 * delta.x;
        camera.pitch += 0.5 * delta.y;
    }

    if input.mouse.wheel > 0      do camera.distance /= 1.2
    else if input.mouse.wheel < 0 do camera.distance *= 1.2
}
