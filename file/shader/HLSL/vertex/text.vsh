#include "common.hlsli"

struct GlyphInstance {
    float2 pen;
    float  depth;
    float  size;
    float4 color;
};
StructuredBuffer<GlyphInstance> instances: register(t0);
StructuredBuffer<uint> offsets: register(t1);

struct VS_IN {
    float3 position: POSITION;
    uint instance_id: SV_INSTANCEID;
};

struct VS_OUT {
    float4 sv_position: SV_POSITION;
    float4 color: COLOR;
};

VS_OUT main(VS_IN vin) {
    VS_OUT vout;

    uint offset = offsets[vin.instance_id];
    GlyphInstance instance = instances[offset];

    float2 pos_pixels = float2(instance.pen.x, -instance.pen.y) + instance.size * float2(vin.position.x, vin.position.y);
    vout.sv_position.xy = (2.0 * pos_pixels / resolution) + float2(-1.0, 1.0);
    vout.sv_position.zw = float2(0.0, 1.0);
    vout.color = instance.color;
    return vout;
}
