# frozen_string_literal: true

require_relative "binary_pack"
require_relative "math3d"
require_relative "scene"

module ThreeDgcViewer
  class SceneUniform
    attr_reader :view, :proj, :view_pos, :gaussian_count, :screen_size, :near_far, :tan_fov, :time

    def initialize(screen_width: Scene::SCREEN_WIDTH, screen_height: Scene::SCREEN_HEIGHT)
      @view = Math3D::Mat4.identity
      @proj = Math3D::Mat4.identity
      @view_pos = [0.0, 0.0, 0.0]
      @gaussian_count = 0
      @screen_size = [positive_int(screen_width), positive_int(screen_height)]
      @near_far = [0.01, 100.0]
      @tan_fov = [0.0, 0.0]
      @time = 0.0
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

    def update_time(dt_sec)
      @time = (@time + (dt_sec.to_f * Scene::TIME_SPEED)) % 1.0
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
        BinaryPack.u32(0)
      )
    end

    private

    def positive_int(value)
      [value.to_i, 1].max
    end
  end
end
