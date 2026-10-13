require "json"

# A `(*argv) -> stdout` runner for TuiosListing and TuiosScreen tests: records
# every argv and answers by the longest matching argv prefix with a String, or
# raises when the answer is a Hiiro::Error.
class TuiosFakeRunner
  attr_reader :calls, :answers

  def initialize(answers = {})
    @calls = []
    @answers = answers
  end

  def call(*argv)
    @calls << argv
    prefix, answer = @answers.select { |key, _| argv.first(key.length) == key }.max_by { |key, _| key.length }
    raise Hiiro::Error, "tuios #{argv.join(' ')} failed: no answer" unless prefix
    raise answer if answer.is_a?(Hiiro::Error)

    answer
  end

  def calls_for(verb) = calls.select { |argv| argv.first == verb }
end

# Trimmed from live `tuios ls --json`, `list-windows`, `list-attention`, and
# `ls --all-hosts --json` output on 2026-10-12.
module TuiosFixtures
  HIIRO = "/Users/me/proj/hiiro".freeze
  FLEET = "/Users/me/proj/fleet".freeze

  def ls_sessions
    [
      { "name" => "zeta", "id" => "s-zeta", "attached" => true, "window_count" => 1, "dir" => "/", "global" => true,
        "windows" => [
          { "id" => "id-z1", "title" => "π ⠹ STAR: Configure Unique Starship Styles Across Fleet", "agent_state" => "working",
            "agent_harness" => "omp", "agent_message" => "Configuring distinct Starship prompts", "foreground_cmd" => "bun", "workspace" => 1 },
        ] },
      { "name" => "alpha", "id" => "s-alpha", "attached" => false, "window_count" => 3, "dir" => "fleet", "branch" => "main",
        "windows" => [
          { "id" => "id-a1", "title" => "π > Implement JSON Task Status Management", "agent_state" => "done", "agent_harness" => "omp",
            "foreground_cmd" => "bun", "workspace" => 2 },
          { "id" => "id-a2", "title" => "inbox remote host capture", "agent_state" => "working", "agent_harness" => "omp", "workspace" => 1 },
          { "id" => "id-a3", "title" => "◑ Md file open with mdoc cli tool", "agent_state" => "needs_input", "agent_harness" => "claude-code",
            "agent_message" => "Open the file?", "foreground_cmd" => "claude", "workspace" => 2 },
        ] },
      { "name" => "beta", "id" => "s-beta", "attached" => false, "window_count" => 0 },
    ]
  end

  def alpha_windows(cwd: HIIRO)
    { "windows" => [
      { "window_id" => "id-a1", "cwd" => cwd, "focused" => false, "index" => 1, "minimized" => false, "running_cmdline" => "bun", "workspace" => 2 },
      { "window_id" => "id-a2", "cwd" => cwd, "focused" => true, "index" => 0, "minimized" => true, "workspace" => 1 },
    ] }
  end

  def zeta_windows
    { "windows" => [
      { "window_id" => "id-z1", "cwd" => FLEET, "focused" => true, "index" => 0, "minimized" => false, "running_cmdline" => "cld", "workspace" => 1 },
    ] }
  end

  def attention
    { "counts" => { "approval" => 0, "ask" => 1, "errored" => 0, "finished" => 2, "mail" => 0 }, "items" => [] }
  end

  def all_hosts
    { "hosts" => [
      { "host" => "local", "status" => "up", "sessions" => [{ "name" => "zeta", "window_count" => 1 }, { "name" => "alpha", "window_count" => 3 }] },
      { "host" => "hscale", "status" => "up" },
      { "host" => "m3pro", "status" => "up", "sessions" => [
        { "name" => "m3pro", "window_count" => 3, "agent_state" => "done", "attached" => true },
        { "name" => "fleet", "window_count" => 1, "attached" => true },
      ] },
      { "host" => "vps", "status" => "up", "sessions" => nil },
    ] }
  end

  def answers(cwd: HIIRO)
    {
      %w[ls --json] => JSON.generate(ls_sessions),
      %w[ls --all-hosts --json] => JSON.generate(all_hosts),
      %w[list-windows -s alpha --json] => JSON.generate(alpha_windows(cwd:)),
      %w[list-windows -s zeta --json] => JSON.generate(zeta_windows),
      %w[list-attention --json] => JSON.generate(attention),
    }
  end
end
