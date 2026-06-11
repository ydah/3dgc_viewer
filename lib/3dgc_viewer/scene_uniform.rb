# frozen_string_literal: true

require_relative "binary_pack"
require_relative "math3d"
require_relative "scene"

module ThreeDgcViewer
  class SceneUniform
    attr_reader :view, :proj, :view_pos, :gaussian_count, :screen_size, :near_far,
                :tan_fov, :time, :background_color, :exposure, :gamma,
                :brightness, :contrast, :opacity_threshold, :scale_multiplier

    def initialize(screen_width: Scene::SCREEN_WIDTH, screen_height: Scene::SCREEN_HEIGHT,
                   background_color: [0.0, 0.0, 0.0, 1.0], exposure: 1.0, gamma: 1.0,
                   brightness: 0.0, contrast: 1.0, opacity_threshold: 0.0, scale_multiplier: 1.0)
      @view = Math3D::Mat4.identity
      @proj = Math3D::Mat4.identity
      @view_pos = [0.0, 0.0, 0.0]
      @gaussian_count = 0
      @screen_size = [positive_int(screen_width), positive_int(screen_height)]
      @near_far = [0.01, 100.0]
      @tan_fov = [0.0, 0.0]
      @time = 0.0
      @background_color = normalize_color(background_color)
      @exposure = exposure.to_f
      @gamma = gamma.to_f
      @brightness = brightness.to_f
      @contrast = contrast.to_f
      @opacity_threshold = opacity_threshold.to_f
      @scale_multiplier = scale_multiplier.to_f
    end

    def update_camera(camera)
      @view = camera.view_matrix
      @proj = camera.projection_matrix
      @view_pos = camera.eye
      @near_far = [camera.znear, camera.zfar]
      tan_fovy = Math.tan((camera.fovy * Math::PI / 180.0) * 0.5)
      @tan_fov = [tan_fovy * camera.aspect, tan_fovy]
    end

    def update_gaussian_count(gaussian_count)
      @gaussian_count = gaussian_count.to_i
    end

    def update_screen_size(width, height)
      @screen_size = [positive_int(width), positive_int(height)]
    end

    def update_time(dt_sec, speed: Scene::TIME_SPEED, range: nil)
      set_time(@time + (dt_sec.to_f * speed.to_f), range: range)
    end

    def set_time(value, range: nil)
      @time = wrap_time(value.to_f, range)
    end

    def pack
      BinaryPack.concat(
        BinaryPack.f32(@view),
        BinaryPack.f32(@proj),
        BinaryPack.f32(@view_pos),
        BinaryPack.u32(@gaussian_count),
        BinaryPack.u32(@screen_size),
        BinaryPack.f32(@near_far),
        BinaryPack.f32(@tan_fov),
        BinaryPack.f32(@time),
        BinaryPack.u32(0),
        BinaryPack.f32(@background_color),
        BinaryPack.f32(@exposure, @gamma),
        BinaryPack.u32(0, 0),
        BinaryPack.f32(@brightness, @contrast, @opacity_threshold, @scale_multiplier)
      )
    end

    private

    def positive_int(value)
      [value.to_i, 1].max
    end

    def normalize_color(color)
      values = Array(color).first(4).map(&:to_f)
      values += [1.0] while values.length < 4
      values
    end

    def wrap_time(value, range)
      return value % 1.0 unless range

      start_time, end_time = range
      length = end_time.to_f - start_time.to_f
      return start_time.to_f if length <= 0.0

      start_time.to_f + ((value - start_time.to_f) % length)
    end
  end
end
