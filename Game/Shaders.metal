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

struct VertexIn {
    float3 position [[attribute(VertexAttributePosition)]];
    float3 normal   [[attribute(VertexAttributeNormal)]];
    float2 uv       [[attribute(VertexAttributeTexcoord)]];
};

struct Varyings {
    float4 position [[position]];
    float3 worldPos;
    float3 normalW;
    float2 uv;
    float4 shadowPos; // light clip space
};

// Helpers to unpack normal matrix rows
inline float3x3 unpackNormalMatrix(constant Uniforms& u) {
    return float3x3(u.normalMatrix0.xyz,
                    u.normalMatrix1.xyz,
                    u.normalMatrix2.xyz);
}

// ---------- Shadow pass (depth-only) ----------
vertex float4 shadowVertex(VertexIn in [[stage_in]],
                           constant Uniforms& u [[buffer(BufferIndexUniforms)]])
{
    float4 world = u.modelMatrix * float4(in.position, 1.0);
    return u.lightViewProjMatrix * world;
}

// ---------- Main pass ----------
vertex Varyings vertexShader(VertexIn in [[stage_in]],
                             constant Uniforms& u [[buffer(BufferIndexUniforms)]])
{
    Varyings out;

    float4 world = u.modelMatrix * float4(in.position, 1.0);
    out.worldPos = world.xyz;

    float3x3 nmat = unpackNormalMatrix(u);
    out.normalW = normalize(nmat * in.normal);

    out.uv = in.uv;
    out.shadowPos = u.lightViewProjMatrix * world;

    out.position = u.projectionMatrix * u.viewMatrix * world;
    return out;
}

fragment float4 fragmentShader(Varyings in [[stage_in]],
                               constant Uniforms& u [[buffer(BufferIndexUniforms)]],
                               constant LightParams& lp [[buffer(BufferIndexLight)]],
                               texture2d<half> baseColor [[texture(TextureIndexBaseColor)]],
                               depth2d<float> shadowMap [[texture(TextureIndexShadowMap)]])
{
    constexpr sampler colorSamp(mip_filter::linear, mag_filter::linear, min_filter::linear);

    // Shadow compare sampler
    constexpr sampler shadowSamp(coord::normalized,
                                 filter::linear,
                                 address::clamp_to_edge,
                                 compare_func::less_equal);

    // Base color
    float3 albedo = float3(baseColor.sample(colorSamp, in.uv).xyz);

    // Lighting vectors
    float3 N = normalize(in.normalW);
    float3 L = normalize(-lp.lightDirection);            // light direction toward surface
    float3 V = normalize(lp.cameraPosition - in.worldPos);
    float3 H = normalize(L + V);

    // Diffuse + spec (Blinn-Phong)
    float NdotL = max(dot(N, L), 0.0);
    float spec = pow(max(dot(N, H), 0.0), 64.0) * step(0.0, NdotL);

    float3 ambient = albedo * lp.ambientIntensity;
    float3 diffuse = albedo * NdotL * lp.lightColor;
    float3 specular = spec * lp.lightColor;

    // Shadow mapping (project into [0,1])
    float3 proj = in.shadowPos.xyz / in.shadowPos.w;
    float2 shadowUV = proj.xy * 0.5 + 0.5;
    float shadowDepth = proj.z;

    // Bias to reduce acne (normal + slope)
    float NdotL2 = saturate(dot(N, L));
    float bias = max(lp.normalBias * (1.0 - NdotL2), lp.slopeBias);
    float biasedDepth = shadowDepth - bias;

    // Outside shadow map => treat as lit
    bool inBounds = all(shadowUV >= float2(0.0)) && all(shadowUV <= float2(1.0))
                    && shadowDepth >= 0.0 && shadowDepth <= 1.0;
    float shadow = 1.0;
    if (inBounds) {
        float2 texel = 1.0 / max(lp.shadowMapSize, float2(1.0));
        float sum = 0.0;
        for (int y = -1; y <= 1; ++y) {
            for (int x = -1; x <= 1; ++x) {
                float2 uv = shadowUV + float2(x, y) * texel;
                sum += shadowMap.sample_compare(shadowSamp, uv, biasedDepth);
            }
        }
        shadow = sum / 9.0;
    }

    float3 lit = ambient + shadow * (diffuse + specular);
    return float4(lit, 1.0);
}
