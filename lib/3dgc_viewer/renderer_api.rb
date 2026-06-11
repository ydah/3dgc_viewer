# frozen_string_literal: true

module ThreeDgcViewer
  class << self
    def render(path, output:, width: nil, height: nil, render_width: nil, render_height: nil,
               render_scale: nil,
               background_color: nil, transparent_background: false,
               exposure: nil, gamma: nil, brightness: nil, contrast: nil,
               opacity_threshold: nil, scale_multiplier: nil,
               sh_degree: nil, max_gaussians: nil, max_file_bytes: nil,
               time: nil, time_speed: nil, time_range: nil, pause: false,
               quality: nil, low_vram: false,
               camera_preset: nil, assert_nonzero: false)
      argv = ["--file", path.to_s, "--screenshot", output.to_s, "--hidden"]
      append_option(argv, "--width", width)
      append_option(argv, "--height", height)
      append_option(argv, "--render-width", render_width)
      append_option(argv, "--render-height", render_height)
      append_option(argv, "--render-scale", render_scale)
      append_option(argv, "--background-color", background_color)
      argv << "--transparent-background" if transparent_background
      append_option(argv, "--exposure", exposure)
      append_option(argv, "--gamma", gamma)
      append_option(argv, "--brightness", brightness)
      append_option(argv, "--contrast", contrast)
      append_option(argv, "--opacity-threshold", opacity_threshold)
      append_option(argv, "--scale-multiplier", scale_multiplier)
      append_option(argv, "--sh-degree", sh_degree)
      append_option(argv, "--max-gaussians", max_gaussians)
      append_option(argv, "--max-file-bytes", max_file_bytes)
      append_option(argv, "--time", time)
      append_option(argv, "--time-speed", time_speed)
      append_option(argv, "--time-range", format_time_range(time_range))
      argv << "--pause" if pause
      append_option(argv, "--quality", quality)
      argv << "--low-vram" if low_vram
      append_option(argv, "--camera-preset", camera_preset)
      argv << "--assert-render-nonzero" if assert_nonzero
      App.run(argv)
    end

    private

    def append_option(argv, name, value)
      return if value.nil?

      argv << name << value.to_s
    end

    def format_time_range(value)
      return nil if value.nil?
      return value if value.is_a?(String)

      Array(value).join(",")
    end
  end
end
