//
//  Shaders.metal
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

// File for Metal shader functions

#include <metal_stdlib>
#include <metal_raytracing>
#include <simd/simd.h>
#import "ShaderTypes.h"

using namespace metal;
using namespace metal::raytracing;

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

kernel void raytraceKernel(texture2d<float, access::write> outTexture [[texture(0)]],
                           constant RTFrameUniforms& frame [[buffer(BufferIndexRTFrame)]],
                           acceleration_structure<instancing> accel [[buffer(BufferIndexRTAccel)]],
                           uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= frame.imageSize.x || gid.y >= frame.imageSize.y) {
        return;
    }

    float2 pixel = (float2(gid) + 0.5) / float2(frame.imageSize);
    float2 ndc = float2(pixel.x * 2.0 - 1.0, (1.0 - pixel.y) * 2.0 - 1.0);

    float4 clip = float4(ndc, 1.0, 1.0);
    float4 world = frame.invViewProj * clip;
    float3 dir = normalize(world.xyz / world.w - frame.cameraPosition);

    ray r;
    r.origin = frame.cameraPosition;
    r.direction = dir;
    r.min_distance = 0.001;
    r.max_distance = 1e6;

    intersector<triangle_data, instancing> isect;
    isect.assume_geometry_type(geometry_type::triangle);
    isect.force_opacity(forced_opacity::opaque);

    intersection_result<triangle_data, instancing> hit = isect.intersect(r, accel);

    float3 color;
    if (hit.type == intersection_type::triangle) {
        float id = float(hit.instance_id);
        float3 base = float3(fract(sin(id * 12.9898) * 43758.5453),
                             fract(sin(id * 78.233) * 43758.5453),
                             fract(sin(id * 39.425) * 43758.5453));

        float3 hitPos = r.origin + r.direction * hit.distance;
        float3 lightDir = normalize(frame.lightDirection);
        float3 L = -lightDir;
        float3 origin = hitPos + L * 0.01;

        ray shadowRay;
        shadowRay.origin = origin;
        shadowRay.direction = L;
        shadowRay.min_distance = 0.001;
        shadowRay.max_distance = 1e6;

        intersection_result<triangle_data, instancing> shadowHit = isect.intersect(shadowRay, accel);
        float shadow = (shadowHit.type == intersection_type::triangle) ? 0.0 : 1.0;

        float3 lit = base * (frame.ambientIntensity + shadow * frame.lightIntensity) * frame.lightColor;
        color = lit;
    } else {
        color = float3(0.02, 0.02, 0.03);
    }

    outTexture.write(float4(color, 1.0), gid);
}
