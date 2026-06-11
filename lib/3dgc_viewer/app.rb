# frozen_string_literal: true

require "logger"
require "optparse"
require "json"
require_relative "app_state"
require_relative "ply_loader"
require_relative "version"
require_relative "window/glfw"

module ThreeDgcViewer
  class App
    LOG_LEVELS = {
      "debug" => Logger::DEBUG,
      "info" => Logger::INFO,
      "warn" => Logger::WARN,
      "warning" => Logger::WARN,
      "error" => Logger::ERROR
    }.freeze
    MAX_WINDOW_DIMENSION = 32_768
    MAX_RENDER_DIMENSION = 32_768
    MAX_RENDER_SCALE = 4.0
    POWER_PREFERENCES = {
      "high-performance" => :high_performance,
      "high_performance" => :high_performance,
      "low-power" => :low_power,
      "low_power" => :low_power
    }.freeze
    PRESENT_MODES = {
      "fifo" => :fifo,
      "mailbox" => :mailbox,
      "immediate" => :immediate
    }.freeze
    QUALITY_PAIR_FACTORS = {
      fast: 16,
      balanced: 32,
      quality: 64
    }.freeze

    Options = Struct.new(
      :file, :width, :height, :log_level, :wgpu_native, :glfw, :show_axis,
      :render_width, :render_height, :render_scale, :render_size_window,
      :max_pairs, :window_only, :validate_ply, :print_scene_info, :print_gpu_info,
      :hidden, :smoke_frame, :smoke_resize,
      :smoke_camera, :assert_render_nonzero,
      :eye, :target, :up, :fov, :znear, :zfar,
      :time, :time_speed, :pause, :power_preference, :present_mode,
      :background_color, :exposure, :gamma,
      :watch, :quality, :low_vram, :json,
      keyword_init: true
    )

    def self.run(argv)
      new(parse_options(argv)).run
    rescue OptionParser::ParseError => e
      warn "error: #{e.message}"
      2
    end

    def self.parse_options(argv)
      options = Options.new(
        width: Scene::SCREEN_WIDTH,
        height: Scene::SCREEN_HEIGHT,
        render_width: Scene::SCREEN_WIDTH,
        render_height: Scene::SCREEN_HEIGHT,
        render_scale: nil,
        render_size_window: false,
        log_level: ENV.fetch("WGPU_GS_VIEWER_LOG", "info"),
        show_axis: true,
        window_only: false,
        validate_ply: false,
        print_scene_info: false,
        print_gpu_info: false,
        hidden: false,
        smoke_frame: false,
        smoke_resize: false,
        smoke_camera: false,
        assert_render_nonzero: false,
        eye: nil,
        target: nil,
        up: nil,
        fov: 45.0,
        znear: 0.1,
        zfar: 10_000.0,
        time: 0.0,
        time_speed: Scene::TIME_SPEED,
        pause: false,
        power_preference: :high_performance,
        present_mode: nil,
        background_color: [0.0, 0.0, 0.0, 1.0],
        exposure: 1.0,
        gamma: 1.0,
        watch: false,
        quality: :balanced,
        low_vram: false,
        json: false
      )
      explicit_render_size = false

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: 3dgc_viewer [options]"
        opts.on("--file PATH", "Load a PLY file at startup") { |value| options.file = value }
        opts.on("--width N", Integer, "Window width (default: 1280)") { |value| options.width = value }
        opts.on("--height N", Integer, "Window height (default: 720)") { |value| options.height = value }
        opts.on("--render-width N", Integer, "Internal render width (default: 1280)") do |value|
          options.render_width = value
          explicit_render_size = true
        end
        opts.on("--render-height N", Integer, "Internal render height (default: 720)") do |value|
          options.render_height = value
          explicit_render_size = true
        end
        opts.on("--render-scale SCALE", Float, "Scale internal render size from window size") { |value| options.render_scale = value }
        opts.on("--render-size-window", "Keep internal render size in sync with framebuffer size") { options.render_size_window = true }
        opts.on("--max-pairs N", Integer, "Initial pair buffer capacity") { |value| options.max_pairs = value }
        opts.on("--camera SPEC", "Camera eye:target:up, each as x,y,z") { |value| apply_camera_spec(options, value) }
        opts.on("--eye X,Y,Z", "Initial camera eye") { |value| options.eye = parse_vec3(value, "--eye") }
        opts.on("--target X,Y,Z", "Initial camera target") { |value| options.target = parse_vec3(value, "--target") }
        opts.on("--up X,Y,Z", "Initial camera up vector") { |value| options.up = parse_vec3(value, "--up") }
        opts.on("--fov DEG", Float, "Vertical field of view in degrees") { |value| options.fov = value }
        opts.on("--znear N", Float, "Camera near plane") { |value| options.znear = value }
        opts.on("--zfar N", Float, "Camera far plane") { |value| options.zfar = value }
        opts.on("--time T", Float, "Initial 4D scene time in [0, 1)") { |value| options.time = value }
        opts.on("--time-speed N", Float, "4D playback speed multiplier") { |value| options.time_speed = value }
        opts.on("--pause", "Start 4D playback paused") { options.pause = true }
        opts.on("--power-preference VALUE", "high-performance/low-power") { |value| options.power_preference = parse_power_preference(value) }
        opts.on("--present-mode MODE", "fifo/mailbox/immediate") { |value| options.present_mode = parse_present_mode(value) }
        opts.on("--background-color COLOR", "#rrggbb, #rrggbbaa, or r,g,b[,a]") { |value| options.background_color = parse_color(value) }
        opts.on("--exposure N", Float, "Render exposure multiplier") { |value| options.exposure = value }
        opts.on("--gamma N", Float, "Output gamma") { |value| options.gamma = value }
        opts.on("--quality PRESET", "fast/balanced/quality") { |value| options.quality = parse_quality(value) }
        opts.on("--low-vram", "Use smaller default GPU pair buffers") { options.low_vram = true }
        opts.on("--watch", "Reload the loaded file when it changes") { options.watch = true }
        opts.on("--json", "Use machine-readable JSON for print commands") { options.json = true }
        opts.on("--log-level LEVEL", "debug/info/warn/error") { |value| options.log_level = value }
        opts.on("--wgpu-native PATH", "Path to libwgpu_native") { |value| options.wgpu_native = value }
        opts.on("--glfw PATH", "Path to libglfw") { |value| options.glfw = value }
        opts.on("--no-axis", "Disable axis overlay") { options.show_axis = false }
        opts.on("--window-only", "Open a GLFW window without wgpu initialization") { options.window_only = true }
        opts.on("--hidden", "Create the window hidden") { options.hidden = true }
        opts.on("--smoke-frame", "Initialize GPU, render one frame, and exit") { options.smoke_frame = true }
        opts.on("--smoke-resize", "During --smoke-frame, resize once and render again") { options.smoke_resize = true }
        opts.on("--smoke-camera", "During --smoke-frame, simulate camera keys and render again") { options.smoke_camera = true }
        opts.on("--assert-render-nonzero", "Fail if the internal render texture has no non-black RGB pixels") { options.assert_render_nonzero = true }
        opts.on("--validate-ply", "Parse --file and exit") { options.validate_ply = true }
        opts.on("--print-scene-info", "Print parsed scene statistics and exit") { options.print_scene_info = true }
        opts.on("--print-gpu-info", "Print GPU/native library locator information and exit") { options.print_gpu_info = true }
        opts.on("--version", "Print version") do
          puts VERSION
          exit 0
        end
        opts.on("-h", "--help", "Print help") do
          puts opts
          exit 0
        end
      end
      parser.parse!(argv)
      validate_options(options, explicit_render_size: explicit_render_size)
      options
    end

    def self.validate_options(options, explicit_render_size:)
      validate_dimension("--width", options.width, MAX_WINDOW_DIMENSION)
      validate_dimension("--height", options.height, MAX_WINDOW_DIMENSION)
      validate_dimension("--render-width", options.render_width, MAX_RENDER_DIMENSION)
      validate_dimension("--render-height", options.render_height, MAX_RENDER_DIMENSION)
      validate_camera_options(options)
      validate_time_options(options)
      validate_tone_options(options)
      validate_log_level(options.log_level)
      validate_file(options.file) if options.file
      validate_positive_int("--max-pairs", options.max_pairs) if options.max_pairs
      apply_render_scale(options, explicit_render_size: explicit_render_size) if options.render_scale
    end

    def self.apply_camera_spec(options, value)
      parts = value.to_s.split(":")
      raise OptionParser::InvalidArgument, "--camera must be eye:target:up" unless parts.length == 3

      options.eye = parse_vec3(parts[0], "--camera eye")
      options.target = parse_vec3(parts[1], "--camera target")
      options.up = parse_vec3(parts[2], "--camera up")
    end

    def self.parse_vec3(value, name)
      parts = value.to_s.split(",")
      raise OptionParser::InvalidArgument, "#{name} must have 3 comma-separated numbers" unless parts.length == 3

      vector = parts.map { |part| Float(part, exception: false) }
      raise OptionParser::InvalidArgument, "#{name} must contain only finite numbers" unless vector.all? { |number| number&.finite? }

      vector
    end

    def self.parse_power_preference(value)
      POWER_PREFERENCES.fetch(value.to_s.downcase) do
        raise OptionParser::InvalidArgument, "--power-preference must be high-performance or low-power"
      end
    end

    def self.parse_present_mode(value)
      PRESENT_MODES.fetch(value.to_s.downcase) do
        raise OptionParser::InvalidArgument, "--present-mode must be fifo, mailbox, or immediate"
      end
    end

    def self.parse_quality(value)
      key = value.to_s.downcase.to_sym
      return key if QUALITY_PAIR_FACTORS.key?(key)

      raise OptionParser::InvalidArgument, "--quality must be fast, balanced, or quality"
    end

    def self.parse_color(value)
      text = value.to_s.strip
      return parse_hex_color(text) if text.start_with?("#")

      parts = text.split(",")
      unless [3, 4].include?(parts.length)
        raise OptionParser::InvalidArgument, "--background-color must be #rrggbb, #rrggbbaa, or r,g,b[,a]"
      end

      color = parts.map { |part| Float(part, exception: false) }
      unless color.all? { |component| component&.finite? && component >= 0.0 && component <= 1.0 }
        raise OptionParser::InvalidArgument, "--background-color components must be finite values from 0 to 1"
      end
      color << 1.0 if color.length == 3
      color
    end

    def self.parse_hex_color(text)
      hex = text.delete_prefix("#")
      unless hex.match?(/\A[0-9a-fA-F]{6}([0-9a-fA-F]{2})?\z/)
        raise OptionParser::InvalidArgument, "--background-color hex must be #rrggbb or #rrggbbaa"
      end

      hex.scan(/../).map { |pair| pair.to_i(16) / 255.0 }.tap do |color|
        color << 1.0 if color.length == 3
      end
    end

    def self.validate_dimension(name, value, max)
      validate_positive_int(name, value)
      raise OptionParser::InvalidArgument, "#{name} must be <= #{max}" if value.to_i > max
    end

    def self.validate_positive_int(name, value)
      raise OptionParser::InvalidArgument, "#{name} must be positive" unless value.to_i.positive?
    end

    def self.validate_log_level(value)
      return if LOG_LEVELS.key?(value.to_s.downcase)

      raise OptionParser::InvalidArgument, "--log-level must be one of: debug, info, warn, error"
    end

    def self.validate_camera_options(options)
      raise OptionParser::InvalidArgument, "--fov must be > 0 and < 180" unless options.fov.to_f.positive? && options.fov.to_f < 180.0
      raise OptionParser::InvalidArgument, "--znear must be positive" unless options.znear.to_f.positive?
      raise OptionParser::InvalidArgument, "--zfar must be positive" unless options.zfar.to_f.positive?
      raise OptionParser::InvalidArgument, "--znear must be less than --zfar" unless options.znear.to_f < options.zfar.to_f

      up = options.up || [0.0, 1.0, 0.0]
      raise OptionParser::InvalidArgument, "--up must not be zero length" if Math3D::Vec3.length(up) < Math3D::EPSILON
    end

    def self.validate_time_options(options)
      raise OptionParser::InvalidArgument, "--time must be finite" unless options.time.to_f.finite?
      raise OptionParser::InvalidArgument, "--time-speed must be finite" unless options.time_speed.to_f.finite?
    end

    def self.validate_tone_options(options)
      raise OptionParser::InvalidArgument, "--exposure must be positive" unless options.exposure.to_f.positive?
      raise OptionParser::InvalidArgument, "--gamma must be positive" unless options.gamma.to_f.positive?
    end

    def self.validate_file(path)
      raise OptionParser::InvalidArgument, "--file does not exist: #{path}" unless File.exist?(path)
      raise OptionParser::InvalidArgument, "--file is not a regular file: #{path}" unless File.file?(path)
      raise OptionParser::InvalidArgument, "--file is not readable: #{path}" unless File.readable?(path)
    end

    def self.apply_render_scale(options, explicit_render_size:)
      raise OptionParser::InvalidArgument, "--render-scale cannot be combined with --render-size-window" if options.render_size_window
      raise OptionParser::InvalidArgument, "--render-scale cannot be combined with --render-width/--render-height" if explicit_render_size
      unless options.render_scale.positive? && options.render_scale <= MAX_RENDER_SCALE
        raise OptionParser::InvalidArgument, "--render-scale must be > 0 and <= #{MAX_RENDER_SCALE}"
      end

      options.render_width = [(options.width * options.render_scale).round, 1].max
      options.render_height = [(options.height * options.render_scale).round, 1].max
    end

    def initialize(options)
      @options = options
      ENV["WGPU_NATIVE_LIB"] = options.wgpu_native if options.wgpu_native
      ENV["WGPU_LIB_PATH"] = options.wgpu_native if options.wgpu_native
      ENV["GLFW_LIB"] = options.glfw if options.glfw
      @logger = Logger.new($stderr)
      @logger.level = logger_level(options.log_level)
      @logger.progname = "3dgc_viewer"
    end

    def run
      log_startup
      return validate_ply if @options.validate_ply
      return print_scene_info if @options.print_scene_info
      return print_gpu_info if @options.print_gpu_info

      @options.window_only ? run_window_only : run_native
      0
    rescue Error => e
      @logger.error(e.message)
      1
    rescue StandardError => e
      @logger.error(e.message)
      1
    end

    private

    def validate_ply
      raise PlyError, "--validate-ply requires --file" unless @options.file

      gaussian_set = PlyLoader.parse_file(@options.file, retain_items: false)
      @logger.info("valid PLY: #{gaussian_set.kind}, #{gaussian_set.count} gaussians")
      0
    end

    def print_scene_info
      raise PlyError, "--print-scene-info requires --file" unless @options.file

      gaussian_set = PlyLoader.parse_file(@options.file, retain_items: false)
      stats = gaussian_set.statistics
      return puts_json(scene_info_hash(gaussian_set, stats)) if @options.json

      puts "kind: #{gaussian_set.kind}"
      puts "gaussians: #{gaussian_set.count}"
      puts "invalid_gaussians: #{stats.invalid_count}"
      unless stats.bounds.empty?
        puts "bounds_min: #{stats.bounds.min.join(", ")}"
        puts "bounds_max: #{stats.bounds.max.join(", ")}"
        puts "bounds_center: #{stats.bounds.center.join(", ")}"
        puts "bounds_radius: #{stats.bounds.radius}"
      end
      puts "opacity_range: #{stats.opacity_min}, #{stats.opacity_max}" if stats.opacity_min && stats.opacity_max
      puts "scale_range: #{stats.scale_min}, #{stats.scale_max}" if stats.scale_min && stats.scale_max
      0
    end

    def print_gpu_info
      return puts_json(gpu_info_hash) if @options.json

      puts "platform: #{LibraryLocator.platform}"
      print_location("wgpu_native", LibraryLocator.wgpu_native_location)
      print_location("glfw", LibraryLocator.glfw_location)
      print_location("surface_shim", LibraryLocator.surface_shim_location)
      puts "shader_dir: #{LibraryLocator.shader_dir}"
      0
    end

    def puts_json(value)
      puts JSON.generate(value)
      0
    end

    def scene_info_hash(gaussian_set, stats)
      {
        kind: gaussian_set.kind,
        gaussians: gaussian_set.count,
        invalid_gaussians: stats.invalid_count,
        bounds: stats.bounds.empty? ? nil : {
          min: stats.bounds.min,
          max: stats.bounds.max,
          center: stats.bounds.center,
          radius: stats.bounds.radius
        },
        opacity_range: range_or_nil(stats.opacity_min, stats.opacity_max),
        scale_range: range_or_nil(stats.scale_min, stats.scale_max),
        metadata: gaussian_set.metadata
      }
    end

    def gpu_info_hash
      {
        platform: LibraryLocator.platform,
        wgpu_native: location_hash(LibraryLocator.wgpu_native_location),
        glfw: location_hash(LibraryLocator.glfw_location),
        surface_shim: location_hash(LibraryLocator.surface_shim_location),
        shader_dir: LibraryLocator.shader_dir
      }
    end

    def location_hash(location)
      {path: location.path, source: location.source, exists: location.exists}
    end

    def range_or_nil(min, max)
      return nil unless min && max

      [min, max]
    end

    def run_window_only
      window = create_window(title: "3dgc_viewer")
      install_window_only_callbacks(window)
      loop_until_close(window)
    ensure
      window&.destroy
    end

    def run_native
      window = create_window(title: "3dgc_viewer")
      state = AppState.new(
        window,
        logger: @logger,
        show_axis: @options.show_axis,
        render_width: @options.render_width,
        render_height: @options.render_height,
        follow_window_render_size: @options.render_size_window,
        initial_camera: build_initial_camera(window),
        initial_time: @options.time,
        time_speed: @options.time_speed,
        time_paused: @options.pause,
        power_preference: @options.power_preference,
        present_mode: @options.present_mode,
        background_color: @options.background_color,
        exposure: @options.exposure,
        gamma: @options.gamma,
        watch_files: @options.watch,
        pair_capacity_factor: pair_capacity_factor
      )
      install_state_callbacks(window, state)
      state.initialize_gpu
      state.handle_drop(@options.file, max_pairs: @options.max_pairs) if @options.file
      if @options.smoke_frame
        render_smoke_frame(window, state)
        return
      end
      loop_until_close(window, state)
    ensure
      state&.release
      window&.destroy
    end

    def create_window(title:)
      Window::GLFW.new(width: @options.width, height: @options.height, title: title, visible: !@options.hidden)
    end

    def build_initial_camera(window)
      camera = Camera.default(width: window.width, height: window.height)
      camera.eye = @options.eye if @options.eye
      camera.target = @options.target if @options.target
      camera.up = @options.up if @options.up
      camera.fovy = @options.fov
      camera.znear = @options.znear
      camera.zfar = @options.zfar
      camera
    end

    def pair_capacity_factor
      return 8 if @options.low_vram

      QUALITY_PAIR_FACTORS.fetch(@options.quality)
    end

    def install_window_only_callbacks(window)
      window.on_key do |key, action|
        window.request_close if key == Window::Keymap::KEY_ESCAPE && action == Window::GLFW::GLFW_PRESS
      end
      window.on_resize { |width, height| @logger.info("resize: #{width}x#{height}") }
      window.on_drop { |paths| @logger.info("drop: #{paths.join(", ")}") }
    end

    def install_state_callbacks(window, state)
      cursor = [0.0, 0.0]
      window.on_key { |key, action| state.handle_key(key, action) }
      window.on_drop { |paths| state.handle_drops(paths, max_pairs: @options.max_pairs) }
      window.on_resize { |width, height| state.resize(width, height) }
      window.on_cursor do |x, y|
        cursor = [x, y]
        state.handle_cursor(x, y)
      end
      window.on_mouse_button { |button, action, _mods| state.handle_mouse_button(button, action, cursor[0], cursor[1]) }
      window.on_scroll { |x_offset, y_offset| state.handle_scroll(x_offset, y_offset) }
    end

    def render_smoke_frame(window, state)
      render_once(window, state)
      run_smoke_resize(window, state) if @options.smoke_resize
      run_smoke_camera(window, state) if @options.smoke_camera
      return unless @options.assert_render_nonzero

      raise WgpuError, "render texture did not contain non-black RGB pixels" unless state.render_texture_rgb_nonzero?
    end

    def render_once(window, state)
      window.poll_events
      state.update
      state.render
    end

    def run_smoke_resize(window, state)
      next_width = [@options.width / 2, 64].max
      next_height = [@options.height / 2, 64].max
      window.set_size(next_width, next_height)
      window.poll_events
      framebuffer_width, framebuffer_height = window.framebuffer_size
      state.resize(framebuffer_width, framebuffer_height)
      render_once(window, state)
    end

    def run_smoke_camera(window, state)
      state.handle_key(Window::Keymap::KEY_A, Window::GLFW::GLFW_PRESS)
      sleep 0.02
      render_once(window, state)
      state.handle_key(Window::Keymap::KEY_A, Window::GLFW::GLFW_RELEASE)
      state.handle_key(Window::Keymap::KEY_Q, Window::GLFW::GLFW_PRESS)
      sleep 0.02
      render_once(window, state)
      state.handle_key(Window::Keymap::KEY_Q, Window::GLFW::GLFW_RELEASE)
    end

    def loop_until_close(window, state = nil)
      until window.should_close?
        window.poll_events
        state&.update
        state&.render
        timeout = state&.should_request_redraw? ? 0.0 : 0.016
        window.wait_events_timeout(timeout || 0.016)
      end
    end

    def log_startup
      @logger.info("3dgc_viewer")
      @logger.info("Ruby: #{RUBY_DESCRIPTION}")
      @logger.info("Platform: #{LibraryLocator.platform}")
      log_location("wgpu-native", LibraryLocator.wgpu_native_location)
      log_location("GLFW", LibraryLocator.glfw_location)
    end

    def print_location(name, location)
      puts "#{name}: #{location.path}"
      puts "#{name}_source: #{location.source}"
      puts "#{name}_exists: #{location.exists}"
    end

    def log_location(name, location)
      @logger.info("#{name}: #{location.path} (#{location.source}, exists=#{location.exists})")
    end

    def logger_level(value)
      LOG_LEVELS.fetch(value.to_s.downcase)
    end
  end
end
