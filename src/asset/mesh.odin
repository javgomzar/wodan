package asset


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
    position_offset:  int,
    attribute_offset: int,
    index_offset:     int,
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
