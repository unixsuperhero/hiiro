class Hiiro
  class Git
    class Pr
      attr_reader :number, :title, :state, :url, :head_branch, :base_branch

      def self.current
        output = `gh pr view --json number,title,state,url,headRefName,baseRefName 2>/dev/null`
        return nil if output.empty?

        require 'json'
        data = JSON.parse(output)
        from_gh_json(data)
      rescue
        nil
      end

      def self.from_gh_json(data)
        new(
          number: data['number'],
          title: data['title'],
          state: data['state'],
          url: data['url'],
          head_branch: data['headRefName'],
          base_branch: data['baseRefName'],
        )
      end

      def self.list(state: 'open', limit: 30)
        output = `gh pr list --state #{state} --limit #{limit} --json number,title,state,url,headRefName,baseRefName 2>/dev/null`
        return [] if output.empty?

        require 'json'
        JSON.parse(output).map { |data| from_gh_json(data) }
      rescue
        []
      end

      def self.create(title:, body: nil, base: nil, draft: false)
        args = ['gh', 'pr', 'create', '--title', title]
        args += ['--body', body] if body
        args += ['--base', base] if base
        args << '--draft' if draft

        system(*args)
      end

      def initialize(number:, title: nil, state: nil, url: nil, head_branch: nil, base_branch: nil)
        @number = number
        @title = title
        @state = state
        @url = url
        @head_branch = head_branch
        @base_branch = base_branch
      end

      def open?
        state&.downcase == 'open'
      end

      def closed?
        state&.downcase == 'closed'
      end

      def merged?
        state&.downcase == 'merged'
      end

      def view
        system('gh', 'pr', 'view', number.to_s)
      end

      def checkout
        system('gh', 'pr', 'checkout', number.to_s)
      end

      def merge(method: nil, delete_branch: true)
        args = ['gh', 'pr', 'merge', number.to_s]
        args << "--#{method}" if method # squash, merge, rebase
        args << '--delete-branch' if delete_branch
        system(*args)
      end

      def close
        system('gh', 'pr', 'close', number.to_s)
      end

      def reopen
        system('gh', 'pr', 'reopen', number.to_s)
      end

      def to_s
        "##{number}: #{title}"
      end

      def to_h
        {
          number: number,
          title: title,
          state: state,
          url: url,
          head_branch: head_branch,
          base_branch: base_branch,
        }.compact
      end
    end
  end
end
