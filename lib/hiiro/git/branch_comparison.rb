class Hiiro
  class Git
    # Two refs and the questions asked about them: ahead/behind, fork point,
    # ancestry, ranges. The base policy that picked the target is explicit.
    class BranchComparison
      BASE_POLICIES = {
        local_main:   %w[main master],                            # h branch diff / ahead / behind / ancestor
        remote_first: %w[origin/master master origin/main main],  # h branch changed / log / forkpoint
      }.freeze

      def self.build(git, source: 'HEAD', target: nil, base_policy: :local_main, fallback: nil)
        return new(git, source: source, target: target, base_policy: base_policy, fallback: fallback, target_source: :explicit) if target

        found = BASE_POLICIES.fetch(base_policy).find { |ref| git.ref_exists?(ref) }
        if found
          new(git, source: source, target: found, base_policy: base_policy, fallback: fallback, target_source: :policy)
        elsif fallback
          new(git, source: source, target: fallback, base_policy: base_policy, fallback: fallback, target_source: :fallback)
        else
          new(git, source: source, target: nil, base_policy: base_policy, fallback: fallback, target_source: :none)
        end
      end

      attr_reader :git, :source, :target, :base_policy, :fallback, :target_source

      def initialize(git, source:, target:, base_policy:, fallback:, target_source:)
        @git = git
        @source = source
        @target = target
        @base_policy = base_policy
        @fallback = fallback
        @target_source = target_source
      end

      def resolved?  = !target.nil?
      def source_sha = git.commit(source)
      def target_sha = resolved? ? git.commit(target) : nil

      def merge_base = resolved? ? git.merge_base(target, source) : nil

      # --fork-point first, then a plain merge-base, then nil.
      def fork_point
        return nil unless resolved?
        @fork_point ||= git.merge_base(target, source, fork_point: true) || git.merge_base(target, source)
      end

      def ahead  = resolved? ? git.rev_list_count(two_dot_range) : nil
      def behind = resolved? ? git.rev_list_count("#{source}..#{target}") : nil

      def ancestor? = resolved? && git.ancestor?(target, source)

      def two_dot_range   = resolved? ? "#{target}..#{source}" : nil
      def three_dot_range = fork_point && "#{fork_point}...#{source}"
      def fork_range      = fork_point && "#{fork_point}..#{source}"

      def changed_paths(relative: true)
        range = three_dot_range or return []
        git.changed_files(range, relative: relative)
      end
    end
  end
end
