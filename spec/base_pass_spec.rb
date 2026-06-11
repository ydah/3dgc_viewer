# frozen_string_literal: true

require "spec_helper"

RSpec.describe ThreeDgcViewer::Passes::BasePass do
  it "releases tracked GPU objects at most once" do
    objects = 2.times.map do
      Class.new do
        attr_reader :release_count

        def initialize
          @release_count = 0
        end

        def release
          @release_count += 1
        end
      end.new
    end
    pass = described_class.new(resources: nil, shader_loader: nil)
    pass.instance_variable_set(:@gpu_objects, objects.dup)

    pass.release
    pass.release

    expect(objects.map(&:release_count)).to eq([1, 1])
  end
end
