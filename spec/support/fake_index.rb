# frozen_string_literal: true

# A desktop file index for `Pikuri::Fileindex::Search` and `Read`, which want a module (they
# rescue `backend::CommandError`): it finds the files under the folders whose text holds the
# query, read off the disk, so a spec needs neither localsearch nor recoll.
#
#   index = FakeIndex.new                     # answers
#   index = FakeIndex.new(available: false)   # as on a machine with no index
#   index.search(query: 'lease', limit: 10, folders: ['/tmp/docs'])   # => [{ path:, snippet:, text_size: }]
module FakeIndex
  # @param available [Boolean] whether the index answers
  # @return [Module] a file-index backend
  def self.new(available: true)
    Module.new do
      const_set(:CommandError, Class.new(StandardError))
      define_singleton_method(:unavailable_reason) { |**| available ? nil : 'not installed' }
      define_singleton_method(:label) { 'fake' }
      define_singleton_method(:limitations) { '' }
      define_singleton_method(:read_text) { |path| File.file?(path) ? File.read(path) : nil }
      define_singleton_method(:paths) do |query:, folders:|
        folders.flat_map { Dir.glob(File.join(_1, '**', '*')) }
               .select { File.file?(_1) && File.read(_1).include?(query) }
      end
      define_singleton_method(:search) do |query:, limit:, folders:|
        paths(query:, folders:).first(limit).map { { path: _1, snippet: query, text_size: File.size(_1) } }
      end
    end
  end
end
