# frozen_string_literal: true

module Semverve
  ##
  # Resolves configured Rake::FileList entries relative to a project root.
  class FileListResolver
    ##
    # Initializes file-list resolution.
    #
    # @param [String] root
    # @param [Rake::FileList] file_list
    #
    # @return [Semverve::FileListResolver]
    def initialize(root:, file_list:)
      @root = root
      @file_list = file_list
    end

    ##
    # Absolute files from the configured file list.
    #
    # @return [Array<String>]
    def files
      configured_files.map { |path| File.expand_path(path, root) }
        .select { |path| File.file?(path) }
        .uniq
    end

    private

    ##
    # Absolute project root.
    #
    # @return [String]
    attr_reader :root

    ##
    # Configured Rake file list.
    #
    # @return [Rake::FileList]
    attr_reader :file_list

    ##
    # Configured files expanded relative to the root.
    #
    # @return [Array<String>]
    def configured_files
      Dir.chdir(root) do
        file_list.to_a.flat_map { |path| expand_file_list_entry(path) }
          .reject { |path| file_list.excluded_from_list?(path) }
      end
    end

    ##
    # Expands glob-like entries that were appended to a Rake::FileList.
    #
    # @param [String] path
    #
    # @return [Array<String>]
    def expand_file_list_entry(path)
      matches = Dir.glob(path)

      matches.empty? ? [path] : matches
    end
  end
end
