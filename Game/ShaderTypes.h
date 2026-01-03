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
    BufferIndexRTInstances  = 6
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
    vector_float3 lightDirection;
    float lightIntensity;
    vector_float3 lightColor;
    float ambientIntensity;
} RTFrameUniforms;

typedef struct
{
    uint32_t baseIndex;
    uint32_t baseVertex;
    uint32_t indexCount;
    uint32_t padding;
    matrix_float4x4 modelMatrix;
} RTInstanceInfo;

#endif /* ShaderTypes_h */
