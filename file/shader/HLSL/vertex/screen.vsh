#include "common.hlsli"

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
    vout.sv_position.xy = (2.0f * float2(vin.position.x, -vin.position.y) / resolution) + float2(-1.0f, 1.0f);
    vout.sv_position.wz = float2(1, 0);
    vout.position = vin.position;
    vout.texture = vin.texture;
    vout.color = vin.color;
	return vout;
}
