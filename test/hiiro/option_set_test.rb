require "test_helper"

class OptionSetTest < Minitest::Test
  def options
    Hiiro::Options.setup do
      flag(:all, short: 'a', desc: 'everything')
      flag(:red, short: 'r', desc: 'failing')
      option(:out, short: 'o', desc: 'output')
      option(:tag, multi: true, desc: 'tags')
      mutual_exclusion(:all, :red)
    end
  end

  def test_help_and_hint_shared_between_options_and_args
    opts = options
    assert_equal opts.help_text, opts.parse([]).help_text
    assert_equal opts.option_set.help_text, opts.help_text
    assert_match(/-h, --help/, opts.help_text)
    assert_equal '[--all] [--red] [--out <val>] [--tag <val>]', opts.hint
  end

  def test_definition_for_tokens
    set = options.option_set
    assert_equal :out, set.definition_for('--out').name
    assert_equal :out, set.definition_for('-o').name
    assert_equal :out, set.definition_for(:out).name
    assert_nil set.definition_for('--nope')
    assert_nil set.definition_for('-z')
  end

  def test_defaults_and_conflicts
    set = options.option_set
    assert_equal({ help: false, all: false, red: false, out: nil, tag: [] }, set.defaults)
    assert_equal [:red], set.conflicts_for(:all)
    assert_equal [:all], set.conflicts_for(:red)
    assert_equal [], set.conflicts_for(:out)
  end

  def test_subset
    sub = options.option_set.subset(%i[red out])
    assert_equal %i[red out], sub.definitions.keys
    assert_equal [:all], sub.conflicts_for(:red)
  end

  def test_parsing_still_applies_mutual_exclusion
    parsed = options.parse(%w[--all --red -o x --tag a --tag b rest])
    refute parsed.all
    assert parsed.red
    assert_equal 'x', parsed.out
    assert_equal %w[a b], parsed.tag
    assert_equal ['rest'], parsed.args
  end
end
