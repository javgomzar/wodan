#ifndef COMMON_HLSLI
#define COMMON_HLSLI

static const float PI = 3.14159265359f;

cbuffer Globals: register(b0) {
    float4x4 projection;
    float4x4 view;
    float2 resolution;
    float2 mouse;
    float2 last_mouse;
    float time;
};

cbuffer Light: register(b1) {
	float3 light_direction;
	float3 light_color;
	float3 camera_position;
	float ambient;
	float diffuse;
};

cbuffer PerDrawData: register(b2) {
    float4x4 transform_model;
    float4x4 transform_normal;
    float4 material_color;
    float metallic;
    float roughness;
    uint color_texture_index;
    uint normal_texture_index;
    uint pbr_texture_index;
};

sampler linear_wrap: register(s0);

#endif