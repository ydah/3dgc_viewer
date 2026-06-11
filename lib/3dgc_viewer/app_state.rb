# frozen_string_literal: true

require "logger"
require_relative "binary_pack"
require_relative "camera"
require_relative "gaussian"
require_relative "gaussian_resources"
require_relative "library_locator"
require_relative "passes"
require_relative "ply_loader"
require_relative "scene_uniform"
require_relative "shader_loader"
require_relative "wgpu/surface_shim"
require_relative "window/glfw"

module ThreeDgcViewer
  class AppState
    GPU_MEMORY_WARNING_BYTES = 4 * 1024 * 1024 * 1024

    attr_reader :window, :scene_type, :resources, :camera, :scene_uniform, :show_axis, :recent_files,
                :render_width, :render_height, :time_speed, :time_paused

    def initialize(window, logger: Logger.new($stderr), show_axis: true,
                   render_width: Scene::SCREEN_WIDTH, render_height: Scene::SCREEN_HEIGHT,
                   follow_window_render_size: false, initial_camera: nil,
                   initial_time: 0.0, time_speed: Scene::TIME_SPEED, time_paused: false,
                   power_preference: :high_performance, present_mode: nil,
                   background_color: [0.0, 0.0, 0.0, 1.0], exposure: 1.0, gamma: 1.0,
                   watch_files: false, pair_capacity_factor: 32)
      @window = window
      @logger = logger
      @show_axis = show_axis
      @follow_window_render_size = follow_window_render_size
      @time_speed = time_speed.to_f
      @time_paused = time_paused
      @power_preference = power_preference
      @requested_present_mode = present_mode
      @watch_files = watch_files
      @pair_capacity_factor = pair_capacity_factor
      @render_width = positive_int(render_width)
      @render_height = positive_int(render_height)
      sync_render_size_to_window if @follow_window_render_size
      @is_surface_configured = false
      @scene_dirty = true
      @scene_type = :gaussian3d
      @scene_bounds = Gaussian::Bounds.empty
      @scene_label = nil
      @scene_path = nil
      @scene_mtime = nil
      @recent_files = []
      @last_fps = nil
      @resource_generation = 0
      @pair_overflow_readback = nil
      @last_update_time = monotonic_time
      @fps_timer = monotonic_time
      @frame_count = 0
      @default_camera = copy_camera(initial_camera || Camera.default(width: window.width, height: window.height))
      @camera = copy_camera(@default_camera)
      @camera_controller = CameraController.new
      @camera_controller.sync_from_camera(@camera)
      @scene_uniform = SceneUniform.new(
        screen_width: @render_width,
        screen_height: @render_height,
        background_color: background_color,
        exposure: exposure,
        gamma: gamma
      )
      @scene_uniform.update_camera(@camera)
      @scene_uniform.set_time(initial_time)
      @resources = build_gaussian_resources(Gaussian::GaussianSet.new(kind: :gaussian3d, items: []))
    end

    def initialize_gpu
      require "wgpu"

      WGPU::SurfaceShim.load!
      @logger.info("wgpu-native: #{::WGPU::Native.library_path}")
      surface_shim = LibraryLocator.surface_shim_location
      @logger.info("surface shim: #{surface_shim.path} (#{surface_shim.source}, exists=#{surface_shim.exists})")

      @instance = ::WGPU::Instance.new
      surface_ptr = WGPU::SurfaceShim.rbwgv_create_surface(@instance.handle, @window.ptr)
      raise WgpuError, "surface shim returned null surface" if surface_ptr.null?

      @surface = ::WGPU::Surface.new(surface_ptr, @instance)
      @adapter = @instance.request_adapter(power_preference: @power_preference, compatible_surface: @surface)
      @device = @adapter.request_device
      @queue = @device.queue
      @logger.info("Adapter: #{@adapter.info.inspect}") if @adapter.respond_to?(:info)
      configure_surface
      sync_render_size_to_window if @follow_window_render_size
      create_render_targets
      create_gpu_scene
      create_passes
      @is_surface_configured = true
    rescue ::WGPU::Error => e
      raise WgpuError, e.message
    end

    def handle_key(key, action)
      pressed = action == Window::GLFW::GLFW_PRESS || action == Window::GLFW::GLFW_REPEAT
      return @window.request_close if key == Window::Keymap::KEY_ESCAPE && pressed
      return if pressed && handle_shortcut(key)

      @scene_dirty = true if @camera_controller.handle_key(key, pressed)
    end

    def handle_mouse_button(button, action, x, y)
      pressed = action == Window::GLFW::GLFW_PRESS
      if pressed
        mode = pointer_mode_for(button)
        @scene_dirty = true if mode && @camera_controller.begin_pointer(mode, x, y)
        return
      end

      @scene_dirty = true if action == Window::GLFW::GLFW_RELEASE && @camera_controller.end_pointer
    end

    def handle_cursor(x, y)
      @scene_dirty = true if @camera_controller.move_pointer(@camera, x, y) == :active
    end

    def handle_scroll(_x_offset, y_offset)
      @scene_dirty = true if @camera_controller.scroll(@camera, y_offset) == :active
    end

    def handle_drops(paths, max_pairs: nil)
      paths = Array(paths).compact
      return @logger.warn("drop ignored: no files") if paths.empty?

      @logger.warn("multiple files dropped; loading first and ignoring #{paths.length - 1}") if paths.length > 1
      handle_drop(paths.first, max_pairs: max_pairs)
    end

    def handle_drop(path, max_pairs: nil)
      gaussian_set = PlyLoader.parse_file(path, retain_items: false)
      replace_gaussians(gaussian_set, max_pairs: max_pairs)
      @scene_path = path
      @scene_mtime = safe_mtime(path)
      @scene_label = File.basename(path)
      add_recent_file(path)
      @logger.info("loaded #{gaussian_set.kind} with #{gaussian_set.count} gaussians")
      log_resource_estimate
      update_window_title
      if gaussian_set.statistics.invalid_count.positive?
        @logger.warn("ignored #{gaussian_set.statistics.invalid_count} invalid gaussians")
      end
    rescue PlyError => e
      @logger.error("PLY parse failed: #{e.message}")
    end

    def resize(width, height)
      @camera.aspect = width.to_f / height.to_f if height.positive?
      if @is_surface_configured
        configure_surface
        recreate_depth_target
        resize_render_target(width, height) if @follow_window_render_size
      end
      @scene_dirty = true
    end

    def update
      now = monotonic_time
      dt = now - @last_update_time
      @last_update_time = now

      reload_changed_scene if @watch_files
      @scene_dirty = true if @camera_controller.update_camera(@camera, dt) == :active
      @scene_uniform.update_camera(@camera)
      @scene_uniform.update_gaussian_count(@resources.gaussian_count)
      @scene_uniform.update_time(dt, speed: @time_speed) if Scene.dynamic?(@scene_type) && !@time_paused
      @queue&.write_buffer(@scene_uniform_buffer, 0, @scene_uniform.pack) if @scene_uniform_buffer
    end

    def render
      render_gpu_frame if @is_surface_configured
      @frame_count += 1
      now = monotonic_time
      return if now - @fps_timer < 5.0

      @last_fps = (@frame_count / (now - @fps_timer)).round(1)
      @logger.info("fps: #{@last_fps}")
      update_window_title
      @frame_count = 0
      @fps_timer = now
    end

    def render_texture_rgb_nonzero?
      raise WgpuError, "GPU is not initialized" unless @device && @queue && @render_texture

      row_bytes = @render_width * 4
      bytes_per_row = align_copy_bytes_per_row(row_bytes)
      data = @queue.read_texture(
        source: {texture: @render_texture},
        data_layout: {
          offset: 0,
          bytes_per_row: bytes_per_row,
          rows_per_image: @render_height
        },
        size: {
          width: @render_width,
          height: @render_height,
          depth_or_array_layers: 1
        },
        device: @device
      )
      @render_height.times.any? do |row|
        data.byteslice(row * bytes_per_row, row_bytes).bytes.each_slice(4).any? do |r, g, b, _a|
          r.to_i.positive? || g.to_i.positive? || b.to_i.positive?
        end
      end
    end

    def should_request_redraw?
      @scene_dirty || Scene.dynamic?(@scene_type)
    end

    def release
      release_completed_pair_overflow_readback
      [
        @preprocess_pass, @prefix_scan_pass, @duplicate_pass, @radix_sort_pass,
        @tile_range_pass, @tile_render_pass, @screen_blit_pass, @axis_pass,
        @scene_uniform_buffer, @render_texture_view, @render_texture_sampler,
        @render_texture, @depth_texture_view, @depth_texture, @surface,
        @queue, @device, @adapter, @instance
      ].compact.each { |object| object.release if object.respond_to?(:release) }
      @resources&.release
    end

    def replace_gaussians(gaussian_set, max_pairs: nil, auto_fit: true)
      @resources.release
      @resources = build_gaussian_resources(gaussian_set, max_pairs: max_pairs)
      @resource_generation += 1
      new_scene_type = gaussian_set.kind
      if @preprocess_pass
        if @scene_type == new_scene_type
          @preprocess_pass.recreate_bind_group(resources: @resources, scene_uniform_buffer: @scene_uniform_buffer)
        else
          @preprocess_pass.release
          @preprocess_pass = Passes::PreprocessPass.new(
            device: @device,
            resources: @resources,
            scene_uniform_buffer: @scene_uniform_buffer,
            scene_type: new_scene_type,
            shader_loader: @shader_loader
          )
        end

        @prefix_scan_pass.recreate_bind_group(resources: @resources)
        @duplicate_pass.recreate_bind_group(resources: @resources)
        @radix_sort_pass.recreate_bind_group(resources: @resources)
        @tile_range_pass.recreate_bind_group(resources: @resources)
        @tile_render_pass.recreate_bind_group(resources: @resources, scene_uniform_buffer: @scene_uniform_buffer, render_texture_view: @render_texture_view)
        @screen_blit_pass.recreate_bind_group(resources: @resources, render_texture_view: @render_texture_view, render_texture_sampler: @render_texture_sampler)
      end

      @scene_type = new_scene_type
      @scene_bounds = gaussian_set.statistics.bounds
      fit_camera_to_scene(gaussian_set.statistics.bounds) if auto_fit
      @scene_uniform.update_gaussian_count(@resources.gaussian_count)
      @scene_uniform.update_screen_size(@render_width, @render_height)
      @queue&.write_buffer(@scene_uniform_buffer, 0, @scene_uniform.pack) if @scene_uniform_buffer
      @scene_dirty = true
    end

    private

    def build_gaussian_resources(gaussian_set, max_pairs: nil)
      GaussianResources.new(
        device: @device,
        queue: @queue,
        gaussian_set: gaussian_set,
        render_width: @render_width,
        render_height: @render_height,
        max_pairs: max_pairs,
        pair_capacity_factor: @pair_capacity_factor
      )
    end

    def pointer_mode_for(button)
      case button
      when Window::GLFW::MOUSE_BUTTON_LEFT
        CameraController::POINTER_ORBIT
      when Window::GLFW::MOUSE_BUTTON_RIGHT, Window::GLFW::MOUSE_BUTTON_MIDDLE
        CameraController::POINTER_PAN
      end
    end

    def handle_shortcut(key)
      case key
      when Window::Keymap::KEY_F
        fit_camera_to_scene(@scene_bounds)
      when Window::Keymap::KEY_L
        return reload_scene
      when Window::Keymap::KEY_R
        reset_camera
      when Window::Keymap::KEY_X
        @show_axis = !@show_axis
      else
        return false
      end

      @scene_dirty = true
      true
    end

    def reload_scene
      return false unless @scene_path

      handle_drop(@scene_path, max_pairs: @resources.max_pairs)
      true
    end

    def reset_camera
      @camera = copy_camera(@default_camera)
      @camera_controller = CameraController.new
      @camera_controller.sync_from_camera(@camera)
      @scene_uniform.update_camera(@camera)
    end

    def copy_camera(camera)
      Camera.new(
        eye: camera.eye.dup,
        target: camera.target.dup,
        up: camera.up.dup,
        aspect: camera.aspect,
        fovy: camera.fovy,
        znear: camera.znear,
        zfar: camera.zfar
      )
    end

    def resize_render_target(width, height)
      width = positive_int(width)
      height = positive_int(height)
      return if @render_width == width && @render_height == height

      @render_width = width
      @render_height = height
      @scene_uniform.update_screen_size(@render_width, @render_height)
      @queue&.write_buffer(@scene_uniform_buffer, 0, @scene_uniform.pack) if @scene_uniform_buffer
      return unless @device

      gaussian_set = @resources.gaussian_set
      max_pairs = @resources.max_pairs
      recreate_render_texture
      replace_gaussians(gaussian_set, max_pairs: max_pairs, auto_fit: false)
      @logger.info("render size: #{@render_width}x#{@render_height}")
    end

    def fit_camera_to_scene(bounds)
      return if bounds.nil? || bounds.empty?

      @camera.fit_bounds(bounds)
      @camera_controller.fit_scene_radius(bounds.radius)
      @camera_controller.sync_from_camera(@camera)
      @scene_uniform.update_camera(@camera)
    end

    def log_resource_estimate
      bytes = @resources.estimated_buffer_bytes
      level = bytes > GPU_MEMORY_WARNING_BYTES ? :warn : :info
      @logger.public_send(level, "GPU buffer estimate: #{format_bytes(bytes)}")
    end

    def format_bytes(bytes)
      units = %w[B KiB MiB GiB TiB]
      value = bytes.to_f
      unit = units.first
      units.each do |candidate|
        unit = candidate
        break if value < 1024.0 || candidate == units.last

        value /= 1024.0
      end
      "#{value.round(1)} #{unit}"
    end

    def update_window_title
      return unless @window.respond_to?(:title=)

      parts = ["3dgc_viewer"]
      parts << @scene_label if @scene_label
      parts << "#{@resources.gaussian_count} gaussians" if @resources
      parts << "#{@last_fps} FPS" if @last_fps
      @window.title = parts.join(" - ")
    end

    def reload_changed_scene
      return unless @scene_path

      mtime = safe_mtime(@scene_path)
      return unless mtime && @scene_mtime && mtime > @scene_mtime

      @logger.info("detected file change; reloading #{@scene_path}")
      reload_scene
    end

    def safe_mtime(path)
      File.mtime(path)
    rescue SystemCallError
      nil
    end

    def add_recent_file(path)
      expanded = File.expand_path(path)
      @recent_files.delete(expanded)
      @recent_files.unshift(expanded)
      @recent_files = @recent_files.first(10)
    end

    def sync_render_size_to_window
      width, height = @window.framebuffer_size
      @render_width = positive_int(width)
      @render_height = positive_int(height)
    end

    def align_copy_bytes_per_row(row_bytes)
      ((row_bytes + 255) / 256) * 256
    end

    def positive_int(value)
      [value.to_i, 1].max
    end

    def configure_surface
      width, height = @window.framebuffer_size
      width = [width, 1].max
      height = [height, 1].max
      caps = @surface.capabilities(@adapter)
      @surface_format = choose_surface_format(caps[:formats])
      @present_mode = choose_present_mode(caps[:present_modes])
      @alpha_mode = caps[:alpha_modes].first || :auto
      @surface.configure(
        device: @device,
        format: @surface_format,
        usage: :render_attachment,
        width: width,
        height: height,
        present_mode: @present_mode,
        alpha_mode: @alpha_mode
      )
      @logger.info("Surface format: #{@surface_format}")
    end

    def choose_surface_format(formats)
      preferred = %i[rgba8_unorm bgra8_unorm]
      preferred.find { |format| formats.include?(format) } ||
        formats.find { |format| !format.to_s.include?("srgb") } ||
        formats.first ||
        :bgra8_unorm
    end

    def choose_present_mode(modes)
      return @requested_present_mode if @requested_present_mode && modes.include?(@requested_present_mode)

      modes.first || :fifo
    end

    def create_render_targets
      recreate_depth_target
      recreate_render_texture
    end

    def recreate_render_texture
      @render_texture_view&.release if @render_texture_view&.respond_to?(:release)
      @render_texture_sampler&.release if @render_texture_sampler&.respond_to?(:release)
      @render_texture&.release if @render_texture&.respond_to?(:release)

      @render_texture = @device.create_texture(
        label: "Render Texture",
        size: {width: @render_width, height: @render_height, depth_or_array_layers: 1},
        format: :rgba8_unorm,
        usage: %i[storage_binding texture_binding copy_src]
      )
      @render_texture_view = @render_texture.create_view
      @render_texture_sampler = @device.create_sampler(
        label: "Render Texture Sampler",
        address_mode_u: :clamp_to_edge,
        address_mode_v: :clamp_to_edge,
        address_mode_w: :clamp_to_edge,
        mag_filter: :linear,
        min_filter: :nearest,
        mipmap_filter: :nearest
      )
    end

    def recreate_depth_target
      @depth_texture_view&.release if @depth_texture_view&.respond_to?(:release)
      @depth_texture&.release if @depth_texture&.respond_to?(:release)

      width, height = @window.framebuffer_size
      width = [width, 1].max
      height = [height, 1].max

      @depth_texture = @device.create_texture(
        label: "Depth Texture",
        size: {width: width, height: height, depth_or_array_layers: 1},
        format: :depth32_float,
        usage: %i[render_attachment texture_binding]
      )
      @depth_texture_view = @depth_texture.create_view
    end

    def create_gpu_scene
      @resources.release
      @resources = build_gaussian_resources(Gaussian::GaussianSet.new(kind: :gaussian3d, items: []))
      @resource_generation += 1
      @scene_uniform.update_screen_size(@render_width, @render_height)
      @scene_uniform.update_camera(@camera)
      @scene_uniform.update_gaussian_count(@resources.gaussian_count)
      @scene_uniform_buffer = @device.create_buffer_with_data(
        label: "Scene Uniform Buffer",
        data: @scene_uniform.pack,
        usage: %i[uniform copy_dst]
      )
    end

    def create_passes
      @shader_loader = ShaderLoader.new(@device)
      @preprocess_pass = Passes::PreprocessPass.new(
        device: @device,
        resources: @resources,
        scene_uniform_buffer: @scene_uniform_buffer,
        scene_type: @scene_type,
        shader_loader: @shader_loader
      )
      @prefix_scan_pass = Passes::PrefixScanPass.new(device: @device, resources: @resources, shader_loader: @shader_loader)
      @duplicate_pass = Passes::DuplicatePass.new(device: @device, resources: @resources, shader_loader: @shader_loader)
      @radix_sort_pass = Passes::RadixSortPass.new(device: @device, resources: @resources, shader_loader: @shader_loader)
      @tile_range_pass = Passes::TileRangePass.new(device: @device, resources: @resources, shader_loader: @shader_loader)
      @tile_render_pass = Passes::TileRenderPass.new(
        device: @device,
        resources: @resources,
        scene_uniform_buffer: @scene_uniform_buffer,
        render_texture_view: @render_texture_view,
        shader_loader: @shader_loader
      )
      @screen_blit_pass = Passes::ScreenBlitPass.new(
        device: @device,
        resources: @resources,
        render_texture_view: @render_texture_view,
        render_texture_sampler: @render_texture_sampler,
        surface_format: @surface_format,
        depth_format: :depth32_float,
        shader_loader: @shader_loader
      )
      @axis_pass = Passes::AxisPass.new(
        device: @device,
        resources: @resources,
        scene_uniform_buffer: @scene_uniform_buffer,
        surface_format: @surface_format,
        shader_loader: @shader_loader
      )
    end

    def render_gpu_frame
      tile_pipeline_ran = false
      @queue.write_buffer(@resources.visible_count_buffer, 0, BinaryPack.u32(0))
      frame_texture = @surface.current_texture
      frame_view = frame_texture.create_view
      encoder = @device.create_command_encoder(label: "Frame Encoder")

      if @scene_dirty || Scene.dynamic?(@scene_type)
        @preprocess_pass.encode(encoder)
        @prefix_scan_pass.encode(encoder)
        @duplicate_pass.encode(encoder)
        @radix_sort_pass.encode(encoder)
        @tile_range_pass.encode(encoder)
        @tile_render_pass.encode(encoder)
        tile_pipeline_ran = true
        @scene_dirty = false
      end

      @screen_blit_pass.encode(encoder, surface_texture_view: frame_view, depth_texture_view: @depth_texture_view)
      @axis_pass.encode(encoder, surface_texture_view: frame_view) if @show_axis
      @queue.submit([encoder.finish])
      @surface.present
      overflow_resized = poll_pair_overflow_readback
      start_pair_overflow_readback if tile_pipeline_ran && !overflow_resized
    rescue ::WGPU::SurfaceError => e
      @logger.warn("surface frame skipped: #{e.message}")
      configure_surface
    ensure
      frame_view&.release if frame_view&.respond_to?(:release)
      frame_texture&.release if frame_texture&.respond_to?(:release)
    end

    def poll_pair_overflow_readback
      readback = @pair_overflow_readback
      return false unless readback
      return false unless readback[:task].complete?

      @pair_overflow_readback = nil
      readback[:task].value
      data = readback[:staging].read_mapped_data(offset: 0, size: 16)
      readback[:staging].unmap
      readback[:staging].release if readback[:staging].respond_to?(:release)
      return false unless readback[:generation] == @resource_generation

      raw_total_pairs, sort_pair_count, visible_count, overflow = data.unpack("L<4")
      return false if overflow.to_i.zero? && raw_total_pairs.to_i <= readback[:max_pairs]

      next_max_pairs = GaussianResources.next_pair_capacity(raw_total_pairs, readback[:max_pairs])
      @logger.warn(
        "pair buffer overflow: raw_total_pairs=#{raw_total_pairs}, " \
        "sort_pair_count=#{sort_pair_count}, visible_count=#{visible_count}, " \
        "max_pairs=#{readback[:max_pairs]}; resizing to #{next_max_pairs}"
      )
      replace_gaussians(@resources.gaussian_set, max_pairs: next_max_pairs, auto_fit: false)
      true
    rescue StandardError => e
      @logger.warn("pair overflow readback failed: #{e.message}")
      release_pair_overflow_readback(readback)
      @pair_overflow_readback = nil
      false
    end

    def start_pair_overflow_readback
      return unless @resources.gaussian_count.positive?
      return if @pair_overflow_readback

      staging = ::WGPU::Buffer.new(
        @device,
        label: "Total Pairs Readback",
        size: 16,
        usage: %i[map_read copy_dst]
      )
      encoder = ::WGPU::CommandEncoder.new(@device, label: "Pair Overflow Readback Encoder")
      encoder.copy_buffer_to_buffer(source: @resources.total_pairs_buffer, destination: staging, size: 16)
      @queue.submit([encoder.finish])
      @pair_overflow_readback = {
        staging: staging,
        task: staging.map_async(:read),
        max_pairs: @resources.max_pairs,
        generation: @resource_generation
      }
    rescue StandardError => e
      @logger.warn("pair overflow readback start failed: #{e.message}")
      staging&.release if staging&.respond_to?(:release)
      @pair_overflow_readback = nil
    end

    def release_completed_pair_overflow_readback
      readback = @pair_overflow_readback
      return unless readback&.dig(:task)&.complete?

      @pair_overflow_readback = nil
      readback[:task].value
      readback[:staging].unmap
      readback[:staging].release if readback[:staging].respond_to?(:release)
    rescue StandardError
      release_pair_overflow_readback(readback)
    end

    def release_pair_overflow_readback(readback)
      return unless readback

      readback[:staging]&.unmap if readback[:staging]&.respond_to?(:unmap)
      readback[:staging]&.release if readback[:staging]&.respond_to?(:release)
    rescue StandardError
      nil
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
