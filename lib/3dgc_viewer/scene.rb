# frozen_string_literal: true

module ThreeDgcViewer
  module Scene
    SCREEN_WIDTH = 1280
    SCREEN_HEIGHT = 720
    TILE_W = 16
    TILE_H = 16
    TIME_SPEED = 0.5

    module_function

    def dynamic?(kind)
      kind == :gaussian4d
    end
  end
end
