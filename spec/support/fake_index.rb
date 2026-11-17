# frozen_string_literal: true

# A desktop file index for `Pikuri::Os::FileindexSearch` and `FileindexRead`, which want a module
# (they rescue `backend::CommandError`): it finds the files whose text holds the query, read off
# the disk, so a spec needs neither localsearch nor recoll.
#
#   index = FakeIndex.new                     # answers
#   index = FakeIndex.new(available: false)   # as on a machine with no index
#   index.search(query: 'lease', limit: 10, folder: '/tmp/docs')   # => [{ path:, snippet: }]
module FakeIndex
  # @param available [Boolean] whether the index answers
  # @return [Module] a file-index backend
  def self.new(available: true)
    Module.new do
      const_set(:CommandError, Class.new(StandardError))
      define_singleton_method(:available?) { available }
      define_singleton_method(:check_binaries!) { raise 'no index' unless available }
      define_singleton_method(:label) { 'fake' }
      define_singleton_method(:limitations) { '' }
      define_singleton_method(:read_text) { |path| File.file?(path) ? File.read(path) : nil }
      define_singleton_method(:search) do |query:, limit:, folder: nil|
        Dir.glob(File.join(folder || Dir.home, '**', '*')).select { File.file?(_1) }
           .select { File.read(_1).include?(query) }.first(limit).map { { path: _1, snippet: query } }
      end
    end
  end
end
