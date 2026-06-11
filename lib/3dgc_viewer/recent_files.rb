# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "atomic_file"

module ThreeDgcViewer
  class RecentFiles
    DEFAULT_LIMIT = 10

    attr_reader :path, :limit

    def self.default_path
      configured = ENV["THREEDGC_VIEWER_RECENT_FILES"]
      return configured unless configured.to_s.empty?

      base =
        if ENV["XDG_STATE_HOME"] && !ENV["XDG_STATE_HOME"].empty?
          ENV["XDG_STATE_HOME"]
        elsif Gem.win_platform? && ENV["APPDATA"] && !ENV["APPDATA"].empty?
          ENV["APPDATA"]
        elsif RUBY_PLATFORM.include?("darwin")
          File.join(Dir.home, "Library", "Application Support")
        else
          File.join(Dir.home, ".local", "state")
        end
      File.join(base, "3dgc_viewer", "recent_files.json")
    rescue ArgumentError
      nil
    end

    def initialize(path: self.class.default_path, limit: DEFAULT_LIMIT)
      @path = path.to_s.empty? ? nil : File.expand_path(path)
      @limit = limit.to_i.positive? ? limit.to_i : DEFAULT_LIMIT
    end

    def load
      return [] unless @path && File.file?(@path)

      entries = JSON.parse(File.read(@path))
      return [] unless entries.is_a?(Array)

      normalize(entries)
    rescue JSON::ParserError, SystemCallError
      []
    end

    def save(paths)
      entries = normalize(paths)
      return entries unless @path

      FileUtils.mkdir_p(File.dirname(@path))
      AtomicFile.write(@path, "#{JSON.pretty_generate(entries)}\n")
      entries
    end

    def clear
      File.delete(@path) if @path && File.exist?(@path)
      []
    rescue Errno::ENOENT
      []
    end

    private

    def normalize(paths)
      Array(paths).filter_map do |path|
        text = path.to_s.strip
        next if text.empty?

        File.expand_path(text)
      end.uniq.first(@limit)
    end
  end
end
