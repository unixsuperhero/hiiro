require_relative "../test_helper"

class LinkImportTest < Minitest::Test
  JP_URL  = "https://jisho.org/search/{q}"
  FAP_URL = "http://auth.example.com:9969"
  BARE    = "https://bare.example.com"
  NEW_URL = "https://new.example.com"

  def setup
    clear
    @base = Dir.mktmpdir("hiiro-link-import-")
    File.write(File.join(@base, "links.yml"), [
      { "url" => NEW_URL, "description" => "new one", "shorthand" => nil, "created_at" => "2026-03-01T00:00:00-05:00" },
      { "url" => FAP_URL, "description" => "dup", "shorthand" => nil, "created_at" => "2026-03-02T00:00:00-05:00" },
    ].to_yaml)

    db = Hiiro::DB.connection
    db.drop_table?(:links)
    db.create_table(:links) do
      primary_key :id
      String :url, null: false, unique: true
      String :description
      String :shorthand
      String :tags_json
      String :created_at
    end
    jp = db[:links].insert(url: JP_URL, description: "jisho {q}", shorthand: "jp", created_at: "2026-02-02T18:03:14-05:00")
    db[:links].insert(url: FAP_URL, description: "fap", created_at: "2026-02-22T01:06:23-05:00")
    db[:links].insert(url: BARE, created_at: "2026-02-23T00:00:00-05:00")
    db[:tags].insert(name: "nas", taggable_type: "Link", taggable_id: jp.to_s)
  end

  def teardown
    FileUtils.remove_entry(@base)
    Hiiro::DB.connection.drop_table?(:links)
    clear
  end

  def clear
    Hiiro::RegistryEntry.dataset.delete
    Hiiro::Tag.dataset.delete
  end

  def test_imports_links_table_and_links_yml_once
    Hiiro::DB.import_tables!(@base)

    link = Hiiro::Table.named("link")
    assert_equal 4, link.count
    assert_equal ["fap", BARE, "jp", "new one"].sort, link.entries.map(&:name).sort
    assert_equal ["nas"], link.find("jp").tags
    assert_equal "jp", link.find("jp").short_name
    assert_equal "2026-02-02T18:03:14-05:00", link.find("jp").created_at
    assert Hiiro::DB.connection.table_exists?(:links), "legacy links table stays for the installed gem"
    assert File.exist?(File.join(@base, "links.yml.bak"))

    count = Hiiro::RegistryEntry.count
    Hiiro::DB.import_tables!(@base)
    assert_equal count, Hiiro::RegistryEntry.count
  end
end
