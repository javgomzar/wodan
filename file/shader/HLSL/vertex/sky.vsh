#include "common.hlsli"

struct VS_IN {
    float3 position: POSITION;
};

struct VS_OUT {
    float4 sv_position: SV_POSITION;
    float3 position: POSITION;
};

VS_OUT main(VS_IN vin) {
    VS_OUT vout;

    float4x4 sky_view = view;
    sky_view[3] = float4(0.0f, 0.0f, 0.0f, 1.0f);
    
    vout.sv_position = mul(mul(float4(vin.position, 1.0f), sky_view), projection);
    vout.sv_position.z = vout.sv_position.w;
    vout.position = vin.position;

    return vout;
}
