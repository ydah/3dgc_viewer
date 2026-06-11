# frozen_string_literal: true

require "rbconfig"

module ThreeDgcViewer
  module LibraryLocator
    Location = Struct.new(:path, :source, :exists, keyword_init: true)

    module_function

    def root
      File.expand_path("../..", __dir__)
    end

    def platform
      host_os = RbConfig::CONFIG.fetch("host_os")
      host_cpu = RbConfig::CONFIG.fetch("host_cpu")

      os =
        case host_os
        when /darwin/ then "macos"
        when /linux/ then "linux"
        when /mswin|mingw|cygwin/ then "windows"
        else host_os
        end

      cpu =
        case host_cpu
        when /arm64|aarch64/ then "arm64"
        when /x86_64|amd64/ then "x64"
        else host_cpu
        end

      "#{os}-#{cpu}"
    end

    def shared_library_extension
      case platform
      when /^macos-/ then "dylib"
      when /^windows-/ then "dll"
      else "so"
      end
    end

    def wgpu_native_path
      wgpu_native_location.path
    end

    def wgpu_native_location
      locate(
        env_key: "WGPU_NATIVE_LIB",
        vendor_glob: File.join(root, "vendor", "wgpu-native", platform, "libwgpu_native.*"),
        fallback: fallback_library_name("wgpu_native")
      )
    end

    def glfw_path
      glfw_location.path
    end

    def glfw_location
      locate(
        env_key: "GLFW_LIB",
        vendor_glob: File.join(root, "vendor", "glfw", platform, "libglfw*"),
        fallback: fallback_library_name("glfw")
      )
    end

    def surface_shim_path
      surface_shim_location.path
    end

    def surface_shim_location
      locate(
        env_key: "THREEDGC_SURFACE_SHIM_LIB",
        vendor_glob: File.join(root, "ext", "3dgc_viewer_native", "3dgc_viewer_surface.{bundle,dylib,so,dll}"),
        fallback: fallback_library_name("3dgc_viewer_surface")
      )
    end

    def shader_dir
      File.join(root, "shaders")
    end

    def locate(env_key:, vendor_glob:, fallback:)
      env_path = ENV[env_key]
      return location(env_path, :env) if env_path && !env_path.empty?

      vendor_path = Dir[vendor_glob].find { |path| File.file?(path) }
      return location(vendor_path, :vendor) if vendor_path

      location(fallback, :fallback)
    end

    def location(path, source)
      Location.new(path: path, source: source, exists: File.file?(path))
    end

    def fallback_library_name(base)
      return "#{base}.dll" if platform.start_with?("windows-")

      "lib#{base}.#{shared_library_extension}"
    end
  end
end
