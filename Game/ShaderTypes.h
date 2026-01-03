//
//  ShaderTypes.h
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

//
//  Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
//
#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef metal::int32_t EnumBackingType;
#else
#import <Foundation/Foundation.h>
typedef NSInteger EnumBackingType;
#endif

#include <simd/simd.h>

typedef NS_ENUM(EnumBackingType, BufferIndex)
{
    BufferIndexMeshVertices = 0,
    BufferIndexUniforms     = 1,
    BufferIndexRTFrame      = 2,
    BufferIndexRTAccel      = 3,
    BufferIndexRTVertices   = 4,
    BufferIndexRTIndices    = 5,
    BufferIndexRTInstances  = 6,
    BufferIndexRTUVs        = 7,
    BufferIndexRTDirLights  = 8,
    BufferIndexRTPointLights = 9,
    BufferIndexRTAreaLights = 10
};

typedef NS_ENUM(EnumBackingType, VertexAttribute)
{
    VertexAttributePosition = 0,
    VertexAttributeNormal   = 1,
    VertexAttributeTexcoord = 2,
};

typedef NS_ENUM(EnumBackingType, TextureIndex)
{
    TextureIndexBaseColor   = 0
};

typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 modelMatrix;
} Uniforms;

typedef struct
{
    matrix_float4x4 invViewProj;
    vector_float3 cameraPosition;
    uint32_t frameIndex;
    vector_uint2 imageSize;
    float ambientIntensity;
    float historyWeight;
    float historyClamp;
    uint32_t samplesPerPixel;
    uint32_t dirLightCount;
    uint32_t pointLightCount;
    uint32_t areaLightCount;
    uint32_t areaLightSamples;
    uint32_t textureCount;
    float denoiseSigma;
    vector_float2 padding;
} RTFrameUniforms;

typedef struct
{
    uint32_t baseIndex;
    uint32_t baseVertex;
    uint32_t indexCount;
    uint32_t padding;
    matrix_float4x4 modelMatrix;
    vector_float3 baseColor;
    float metallic;
    float roughness;
    vector_float3 padding2;
    uint32_t baseColorTexIndex;
    vector_uint3 padding3;
} RTInstanceInfo;

typedef struct
{
    vector_float3 direction;
    float intensity;
    vector_float3 color;
    float padding;
} RTDirectionalLight;

typedef struct
{
    vector_float3 position;
    float intensity;
    vector_float3 color;
    float radius;
} RTPointLight;

typedef struct
{
    vector_float3 position;
    float intensity;
    vector_float3 u;
    float padding0;
    vector_float3 v;
    float padding1;
    vector_float3 color;
    float padding2;
} RTAreaLight;

#endif /* ShaderTypes_h */
