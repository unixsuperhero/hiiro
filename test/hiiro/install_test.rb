require_relative "../test_helper"
require "digest"
require "json"

class InstallTest < Minitest::Test
  def setup
    @root = File.realpath(Dir.mktmpdir("hiiro-install-"))
    @pkg = File.join(@root, "pkg")
    @bin = File.join(@root, "home/bin")
    @plugins = File.join(@root, "home/plugins")
    @manifest = File.join(@root, "home/manifest.json")
    write("bin/h-alpha", "alpha 1\n")
    write("bin/h-beta", "beta 1\n")
    write("bin/h-gamma", "gamma 1\n")
    write("exe/x", "x 1\n")
    File.symlink("../exe/x", File.join(@pkg, "bin/h-linked"))
    write("bin/lib/support.rb", "SUPPORT = 1\n")
    write("bin/lib/tool", "tool 1\n", mode: 0o755)
    write("plugins/pins.rb", "module Pins; end\n")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_planning_creates_and_writes_nothing
    before = snapshot
    plan = plan_for

    assert_equal before, snapshot
    refute File.exist?(File.join(@root, "home"))
    assert_equal [
      %w[missing support bin/lib/support.rb bin/lib/support.rb], %w[missing support bin/lib/tool bin/lib/tool],
      %w[missing command bin/h-alpha bin/zz-alpha], %w[missing command bin/h-beta bin/zz-beta],
      %w[missing command bin/h-gamma bin/zz-gamma], %w[missing command bin/h-linked bin/zz-linked],
      %w[missing plugin plugins/pins.rb plugins/pins.rb]
    ], rows(plan)
  end

  def test_apply_installs_bytes_modes_and_ownership
    outcomes = apply(plan_for, apply: true)

    assert_equal ["installed"], outcomes.map(&:action).uniq
    assert_equal "alpha 1\n", File.read(dest("bin/zz-alpha"))
    assert_equal "x 1\n", File.read(dest("bin/zz-linked"))
    refute File.symlink?(dest("bin/zz-linked"))
    assert_equal "SUPPORT = 1\n", File.read(dest("bin/lib/support.rb"))
    assert_equal({ "bin/zz-alpha" => 0o755, "bin/zz-linked" => 0o755, "bin/lib/support.rb" => 0o644,
                   "bin/lib/tool" => 0o755, "plugins/pins.rb" => 0o644 },
                 %w[bin/zz-alpha bin/zz-linked bin/lib/support.rb bin/lib/tool plugins/pins.rb].to_h { |p| [p, File.stat(dest(p)).mode & 0o7777] })
    assert_equal({ "asset" => "command", "source" => "bin/h-linked", "package" => "hiiro", "version" => "1.0.0",
                   "root" => @pkg, "sha256" => Digest::SHA256.hexdigest("x 1\n"), "mode" => "0755",
                   "owner" => "installed", "link" => "../exe/x" }, manifest_json[dest("bin/zz-linked")])
    assert_equal 7, manifest_json.size
    assert_equal ["unchanged"], plan_for.entries.map(&:kind).uniq
  end

  def test_update_replaces_only_owned_unmodified_files_and_converges
    apply(plan_for, apply: true)
    write("bin/h-alpha", "alpha 2\n")                     # owned, untouched: updatable
    write("bin/h-beta", "beta 2\n")
    File.write(dest("bin/zz-beta"), "beta mine\n")        # owned, edited: user-modified
    write("bin/h-delta", "delta 1\n")
    File.write(dest("bin/zz-delta"), "delta 1\n")         # never written by hiiro: collision, same bytes
    File.delete(File.join(@pkg, "bin/h-gamma"))           # owned, unchanged, no longer shipped
    File.delete(File.join(@pkg, "bin/lib/tool"))
    File.write(dest("bin/lib/tool"), "tool mine\n")       # owned, edited, no longer shipped
    before = snapshot

    plan = plan_for("1.1.0")
    assert_equal before, snapshot
    assert_equal [
      %w[updatable command bin/h-alpha bin/zz-alpha], %w[user-modified command bin/h-beta bin/zz-beta],
      %w[collision command bin/h-delta bin/zz-delta], %w[obsolete support bin/lib/tool bin/lib/tool],
      %w[obsolete command bin/h-gamma bin/zz-gamma]
    ], rows(plan).reject { |row| row.first == "unchanged" }
    assert_equal [false, true], plan.of("obsolete").map(&:removable?)

    assert_equal [%w[updated bin/zz-alpha]], apply(plan, apply: true).map { |o| [o.action, rel(o.entry.destination)] }
    assert_equal "alpha 2\n", File.read(dest("bin/zz-alpha"))
    assert_equal "1.1.0", manifest_json[dest("bin/zz-alpha")]["version"]
    assert_equal ["beta mine\n", "delta 1\n", "gamma 1\n", "tool mine\n"],
                 %w[bin/zz-beta bin/zz-delta bin/zz-gamma bin/lib/tool].map { |p| File.read(dest(p)) }
    refute manifest_json.key?(dest("bin/zz-delta"))

    again = plan_for("1.1.0")
    assert_empty again.of("missing", "updatable")
    assert_equal [], apply(again, apply: true)

    assert_equal [%w[removed bin/zz-gamma]], apply(again, retire: true).map { |o| [o.action, rel(o.entry.destination)] }
    refute File.exist?(dest("bin/zz-gamma"))
    assert_equal "tool mine\n", File.read(dest("bin/lib/tool"))
    refute manifest_json.key?(dest("bin/zz-gamma"))
    assert manifest_json.key?(dest("bin/lib/tool"))
  end

  def test_edits_made_after_planning_survive_apply
    apply(plan_for, apply: true)
    write("bin/h-alpha", "alpha 2\n")
    plan = plan_for("1.1.0")
    File.write(dest("bin/zz-alpha"), "alpha edited after the plan\n")

    outcomes = apply(plan, apply: true)

    assert_equal [%w[changed bin/zz-alpha]], outcomes.map { |o| [o.action, rel(o.entry.destination)] }
    refute outcomes.first.ok?
    assert_equal "alpha edited after the plan\n", File.read(dest("bin/zz-alpha"))
    assert_equal ["1.0.0", Digest::SHA256.hexdigest("alpha 1\n")], manifest_json[dest("bin/zz-alpha")].values_at("version", "sha256")
  end

  def test_failed_writes_are_reported_and_never_owned
    FileUtils.mkdir_p(File.dirname(@plugins))
    File.write(@plugins, "a file where the plugin directory should be\n")

    outcomes = apply(plan_for, apply: true)

    failed = outcomes.reject(&:ok?)
    assert_equal [["failed", "plugins/pins.rb"]], failed.map { |o| [o.action, rel(o.entry.destination)] }
    assert_match(/File exists|Not a directory/, failed.first.error)
    refute manifest_json.key?(dest("plugins/pins.rb"))
    assert manifest_json.key?(dest("bin/zz-alpha"))
  end

  def test_unreadable_manifest_location_leaves_nothing_owned
    FileUtils.mkdir_p(File.join(@root, "home"))
    File.write(File.join(@root, "home/blocked"), "")
    @manifest = File.join(@root, "home/blocked/manifest.json")   # its directory is a file

    outcomes = apply(plan_for, apply: true)

    assert_equal ["failed"], outcomes.map(&:action).uniq
    assert_match(/\Amanifest not saved: /, outcomes.first.error)
  end

  def test_adoption_records_ownership_without_writing_then_allows_updates
    FileUtils.mkdir_p(@bin)
    File.write(dest("bin/zz-alpha"), "alpha mine\n")
    assert_equal "collision", plan_for.of("collision").first.kind
    assert_empty plan_for.select(apply: true, names: ["zz-alpha"])

    assert_equal ["adopted"], apply(plan_for, adopt: true, names: ["zz-alpha"]).map(&:action)
    assert_equal "alpha mine\n", File.read(dest("bin/zz-alpha"))
    assert_equal ["adopted", Digest::SHA256.hexdigest("alpha mine\n")], manifest_json[dest("bin/zz-alpha")].values_at("owner", "sha256")

    assert_equal "updatable", plan_for.entries.find { |e| rel(e.destination) == "bin/zz-alpha" }.kind
    apply(plan_for, apply: true, names: ["bin/h-alpha"])
    assert_equal "alpha 1\n", File.read(dest("bin/zz-alpha"))
  end

  def test_a_linked_destination_is_never_written_through
    target = File.join(@root, "checkout-h-alpha")
    File.write(target, "my checkout\n")
    FileUtils.mkdir_p(@bin)
    File.symlink(target, dest("bin/zz-alpha"))

    plan = plan_for
    entry = plan.entries.find { |e| rel(e.destination) == "bin/zz-alpha" }
    assert_equal ["collision", "link"], [entry.kind, entry.current.type]
    apply(plan, apply: true)
    outcome = apply(plan_for, adopt: true, names: ["zz-alpha"]).first

    assert_equal ["failed", "only a regular file can be adopted (found link)"], [outcome.action, outcome.error]
    assert_equal "my checkout\n", File.read(target)
    assert_equal target, File.readlink(dest("bin/zz-alpha"))
  end

  def test_origin_names_the_package_or_the_user
    apply(plan_for, apply: true)
    manifest = Hiiro::Install::Manifest.load(@manifest)
    package = package_for("1.0.0")
    File.write(dest("bin/zz-beta"), "beta mine\n")
    user = File.join(@root, "elsewhere/zz-own")
    origin = ->(path) { Hiiro::Install.origin(path, manifest:, package:) }

    assert_equal "managed hiiro 1.0.0", origin.(dest("bin/zz-alpha"))
    assert_equal "modified (managed hiiro 1.0.0)", origin.(dest("bin/zz-beta"))
    assert_equal "package hiiro 1.0.0", origin.(File.join(@pkg, "bin/h-alpha"))
    assert_equal "package hiiro 1.0.0", origin.("#{File.join(@pkg, 'lib/x.rb')}:12")
    assert_equal "user", origin.(user)
  end

  private

  def write(rel, content, mode: 0o755)
    path = File.join(@pkg, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    File.chmod(rel.start_with?("bin/lib/support") || rel.start_with?("plugins") ? 0o644 : mode, path)
  end

  def package_for(version) = Hiiro::Install::Package.new(name: "hiiro", version:, root: @pkg)

  def plan_for(version = "1.0.0")
    Hiiro::Install::Plan.new(package: package_for(version), prefix: "zz", bin_dir: @bin, plugin_dir: @plugins,
                             manifest: Hiiro::Install::Manifest.load(@manifest))
  end

  def apply(plan, **selection) = plan.apply(plan.select(**selection))

  def dest(rel) = rel.start_with?("plugins/") ? File.join(@plugins, rel.delete_prefix("plugins/")) : File.join(@bin, rel.delete_prefix("bin/"))
  def rel(path) = path.start_with?(@plugins) ? path.sub(@plugins, "plugins") : path.sub(@bin, "bin")
  def rows(plan) = plan.entries.map { |e| [e.kind, e.asset, e.source, rel(e.destination)] }
  def manifest_json = JSON.parse(File.read(@manifest))["assets"]

  def snapshot
    Dir.glob("**/*", File::FNM_DOTMATCH, base: @root).reject { |p| p.end_with?(".") }.sort.to_h do |path|
      full = File.join(@root, path)
      [path, File.symlink?(full) || File.directory?(full) ? :entry : [Digest::SHA256.file(full).hexdigest, File.stat(full).mode]]
    end
  end
end
