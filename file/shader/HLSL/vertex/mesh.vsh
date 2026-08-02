#include "common.hlsli"

struct VS_IN {
    float3 Position: POSITION;
    float3 Normal: NORMAL;
    float2 Texture: TEXCOORD;
    float4 Color: COLOR;
};

struct VS_OUT {
    float4 Position: SV_POSITION;
    float3 WorldPosition: POSITION;
    float3 Normal: NORMAL;
    float2 Texture: TEXCOORD0;
    float4 Color: COLOR;
};

VS_OUT main(VS_IN vin) {
    VS_OUT vout;
    
    vout.Position = mul(mul(mul(float4(vin.Position, 1.0f), Model), View), Projection);
    vout.WorldPosition = vin.Position;
    vout.Texture = vin.Texture;
    vout.Normal = normalize(mul(float4(vin.Normal, 0.0f), Normal));

    return vout;
}
