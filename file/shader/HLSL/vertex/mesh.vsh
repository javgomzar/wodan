#include "common.hlsli"

struct VS_IN {
    float3 position: POSITION;
    float3 normal: NORMAL;
    float2 texture: TEXCOORD;
    float4 color: COLOR;
};

struct VS_OUT {
    float4 position: SV_POSITION;
    float3 world_position: POSITION;
    float3 normal: NORMAL;
    float2 texture: TEXCOORD0;
    float4 color: COLOR;
};

VS_OUT main(VS_IN vin) {
    VS_OUT vout;
    
    vout.position = mul(mul(mul(float4(vin.position, 1.0f), transform_model), view), projection);
    vout.world_position = vin.position;
    vout.normal = normalize(mul(float4(vin.normal, 0.0f), transform_normal));
    vout.texture = vin.texture;
    vout.color = vin.color;

    return vout;
}
