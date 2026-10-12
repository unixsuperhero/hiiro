require 'test_helper'

class PinRecordTest < Minitest::Test
  def setup
    Hiiro::PinRecord.where(command: 'record-test').delete
  end

  def teardown
    Hiiro::PinRecord.where(command: 'record-test').delete
  end

  def test_values_round_trip_without_guessing_types
    values = ['42', 42, 'false', false, '[1]', [1], '{"a":1}', { 'a' => 1 }, '', nil]
    values.each_with_index { |value, i| Hiiro::PinRecord.set('record-test', i.to_s, value) }
    assert_equal values, (0...values.size).map { |i| Hiiro::PinRecord.find_key('record-test', i.to_s).value }
    assert_equal 'null', Hiiro::PinRecord.find_key('record-test', '9').value_json
    assert_equal ['json'], Hiiro::PinRecord.where(command: 'record-test').select_map(:value_format).uniq
  end

  def test_set_retains_id_and_remove_uses_exact_command_key
    first = Hiiro::PinRecord.set('record-test', 'apple', 'old')
    Hiiro::PinRecord.set('record-test', 'apricot', 'keep')
    Hiiro::PinRecord.set('record-test', 'apple', 'new')
    assert_equal first.id, Hiiro::PinRecord.find_key('record-test', 'apple').id
    assert_nil Hiiro::PinRecord.remove('record-test', 'ap')
    assert_equal({ 'apple' => 'new', 'apricot' => 'keep' }, command_values)
    Hiiro::PinRecord.remove('record-test', 'apple')
    assert_equal({ 'apricot' => 'keep' }, command_values)
  end

  def test_legacy_rows_keep_previous_semantics_and_expose_type_ambiguity
    ['plain', '42', 'false', '"quoted"', '[1]'].each_with_index do |raw, i|
      Hiiro::PinRecord.create(command: 'record-test', key: i.to_s, value_json: raw, value_format: 'legacy')
    end
    rows = Hiiro::PinRecord.for_command('record-test')
    assert_equal ['plain', 42, false, 'quoted', [1]], rows.map(&:value)
    assert_equal [false, true, true, true, true], rows.map(&:legacy_ambiguous?)
    id = rows[1].id
    Hiiro::PinRecord.set('record-test', '1', '42')
    resolved = Hiiro::PinRecord.find_key('record-test', '1')
    assert_equal [id, '42', 'json', false], [resolved.id, resolved.value, resolved.value_format, resolved.legacy_ambiguous?]
  end

  def test_invalid_canonical_json_is_not_silently_read_as_text
    Hiiro::PinRecord.set('record-test', 'good', 'plain')
    row = Hiiro::PinRecord.create(command: 'record-test', key: 'bad', value_json: 'plain', value_format: 'json')
    assert_raises(JSON::ParserError) { row.value }
    assert_equal 'plain', Hiiro::PinRecord.find_key('record-test', 'good').value
  end

  def test_schema_upgrade_marks_only_existing_rows_legacy_and_preserves_bytes
    db = Sequel.sqlite
    db.create_table(:pins) do
      primary_key :id
      String :command
      String :key
      String :value_json
    end
    db[:pins].insert(id: 17, command: 'old', key: 'text', value_json: '42')
    Hiiro::PinRecord.create_table!(db)
    Hiiro::PinRecord.migrate!(db)
    db[:pins].insert(command: 'new', key: 'text', value_json: '"42"')
    Hiiro::PinRecord.migrate!(db)
    assert_equal({ id: 17, command: 'old', key: 'text', value_json: '42', value_format: 'legacy' }, db[:pins].where(id: 17).first)
    assert_equal 'json', db[:pins].where(command: 'new').get(:value_format)
  ensure
    db&.disconnect
  end

  private

  def command_values
    Hiiro::PinRecord.for_command('record-test').to_h { |row| [row.key, row.value] }
  end
end
