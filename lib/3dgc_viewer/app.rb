# frozen_string_literal: true

require "logger"
require "optparse"
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

    Options = Struct.new(
      :file, :width, :height, :log_level, :wgpu_native, :glfw, :show_axis,
      :render_width, :render_height, :render_scale, :render_size_window,
      :max_pairs, :window_only, :validate_ply, :print_scene_info,
      :hidden, :smoke_frame, :smoke_resize,
      :smoke_camera, :assert_render_nonzero,
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
        hidden: false,
        smoke_frame: false,
        smoke_resize: false,
        smoke_camera: false,
        assert_render_nonzero: false
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
      validate_log_level(options.log_level)
      validate_file(options.file) if options.file
      validate_positive_int("--max-pairs", options.max_pairs) if options.max_pairs
      apply_render_scale(options, explicit_render_size: explicit_render_size) if options.render_scale
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
        follow_window_render_size: @options.render_size_window
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

    def install_window_only_callbacks(window)
      window.on_key do |key, action|
        window.request_close if key == Window::Keymap::KEY_ESCAPE && action == Window::GLFW::GLFW_PRESS
      end
      window.on_resize { |width, height| @logger.info("resize: #{width}x#{height}") }
      window.on_drop { |paths| @logger.info("drop: #{paths.join(", ")}") }
    end

    def install_state_callbacks(window, state)
      window.on_key { |key, action| state.handle_key(key, action) }
      window.on_drop { |paths| state.handle_drop(paths.first) if paths.first }
      window.on_resize { |width, height| state.resize(width, height) }
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
      @logger.info("wgpu-native: #{LibraryLocator.wgpu_native_path}")
      @logger.info("GLFW: #{LibraryLocator.glfw_path}")
    end

    def logger_level(value)
      LOG_LEVELS.fetch(value.to_s.downcase)
    end
  end
end
