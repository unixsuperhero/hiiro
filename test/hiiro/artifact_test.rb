require "test_helper"

class ArtifactTest < Minitest::Test
  def payload = Hiiro::Clipboard::Payload.new(source: :text_arg, content_type: 'text/plain', bytes: 'note')

  def test_inbox_names_run_out_instead_of_retrying_forever
    Dir.mktmpdir do |dir|
      names = ['b.txt', *(2..1000).map { |n| "b-#{n}.txt" }]
      names.each { |name| File.write(File.join(dir, name), 'taken') }

      outcome = Hiiro::Artifact.write(payload, Hiiro::Artifact.numbered(dir, 'b', 'txt'))

      assert_equal [:write_failed, "#{dir}/b-1000.txt already exists"], [outcome.status, outcome.detail]
      assert_equal names.sort, Dir.children(dir).sort
      assert_equal ['taken'], names.map { |name| File.read(File.join(dir, name)) }.uniq
    end
  end

  def test_an_inbox_that_is_a_file_fails_on_the_first_name
    Dir.mktmpdir do |dir|
      inbox = File.join(dir, 'inbox')
      File.write(inbox, 'not a directory')

      outcome = Hiiro::Artifact.write(payload, Hiiro::Artifact.numbered(inbox, 'b', 'txt'))

      assert_equal :write_failed, outcome.status
      assert_equal "Could not write #{inbox}/b.txt: File exists @ dir_s_mkdir - #{inbox}", outcome.detail
      assert_equal 'not a directory', File.read(inbox)
    end
  end
end
