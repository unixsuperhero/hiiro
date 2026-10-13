require 'fileutils'

class Hiiro
  # Which reusable Herdr pane belongs to which run. Selection and reservation
  # happen under one lock, so concurrent launchers never pick the same pane.
  class PaneReservations
    # A reservation whose run record has not been written yet still holds the
    # pane for this long; after that the launcher is presumed dead.
    UNRECORDED_GRACE = 60

    def self.default = new(File.join(Dir.home, '.local/share/hiiro/bg/reservations'))

    def self.settle(run, store:)
      dir = run.placement['reservations']
      pane = run.placement['pane']
      new(dir).release(pane, run.id) if dir && pane
    end

    attr_reader :dir

    def initialize(dir)
      @dir = dir
    end

    def synchronize
      FileUtils.mkdir_p(dir)
      File.open(File.join(dir, '.lock'), File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        yield self
      end
    end

    def holder(pane_id)
      path = path_for(pane_id)
      File.exist?(path) ? File.read(path).strip : nil
    end

    # Call inside synchronize.
    def reserved?(pane_id, store:)
      run_id = holder(pane_id)
      return false unless run_id

      run = store.find(run_id)
      return run.active? if run

      File.mtime(path_for(pane_id)) > Time.now - UNRECORDED_GRACE
    end

    # Call inside synchronize.
    def reserve(pane_id, run_id)
      File.write(path_for(pane_id), run_id)
    end

    def release(pane_id, run_id)
      synchronize do
        File.delete(path_for(pane_id)) if holder(pane_id) == run_id
      end
    end

    private

    def path_for(pane_id) = File.join(dir, pane_id.to_s.gsub(/[^\w.-]/, '_'))
  end
end
