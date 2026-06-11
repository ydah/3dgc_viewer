# frozen_string_literal: true

require "spec_helper"

RSpec.describe "WGSL shader constants" do
  it "keeps tile dimensions aligned with Ruby scene constants" do
    shader_paths = Dir[File.expand_path("../shaders/*.wgsl", __dir__)]
    checked = []

    shader_paths.each do |path|
      constants = File.read(path).scan(/^const\s+(TILE_[WH]):\s*u32\s*=\s*(\d+)u;/).to_h
      next if constants.empty?

      checked << File.basename(path)
      expect(constants.fetch("TILE_W").to_i).to eq(ThreeDgcViewer::Scene::TILE_W)
      expect(constants.fetch("TILE_H").to_i).to eq(ThreeDgcViewer::Scene::TILE_H)
    end

    expect(checked).not_to be_empty
  end
end
