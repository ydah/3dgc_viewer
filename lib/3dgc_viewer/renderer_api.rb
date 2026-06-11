# frozen_string_literal: true

module ThreeDgcViewer
  class << self
    def render(path, output:, width: nil, height: nil, render_width: nil, render_height: nil,
               background_color: nil, assert_nonzero: false)
      argv = ["--file", path.to_s, "--screenshot", output.to_s, "--hidden"]
      append_option(argv, "--width", width)
      append_option(argv, "--height", height)
      append_option(argv, "--render-width", render_width)
      append_option(argv, "--render-height", render_height)
      append_option(argv, "--background-color", background_color)
      argv << "--assert-render-nonzero" if assert_nonzero
      App.run(argv)
    end

    private

    def append_option(argv, name, value)
      return if value.nil?

      argv << name << value.to_s
    end
  end
end
