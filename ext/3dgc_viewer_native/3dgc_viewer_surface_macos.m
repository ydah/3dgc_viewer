#define GLFW_EXPOSE_NATIVE_COCOA

#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>
#include <Foundation/Foundation.h>
#include <QuartzCore/CAMetalLayer.h>

#include "3dgc_viewer_surface.h"

WGPUSurface rbwgv_create_surface(WGPUInstance instance, GLFWwindow *window) {
  NSWindow *ns_window = glfwGetCocoaWindow(window);
  [ns_window.contentView setWantsLayer:YES];
  id metal_layer = [CAMetalLayer layer];
  [ns_window.contentView setLayer:metal_layer];

  WGPUSurfaceSourceMetalLayer source = {
    .chain = { .next = NULL, .sType = WGPUSType_SurfaceSourceMetalLayer },
    .layer = metal_layer,
  };
  WGPUSurfaceDescriptor desc = {
    .nextInChain = (const WGPUChainedStruct *)&source,
    .label = { .data = NULL, .length = 0 },
  };
  return wgpuInstanceCreateSurface(instance, &desc);
}
