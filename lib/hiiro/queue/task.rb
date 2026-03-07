class Hiiro
  class Queue
    # Value object representing a queue task (prompt) with its status.
    # Provides convenience methods for launching, status checking, and path resolution.
    class Task
      attr_reader :name, :status, :queue

      def initialize(name:, status:, queue:)
        @name = name
        @status = status
        @queue = queue
      end

      # --- Status Predicates ---

      def pending?
        status == 'pending'
      end

      def running?
        status == 'running'
      end

      def done?
        status == 'done'
      end

      def failed?
        status == 'failed'
      end

      def wip?
        status == 'wip'
      end

      def retryable?
        done? || failed?
      end

      # --- Path Accessors ---

      def path
        queue.task_path(name, status.to_sym)
      end

      def meta_path
        queue.meta_path(name, status.to_sym)
      end

      def meta
        queue.meta_for(name, status.to_sym)
      end

      # --- Actor Methods ---

      # Launch this task (must be pending).
      #
      # @param hiiro [Hiiro, nil] optional Hiiro instance for environment access
      # @return [Boolean] true if launched successfully
      def launch(hiiro: nil)
        return false unless pending?
        Launch.new(self, queue, hiiro: hiiro).call
      end

      # --- Serialization ---

      def to_h
        { name: name, status: status }
      end
    end
  end
end
