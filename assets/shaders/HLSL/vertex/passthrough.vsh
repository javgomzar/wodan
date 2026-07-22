cbuffer Globals: register(b0) {
    float4x4 Projection;
    float4x4 View;
    float2 Resolution;
    float2 Mouse;
    float2 LastMouse;
    float Time;
};

struct VS_IN {
    float3 position: POSITION;
    float3 normal: NORMAL;
    float2 texture: TEXCOORD;
    float4 color: COLOR;
};

struct VS_OUT {
    float4 sv_position: SV_POSITION;
    float3 position: POSITION;
    float3 normal: NORMAL;
    float2 texture: TEXCOORD;
    float4 color: COLOR;
};

VS_OUT main(VS_IN vin) {
    VS_OUT vout;
    vout.sv_position.xyz = vin.position.xyz;
    vout.sv_position.w = 1;
    vout.position = vin.position;
    vout.normal = vin.normal;
    vout.texture = vin.texture;
    vout.color = vin.color;
	return vout;
}
