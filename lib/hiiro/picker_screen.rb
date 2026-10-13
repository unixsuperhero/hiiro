require 'set'
require_relative 'tui'
require_relative 'picker'

class Hiiro
  # The shared picker on the Tui engine. Items are Picker::Items; rules hide
  # the ones they match. Enter chooses, Tab marks (multi), the edit key
  # (Ctrl-E, or HIIRO_PICKER_EDIT_KEY=ctrl-X) opens the document in $EDITOR,
  # Ctrl-X switches to the excluded view, where u restores the item under the
  # cursor. Every change is previewed (mode :confirm) before it is saved.
  class PickerScreen < Tui::Screen
    key :enter, :choose
    key "\t", :toggle_mark
    key "\u0018", :toggle_excluded
    key 'u', :restore

    def self.edit_key(env = ENV)
      letter = env.fetch('HIIRO_PICKER_EDIT_KEY', 'ctrl-e').downcase[/\Actrl-([a-z])\z/, 1] || 'e'
      [(letter.ord - 96).chr, "^#{letter.upcase}"]
    end

    attr_reader :rules, :marks, :view

    def initialize(name:, family:, items:, context:, store:, editor:, multi: false)
      @name = name
      @family = family
      @all_items = items
      @context = context
      @store = store
      @editor = editor
      @multi = multi
      @marks = Set.new
      @view = :visible
      @edit_key, @edit_label = self.class.edit_key
      @rules = store.applicable(name, context)
      exclude!
      super(items: view_items, empty_message: 'Nothing to choose.')
    end

    def nothing_to_show? = @all_items.empty?

    def header_lines
      return confirm_header if state.mode == :confirm

      where = @context.task_id ? "  #{@context.describe('task')}" : ''
      title = "#{@name}  #{@view == :excluded ? 'excluded' : 'choices'}  (#{@excluded.length} excluded)#{where}"
      keys = if @view == :excluded
        "u restore  #{@edit_label} edit rules  ^X back"
      else
        "Enter choose#{'  Tab mark' if @multi}  #{@edit_label} edit  ^X excluded"
      end
      [title, keys]
    end

    def format_row(item, current, line_cols)
      return super unless item.is_a?(Picker::Item)

      text = item.label
      text = "#{text}  <- #{@excluded[item.identity].describe}" if @view == :excluded
      prefix = "#{current ? '>' : ' '}#{@marks.include?(item.identity) ? '*' : ' '} "
      prefix + visible_text(text, [line_cols - prefix.length, 1].max, horizontal_offset)
    end

    private

    def list_mode_key(key)
      return edit if key == @edit_key

      super
    end

    def confirm_mode_key(key)
      case key
      when 'y', :enter then save_pending
      when 'n', :escape then leave_confirm('Cancelled; nothing saved')
      when :ctrl_c then quit
      when 'j', :down then move(1)
      when 'k', :up then move(-1)
      end
    end

    def filtered_items
      return @preview if state.mode == :confirm

      super
    end

    def choose
      return self.message = 'Excluded; press u to restore it' if @view == :excluded

      item = current_item
      return self.message = 'Nothing to choose' unless item
      return finish(item) unless @multi

      marked = items.select { |candidate| @marks.include?(candidate.identity) }
      finish(marked.empty? ? [item] : marked)
    end

    def toggle_mark
      return unless @multi && @view == :visible && current_item

      identity = current_item.identity
      @marks.delete(identity) unless @marks.add?(identity)
      move(1)
    end

    def toggle_excluded
      position = anchor
      @view = @view == :visible ? :excluded : :visible
      @empty_message = @view == :excluded ? 'Nothing excluded.' : 'Nothing to choose.'
      self.message = nil
      @items = view_items
      if @return_to
        rebuild(@return_to)
        @return_to = nil
      else
        @return_to = position
        state.cursor = 0
        state.top = 0
      end
    end

    def edit
      snapshot, text = @recovery || begin
        listed = @view == :visible ? filtered_items.dup : []
        [listed, document(listed).text]
      end
      edited = suspend { @editor.call(text) }
      change = edited.valid? ? document(snapshot).change(edited.parsed) : raise(Picker::Invalid, edited.error.message)
      @recovery = nil
      change.empty? ? self.message = 'No changes' : confirm(change)
    rescue Picker::Invalid => error
      kept = @editor.keep
      @recovery = [snapshot, "# error: #{error.message}\n#{edited&.result.to_s.sub(/\A# error: .*\n/, '')}"]
      self.message = "Not saved: #{error.message}#{" (text kept at #{kept}; #{@edit_label} reopens it)" if kept}"
    end

    def restore
      return unless @view == :excluded && (item = current_item)

      confirm(Picker::Change.new(add: [], remove: @rules.select { |rule| rule.matches?(item) }))
    end

    def document(snapshot)
      Picker::Document.new(picker: @name, family: @family, snapshot: snapshot, rules: @rules, context: @context)
    end

    def confirm(change)
      self.message = nil
      @pending = change
      @before_confirm = anchor
      @preview = preview_rows(change)
      state.mode = :confirm
      state.cursor = 0
      state.top = 0
    end

    def confirm_header
      added = @pending.add.length
      removed = @pending.remove.length
      lines = ["Save #{added} new and remove #{removed} rule#{'s' unless removed == 1}?  y save  n cancel"]
      lines << 'Global rules apply to every picker.' if @pending.add.any? { |rule| rule.scope == 'global' }
      lines
    end

    def preview_rows(change)
      after = @rules.reject { |rule| change.remove.include?(rule) } + change.add
      rows = change.remove.map { |rule| "- rule  #{rule.describe}" } + change.add.map { |rule| "+ rule  #{rule.describe}" }
      @all_items.each do |item|
        now = after.find { |rule| rule.matches?(item) }
        before = @excluded[item.identity]
        rows << "exclude  #{item.label}  <- #{now.describe}" if now && !before
        rows << "restore  #{item.label}" if before && !now
      end
      rows
    end

    def save_pending
      added = @pending.add.length
      removed = @pending.remove.length
      @store.apply!(@pending)
      @rules = @store.applicable(@name, @context)
      leave_confirm("Saved: #{added} added, #{removed} removed")
    end

    def leave_confirm(text)
      state.mode = :list
      @pending = @preview = nil
      exclude!
      @items = view_items
      @marks.select! { |identity| !@excluded.key?(identity) }
      rebuild(@before_confirm)
      self.message = text
    end

    def exclude!
      @excluded = @all_items.each_with_object({}) do |item, found|
        rule = @rules.find { |candidate| candidate.matches?(item) }
        found[item.identity] = rule if rule
      end
    end

    def view_items
      @all_items.select { |item| @excluded.key?(item.identity) == (@view == :excluded) }
    end

    def anchor
      { cursor: cursor, top: top, key: current_item&.identity, list: filtered_items.map(&:identity) }
    end

    # Back on the anchored item when it is still listed; otherwise on the next
    # listed item after it, else the nearest one before it. The row keeps its
    # distance from the top of the window.
    def rebuild(anchor)
      list = filtered_items.map(&:identity)
      index = list.index(anchor[:key])
      unless index
        position = anchor[:list].index(anchor[:key]) || anchor[:cursor]
        later = anchor[:list][(position + 1)..].to_a.find { |identity| list.include?(identity) }
        earlier = anchor[:list][0...position].to_a.reverse.find { |identity| list.include?(identity) }
        index = list.index(later || earlier) || 0
      end
      state.cursor = index.clamp(0, [list.length - 1, 0].max)
      state.top = (state.cursor - (anchor[:cursor] - anchor[:top])).clamp(0, [list.length - body_rows_budget, 0].max)
      scroll_into_view(body_rows_budget)
    end
  end
end
