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
                       thread uint &seed,
                       thread float3 &primaryNormal,
                       thread float &primaryDepth,
                       thread float &primaryRoughness,
                       thread uint &primaryHit,
                       bool recordPrimary) {
    constexpr sampler colorSamp(mip_filter::linear, mag_filter::linear, min_filter::linear);
    float3 radiance = float3(0.0);
    float3 throughput = float3(1.0);

    for (uint bounce = 0; bounce < 2; ++bounce) {
        intersection_result<triangle_data, instancing> hit = isect.intersect(current, accel);
        if (hit.type != intersection_type::triangle) {
            if (bounce == 0 && recordPrimary) {
                primaryHit = 0;
                primaryNormal = float3(0.0);
                primaryDepth = 1e6;
                primaryRoughness = 1.0;
            }
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

        if (bounce == 0 && recordPrimary) {
            primaryHit = 1;
            primaryNormal = N;
            primaryDepth = hit.distance;
            primaryRoughness = roughness;
        }

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
                           texture2d<float, access::write> gNormal [[texture(1)]],
                           texture2d<float, access::write> gDepth [[texture(2)]],
                           texture2d<float, access::write> gRoughness [[texture(3)]],
                           array<texture2d<float, access::sample>, MAX_RT_TEXTURES> baseColorTextures [[texture(4)]],
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
    float3 primaryNormal = float3(0.0);
    float primaryDepth = 1e6;
    float primaryRoughness = 1.0;
    uint primaryHit = 0u;

    for (uint s = 0; s < spp; ++s) {
        uint seed = baseSeed ^ (s * 16807u);
        float2 jitter = (s == 0) ? float2(0.5, 0.5) : float2(rand01(seed), rand01(seed));
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
                             seed,
                             primaryNormal,
                             primaryDepth,
                             primaryRoughness,
                             primaryHit,
                             s == 0);
    }
    radiance /= float(spp);

    outTexture.write(float4(radiance, 1.0), gid);
    if (primaryHit == 0u) {
        gNormal.write(float4(0.0, 0.0, 0.0, 1.0), gid);
        gDepth.write(float4(1e6, 0.0, 0.0, 0.0), gid);
        gRoughness.write(float4(1.0, 0.0, 0.0, 0.0), gid);
    } else {
        gNormal.write(float4(primaryNormal, 1.0), gid);
        gDepth.write(float4(primaryDepth, 0.0, 0.0, 0.0), gid);
        gRoughness.write(float4(primaryRoughness, 0.0, 0.0, 0.0), gid);
    }
}

inline float luminance(float3 c) {
    return dot(c, float3(0.299, 0.587, 0.114));
}

kernel void temporalReprojectKernel(texture2d<float, access::read> rtColor [[texture(0)]],
                                    texture2d<float, access::read> gNormal [[texture(1)]],
                                    texture2d<float, access::read> gDepth [[texture(2)]],
                                    texture2d<float, access::read> gRoughness [[texture(3)]],
                                    texture2d<float, access::read> historyColorIn [[texture(4)]],
                                    texture2d<float, access::read> historyMomentsIn [[texture(5)]],
                                    texture2d<float, access::read> historyNormalIn [[texture(6)]],
                                    texture2d<float, access::read> historyDepthIn [[texture(7)]],
                                    texture2d<float, access::write> historyColorOut [[texture(8)]],
                                    texture2d<float, access::write> historyMomentsOut [[texture(9)]],
                                    texture2d<float, access::write> historyNormalOut [[texture(10)]],
                                    texture2d<float, access::write> historyDepthOut [[texture(11)]],
                                    texture2d<float, access::write> outTemporal [[texture(12)]],
                                    constant RTFrameUniforms& frame [[buffer(BufferIndexRTFrame)]],
                                    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= frame.imageSize.x || gid.y >= frame.imageSize.y) {
        return;
    }

    float3 currColor = rtColor.read(gid).xyz;
    float3 currNormal = gNormal.read(gid).xyz;
    float currDepth = gDepth.read(gid).x;
    float currRoughness = gRoughness.read(gid).x;

    float luma = luminance(currColor);
    float2 currMoments = float2(luma, luma * luma);

    if (frame.resetHistory != 0 || currDepth > 1e5) {
        historyColorOut.write(float4(currColor, 1.0), gid);
        historyMomentsOut.write(float4(currMoments, 0.0, 0.0), gid);
        historyNormalOut.write(float4(currNormal, 1.0), gid);
        historyDepthOut.write(float4(currDepth, 0.0, 0.0, 0.0), gid);
        outTemporal.write(float4(currColor, 1.0), gid);
        return;
    }

    float2 pixel = (float2(gid) + 0.5) / float2(frame.imageSize);
    float2 ndc = float2(pixel.x * 2.0 - 1.0, (1.0 - pixel.y) * 2.0 - 1.0);
    float4 clip = float4(ndc, 1.0, 1.0);
    float4 world = frame.invViewProj * clip;
    float3 dir = normalize(world.xyz / world.w - frame.cameraPosition);
    float3 worldPos = frame.cameraPosition + dir * currDepth;

    float4 prevClip = frame.prevViewProj * float4(worldPos, 1.0);
    if (prevClip.w <= 0.0) {
        historyColorOut.write(float4(currColor, 1.0), gid);
        historyMomentsOut.write(float4(currMoments, 0.0, 0.0), gid);
        historyNormalOut.write(float4(currNormal, 1.0), gid);
        historyDepthOut.write(float4(currDepth, 0.0, 0.0, 0.0), gid);
        outTemporal.write(float4(currColor, 1.0), gid);
        return;
    }

    float2 prevNdc = prevClip.xy / prevClip.w;
    float2 prevUv = float2(prevNdc.x * 0.5 + 0.5, 1.0 - (prevNdc.y * 0.5 + 0.5));
    if (any(prevUv < 0.0) || any(prevUv > 1.0)) {
        historyColorOut.write(float4(currColor, 1.0), gid);
        historyMomentsOut.write(float4(currMoments, 0.0, 0.0), gid);
        historyNormalOut.write(float4(currNormal, 1.0), gid);
        historyDepthOut.write(float4(currDepth, 0.0, 0.0, 0.0), gid);
        outTemporal.write(float4(currColor, 1.0), gid);
        return;
    }

    uint2 prevCoord = uint2(prevUv * float2(frame.imageSize));
    prevCoord.x = min(prevCoord.x, frame.imageSize.x - 1);
    prevCoord.y = min(prevCoord.y, frame.imageSize.y - 1);

    float3 historyColor = historyColorIn.read(prevCoord).xyz;
    float2 historyMoments = historyMomentsIn.read(prevCoord).xy;
    float3 historyNormal = historyNormalIn.read(prevCoord).xyz;
    float historyDepth = historyDepthIn.read(prevCoord).x;

    float prevExpectedDepth = length(worldPos - frame.prevCameraPosition);
    float depthThreshold = max(0.05, prevExpectedDepth * 0.01);
    float normalThreshold = mix(0.7, 0.9, 1.0 - currRoughness);

    bool depthOk = fabs(historyDepth - prevExpectedDepth) <= depthThreshold;
    bool normalOk = dot(currNormal, historyNormal) >= normalThreshold;
    bool valid = depthOk && normalOk;

    float historyWeight = valid ? frame.historyWeight : 0.0;
    float variance = max(historyMoments.y - historyMoments.x * historyMoments.x, 0.0);
    float sigma = sqrt(variance + 1e-5);
    float3 clampedHistory = clamp(historyColor,
                                  currColor - frame.historyClamp * sigma,
                                  currColor + frame.historyClamp * sigma);

    float3 outColor = mix(currColor, clampedHistory, historyWeight);
    float2 outMoments = mix(currMoments, historyMoments, historyWeight);

    historyColorOut.write(float4(outColor, 1.0), gid);
    historyMomentsOut.write(float4(outMoments, 0.0, 0.0), gid);
    historyNormalOut.write(float4(currNormal, 1.0), gid);
    historyDepthOut.write(float4(currDepth, 0.0, 0.0, 0.0), gid);
    outTemporal.write(float4(outColor, 1.0), gid);
}

kernel void spatialDenoiseKernel(texture2d<float, access::read> temporalColor [[texture(0)]],
                                 texture2d<float, access::read> gNormal [[texture(1)]],
                                 texture2d<float, access::read> gDepth [[texture(2)]],
                                 texture2d<float, access::read> gRoughness [[texture(3)]],
                                 texture2d<float, access::write> outTexture [[texture(4)]],
                                 constant RTFrameUniforms& frame [[buffer(BufferIndexRTFrame)]],
                                 uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= frame.imageSize.x || gid.y >= frame.imageSize.y) {
        return;
    }

    float3 center = temporalColor.read(gid).xyz;
    float3 centerNormal = gNormal.read(gid).xyz;
    float centerDepth = gDepth.read(gid).x;
    float centerRoughness = gRoughness.read(gid).x;

    if (centerDepth > 1e5) {
        outTexture.write(float4(center, 1.0), gid);
        return;
    }

    float depthSigma = 1.0 / max(centerDepth * 0.02, 0.01);
    float normalSigma = mix(16.0, 4.0, centerRoughness);
    float colorSigma = max(frame.denoiseSigma, 0.1);
    int step = max(int(frame.atrousStep + 0.5), 1);

    float3 sum = float3(0.0);
    float wsum = 0.0;

    const float k[5] = { 1.0, 4.0, 6.0, 4.0, 1.0 };
    for (int fy = -2; fy <= 2; ++fy) {
        int yy = int(gid.y) + fy * step;
        if (yy < 0 || yy >= int(frame.imageSize.y)) { continue; }
        for (int fx = -2; fx <= 2; ++fx) {
            int xx = int(gid.x) + fx * step;
            if (xx < 0 || xx >= int(frame.imageSize.x)) { continue; }
            uint2 coord = uint2(xx, yy);
            float3 c = temporalColor.read(coord).xyz;
            float3 n = gNormal.read(coord).xyz;
            float d = gDepth.read(coord).x;

            float depthDiff = fabs(d - centerDepth);
            float normalDiff = max(0.0, 1.0 - dot(centerNormal, n));
            float colorDiff = length(c - center);

            float w = 1.0 / (1.0 + depthDiff * depthDiff * depthSigma);
            w *= 1.0 / (1.0 + normalDiff * normalDiff * normalSigma);
            w *= 1.0 / (1.0 + colorDiff * colorDiff * colorSigma);
            w *= k[fy + 2] * k[fx + 2];
            sum += c * w;
            wsum += w;
        }
    }

    float3 outc = (wsum > 0.0) ? (sum / wsum) : center;
    outTexture.write(float4(outc, 1.0), gid);
}
