package asset


Vertex_Position :: distinct [3]f32

Vertex_Attributes :: struct #align(16) {
    normal:  [3]f32,
    texture: [2]f32,
    color:   [4]f32,
}

Topology :: enum u32 {
    Point,
    Line,
    Line_Strip,
    Triangle,
    Triangle_Strip,
}

Primitive :: struct {
    topology:         Topology,
    indices:          []u32,
    positions:        []Vertex_Position,
    attributes:       []Vertex_Attributes,
    index_offset:     int,
    position_offset:  int,
    attribute_offset: int,
}

Mesh :: struct {
    name:       string,
    primitives: []Primitive,
}

Material :: struct {
    name:          string,
    base_color:    [4]f32,
    metallic:      f32,
    roughness:     f32,
    color_texture: Maybe(Texture),
}
