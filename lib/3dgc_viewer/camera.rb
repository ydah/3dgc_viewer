# frozen_string_literal: true

require_relative "math3d"
require_relative "window/keymap"

module ThreeDgcViewer
  Camera = Struct.new(:eye, :target, :up, :aspect, :fovy, :znear, :zfar, keyword_init: true) do
    def self.default(width: Scene::SCREEN_WIDTH, height: Scene::SCREEN_HEIGHT)
      new(
        eye: [10.0, 5.0, 10.0],
        target: [0.0, 0.0, 0.0],
        up: [0.0, 1.0, 0.0],
        aspect: width.to_f / height.to_f,
        fovy: 45.0,
        znear: 0.1,
        zfar: 10_000.0
      )
    end

    def view_matrix
      Math3D::Mat4.look_at_rh(eye, target, up)
    end

    def projection_matrix
      Math3D::Mat4.perspective_rh(fovy * Math::PI / 180.0, aspect, znear, zfar)
    end

    def fit_bounds(bounds, padding: 1.25)
      return self if bounds.nil? || bounds.empty?

      scene_center = bounds.center
      scene_radius = bounds.radius * padding.to_f
      half_fovy = (fovy * Math::PI / 180.0) * 0.5
      half_fovx = Math.atan(Math.tan(half_fovy) * aspect.to_f)
      fit_half_angle = [half_fovy, half_fovx].min
      distance = scene_radius / Math.sin(fit_half_angle)
      direction = Math3D::Vec3.normalize(Math3D::Vec3.sub(eye, target))
      direction = [0.0, 0.0, 1.0] if Math3D::Vec3.length(direction) < Math3D::EPSILON

      self.target = scene_center
      self.eye = Math3D::Vec3.add(scene_center, Math3D::Vec3.mul_scalar(direction, distance))
      self.znear = [distance - (scene_radius * 2.0), distance * 0.001, 0.001].max
      self.zfar = [distance + (scene_radius * 2.0), znear * 2.0].max
      self
    end
  end

  class CameraController
    attr_reader :radius

    def initialize(speed: 1.0)
      @rotate_speed = speed * 0.25
      @base_zoom_speed = speed
      @zoom_speed = speed
      @radius = 1.0
      @scene_radius = 1.0
      @keys = {
        yaw_left: false,
        yaw_right: false,
        pitch_up: false,
        pitch_down: false,
        roll_left: false,
        roll_right: false,
        zoom_in: false,
        zoom_out: false
      }
    end

    def sync_from_camera(camera)
      @radius = Math3D::Vec3.length(Math3D::Vec3.sub(camera.eye, camera.target))
    end

    def fit_scene_radius(radius)
      @scene_radius = [radius.to_f, 0.01].max
      @zoom_speed = @base_zoom_speed * @scene_radius
    end

    def handle_key(key, pressed)
      action = Window::Keymap.camera_action(key)
      return false unless action && @keys.key?(action)

      changed = @keys[action] != pressed
      @keys[action] = pressed
      changed
    end

    def update_camera(camera, dt_sec)
      offset = Math3D::Vec3.sub(camera.eye, camera.target)
      up = Math3D::Vec3.normalize(camera.up)
      changed = false

      yaw = axis_value(:yaw_left, :yaw_right) * @rotate_speed * dt_sec
      if yaw != 0.0
        offset = Math3D::Quat.rotate_vec3(Math3D::Quat.from_axis_angle([0.0, 1.0, 0.0], yaw), offset)
        up = Math3D::Quat.rotate_vec3(Math3D::Quat.from_axis_angle([0.0, 1.0, 0.0], yaw), up)
        changed = true
      end

      right = Math3D::Vec3.normalize(Math3D::Vec3.cross(up, Math3D::Vec3.normalize(offset)))
      pitch = axis_value(:pitch_up, :pitch_down) * @rotate_speed * dt_sec
      if pitch != 0.0
        q = Math3D::Quat.from_axis_angle(right, pitch)
        offset = Math3D::Quat.rotate_vec3(q, offset)
        up = Math3D::Quat.rotate_vec3(q, up)
        changed = true
      end

      forward = Math3D::Vec3.normalize(Math3D::Vec3.mul_scalar(offset, -1.0))
      roll = axis_value(:roll_left, :roll_right) * @rotate_speed * dt_sec
      if roll != 0.0
        up = Math3D::Quat.rotate_vec3(Math3D::Quat.from_axis_angle(forward, roll), up)
        changed = true
      end

      zoom = axis_value(:zoom_out, :zoom_in) * @zoom_speed * dt_sec
      if zoom != 0.0
        @radius = [@radius - zoom, 0.01].max
        offset = Math3D::Vec3.mul_scalar(Math3D::Vec3.normalize(offset), @radius)
        changed = true
      else
        @radius = Math3D::Vec3.length(offset)
      end

      return :idle unless changed

      camera.eye = Math3D::Vec3.add(camera.target, offset)
      camera.up = Math3D::Vec3.normalize(up)
      :active
    end

    private

    def axis_value(negative_key, positive_key)
      (@keys[negative_key] ? -1.0 : 0.0) + (@keys[positive_key] ? 1.0 : 0.0)
    end
  end
end
