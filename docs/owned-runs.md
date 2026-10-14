# Owned runs

`Hiiro::OwnedRun` (lib/hiiro/owned_run.rb) is the launch contract shared by `h queue`, `h service`, and `h bg`. It separates four facts that used to be conflated: a terminal was allocated, the command started, it became ready, and it ended with a particular status.

## Shapes

```js
// What a consumer asks for (OwnedRun::LaunchRequest)
const request = {
  id: "run-20261013120000-1a2b3c4d",
  owner: { kind: "service", definition: "web", instance: "web@1a2b3c4d", directory: "/work/a/web", task: "a" },
  command: { kind: "argv", argv: ["/bin/bash", ".../scripts/web@1a2b3c4d/launch.sh"], cwd: "/work/a/web", env: {} },
  placement: { kind: "herdr-tab" },          // current | herdr-tab | herdr-split | herdr-pane | detached
  process_group: true,                       // the child gets its own group so a stop reaches its tree
  ready: { kind: "shell", shell: "curl -sf localhost:3000", cwd: "/work/a/web" } // optional
};

// What is recorded (~/.local/share/hiiro/runs/RUN_ID.json)
const run = {
  id: "run-20261013120000-1a2b3c4d",
  owner: { /* as above */ },
  state: "started",                          // allocated | started | ready | completed | failed
  terminal: { herdr_workspace: "w1", herdr_tab: "w1:t3", herdr_pane: "w1:p3" },
  process: { pid: 4242, started: "Tue Oct 13 12:00:01 2026" },   // pid + kernel start time
  outcome: null,                             // { exit_code: 7, signal: null } or { exit_code: null, signal: "TERM" }
  error: null,                               // why it failed before or without starting
  times: { allocated: "...", started: "..." }
};
```

`CommandSpecification` keeps argv and authored shell text apart: `CommandSpecification.new('omp', '@file')` is argv; `CommandSpecification.shell('curl -sf ...')` keeps the text and runs it with `/bin/bash -c`.

## States

```text
allocated -> started -> ready -> completed | failed
allocated -> failed                (never started)
started   -> completed | failed    (readiness not configured or not reached)
```

All transitions go through `OwnedRun#transition`; any other move raises `OwnedRun::InvalidTransition`. `completed` means exit 0. A nonzero exit or a signal is `failed` with that outcome; a signal is never exit zero. Records are rewritten atomically under a per-run lock, so the launcher and the supervisor cannot both win a transition.

## Who records what

- The launcher (`OwnedRun::Launcher`) allocates a place (current terminal, new Herdr tab or split, a reserved pane, or a detached process), writes the `allocated` record, hands it to the supervisor, and waits up to 10 seconds for `started`. A tab Herdr did not create, a command Herdr did not run, an `exec` that failed, or a start not observed in time becomes `failed` with an error, and the launch raises `OwnedRun::LaunchError`.
- The supervisor (`OwnedRun::Supervisor`, `ruby -I LIB -r hiiro/owned_run`) runs in the allocated place. It spawns the child, records `started` with the child's pid and start time, polls the `ready` command when one is configured, waits for the child, and records the outcome. A child that cannot be spawned (missing executable or directory) is `failed` without running. If the launcher already gave up on the run, the supervisor does not start the child.
- A detached launch given a log (`Launcher#detached(request, log: PATH)`, used by `h queue tick`) sends the supervisor's and the child's stdout and stderr to that file.
- Interactive children (queue agents) share the terminal's foreground process group and receive Ctrl-C themselves. Isolated children (services) get their own process group; the supervisor forwards INT, TERM, HUP, and QUIT to it.

## Owners

| Owner | Settled after the run finishes by | Completion means |
|-------|-----------------------------------|------------------|
| `queue` | `Hiiro::QueueClaim` moves `running/NAME.{md,meta,log}` to `done/` (exit 0) or `failed/` and removes the body | queue entry done; the task is untouched |
| `background` | `Hiiro::PaneReservations` releases the reserved `h-bg` pane | nothing else |
| `service` | nothing; `h service` reads the run for `ls` / `status` / `clean` | process ended |
| `job` | the scheduling worker (`Hiiro::Job.execute`) writes the `job_outcomes` row and settles the occurrence claim; a later worker does it from this record if that worker died | the occurrence ran; see [h schedule](h-schedule.md) |

Stopping uses the recorded identity: a pid is signalled only while `ps` still reports the recorded start time, so a reused pid is never mistaken for the run. Callers wait for the exit to be observed before cleaning up.

## Storage

Run records are runtime files under `~/.local/share/hiiro/runs/` (`RUN_ID.json` plus a `RUN_ID.lock`, and for a detached launch without its own log, such as `h bg run` or a detached service, `RUN_ID.log` holding the child's stdout and stderr; a detached launch never keeps the caller's stdout or stderr open). They are not domain records and are not part of `h db` export. Remove old ones by hand when they are no longer useful.
