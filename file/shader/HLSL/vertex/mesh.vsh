#include "common.hlsli"

StructuredBuffer<float4x4> joint_transforms: register(t2);

struct VS_IN {
    float3 position: POSITION;
    float3 normal:   NORMAL;
    float2 texture:  TEXCOORD;
    float4 color:    COLOR;
    uint4 joints:    JOINTS;
    float4 weights:  WEIGHTS;
};

struct VS_OUT {
    float4 position:       SV_POSITION;
    float3 world_position: POSITION;
    float3 normal:         NORMAL;
    float2 texture:        TEXCOORD0;
    float4 color:          COLOR;
};

VS_OUT main(VS_IN vin) {
    VS_OUT vout;

    float4x4 skin = float4x4(
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    );
    if (joints > 0) {
        skin = 
            vin.weights.x * joint_transforms[vin.joints.x] +
            vin.weights.y * joint_transforms[vin.joints.y] +
            vin.weights.z * joint_transforms[vin.joints.z] +
            vin.weights.w * joint_transforms[vin.joints.w];
    }
    
    vout.position = mul(mul(mul(mul(float4(vin.position, 1.0f), skin), transform_model), view), projection);
    vout.world_position = vin.position;
    vout.normal = normalize(mul(mul(float4(vin.normal, 0.0f), skin), transform_normal));
    vout.texture = vin.texture;
    vout.color = vin.color;

    return vout;
}
