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
    BufferIndexRTVerticesDynamic = 9,
    BufferIndexRTIndicesDynamic  = 10,
    BufferIndexRTUVsDynamic      = 11
};

typedef NS_ENUM(EnumBackingType, VertexAttribute)
{
    VertexAttributePosition = 0,
    VertexAttributeNormal   = 1,
    VertexAttributeTexcoord = 2,
};

typedef NS_ENUM(EnumBackingType, TextureIndex)
{
    TextureIndexBaseColor       = 0,
    TextureIndexNormal          = 1,
    TextureIndexMetallicRoughness = 2,
    TextureIndexEmissive        = 3,
    TextureIndexOcclusion       = 4
};

typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 modelMatrix;
    vector_float3 baseColorFactor;
    float baseAlpha;
} Uniforms;

typedef struct
{
    matrix_float4x4 invViewProj;
    vector_float3 cameraPosition;
    vector_uint2 imageSize;
    float ambientIntensity;
    uint32_t pad0;
    uint32_t textureCount;
    uint32_t dirLightCount;
    vector_float3 envSH0;
    vector_float3 envSH1;
    vector_float3 envSH2;
    vector_float3 envSH3;
    vector_float3 envSH4;
    vector_float3 envSH5;
    vector_float3 envSH6;
    vector_float3 envSH7;
    vector_float3 envSH8;
} RTFrameUniforms;

typedef struct
{
    uint32_t baseIndex;
    uint32_t baseVertex;
    uint32_t indexCount;
    uint32_t bufferIndex;
    matrix_float4x4 modelMatrix;
    vector_float3 baseColorFactor;
    float metallicFactor;
    vector_float3 emissiveFactor;
    float occlusionStrength;
    vector_float2 mrFactors;
    vector_float2 padding0;
    uint32_t baseColorTexIndex;
    uint32_t normalTexIndex;
    uint32_t metallicRoughnessTexIndex;
    uint32_t emissiveTexIndex;
    uint32_t occlusionTexIndex;
    vector_uint3 padding1;
} RTInstanceInfo;

typedef struct
{
    vector_float3 direction;
    float intensity;
    vector_float3 color;
    float padding;
} RTDirectionalLight;

#endif /* ShaderTypes_h */
