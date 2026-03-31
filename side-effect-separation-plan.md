
❯ our test suite hasn't been kept up-to-date.  part of the reason is that
claude has constantly mixed presentation logic with application/domain
logic.  another part is that the majority of what hiiro is doing is
heavily side-effect focused

∴ Thinking…

  The user is raising a real architectural concern: the test suite is hard
  to maintain because:

  1. Presentation logic mixed with domain logic — makes it hard to test the
   domain logic without also dealing with terminal output, formatting, etc.
  2. Side-effect heavy — most of hiiro's operations involve tmux, git, file
   system, process exec, etc. Hard to unit test without extensive mocking.

  This is a really interesting architectural problem. Let me think about
  what the right approach is.

  The core problem:
  - Commands like h branch saved do: git operations, tmux operations, file
  writes, terminal output — all interleaved
  - Sequel models help somewhat (DB operations are more testable), but the
  bin files still mix everything

  - The Hiiro::TestHarness stubs system calls but that's limited

  The real solution is separating concerns: pure domain objects that return
   values without I/O, a store layer using Sequel for testable database
  access, presenters that format domain objects into strings, and isolated
  side-effect executors for tmux, git, and process calls that can be
  stubbed at the boundary.

  The current codebase mixes everything together—bin files orchestrate and
  execute, models like TodoItem blend formatting with domain logic, and
  PinnedPRManager handles display, API calls, file writes, and business
  logic in one place.

  The SQLite migration actually improves testability significantly because
  the store layer is now real and testable with an in-memory database,
  making queries like TodoItem.where(status: 'active') verifiable without
  file fixtures.

  I should recommend extracting presenters for display logic, creating
  service or command objects for domain operations separate from bin file
  orchestration, and keeping side effects isolated and minimal so they're
  easy to stub in tests.

  The user seems to be flagging this as context rather than asking for a
  full refactor right now—they're pointing out that the test suite isn't
  reliable and that mixing presentation with domain logic has been a
  recurring problem. I should acknowledge this is a real issue, show how
  the Sequel models actually help, and suggest a practical path forward
  that doesn't require rewriting everything at once.

  The key realization is that migrating to SQLite with Sequel models is
  actually an opportunity to enforce better separation of concerns—the
  models can be tested in isolation with an in-memory database, which gives
   us a much cleaner testing story than what we have now. I'm sketching out
   what a proper test for a Sequel model would look like...

  Setting up test fixtures with an in-memory database...

  This approach is cleaner than the current YAML fixture setup, and it also
   suggests a testing strategy where the bin files get lighter
  integration-style tests while the actual domain logic gets proper unit
  coverage.

⏺ This is a real architectural problem, and it's worth being direct about
  it.

  The root issue: hiiro's bin files are doing 4 different jobs at once —

  bin/h-branch:
    1. Parse args               ← orchestration
    2. Query git / tmux state   ← side effects
    3. Transform / decide       ← domain logic
    4. Print output             ← presentation
    5. Write to files/DB        ← persistence

  When all 5 are interleaved in one block, there's nothing to test that
  doesn't also require a terminal, a tmux session, or a real git repo.

  The SQLite migration actually helps here — the models are now the
  cleanest layer in the codebase and are trivially testable:

  # test setup — in-memory DB, no files, no fixtures
  def setup
    @db = Sequel.sqlite
    Hiiro::DB.instance_variable_set(:@connection, @db)
    Hiiro::TodoItem.create_table!(@db)
  end

  def test_active_todos
    Hiiro::TodoItem.create(text: "Fix bug",    status: "not_started")
    Hiiro::TodoItem.create(text: "Ship thing", status: "done")
    assert_equal 1, Hiiro::TodoItem.where(status: "not_started").count
  end

  No YAML, no filesystem, runs in microseconds.

  The presentation mixing is the harder problem. Something like
  PinnedPRManager#display_pinned is 60 lines of ANSI/formatting logic —
  completely untestable and it lives right next to the query logic.

  A few options for how to handle this going forward:

  Option A — Incrementally extract presenters as we touch files
  When a file gets a Sequel model anyway, also extract its display methods
  into a Presenter class. No big-bang refactor, just enforce the rule going
   forward.

  Option B — Write tests only for the model/domain layer, skip bin files
  Accept that bin files are thin orchestrators and only test what's
  actually testable — the Sequel models, matchers, option parsing. Stop
  trying to test the side-effect-heavy bin files.

  Option C — Define a Hiiro::Effects interface
  Create an injectable adapter for side effects (tmux calls, git calls,
  exec). Bin files get effects: injected; tests pass a double. Most
  invasive but gives full coverage.

  Given that the test suite is already out of date and hiiro is a personal
  CLI tool, I'd suggest Option B as baseline + Option A opportunistically.
  Write solid tests for the model layer (which is now genuinely clean), and
   extract presenters when you're already editing a file for another
  reason.

  Do you want to:
  1. Tackle the test architecture as part of this branch before committing?
  2. Just get the SQLite work committed and come back to tests separately?
  3. Something else — like establishing a testing convention and letting
  the models be the starting point?


@hdb-command❯ h-db agent work complete

∴ Thinking…

  The h-db command is done. Now I need to wait for the final-wiring agent
  to finish, then do commits.

  Let me also respond to the user's question about tests. They asked about
  options. Let me address this.

  The user's message was about the test suite being out of date because of
  mixed concerns. I asked what they want to do. I'm waiting for their
  response on that.

  Actually, looking back - the user said "our test suite hasn't been kept
  up-to-date" as a statement, not as a question asking for a response. They
   may have been saying this as context for why the final-wiring agent's
  test run might show failures. Let me just acknowledge the h-db completion
   and wait for final-wiring.

⏺ ✅ bin/h-db done — status, tables, q/query, migrate (with tar backup),
  restore. Also added q/query to bin/h-branch and bin/h-pr.

  Still waiting on final-wiring to finish auditing the requires, running
  syntax checks, and consolidating the CHANGELOG. Once it reports back I'll
   kick off the commit agent.

  On the test question — no pressure to decide now. The model layer is
  ready to be tested cleanly whenever you want to start. The commits come
  first.


∴ Thinking…

  Just an idle notification. Still waiting for final-wiring agent to
  complete.

⏺ Still waiting on final-wiring.

❯ i like the Option B + Option A suggestion.  could you also write an
implementation plan and save it in plans/ for Option C

