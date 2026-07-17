package main


input_mode :: enum {
    Keyboard,
    Controller,
}

button_state :: struct {
    is_down: bool,
    was_down: bool,
    just_pressed: bool,
    just_lifted: bool,
}

reset_button_state :: proc(button: ^button_state) {
    button.was_down = button.is_down
    button.just_pressed = false
    button.just_lifted = false
}

press_button :: proc(button: ^button_state) {
    button.is_down = true
    button.just_pressed = !button.was_down
}

lift_button :: proc(button: ^button_state) {
    button.is_down = false
    button.just_lifted = button.was_down
}

keyboard_key :: enum {
    One, Two, Three, Four, Five, Six, Seven, Eight, Nine, Zero,
    Q, W, E, R, T, Y, U, I, O, P,
      A, S, D, F, G, H, J, K, L,
        Z, X, C, V, B, N, M,
    Up, Down, Left, Right,
    Escape,
    Space,
    Enter,
    Shift,
    Control,
    Alt,
    F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
    PageUp, PageDown,
}

controller_key :: enum {
    A, B, X, Y,
    LB, RB,
    LT, RT,
    LS, RS,
    Start,
    Back,
}

input_context :: struct {
    mode: input_mode,
    keyboard: struct {
        key: [keyboard_key]button_state,
        some_down: bool,
    },
    mouse: struct {
        left_click: button_state,
        middle_click: button_state,
        right_click: button_state,
        cursor: [2]f32,
        last_cursor: [2]f32,
        wheel: i16,
        some_down: bool,
    },
    controller: struct {
        left_stick: [2]f32,
        right_stick: [2]f32,
        key: [controller_key]button_state,
        pad: struct {
            left: button_state,
            right: button_state,
            up: button_state,
            down: button_state,
        },
        some_down: bool,
    },
}

reset_input :: proc(input: ^input_context) {
    for &button, key in input.keyboard.key {
        reset_button_state(&button)
    }
    input.keyboard.some_down = false
    
    reset_button_state(&input.mouse.left_click)
    reset_button_state(&input.mouse.middle_click)
    reset_button_state(&input.mouse.right_click)
    input.mouse.last_cursor = input.mouse.cursor
    input.mouse.cursor = {0, 0}
    input.mouse.wheel = 0
    input.mouse.some_down = false

    input.controller.left_stick = {0, 0}
    input.controller.right_stick = {0, 0}
    for &button, key in input.controller.key {
        reset_button_state(&button)
    }
    reset_button_state(&input.controller.pad.left)
    reset_button_state(&input.controller.pad.right)
    reset_button_state(&input.controller.pad.up)
    reset_button_state(&input.controller.pad.down)
    input.controller.some_down = false
}
