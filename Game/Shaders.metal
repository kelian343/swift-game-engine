//
//  Shaders.metal
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

#include <metal_stdlib>
#include <metal_raytracing>
#include <simd/simd.h>
#import "ShaderTypes.h"

using namespace metal;
using namespace metal::raytracing;

#define MAX_RT_TEXTURES 32

#include "ShadersRaster.metalinc"
#include "RayTracing.metalinc"
#include "Denoise.metalinc"
