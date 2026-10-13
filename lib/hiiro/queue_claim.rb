require 'fileutils'

class Hiiro
  # One launcher's exclusive hold on a queue entry. Claiming renames the pending
  # prompt into running/, so competing launchers cannot both win; settling moves
  # the entry to done/ or failed/ from its run's observed outcome.
  class QueueClaim
    def self.claim(root, name)
      FileUtils.mkdir_p(File.join(root, 'running'))
      File.rename(File.join(root, 'pending', "#{name}.md"), File.join(root, 'running', "#{name}.md"))
      new(root, name)
    rescue Errno::ENOENT
      nil
    end

    def self.settle(run, store: nil)
      new(run.owner.fetch('root'), run.owner.fetch('name')).settle(run.state == 'completed' ? 'done' : 'failed')
    end

    attr_reader :root, :name

    def initialize(root, name)
      @root = root
      @name = name
    end

    def owner = { 'kind' => 'queue', 'root' => root, 'name' => name }
    def running_path(ext) = File.join(root, 'running', "#{name}#{ext}")

    # Idempotent: a second settle finds nothing left in running/.
    def settle(status)
      destination = File.join(root, status)
      FileUtils.mkdir_p(destination)
      %w[.md .meta .log].each do |ext|
        File.rename(running_path(ext), File.join(destination, "#{name}#{ext}"))
      rescue Errno::ENOENT
        nil
      end
      FileUtils.rm_f(running_path('.prompt'))
    end
  end
end
