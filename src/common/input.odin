package common


Input_Mode :: enum {
    Keyboard,
    Controller,
}

Button_State :: struct {
    is_down: bool,
    was_down: bool,
    just_pressed: bool,
    just_lifted: bool,
}

reset_button_state :: proc(button: ^Button_State) {
    button.was_down = button.is_down
    button.just_pressed = false
    button.just_lifted = false
}

press_button :: proc(button: ^Button_State) {
    button.is_down = true
    button.just_pressed = !button.was_down
}

lift_button :: proc(button: ^Button_State) {
    button.is_down = false
    button.just_lifted = button.was_down
}

Keyboard_Key :: enum {
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
    Page_Up, Page_Down,
}

controller_key :: enum {
    A, B, X, Y,
    LB, RB,
    LT, RT,
    LS, RS,
    Start,
    Back,
}

Input_Context :: struct {
    mode: Input_Mode,
    keyboard: struct {
        key: [Keyboard_Key]Button_State,
        some_down: bool,
    },
    mouse: struct {
        left_click: Button_State,
        middle_click: Button_State,
        right_click: Button_State,
        cursor: [2]f32,
        last_cursor: [2]f32,
        wheel: i16,
        some_down: bool,
    },
    controller: struct {
        left_stick: [2]f32,
        right_stick: [2]f32,
        key: [controller_key]Button_State,
        pad: struct {
            left: Button_State,
            right: Button_State,
            up: Button_State,
            down: Button_State,
        },
        some_down: bool,
    },
}

reset_input :: proc(input: ^Input_Context) {
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
