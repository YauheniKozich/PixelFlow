//
//  ParticleShader.metal
//  PixelFlow
//
//  Created by Yauheni Kozich on 31.10.25.
//  Updated: 2025-01-01 - Modular shader architecture
//
//  Main shader file that imports all modular components
//  Organized in Shaders/ folder for better maintainability
//

// Import common headers first (only once)
#include "Core/Common.h"
#include "Core/Utils.h"


// Import shader components (with header guards)
#include "Compute/Physics.h"
#include "Rendering/Basic.h"


// All shader functions are now distributed across the modular files above
// This file serves as the main entry point for Metal compilation
