class Hiiro
  # One named key/value list, stored as registry.resource_type.
  class Table
    attr_reader :name

    def self.all          = RegistryEntry.known_types.map { |type| new(type) }
    def self.named(name)  = new(name)

    def initialize(name)
      @name = name.to_s
    end

    def exists? = !dataset.empty?

    def entries(scope: TableScope.global) = scope.apply(dataset).order(:name).all
    def count(scope: TableScope.global)   = scope.apply(dataset).count

    def add(name, value: nil, short: nil, desc: nil, meta: nil, task_id: nil)
      RegistryEntry.create(
        resource_type: self.name,
        name:          name,
        value:         value,
        short_name:    short,
        description:   desc,
        meta_json:     meta && Hiiro::DB::JSON.dump(meta),
        task_id:       task_id,
        created_at:    Time.now.iso8601
      )
    end

    def find(ref) = RegistryEntry.find_by_ref(ref, type: name)

    def rename(new_name)
      target = self.class.named(new_name)
      raise Hiiro::Error, "table already exists: #{target.name}" if target.exists?

      dataset.update(resource_type: target.name)
      target
    end

    def ==(other) = other.is_a?(Table) && name == other.name
    alias eql? ==
    def hash = name.hash
    def to_s = name

    private

    def dataset = RegistryEntry.where(resource_type: name)
  end
end
