# frozen_string_literal: true

require "logger"
require "optparse"
require "json"
require "time"
require_relative "app_state"
require_relative "camera_bookmarks"
require_relative "camera_preset"
require_relative "controls_help"
require_relative "ply_loader"
require_relative "recent_files"
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
    EXIT_RUNTIME_ERROR = 1
    EXIT_USAGE_ERROR = 2
    EXIT_PLY_ERROR = 3
    EXIT_SHADER_ERROR = 4
    EXIT_WGPU_ERROR = 5
    EXIT_WINDOW_ERROR = 6

    Options = Struct.new(
      :file, :width, :height, :log_level, :wgpu_native, :glfw, :show_axis,
      :render_width, :render_height, :render_scale, :render_size_window,
      :max_pairs, :window_only, :validate_ply, :print_scene_info, :print_gpu_info, :print_controls,
      :print_recent_files, :clear_recent_files, :recent_files, :recent_files_path,
      :camera_preset, :save_camera_preset, :camera_bookmarks, :camera_bookmark,
      :save_camera_bookmark, :print_camera_bookmarks,
      :log_json, :debug_errors,
      :hidden, :smoke_frame, :smoke_resize,
      :smoke_camera, :assert_render_nonzero,
      :print_render_stats, :screenshot, :benchmark, :frame_sequence, :frame_sequence_count, :frame_sequence_step,
      :max_gaussians, :max_file_bytes,
      :eye, :target, :up, :fov, :znear, :zfar,
      :time, :time_speed, :time_range, :pause, :turntable_speed, :power_preference, :present_mode,
      :background_color, :exposure, :gamma, :brightness, :contrast,
      :opacity_threshold, :scale_multiplier, :sh_degree,
      :shader_dev, :watch, :quality, :low_vram, :json,
      keyword_init: true
    )

    def self.run(argv)
      new(parse_options(argv)).run
    rescue OptionParser::ParseError => e
      warn "error: #{e.message}"
      EXIT_USAGE_ERROR
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
        print_controls: false,
        print_recent_files: false,
        clear_recent_files: false,
        recent_files: true,
        recent_files_path: nil,
        camera_preset: nil,
        save_camera_preset: nil,
        camera_bookmarks: nil,
        camera_bookmark: nil,
        save_camera_bookmark: nil,
        print_camera_bookmarks: false,
        log_json: false,
        debug_errors: false,
        hidden: false,
        smoke_frame: false,
        smoke_resize: false,
        smoke_camera: false,
        assert_render_nonzero: false,
        print_render_stats: false,
        screenshot: nil,
        benchmark: nil,
        frame_sequence: nil,
        frame_sequence_count: 1,
        frame_sequence_step: nil,
        max_gaussians: PlyLoader::MAX_VERTEX_COUNT,
        max_file_bytes: nil,
        eye: nil,
        target: nil,
        up: nil,
        fov: 45.0,
        znear: 0.1,
        zfar: 10_000.0,
        time: 0.0,
        time_speed: Scene::TIME_SPEED,
        time_range: nil,
        pause: false,
        turntable_speed: 0.0,
        power_preference: :high_performance,
        present_mode: nil,
        background_color: [0.0, 0.0, 0.0, 1.0],
        exposure: 1.0,
        gamma: 1.0,
        brightness: 0.0,
        contrast: 1.0,
        opacity_threshold: 0.0,
        scale_multiplier: 1.0,
        sh_degree: PlyLoader::MAX_SH_DEGREE,
        shader_dev: false,
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
        opts.on("--camera-preset PATH", "Load initial camera from JSON preset") { |value| apply_camera_preset(options, value) }
        opts.on("--save-camera-preset PATH", "Write the initial camera JSON preset and exit") { |value| options.save_camera_preset = value }
        opts.on("--camera-bookmarks PATH", "Read/write named camera bookmark JSON") { |value| options.camera_bookmarks = value }
        opts.on("--camera-bookmark NAME", "Load initial camera from named bookmark") { |value| options.camera_bookmark = value }
        opts.on("--save-camera-bookmark NAME", "Write the initial camera as named bookmark and exit") { |value| options.save_camera_bookmark = value }
        opts.on("--print-camera-bookmarks", "Print camera bookmark names and exit") { options.print_camera_bookmarks = true }
        opts.on("--eye X,Y,Z", "Initial camera eye") { |value| options.eye = parse_vec3(value, "--eye") }
        opts.on("--target X,Y,Z", "Initial camera target") { |value| options.target = parse_vec3(value, "--target") }
        opts.on("--up X,Y,Z", "Initial camera up vector") { |value| options.up = parse_vec3(value, "--up") }
        opts.on("--fov DEG", Float, "Vertical field of view in degrees") { |value| options.fov = value }
        opts.on("--znear N", Float, "Camera near plane") { |value| options.znear = value }
        opts.on("--zfar N", Float, "Camera far plane") { |value| options.zfar = value }
        opts.on("--time T", Float, "Initial 4D scene time in [0, 1)") { |value| options.time = value }
        opts.on("--time-speed N", Float, "4D playback speed multiplier") { |value| options.time_speed = value }
        opts.on("--time-range START,END", "4D playback loop range in [0, 1]") { |value| options.time_range = parse_time_range(value) }
        opts.on("--pause", "Start 4D playback paused") { options.pause = true }
        opts.on("--turntable", "Enable turntable camera animation") { options.turntable_speed = AppState::DEFAULT_TURNTABLE_SPEED }
        opts.on("--turntable-speed DEG_PER_SEC", Float, "Turntable camera speed in degrees per second") { |value| options.turntable_speed = value }
        opts.on("--power-preference VALUE", "high-performance/low-power") { |value| options.power_preference = parse_power_preference(value) }
        opts.on("--present-mode MODE", "fifo/mailbox/immediate") { |value| options.present_mode = parse_present_mode(value) }
        opts.on("--background-color COLOR", "#rrggbb, #rrggbbaa, or r,g,b[,a]") { |value| options.background_color = parse_color(value) }
        opts.on("--transparent-background", "Set background alpha to 0 for RGBA screenshots") { options.background_color[3] = 0.0 }
        opts.on("--exposure N", Float, "Render exposure multiplier") { |value| options.exposure = value }
        opts.on("--gamma N", Float, "Output gamma") { |value| options.gamma = value }
        opts.on("--brightness N", Float, "Output brightness offset") { |value| options.brightness = value }
        opts.on("--contrast N", Float, "Output contrast multiplier") { |value| options.contrast = value }
        opts.on("--opacity-threshold N", Float, "Cull splats below alpha threshold") { |value| options.opacity_threshold = value }
        opts.on("--scale-multiplier N", Float, "Global splat scale multiplier") { |value| options.scale_multiplier = value }
        opts.on("--sh-degree N", Integer, "3DGS spherical harmonics degree 0-3") { |value| options.sh_degree = value }
        opts.on("--shader-dev", "Disable shader source cache and enable H reload shortcut") { options.shader_dev = true }
        opts.on("--quality PRESET", "fast/balanced/quality") { |value| options.quality = parse_quality(value) }
        opts.on("--low-vram", "Use smaller default GPU pair buffers") { options.low_vram = true }
        opts.on("--watch", "Reload the loaded file when it changes") { options.watch = true }
        opts.on("--json", "Use machine-readable JSON for print commands") { options.json = true }
        opts.on("--log-json", "Write logs as JSON lines to stderr") { options.log_json = true }
        opts.on("--debug-errors", "Log exception backtraces on failure") { options.debug_errors = true }
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
        opts.on("--print-render-stats", "Print rendered texture pixel statistics and exit") { options.print_render_stats = true }
        opts.on("--screenshot PATH", "Save one rendered frame as .ppm RGB or .pam RGBA and exit") { |value| options.screenshot = value }
        opts.on("--benchmark N", Integer, "Render N frames and print timing, then exit") { |value| options.benchmark = value }
        opts.on("--frame-sequence PATTERN", "Save frame sequence using printf pattern, e.g. frame_%04d.pam") { |value| options.frame_sequence = value }
        opts.on("--frame-sequence-count N", Integer, "Number of frames for --frame-sequence") { |value| options.frame_sequence_count = value }
        opts.on("--frame-sequence-step T", Float, "4D time step per sequence frame") { |value| options.frame_sequence_step = value }
        opts.on("--max-gaussians N", Integer, "Reject PLY files with more than N vertices") { |value| options.max_gaussians = value }
        opts.on("--max-file-bytes N", Integer, "Reject PLY files larger than N bytes") { |value| options.max_file_bytes = value }
        opts.on("--validate-ply", "Parse --file and exit") { options.validate_ply = true }
        opts.on("--print-scene-info", "Print parsed scene statistics and exit") { options.print_scene_info = true }
        opts.on("--print-gpu-info", "Print GPU/native library locator information and exit") { options.print_gpu_info = true }
        opts.on("--print-controls", "Print keyboard and mouse controls and exit") { options.print_controls = true }
        opts.on("--print-recent-files", "Print recent file history and exit") { options.print_recent_files = true }
        opts.on("--clear-recent-files", "Clear recent file history and exit") { options.clear_recent_files = true }
        opts.on("--recent-files PATH", "Read/write recent file history at PATH") do |value|
          options.recent_files = true
          options.recent_files_path = value
        end
        opts.on("--no-recent-files", "Disable persistent recent file history") { options.recent_files = false }
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
      apply_camera_bookmark_if_requested(options)
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
      validate_sh_options(options)
      validate_max_gaussians_option(options)
      validate_max_file_bytes_option(options)
      validate_log_level(options.log_level)
      validate_file(options.file, option_name: "--file") if options.file
      validate_output_file("--save-camera-preset", options.save_camera_preset) if options.save_camera_preset
      validate_camera_bookmark_options(options)
      validate_positive_int("--max-pairs", options.max_pairs) if options.max_pairs
      validate_positive_int("--benchmark", options.benchmark) if options.benchmark
      validate_screenshot_path(options.screenshot) if options.screenshot
      validate_frame_sequence_options(options)
      validate_recent_files_options(options)
      validate_batch_options(options)
      apply_render_scale(options, explicit_render_size: explicit_render_size) if options.render_scale
    end

    def self.apply_camera_spec(options, value)
      parts = value.to_s.split(":")
      raise OptionParser::InvalidArgument, "--camera must be eye:target:up" unless parts.length == 3

      options.eye = parse_vec3(parts[0], "--camera eye")
      options.target = parse_vec3(parts[1], "--camera target")
      options.up = parse_vec3(parts[2], "--camera up")
    end

    def self.apply_camera_preset(options, path)
      validate_file(path, option_name: "--camera-preset")
      CameraPreset.apply_to_options(options, CameraPreset.load_file(path))
      options.camera_preset = path
    rescue ArgumentError => e
      raise OptionParser::InvalidArgument, "--camera-preset #{e.message}"
    end

    def self.apply_camera_bookmark_if_requested(options)
      return unless options.camera_bookmark
      raise OptionParser::InvalidArgument, "--camera-bookmark requires --camera-bookmarks" unless options.camera_bookmarks

      validate_file(options.camera_bookmarks, option_name: "--camera-bookmarks")
      CameraPreset.apply_to_options(
        options,
        CameraBookmarks.fetch_file(options.camera_bookmarks, options.camera_bookmark)
      )
    rescue ArgumentError => e
      raise OptionParser::InvalidArgument, "--camera-bookmark #{e.message}"
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
      raise OptionParser::InvalidArgument, "--turntable-speed must be finite" unless options.turntable_speed.to_f.finite?
    end

    def self.parse_time_range(value)
      parts = value.to_s.split(",")
      raise OptionParser::InvalidArgument, "--time-range must be START,END" unless parts.length == 2

      range = parts.map { |part| Float(part, exception: false) }
      unless range.all? { |number| number&.finite? } && range[0] >= 0.0 && range[0] < range[1] && range[1] <= 1.0
        raise OptionParser::InvalidArgument, "--time-range must satisfy 0 <= START < END <= 1"
      end

      range
    end

    def self.validate_tone_options(options)
      raise OptionParser::InvalidArgument, "--exposure must be positive" unless options.exposure.to_f.positive?
      raise OptionParser::InvalidArgument, "--gamma must be positive" unless options.gamma.to_f.positive?
      raise OptionParser::InvalidArgument, "--brightness must be finite" unless options.brightness.to_f.finite?
      raise OptionParser::InvalidArgument, "--contrast must be positive" unless options.contrast.to_f.positive?
      threshold = options.opacity_threshold.to_f
      raise OptionParser::InvalidArgument, "--opacity-threshold must be from 0 to 1" unless threshold.finite? && threshold >= 0.0 && threshold <= 1.0
      raise OptionParser::InvalidArgument, "--scale-multiplier must be positive" unless options.scale_multiplier.to_f.positive?
    end

    def self.validate_sh_options(options)
      PlyLoader.validate_sh_degree(options.sh_degree)
    rescue ArgumentError => e
      raise OptionParser::InvalidArgument, "--sh-degree #{e.message}"
    end

    def self.validate_max_gaussians_option(options)
      PlyLoader.validate_max_vertex_count(options.max_gaussians)
    rescue ArgumentError => e
      raise OptionParser::InvalidArgument, "--max-gaussians #{e.message}"
    end

    def self.validate_max_file_bytes_option(options)
      PlyLoader.validate_max_file_bytes(options.max_file_bytes)
    rescue ArgumentError => e
      raise OptionParser::InvalidArgument, "--max-file-bytes #{e.message}"
    end

    def self.validate_file(path, option_name:)
      raise OptionParser::InvalidArgument, "#{option_name} does not exist: #{path}" unless File.exist?(path)
      raise OptionParser::InvalidArgument, "#{option_name} is not a regular file: #{path}" unless File.file?(path)
      raise OptionParser::InvalidArgument, "#{option_name} is not readable: #{path}" unless File.readable?(path)
    end

    def self.validate_output_file(option_name, path)
      raise OptionParser::InvalidArgument, "#{option_name} must not be empty" if path.to_s.empty?

      directory = File.dirname(path)
      raise OptionParser::InvalidArgument, "#{option_name} directory does not exist: #{directory}" unless Dir.exist?(directory)
      raise OptionParser::InvalidArgument, "#{option_name} directory is not writable: #{directory}" unless File.writable?(directory)
      raise OptionParser::InvalidArgument, "#{option_name} file is not writable: #{path}" if File.exist?(path) && !File.writable?(path)
    end

    def self.validate_screenshot_path(path)
      raise OptionParser::InvalidArgument, "--screenshot must not be empty" if path.to_s.empty?
      validate_image_output_path("--screenshot", path)
    end

    def self.validate_image_output_path(option_name, path)
      extensions = %w[.ppm .pam]
      unless extensions.any? { |extension| File.extname(path).casecmp?(extension) }
        raise OptionParser::InvalidArgument, "#{option_name} path must end with .ppm or .pam"
      end

      directory = File.dirname(path)
      raise OptionParser::InvalidArgument, "#{option_name} directory does not exist: #{directory}" unless Dir.exist?(directory)
      raise OptionParser::InvalidArgument, "#{option_name} directory is not writable: #{directory}" unless File.writable?(directory)
      raise OptionParser::InvalidArgument, "#{option_name} file is not writable: #{path}" if File.exist?(path) && !File.writable?(path)
    end

    def self.validate_frame_sequence_options(options)
      if options.frame_sequence
        validate_positive_int("--frame-sequence-count", options.frame_sequence_count)
        if options.frame_sequence_step && !options.frame_sequence_step.to_f.finite?
          raise OptionParser::InvalidArgument, "--frame-sequence-step must be finite"
        end
        raise OptionParser::InvalidArgument, "--frame-sequence must include a printf integer placeholder" unless options.frame_sequence.include?("%")

        validate_image_output_path("--frame-sequence", format_frame_sequence_path(options.frame_sequence, 0))
        return
      end

      unless options.frame_sequence_count == 1
        raise OptionParser::InvalidArgument, "--frame-sequence-count requires --frame-sequence"
      end
      return unless options.frame_sequence_step

      raise OptionParser::InvalidArgument, "--frame-sequence-step requires --frame-sequence"
    rescue ArgumentError => e
      raise OptionParser::InvalidArgument, "--frame-sequence pattern is invalid: #{e.message}"
    end

    def self.validate_batch_options(options)
      return unless options.window_only
      return unless options.smoke_frame || options.screenshot || options.benchmark || options.frame_sequence || options.print_render_stats

      raise OptionParser::InvalidArgument, "--window-only cannot be combined with render batch options"
    end

    def self.validate_recent_files_options(options)
      if options.clear_recent_files && !options.recent_files
        raise OptionParser::InvalidArgument, "--clear-recent-files cannot be combined with --no-recent-files"
      end
      return if options.recent_files_path.nil? || !options.recent_files
      return unless options.recent_files_path.to_s.empty?

      raise OptionParser::InvalidArgument, "--recent-files must not be empty"
    end

    def self.validate_camera_bookmark_options(options)
      if options.camera_bookmark && options.camera_preset
        raise OptionParser::InvalidArgument, "--camera-bookmark cannot be combined with --camera-preset"
      end
      if options.print_camera_bookmarks
        raise OptionParser::InvalidArgument, "--print-camera-bookmarks requires --camera-bookmarks" unless options.camera_bookmarks
        validate_file(options.camera_bookmarks, option_name: "--camera-bookmarks")
      end
      if options.save_camera_bookmark
        raise OptionParser::InvalidArgument, "--save-camera-bookmark requires --camera-bookmarks" unless options.camera_bookmarks
        validate_output_file("--camera-bookmarks", options.camera_bookmarks)
      end
    end

    def self.format_frame_sequence_path(pattern, index)
      format(pattern, index)
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
      @logger.formatter = json_log_formatter if options.log_json
    end

    def run
      log_startup
      return validate_ply if @options.validate_ply
      return print_scene_info if @options.print_scene_info
      return print_gpu_info if @options.print_gpu_info
      return print_controls if @options.print_controls
      return clear_recent_files if @options.clear_recent_files
      return print_recent_files if @options.print_recent_files
      return print_camera_bookmarks if @options.print_camera_bookmarks
      return save_camera_preset if @options.save_camera_preset
      return save_camera_bookmark if @options.save_camera_bookmark

      @options.window_only ? run_window_only : run_native
      0
    rescue Error => e
      log_exception(e)
      exit_code = exit_code_for(e)
      print_json_error(e, exit_code)
      exit_code
    rescue StandardError => e
      log_exception(e)
      print_json_error(e, EXIT_RUNTIME_ERROR)
      EXIT_RUNTIME_ERROR
    end

    private

    def validate_ply
      raise PlyError, "--validate-ply requires --file" unless @options.file

      gaussian_set = PlyLoader.parse_file(
        @options.file,
        retain_items: false,
        sh_degree: @options.sh_degree,
        max_vertex_count: @options.max_gaussians,
        max_file_bytes: @options.max_file_bytes
      )
      return puts_json(scene_info_hash(gaussian_set, gaussian_set.statistics)) if @options.json

      @logger.info("valid PLY: #{gaussian_set.kind}, #{gaussian_set.count} gaussians")
      0
    end

    def print_scene_info
      raise PlyError, "--print-scene-info requires --file" unless @options.file

      gaussian_set = PlyLoader.parse_file(
        @options.file,
        retain_items: false,
        sh_degree: @options.sh_degree,
        max_vertex_count: @options.max_gaussians,
        max_file_bytes: @options.max_file_bytes
      )
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
      estimate = resource_estimate_hash(gaussian_set)
      puts "estimated_gpu_buffer_bytes: #{estimate[:gpu_buffer_bytes]}"
      puts "estimated_gpu_buffer_human: #{estimate[:gpu_buffer_human]}"
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

    def print_controls
      return puts_json(ControlsHelp.entries) if @options.json

      puts ControlsHelp.text
      0
    end

    def print_recent_files
      files = build_recent_files_store&.load || []
      return puts_json(files) if @options.json

      puts files
      0
    end

    def clear_recent_files
      files = build_recent_files_store&.clear || []
      return puts_json(files) if @options.json

      puts "cleared recent files"
      0
    end

    def save_camera_preset
      camera = build_initial_camera_for_size(@options.width, @options.height)
      CameraPreset.write_file(@options.save_camera_preset, camera)
      @logger.info("camera preset saved: #{@options.save_camera_preset}")
      0
    end

    def print_camera_bookmarks
      names = CameraBookmarks.names_file(@options.camera_bookmarks)
      return puts_json(names) if @options.json

      puts names
      0
    rescue ArgumentError => e
      raise Error, e.message
    end

    def save_camera_bookmark
      camera = build_initial_camera_for_size(@options.width, @options.height)
      CameraBookmarks.write_file(@options.camera_bookmarks, @options.save_camera_bookmark, camera)
      @logger.info("camera bookmark saved: #{@options.save_camera_bookmark}")
      0
    rescue ArgumentError => e
      raise Error, e.message
    end

    def puts_json(value)
      puts JSON.generate(value)
      0
    end

    def print_json_error(error, exit_code)
      return unless @options.json

      puts JSON.generate(
        error: error.class.name.split("::").last,
        message: error.message,
        exit_code: exit_code
      )
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
        resource_estimate: resource_estimate_hash(gaussian_set),
        metadata: gaussian_set.metadata
      }
    end

    def resource_estimate_hash(gaussian_set)
      resources = GaussianResources.new(
        gaussian_set: gaussian_set,
        render_width: @options.render_width,
        render_height: @options.render_height,
        max_pairs: @options.max_pairs,
        pair_capacity_factor: pair_capacity_factor
      )
      {
        render_width: resources.render_width,
        render_height: resources.render_height,
        max_pairs: resources.max_pairs,
        gpu_buffer_bytes: resources.estimated_buffer_bytes,
        gpu_buffer_human: format_bytes(resources.estimated_buffer_bytes)
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
        time_range: @options.time_range,
        time_paused: @options.pause,
        turntable_speed: @options.turntable_speed,
        power_preference: @options.power_preference,
        present_mode: @options.present_mode,
        background_color: @options.background_color,
        exposure: @options.exposure,
        gamma: @options.gamma,
        brightness: @options.brightness,
        contrast: @options.contrast,
        opacity_threshold: @options.opacity_threshold,
        scale_multiplier: @options.scale_multiplier,
        sh_degree: @options.sh_degree,
        max_gaussians: @options.max_gaussians,
        max_file_bytes: @options.max_file_bytes,
        shader_dev: @options.shader_dev,
        watch_files: @options.watch,
        pair_capacity_factor: pair_capacity_factor,
        recent_files_store: build_recent_files_store
      )
      install_state_callbacks(window, state)
      state.initialize_gpu
      state.handle_drop(@options.file, max_pairs: @options.max_pairs) if @options.file
      if batch_render_mode?
        run_batch_render(window, state)
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
      build_initial_camera_for_size(window.width, window.height)
    end

    def build_initial_camera_for_size(width, height)
      camera = Camera.default(width: width, height: height)
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

    def build_recent_files_store
      return nil unless @options.recent_files

      RecentFiles.new(path: @options.recent_files_path)
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

    def batch_render_mode?
      @options.smoke_frame || @options.screenshot || @options.benchmark || @options.frame_sequence || @options.print_render_stats
    end

    def run_batch_render(window, state)
      render_once(window, state) unless (@options.benchmark || @options.frame_sequence) && !@options.smoke_frame
      run_smoke_resize(window, state) if @options.smoke_resize
      run_smoke_camera(window, state) if @options.smoke_camera
      run_benchmark(window, state) if @options.benchmark
      run_frame_sequence(window, state) if @options.frame_sequence
      save_screenshot(state) if @options.screenshot
      print_render_stats(state) if @options.print_render_stats
      return unless @options.assert_render_nonzero

      raise WgpuError, "render texture did not contain non-black RGB pixels" unless state.render_texture_rgb_nonzero?
    end

    def run_benchmark(window, state)
      frames = @options.benchmark
      frame_statistics = FrameStatistics.new(max_samples: frames)
      started = monotonic_time
      frames.times do
        frame_started = monotonic_time
        render_once(window, state)
        frame_statistics.record(monotonic_time - frame_started)
      end
      elapsed = monotonic_time - started
      seconds_per_frame = elapsed / frames
      frame_snapshot = frame_statistics.snapshot || {}
      result = {
        frames: frames,
        seconds: elapsed.round(6),
        fps: (frames / elapsed).round(2),
        frame_ms: (seconds_per_frame * 1000.0).round(3),
        frame_p50_ms: frame_snapshot.fetch(:p50_ms).round(3),
        frame_p95_ms: frame_snapshot.fetch(:p95_ms).round(3),
        frame_p99_ms: frame_snapshot.fetch(:p99_ms).round(3)
      }

      return puts_json(result) if @options.json

      puts "benchmark_frames: #{result[:frames]}"
      puts "benchmark_seconds: #{result[:seconds]}"
      puts "benchmark_fps: #{result[:fps]}"
      puts "benchmark_frame_ms: #{result[:frame_ms]}"
      puts "benchmark_frame_p50_ms: #{result[:frame_p50_ms]}"
      puts "benchmark_frame_p95_ms: #{result[:frame_p95_ms]}"
      puts "benchmark_frame_p99_ms: #{result[:frame_p99_ms]}"
    end

    def save_screenshot(state)
      state.save_screenshot(@options.screenshot)
      @logger.info("screenshot saved: #{@options.screenshot}")
    end

    def print_render_stats(state)
      stats = state.render_texture_statistics
      return puts_json(stats) if @options.json

      puts "render_width: #{stats[:width]}"
      puts "render_height: #{stats[:height]}"
      puts "render_pixels: #{stats[:pixels]}"
      puts "render_nonzero_rgb_pixels: #{stats[:nonzero_rgb_pixels]}"
      puts "render_rgb_sum: #{stats[:rgb_sum]}"
      puts "render_alpha_sum: #{stats[:alpha_sum]}"
      puts "render_luminance_histogram: #{stats[:luminance_histogram].join(",")}"
      puts "render_checksum: #{stats[:checksum]}"
    end

    def run_frame_sequence(window, state)
      count = @options.frame_sequence_count
      step = @options.frame_sequence_step || default_frame_sequence_step(count)
      count.times do |index|
        state.set_time(@options.time + index * step)
        render_once(window, state)
        path = self.class.format_frame_sequence_path(@options.frame_sequence, index)
        state.save_screenshot(path)
        @logger.info("sequence frame saved: #{path}")
      end
    end

    def default_frame_sequence_step(count)
      return 0.0 if count <= 1

      1.0 / count
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

    def json_log_formatter
      proc do |severity, datetime, progname, message|
        JSON.generate(
          time: datetime.iso8601(6),
          level: severity.downcase,
          progname: progname,
          message: message.to_s
        ) + "\n"
      end
    end

    def log_exception(error)
      @logger.error(error.message)
      return unless @options.debug_errors && error.backtrace

      @logger.debug(error.backtrace.join("\n"))
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def exit_code_for(error)
      case error
      when PlyError then EXIT_PLY_ERROR
      when ShaderError then EXIT_SHADER_ERROR
      when WgpuError then EXIT_WGPU_ERROR
      when WindowError then EXIT_WINDOW_ERROR
      else EXIT_RUNTIME_ERROR
      end
    end
  end
end
