#include "common.hlsli"

struct VS_IN {
    float3 position: POSITION;
};

struct VS_OUT {
    float4 position: SV_POSITION;
    float3 world_position: POSITION;
};
 
VS_OUT main(VS_IN vin) {
    VS_OUT vout;
    
    vout.position = mul(mul(mul(float4(vin.position, 1.0f), transform_model), view), projection);
    vout.world_position = vin.position;

    return vout;
}
