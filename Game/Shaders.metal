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

inline uint hash_u32(uint x) {
    x ^= x >> 16;
    x *= 0x7feb352d;
    x ^= x >> 15;
    x *= 0x846ca68b;
    x ^= x >> 16;
    return x;
}

inline float rand01(thread uint &state) {
    state = hash_u32(state);
    return float(state & 0x00FFFFFFu) / float(0x01000000u);
}

inline float3x3 make_basis(float3 n) {
    float3 t = normalize(abs(n.z) < 0.999 ? cross(n, float3(0, 0, 1)) : cross(n, float3(0, 1, 0)));
    float3 b = cross(n, t);
    return float3x3(t, b, n);
}

inline float3 sample_hemisphere(float3 n, thread uint &state) {
    float u1 = rand01(state);
    float u2 = rand01(state);
    float r = sqrt(u1);
    float phi = 6.2831853 * u2;
    float x = r * cos(phi);
    float y = r * sin(phi);
    float z = sqrt(max(0.0, 1.0 - u1));
    float3 local = float3(x, y, z);
    return make_basis(n) * local;
}

kernel void raytraceKernel(texture2d<float, access::write> outTexture [[texture(0)]],
                           constant RTFrameUniforms& frame [[buffer(BufferIndexRTFrame)]],
                           acceleration_structure<instancing> accel [[buffer(BufferIndexRTAccel)]],
                           device const float3 *rtVertices [[buffer(BufferIndexRTVertices)]],
                           device const uint *rtIndices [[buffer(BufferIndexRTIndices)]],
                           device const RTInstanceInfo *rtInstances [[buffer(BufferIndexRTInstances)]],
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

    intersector<triangle_data, instancing> isect;
    isect.assume_geometry_type(geometry_type::triangle);
    isect.force_opacity(forced_opacity::opaque);

    uint seed = (gid.x * 1973u) ^ (gid.y * 9277u) ^ (frame.frameIndex * 26699u);

    float3 radiance = float3(0.0);
    float3 throughput = float3(1.0);
    ray current;
    current.origin = frame.cameraPosition;
    current.direction = dir;
    current.min_distance = 0.001;
    current.max_distance = 1e6;

    for (uint bounce = 0; bounce < 2; ++bounce) {
        intersection_result<triangle_data, instancing> hit = isect.intersect(current, accel);
        if (hit.type != intersection_type::triangle) {
            radiance += throughput * float3(0.02, 0.02, 0.03);
            break;
        }

        RTInstanceInfo inst = rtInstances[hit.instance_id];
        uint triBase = inst.baseIndex + hit.primitive_id * 3;
        if (triBase + 2 >= inst.baseIndex + inst.indexCount) {
            radiance += throughput * float3(0.0);
            break;
        }

        uint i0 = rtIndices[triBase + 0];
        uint i1 = rtIndices[triBase + 1];
        uint i2 = rtIndices[triBase + 2];

        float3 v0 = rtVertices[inst.baseVertex + i0];
        float3 v1 = rtVertices[inst.baseVertex + i1];
        float3 v2 = rtVertices[inst.baseVertex + i2];

        float3 w0 = (inst.modelMatrix * float4(v0, 1.0)).xyz;
        float3 w1 = (inst.modelMatrix * float4(v1, 1.0)).xyz;
        float3 w2 = (inst.modelMatrix * float4(v2, 1.0)).xyz;

        float3 N = normalize(cross(w1 - w0, w2 - w0));
        if (dot(N, current.direction) > 0.0) { N = -N; }

        float id = float(hit.instance_id);
        float3 base = float3(fract(sin(id * 12.9898) * 43758.5453),
                             fract(sin(id * 78.233) * 43758.5453),
                             fract(sin(id * 39.425) * 43758.5453));

        float3 hitPos = current.origin + current.direction * hit.distance;
        float3 lightDir = normalize(frame.lightDirection);
        float3 L = -lightDir;
        float NdotL = max(dot(N, L), 0.0);

        if (NdotL > 0.0) {
            ray shadowRay;
            shadowRay.origin = hitPos + N * 0.01;
            shadowRay.direction = L;
            shadowRay.min_distance = 0.001;
            shadowRay.max_distance = 1e6;

            intersection_result<triangle_data, instancing> shadowHit = isect.intersect(shadowRay, accel);
            float shadow = (shadowHit.type == intersection_type::triangle) ? 0.0 : 1.0;
            radiance += throughput * base * frame.lightColor * (frame.ambientIntensity + shadow * frame.lightIntensity * NdotL);
        } else {
            radiance += throughput * base * frame.ambientIntensity;
        }

        float3 diffuseDir = sample_hemisphere(N, seed);
        float3 reflectDir = reflect(current.direction, N);
        float3 nextDir = normalize(mix(diffuseDir, reflectDir, 0.2));

        throughput *= base;
        current.origin = hitPos + nextDir * 0.01;
        current.direction = nextDir;
        current.min_distance = 0.001;
        current.max_distance = 1e6;
    }

    outTexture.write(float4(radiance, 1.0), gid);
}
