#pragma once

#include <GLFW/glfw3.h>
#include <webgpu.h>

#ifdef __cplusplus
extern "C" {
#endif

WGPUSurface rbwgv_create_surface(WGPUInstance instance, GLFWwindow *window);

#ifdef __cplusplus
}
#endif
