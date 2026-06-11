# frozen_string_literal: true

require "spec_helper"
require "json"
require "tempfile"

RSpec.describe ThreeDgcViewer::RecentFiles do
  it "loads missing history as empty" do
    store = described_class.new(path: File.join(Dir.tmpdir, "missing-3dgc-recent.json"))

    expect(store.load).to eq([])
  end

  it "saves normalized unique paths up to the limit" do
    file = Tempfile.new(["recent", ".json"])
    path = file.path
    file.close
    file.unlink
    store = described_class.new(path: path, limit: 2)

    saved = store.save(["a.ply", "b.ply", "a.ply", "c.ply"])

    expect(saved).to eq([File.expand_path("a.ply"), File.expand_path("b.ply")])
    expect(store.load).to eq(saved)
    expect(JSON.parse(File.read(path))).to eq(saved)
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  it "ignores invalid JSON history" do
    file = Tempfile.new(["recent", ".json"])
    file.write("not json")
    file.close

    store = described_class.new(path: file.path)

    expect(store.load).to eq([])
  ensure
    file&.unlink
  end
end
