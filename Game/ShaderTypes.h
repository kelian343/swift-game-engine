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
    BufferIndexLight        = 2
};

typedef NS_ENUM(EnumBackingType, VertexAttribute)
{
    VertexAttributePosition = 0,
    VertexAttributeNormal   = 1,
    VertexAttributeTexcoord = 2,
};

typedef NS_ENUM(EnumBackingType, TextureIndex)
{
    TextureIndexBaseColor   = 0,
    TextureIndexShadowMap   = 1
};

typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 modelMatrix;

    matrix_float4x4 lightViewProjMatrix;

    // 3x3 packed in 3 float4 (alignment friendly)
    vector_float4 normalMatrix0;
    vector_float4 normalMatrix1;
    vector_float4 normalMatrix2;
} Uniforms;

typedef struct
{
    vector_float3 lightDirection; // direction *toward* surface (i.e. from light to world is -dir)
    float         padding0;

    vector_float3 lightColor;
    float         ambientIntensity;

    vector_float3 cameraPosition;
    float         shadowBias; // e.g. 0.001 ~ 0.01
} LightParams;

#endif /* ShaderTypes_h */
