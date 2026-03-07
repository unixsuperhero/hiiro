class Hiiro
  class ServiceManager
    # Value object for a group member.
    # Represents a service within a group with optional variation overrides.
    class Member
      attr_reader :name, :use_overrides

      def initialize(name:, use_overrides: {})
        @name = name
        @use_overrides = use_overrides
      end
    end
  end
end
