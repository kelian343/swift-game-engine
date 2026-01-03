//
//  Shaders.metal
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

// File for Metal shader functions

#include <metal_stdlib>
#include <simd/simd.h>
#import "ShaderTypes.h"

using namespace metal;

struct VertexIn {
    float3 position [[attribute(VertexAttributePosition)]];
    float3 normal   [[attribute(VertexAttributeNormal)]];
    float2 uv       [[attribute(VertexAttributeTexcoord)]];
};

struct Varyings {
    float4 position [[position]];
    float2 uv;
};

vertex Varyings vertexShader(VertexIn in [[stage_in]],
                             constant Uniforms& u [[buffer(BufferIndexUniforms)]])
{
    Varyings out;

    float4 world = u.modelMatrix * float4(in.position, 1.0);
    out.uv = in.uv;
    out.position = u.projectionMatrix * u.viewMatrix * world;
    return out;
}

fragment float4 fragmentShader(Varyings in [[stage_in]],
                               constant Uniforms& u [[buffer(BufferIndexUniforms)]],
                               texture2d<half> baseColor [[texture(TextureIndexBaseColor)]])
{
    constexpr sampler colorSamp(mip_filter::linear, mag_filter::linear, min_filter::linear);
    float3 albedo = float3(baseColor.sample(colorSamp, in.uv).xyz);
    return float4(albedo, 1.0);
}
