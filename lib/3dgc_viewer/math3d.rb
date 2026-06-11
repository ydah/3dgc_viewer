# frozen_string_literal: true

module ThreeDgcViewer
  module Math3D
    EPSILON = 1e-6

    module Vec3
      module_function

      def make(x, y, z)
        [x.to_f, y.to_f, z.to_f].freeze
      end

      def add(a, b)
        make(a[0] + b[0], a[1] + b[1], a[2] + b[2])
      end

      def sub(a, b)
        make(a[0] - b[0], a[1] - b[1], a[2] - b[2])
      end

      def mul_scalar(a, scalar)
        make(a[0] * scalar, a[1] * scalar, a[2] * scalar)
      end

      def div_scalar(a, scalar)
        raise ArgumentError, "division by zero" if scalar.to_f.abs < EPSILON

        mul_scalar(a, 1.0 / scalar)
      end

      def dot(a, b)
        (a[0] * b[0]) + (a[1] * b[1]) + (a[2] * b[2])
      end

      def cross(a, b)
        make(
          (a[1] * b[2]) - (a[2] * b[1]),
          (a[2] * b[0]) - (a[0] * b[2]),
          (a[0] * b[1]) - (a[1] * b[0])
        )
      end

      def length(a)
        Math.sqrt(dot(a, a))
      end

      def normalize(a)
        len = length(a)
        return make(0.0, 0.0, 0.0) if len < EPSILON

        div_scalar(a, len)
      end
    end

    module Quat
      module_function

      def identity
        [0.0, 0.0, 0.0, 1.0].freeze
      end

      def make(x, y, z, w)
        [x.to_f, y.to_f, z.to_f, w.to_f].freeze
      end

      def from_axis_angle(axis, angle)
        n = Vec3.normalize(axis)
        half = angle.to_f * 0.5
        s = Math.sin(half)
        make(n[0] * s, n[1] * s, n[2] * s, Math.cos(half))
      end

      def from_rotation_arc(from, to)
        f = Vec3.normalize(from)
        t = Vec3.normalize(to)
        d = Vec3.dot(f, t)

        return identity if d > 1.0 - EPSILON

        if d < -1.0 + EPSILON
          axis = Vec3.cross([1.0, 0.0, 0.0], f)
          axis = Vec3.cross([0.0, 1.0, 0.0], f) if Vec3.length(axis) < EPSILON
          return from_axis_angle(axis, Math::PI)
        end

        c = Vec3.cross(f, t)
        normalize(make(c[0], c[1], c[2], 1.0 + d))
      end

      def normalize(q)
        len = Math.sqrt(q.sum { |v| v * v })
        return identity if len < EPSILON

        make(q[0] / len, q[1] / len, q[2] / len, q[3] / len)
      end

      def multiply(a, b)
        ax, ay, az, aw = a
        bx, by, bz, bw = b

        make(
          (aw * bx) + (ax * bw) + (ay * bz) - (az * by),
          (aw * by) - (ax * bz) + (ay * bw) + (az * bx),
          (aw * bz) + (ax * by) - (ay * bx) + (az * bw),
          (aw * bw) - (ax * bx) - (ay * by) - (az * bz)
        )
      end

      def conjugate(q)
        make(-q[0], -q[1], -q[2], q[3])
      end

      def rotate_vec3(q, v)
        qv = [v[0], v[1], v[2], 0.0]
        rotated = multiply(multiply(q, qv), conjugate(q))
        Vec3.make(rotated[0], rotated[1], rotated[2])
      end
    end

    module Mat4
      module_function

      def identity
        [
          1.0, 0.0, 0.0, 0.0,
          0.0, 1.0, 0.0, 0.0,
          0.0, 0.0, 1.0, 0.0,
          0.0, 0.0, 0.0, 1.0
        ].freeze
      end

      def look_at_rh(eye, target, up)
        f = Vec3.normalize(Vec3.sub(target, eye))
        f = [0.0, 0.0, -1.0] if Vec3.length(f) < EPSILON

        up = Vec3.normalize(up)
        up = [0.0, 1.0, 0.0] if Vec3.length(up) < EPSILON
        s = Vec3.normalize(Vec3.cross(f, up))
        if Vec3.length(s) < EPSILON
          fallback_up = f[1].abs < 0.9 ? [0.0, 1.0, 0.0] : [1.0, 0.0, 0.0]
          s = Vec3.normalize(Vec3.cross(f, fallback_up))
        end
        u = Vec3.cross(s, f)

        [
          s[0], u[0], -f[0], 0.0,
          s[1], u[1], -f[1], 0.0,
          s[2], u[2], -f[2], 0.0,
          -Vec3.dot(s, eye), -Vec3.dot(u, eye), Vec3.dot(f, eye), 1.0
        ].freeze
      end

      def perspective_rh(fovy_rad, aspect, znear, zfar)
        raise ArgumentError, "aspect must be positive" unless aspect.to_f.positive?
        raise ArgumentError, "znear/zfar must be positive" unless znear.to_f.positive? && zfar.to_f.positive?
        raise ArgumentError, "znear must differ from zfar" if (zfar.to_f - znear.to_f).abs < EPSILON

        f = 1.0 / Math.tan(fovy_rad.to_f * 0.5)
        [
          f / aspect, 0.0, 0.0, 0.0,
          0.0, f, 0.0, 0.0,
          0.0, 0.0, zfar / (znear - zfar), -1.0,
          0.0, 0.0, (znear * zfar) / (znear - zfar), 0.0
        ].freeze
      end
    end
  end
end
