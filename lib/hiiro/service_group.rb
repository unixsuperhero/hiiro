class Hiiro
  class ServiceGroup
    attr_reader :name, :members

    def initialize(name:, services:, **config)
      @name = name
      @members = Array(services).map { |m| m.is_a?(Hash) ? Member.new(**m) : m }
      @config = config
    end

    def member_names
      members.map(&:name)
    end

    def empty?
      members.empty?
    end

    class Member
      attr_reader :name, :use

      def initialize(name:, use: {}, **_rest)
        @name = name
        @use = use || {}
      end
    end
  end
end
