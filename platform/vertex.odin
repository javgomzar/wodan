package main

vertex_position :: [3]f32

vertex_attributes :: struct #align(16) {
    normal:  [3]f32,
    texture: [2]f32,
    color:   [4]f32,
}

triangle_positions := [3]vertex_position {
    {0.0, 0.25, 0.0},
    {0.25, -0.25, 0.0},
    {-0.25, -0.25, 0.0},
}

triangle_attributes := [3]vertex_attributes {
    {{}, {}, {1.0, 0.0, 0.0, 1.0}},
    {{}, {}, {0.0, 1.0, 0.0, 1.0}},
    {{}, {}, {0.0, 0.0, 1.0, 1.0}},
}
