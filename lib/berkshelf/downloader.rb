require_relative 'dependency'
require_relative 'location'

module Berkshelf
  class Downloader
    extend Forwardable

    DEFAULT_LOCATIONS = [
      {
        type: :site,
        value: Location::OPSCODE_COMMUNITY_API,
        options: Hash.new
      }
    ]

    # @return [String]
    #   a filepath to download dependencies to
    attr_reader :cookbook_store

    def_delegators :@cookbook_store, :storage_path

    # @option options [Array<Hash>] locations
    def initialize(cookbook_store, options = {})
      @cookbook_store = cookbook_store
      @locations = options.fetch(:locations, Array.new)
    end

    # @return [Array<Hash>]
    #   an Array of Hashes representing each default location that can be used to attempt
    #   to download dependencies which do not have an explicit location. An array of default locations will
    #   be used if no locations are explicitly added by the {#add_location} function.
    def locations
      @locations.any? ? @locations : DEFAULT_LOCATIONS
    end

    # Create a location hash and add it to the end of the array of locations.
    #
    # subject.add_location(:chef_api, "http://chef:8080", node_name: "reset", client_key: "/Users/reset/.chef/reset.pem") =>
    #   [ { type: :chef_api, value: "http://chef:8080/", node_name: "reset", client_key: "/Users/reset/.chef/reset.pem" } ]
    #
    # @param [Symbol] type
    # @param [String, Symbol] value
    # @param [Hash] options
    #
    # @return [Hash]
    def add_location(type, value, options = {})
      if has_location?(type, value)
        raise DuplicateLocationDefined,
          "A default '#{type}' location with the value '#{value}' is already defined"
      end

      @locations.push(type: type, value: value, options: options)
    end

    # Checks the list of default locations if a location of the given type and value has already
    # been added and returns true or false.
    #
    # @return [Boolean]
    def has_location?(type, value)
      @locations.select { |loc| loc[:type] == type && loc[:value] == value }.any?
    end

    # Downloads the given Berkshelf::Dependency.
    #
    # @param [Berkshelf::Dependency] dependency
    #   the dependency to download
    #
    # @return [Array]
    #   an array containing the downloaded CachedCookbook and the Location used
    #   to download the cookbook
    def download(dependency)
      cached_cookbook, location = if dependency.location
        begin
          [dependency.location.download(storage_path), dependency.location]
        rescue CookbookValidationFailure; raise
        rescue
          Berkshelf.formatter.error "Failed to download '#{dependency.name}' from #{dependency.location}"
          raise
        end
      else
        search_locations(dependency)
      end

      dependency.cached_cookbook = cached_cookbook

      [cached_cookbook, location]
    end

    private

      # Searches locations for a Berkshelf::Dependency. If the dependency does not contain a
      # value for {Berkshelf::Dependency#location}, the default locations of this
      # downloader will be used to attempt to retrieve the dependency.
      #
      # @param [Berkshelf::Dependency] dependency
      #   the dependency to download
      #
      # @return [Array]
      #   an array containing the downloaded CachedCookbook and the Location used
      #   to download the cookbook
      def search_locations(dependency)
        cached_cookbook = nil
        location = nil

        locations.each do |loc|
          location = Location.init(
            dependency.name,
            dependency.version_constraint,
            loc[:options].merge(loc[:type] => loc[:value])
          )
          begin
            cached_cookbook = location.download(storage_path)
            break
          rescue Berkshelf::CookbookNotFound
            cached_cookbook, location = nil
            next
          end
        end

        if cached_cookbook.nil?
          raise CookbookNotFound, "Cookbook '#{dependency.name}' not found in any of the default locations"
        end

        [ cached_cookbook, location ]
      end


      # Validates that a dependency is an instance of Berkshelf::Dependency
      #
      # @param [Berkshelf::Dependency] dependency
      #
      # @return [Boolean]
      def validate_dependency(dependency)
        dependency.is_a?(Berkshelf::Dependency)
      end
  end
end
