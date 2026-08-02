#ifndef COMMON_HLSLI
#define COMMON_HLSLI

cbuffer Globals: register(b0) {
    float4x4 Projection;
    float4x4 View;
    float2 Resolution;
    float2 Mouse;
    float2 LastMouse;
    float Time;
};

cbuffer Transforms: register(b1) {
    float4x4 Model;
    float4x4 Normal;
};

cbuffer Light: register(b2) {
	float3 LightDirection;
	float3 LightColor;
	float3 CameraPosition;
	float Ambient;
	float Diffuse;
};

#endif