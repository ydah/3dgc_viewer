#include "3dgc_viewer_surface.h"

#if defined(_WIN32)
#define GLFW_EXPOSE_NATIVE_WIN32
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>
#include <windows.h>

WGPUSurface rbwgv_create_surface(WGPUInstance instance, GLFWwindow *window) {
  HWND hwnd = glfwGetWin32Window(window);
  HINSTANCE hinstance = GetModuleHandle(NULL);
  WGPUSurfaceSourceWindowsHWND source = {
    .chain = { .next = NULL, .sType = WGPUSType_SurfaceSourceWindowsHWND },
    .hinstance = hinstance,
    .hwnd = hwnd,
  };
  WGPUSurfaceDescriptor desc = {
    .nextInChain = (const WGPUChainedStruct *)&source,
    .label = { .data = NULL, .length = 0 },
  };
  return wgpuInstanceCreateSurface(instance, &desc);
}
#endif

#if defined(__linux__)
#define GLFW_EXPOSE_NATIVE_X11
#define GLFW_EXPOSE_NATIVE_WAYLAND
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>

WGPUSurface rbwgv_create_surface(WGPUInstance instance, GLFWwindow *window) {
  if (glfwGetPlatform() == GLFW_PLATFORM_X11) {
    Display *display = glfwGetX11Display();
    Window xwindow = glfwGetX11Window(window);
    WGPUSurfaceSourceXlibWindow source = {
      .chain = { .next = NULL, .sType = WGPUSType_SurfaceSourceXlibWindow },
      .display = display,
      .window = xwindow,
    };
    WGPUSurfaceDescriptor desc = {
      .nextInChain = (const WGPUChainedStruct *)&source,
      .label = { .data = NULL, .length = 0 },
    };
    return wgpuInstanceCreateSurface(instance, &desc);
  }

  if (glfwGetPlatform() == GLFW_PLATFORM_WAYLAND) {
    struct wl_display *display = glfwGetWaylandDisplay();
    struct wl_surface *surface = glfwGetWaylandWindow(window);
    WGPUSurfaceSourceWaylandSurface source = {
      .chain = { .next = NULL, .sType = WGPUSType_SurfaceSourceWaylandSurface },
      .display = display,
      .surface = surface,
    };
    WGPUSurfaceDescriptor desc = {
      .nextInChain = (const WGPUChainedStruct *)&source,
      .label = { .data = NULL, .length = 0 },
    };
    return wgpuInstanceCreateSurface(instance, &desc);
  }

  return NULL;
}
#endif
