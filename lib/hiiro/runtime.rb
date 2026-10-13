require 'json'
require 'securerandom'

class Hiiro
  # Workstation runtime: persistence, invocation history, and task auto-tagging.
  #
  # Import, registration, help, completion, and discovery never start it. It
  # starts when an operation first uses persistence (any reference to DB or a
  # model autoloads hiiro/persistence) or when code calls activate!.
  #
  # Every Hiiro.init adds a frame { id, bin, subcmd, args, pwd } to
  # HIIRO_INVOCATION_FRAMES and the first one allocates HIIRO_INVOCATION_ID.
  # Both are environment variables, so an external command inherits them. The
  # process that starts the runtime writes the invocation (once) and every
  # pending frame as an ordered resolution; a frame already written by a child
  # is skipped by its id. Task-enabled instances in that process then tag the
  # current branch.
  module Runtime
    FRAMES = 'HIIRO_INVOCATION_FRAMES'
    ID = 'HIIRO_INVOCATION_ID'

    @tagging = []

    class << self
      def active? = @active == true

      def activate!
        Hiiro::DB.setup!
        self
      end

      def started!
        return if active?

        @active = true
        record!
      end

      def track(hiiro)
        ENV[ID] ||= "inv_#{Time.now.strftime('%Y%m%d%H%M%S%L')}_#{SecureRandom.hex(4)}"
        frame = hiiro.invocation_frame.merge(id: SecureRandom.hex(8), pwd: Dir.pwd)
        ENV[FRAMES] = JSON.generate(pending_frames << frame)
        @tagging << hiiro if hiiro.tasks_enabled?
        record! if active?
      end

      def pending_frames
        JSON.parse(ENV.fetch(FRAMES, '[]'))
      rescue JSON::ParserError
        []
      end

      private

      def record!
        frames = pending_frames
        Hiiro::Invocation.record_frames!(ENV[ID], frames) if ENV[ID] && frames.any?
        ENV.delete(FRAMES)
        tagging, @tagging = @tagging, []
        tagging.each(&:auto_tag_branch_with_task)
      end
    end
  end
end
