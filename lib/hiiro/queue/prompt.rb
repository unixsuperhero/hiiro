require 'front_matter_parser'

class Hiiro
  class Queue
    # Value object representing a parsed prompt with frontmatter.
    # Extracts task_name, tree_name, session_name from YAML frontmatter
    # and resolves them to actual Task/Tree/Session objects.
    class Prompt
      # Parse a prompt from a file path.
      #
      # @param path [String] path to the markdown file
      # @param hiiro [Hiiro, nil] optional Hiiro instance for environment access
      # @return [Prompt, nil] parsed prompt or nil if file doesn't exist
      def self.from_file(path, hiiro: nil)
        return nil unless File.exist?(path)
        new(FrontMatterParser::Parser.parse_file(path), hiiro: hiiro)
      end

      attr_reader :hiiro, :doc

      def initialize(doc, hiiro: nil)
        @hiiro = hiiro
        @doc = doc
      end

      # --- Data Accessors ---

      def frontmatter
        doc.front_matter || {}
      end

      def frontmatter_value(key)
        frontmatter[key]
      end

      def content
        doc.content.strip
      end

      alias_method :body, :content

      def task_name
        frontmatter_value('task_name')
      end

      def tree_name
        frontmatter_value('tree_name')
      end

      def session_name
        frontmatter_value('session_name')
      end

      # --- Related Objects ---

      # Resolve the task from frontmatter.
      #
      # @return [Task, nil] resolved task or nil
      def task
        return nil unless task_name
        hiiro&.environment&.find_task(task_name)
      end

      # Resolve the session from frontmatter.
      #
      # @return [TmuxSession, nil] resolved session or nil
      def session
        return nil unless session_name
        hiiro&.environment&.find_session(session_name)
      end

      # Resolve the tree from frontmatter.
      #
      # @return [Tree, nil] resolved tree or nil
      def tree
        return nil unless tree_name
        hiiro&.environment&.find_tree(tree_name)
      end
    end
  end
end
