//
//  Shaders.metal
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>
#import "ShaderTypes.h"

using namespace metal;

typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float3 normal   [[attribute(VertexAttributeNormal)]];
    float2 uv       [[attribute(VertexAttributeTexcoord)]];
} VertexIn;

typedef struct
{
    float4 position [[position]];
    float3 normal;
    float2 uv;
} Varyings;

vertex Varyings vertexShader(VertexIn in                 [[stage_in]],
                             constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]])
{
    Varyings out;
    float4 pos = float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * pos;
    out.normal = in.normal;
    out.uv = in.uv;
    return out;
}

fragment float4 fragmentShader(Varyings in                 [[stage_in]],
                               constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]],
                               texture2d<half> baseColor   [[texture(TextureIndexBaseColor)]])
{
    constexpr sampler s(mip_filter::linear, mag_filter::linear, min_filter::linear);
    half4 c = baseColor.sample(s, in.uv);
    return float4(c);
}
