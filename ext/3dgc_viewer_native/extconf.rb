# frozen_string_literal: true

require "mkmf"

begin
  require "wgpu/native/loader"
  wgpu_cache_dir = WGPU::Native.cache_dir
  wgpu_lib_dir = File.join(wgpu_cache_dir, "lib")
  dir_config("wgpu", File.join(wgpu_cache_dir, "include", "webgpu"), wgpu_lib_dir)
  $LDFLAGS << " -Wl,-rpath,#{wgpu_lib_dir}" if RUBY_PLATFORM.match?(/darwin|linux/)
rescue LoadError
  dir_config("wgpu")
end

dir_config("glfw")

abort "missing GLFW/glfw3.h" unless have_header("GLFW/glfw3.h")
abort "missing GLFW/glfw3native.h" unless have_header("GLFW/glfw3native.h")
abort "missing webgpu.h" unless have_header("webgpu.h")

if RUBY_PLATFORM.match?(/darwin/)
  $srcs = ["3dgc_viewer_surface_macos.m"]
  $LDFLAGS << " -framework Cocoa -framework QuartzCore"
elsif RUBY_PLATFORM.match?(/mingw|mswin/)
  $srcs = ["3dgc_viewer_surface.c"]
  have_library("user32")
else
  $srcs = ["3dgc_viewer_surface.c"]
end

have_library("glfw")
have_library("wgpu_native")

create_makefile("3dgc_viewer_surface")
