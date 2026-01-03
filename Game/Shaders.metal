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

#define MAX_RT_TEXTURES 32

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

inline float sat(float v) {
    return clamp(v, 0.0, 1.0);
}

inline float3 fresnel_schlick(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

inline float ggx_D(float NoH, float alpha) {
    float a2 = alpha * alpha;
    float denom = (NoH * NoH) * (a2 - 1.0) + 1.0;
    return a2 / (3.14159265 * denom * denom);
}

inline float ggx_G1(float NoV, float alpha) {
    float a = alpha;
    float a2 = a * a;
    float denom = NoV + sqrt(a2 + (1.0 - a2) * NoV * NoV);
    return 2.0 * NoV / max(denom, 1e-4);
}

inline float ggx_G(float NoV, float NoL, float alpha) {
    return ggx_G1(NoV, alpha) * ggx_G1(NoL, alpha);
}

inline float3 sample_ggx(float3 N, float alpha, thread uint &state) {
    float u1 = rand01(state);
    float u2 = rand01(state);
    float a2 = alpha * alpha;
    float phi = 6.2831853 * u1;
    float cosTheta = sqrt((1.0 - u2) / (1.0 + (a2 - 1.0) * u2));
    float sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta));
    float3 Ht = float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
    return normalize(make_basis(N) * Ht);
}

inline float3 traceRay(ray current,
                       thread intersector<triangle_data, instancing> &isect,
                       acceleration_structure<instancing> accel,
                       device const float3 *rtVertices,
                       device const uint *rtIndices,
                       device const RTInstanceInfo *rtInstances,
                       device const float2 *rtUVs,
                       array<texture2d<float, access::sample>, MAX_RT_TEXTURES> baseColorTextures,
                       device const RTDirectionalLight *dirLights,
                       device const RTPointLight *pointLights,
                       device const RTAreaLight *areaLights,
                       constant RTFrameUniforms& frame,
                       thread uint &seed) {
    constexpr sampler colorSamp(mip_filter::linear, mag_filter::linear, min_filter::linear);
    float3 radiance = float3(0.0);
    float3 throughput = float3(1.0);

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

        float3 base = inst.baseColor;
        float metallic = clamp(inst.metallic, 0.0, 1.0);
        float roughness = clamp(inst.roughness, 0.05, 1.0);

        if (inst.baseColorTexIndex < frame.textureCount && inst.baseColorTexIndex < MAX_RT_TEXTURES) {
            float2 bary = hit.triangle_barycentric_coord;
            float w = 1.0 - bary.x - bary.y;
            float2 uv0 = rtUVs[inst.baseVertex + i0];
            float2 uv1 = rtUVs[inst.baseVertex + i1];
            float2 uv2 = rtUVs[inst.baseVertex + i2];
            float2 uv = uv0 * w + uv1 * bary.x + uv2 * bary.y;
            float3 tex = float3(baseColorTextures[inst.baseColorTexIndex].sample(colorSamp, uv).xyz);
            base *= tex;
        }

        float3 hitPos = current.origin + current.direction * hit.distance;
        radiance += throughput * base * frame.ambientIntensity;

        for (uint i = 0; i < frame.dirLightCount; ++i) {
            RTDirectionalLight l = dirLights[i];
            float3 L = normalize(-l.direction);
            float NdotL = max(dot(N, L), 0.0);
            if (NdotL <= 0.0) { continue; }

            ray shadowRay;
            shadowRay.origin = hitPos + N * 0.01;
            shadowRay.direction = L;
            shadowRay.min_distance = 0.001;
            shadowRay.max_distance = 1e6;

            intersection_result<triangle_data, instancing> shadowHit = isect.intersect(shadowRay, accel);
            float shadow = (shadowHit.type == intersection_type::triangle) ? 0.0 : 1.0;
            float3 diffColor = base * (1.0 - metallic);
            radiance += throughput * diffColor * l.color * (l.intensity * NdotL * shadow);
        }

        for (uint i = 0; i < frame.pointLightCount; ++i) {
            RTPointLight l = pointLights[i];
            float3 toPoint = l.position - hitPos;
            float dist = length(toPoint);
            float3 Lp = (dist > 0.0) ? (toPoint / dist) : float3(0.0);
            float NdotLp = max(dot(N, Lp), 0.0);
            if (NdotLp <= 0.0 || dist <= 0.0) { continue; }

            ray pointShadow;
            pointShadow.origin = hitPos + N * 0.01;
            pointShadow.direction = Lp;
            pointShadow.min_distance = 0.001;
            pointShadow.max_distance = dist - 0.01;

            intersection_result<triangle_data, instancing> pointHit = isect.intersect(pointShadow, accel);
            float pointShadowTerm = (pointHit.type == intersection_type::triangle) ? 0.0 : 1.0;
            float attenuation = 1.0 / max(dist * dist, 0.001);
            float3 diffColor = base * (1.0 - metallic);
            radiance += throughput * diffColor * l.color
                * (l.intensity * attenuation * NdotLp * pointShadowTerm);
        }

        uint areaSamples = max(frame.areaLightSamples, 1u);
        for (uint i = 0; i < frame.areaLightCount; ++i) {
            RTAreaLight l = areaLights[i];
            float3 areaAccum = float3(0.0);
            for (uint a = 0; a < areaSamples; ++a) {
                float2 r = float2(rand01(seed), rand01(seed)) * 2.0 - 1.0;
                float3 lightPos = l.position + l.u * r.x + l.v * r.y;
                float3 toArea = lightPos - hitPos;
                float distA = length(toArea);
                float3 La = (distA > 0.0) ? (toArea / distA) : float3(0.0);
                float NdotLa = max(dot(N, La), 0.0);
                if (NdotLa <= 0.0 || distA <= 0.0) { continue; }

                ray areaShadow;
                areaShadow.origin = hitPos + N * 0.01;
                areaShadow.direction = La;
                areaShadow.min_distance = 0.001;
                areaShadow.max_distance = distA - 0.01;

                intersection_result<triangle_data, instancing> areaHit = isect.intersect(areaShadow, accel);
                float areaShadowTerm = (areaHit.type == intersection_type::triangle) ? 0.0 : 1.0;
                float attenuationA = 1.0 / max(distA * distA, 0.001);
                areaAccum += l.color * (l.intensity * attenuationA * NdotLa * areaShadowTerm);
            }
            float3 diffColor = base * (1.0 - metallic);
            radiance += throughput * diffColor * (areaAccum / float(areaSamples));
        }

        float3 V = normalize(-current.direction);
        float NoV = sat(dot(N, V));
        float alpha = roughness * roughness;
        float pSpec = mix(0.1, 0.9, metallic);

        float3 nextDir;
        float pdf = 1.0;
        float3 brdf = float3(1.0);

        if (rand01(seed) < pSpec) {
            float3 H = sample_ggx(N, alpha, seed);
            float3 L = reflect(-V, H);
            float NoL = sat(dot(N, L));
            float NoH = sat(dot(N, H));
            float VoH = sat(dot(V, H));
            if (NoL > 0.0) {
                float D = ggx_D(NoH, alpha);
                float G = ggx_G(NoV, NoL, alpha);
                float3 F0 = mix(float3(0.04), base, metallic);
                float3 F = fresnel_schlick(VoH, F0);
                brdf = (D * G) * F / max(4.0 * NoV * NoL, 1e-4);
                pdf = max(D * NoH / max(4.0 * VoH, 1e-4), 1e-5);
                throughput *= brdf * NoL / pdf;
                throughput /= max(pSpec, 1e-3);
                nextDir = L;
            } else {
                nextDir = sample_hemisphere(N, seed);
                throughput *= base * (1.0 - metallic);
                throughput /= max(1.0 - pSpec, 1e-3);
            }
        } else {
            nextDir = sample_hemisphere(N, seed);
            throughput *= base * (1.0 - metallic);
            throughput /= max(1.0 - pSpec, 1e-3);
        }

        current.origin = hitPos + nextDir * 0.01;
        current.direction = nextDir;
        current.min_distance = 0.001;
        current.max_distance = 1e6;
    }

    return radiance;
}

kernel void raytraceKernel(texture2d<float, access::write> outTexture [[texture(0)]],
                           texture2d<float, access::read_write> accumTexture [[texture(1)]],
                           array<texture2d<float, access::sample>, MAX_RT_TEXTURES> baseColorTextures [[texture(2)]],
                           constant RTFrameUniforms& frame [[buffer(BufferIndexRTFrame)]],
                           acceleration_structure<instancing> accel [[buffer(BufferIndexRTAccel)]],
                           device const float3 *rtVertices [[buffer(BufferIndexRTVertices)]],
                           device const uint *rtIndices [[buffer(BufferIndexRTIndices)]],
                           device const RTInstanceInfo *rtInstances [[buffer(BufferIndexRTInstances)]],
                           device const float2 *rtUVs [[buffer(BufferIndexRTUVs)]],
                           device const RTDirectionalLight *dirLights [[buffer(BufferIndexRTDirLights)]],
                           device const RTPointLight *pointLights [[buffer(BufferIndexRTPointLights)]],
                           device const RTAreaLight *areaLights [[buffer(BufferIndexRTAreaLights)]],
                           uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= frame.imageSize.x || gid.y >= frame.imageSize.y) {
        return;
    }

    intersector<triangle_data, instancing> isect;
    isect.assume_geometry_type(geometry_type::triangle);
    isect.force_opacity(forced_opacity::opaque);

    uint baseSeed = (gid.x * 1973u) ^ (gid.y * 9277u) ^ (frame.frameIndex * 26699u);
    uint spp = max(frame.samplesPerPixel, 1u);
    float3 radiance = float3(0.0);

    for (uint s = 0; s < spp; ++s) {
        uint seed = baseSeed ^ (s * 16807u);
        float2 jitter = float2(rand01(seed), rand01(seed));
        float2 pixel = (float2(gid) + jitter) / float2(frame.imageSize);
        float2 ndc = float2(pixel.x * 2.0 - 1.0, (1.0 - pixel.y) * 2.0 - 1.0);

        float4 clip = float4(ndc, 1.0, 1.0);
        float4 world = frame.invViewProj * clip;
        float3 dir = normalize(world.xyz / world.w - frame.cameraPosition);

        ray current;
        current.origin = frame.cameraPosition;
        current.direction = dir;
        current.min_distance = 0.001;
        current.max_distance = 1e6;

        radiance += traceRay(current,
                             isect,
                             accel,
                             rtVertices,
                             rtIndices,
                             rtInstances,
                             rtUVs,
                             baseColorTextures,
                             dirLights,
                             pointLights,
                             areaLights,
                             frame,
                             seed);
    }
    radiance /= float(spp);

    float3 currentColor = radiance;
    float3 prev = accumTexture.read(gid).xyz;
    if (frame.frameIndex == 0) {
        prev = currentColor;
    }

    float3 clamped = clamp(prev, currentColor - frame.historyClamp, currentColor + frame.historyClamp);
    float3 accum = mix(currentColor, clamped, frame.historyWeight);

    accumTexture.write(float4(accum, 1.0), gid);
    outTexture.write(float4(accum, 1.0), gid);
}

kernel void denoiseKernel(texture2d<float, access::read> accumTexture [[texture(0)]],
                          texture2d<float, access::write> outTexture [[texture(1)]],
                          constant RTFrameUniforms& frame [[buffer(BufferIndexRTFrame)]],
                          uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= frame.imageSize.x || gid.y >= frame.imageSize.y) {
        return;
    }

    float3 center = accumTexture.read(gid).xyz;
    float sigma = max(frame.denoiseSigma, 0.001);

    float3 sum = float3(0.0);
    float wsum = 0.0;

    for (int y = -1; y <= 1; ++y) {
        int yy = int(gid.y) + y;
        if (yy < 0 || yy >= int(frame.imageSize.y)) { continue; }
        for (int x = -1; x <= 1; ++x) {
            int xx = int(gid.x) + x;
            if (xx < 0 || xx >= int(frame.imageSize.x)) { continue; }
            float3 c = accumTexture.read(uint2(xx, yy)).xyz;
            float3 d = c - center;
            float w = 1.0 / (1.0 + dot(d, d) * sigma);
            sum += c * w;
            wsum += w;
        }
    }

    float3 outc = (wsum > 0.0) ? (sum / wsum) : center;
    outTexture.write(float4(outc, 1.0), gid);
}
