# frozen_string_literal: true

module ThreeDgcViewer
  module ControlsHelp
    ENTRIES = [
      ["Esc", "Close window"],
      ["A/D or Left/Right", "Orbit yaw"],
      ["W/S or Up/Down", "Orbit pitch"],
      ["Q/E", "Zoom in/out"],
      ["Z/C", "Roll camera"],
      ["Left mouse drag", "Orbit camera"],
      ["Right or middle mouse drag", "Pan camera"],
      ["Mouse wheel or trackpad scroll", "Zoom camera"],
      ["Space", "Toggle playback pause"],
      ["F", "Fit view to scene"],
      ["R", "Reset camera"],
      ["T", "Toggle turntable animation"],
      ["X", "Toggle axis overlay"],
      ["L", "Reload current file"]
    ].freeze

    module_function

    def entries
      ENTRIES.map { |keys, action| {keys: keys, action: action} }
    end

    def text
      entries.map { |entry| "#{entry[:keys]}: #{entry[:action]}" }.join("\n")
    end
  end
end
