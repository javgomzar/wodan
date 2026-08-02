package common


Vertex_Position :: distinct [3]f32

Vertex_Attributes :: struct #align(16) {
    normal:  [3]f32,
    texture: [2]f32,
    color:   [4]f32,
}

triangle_positions := [3]Vertex_Position {
    {0.0, 0.25, 0.0},
    {0.25, -0.25, 0.0},
    {-0.25, -0.25, 0.0},
}

triangle_attributes := [3]Vertex_Attributes {
    {{}, {}, {1.0, 0.0, 0.0, 1.0}},
    {{}, {}, {0.0, 1.0, 0.0, 1.0}},
    {{}, {}, {0.0, 0.0, 1.0, 1.0}},
}
