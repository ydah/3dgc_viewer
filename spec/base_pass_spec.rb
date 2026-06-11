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

  it "rejects encode after release until recreated" do
    pass = described_class.new(resources: nil, shader_loader: nil)

    pass.release

    expect { pass.encode(nil) }
      .to raise_error(ThreeDgcViewer::ResourceError, /used after release/)

    pass.recreate_bind_group(resources: nil)
    expect { pass.encode(nil) }.not_to raise_error
  end
end
