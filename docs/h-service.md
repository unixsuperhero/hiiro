# h service

Manage background development services with Herdr integration, env file management, and service groups.

Config lives in `~/.config/hiiro/services.yml`. Runtime state is tracked in `~/.config/hiiro/services/running.yml`, one record per running instance.

## Instances and runs

A definition is what `services.yml` describes; an instance is that definition running for one resolved base directory, task, and set of `--use` variations. The same definition started from two task worktrees is two instances with separate keys (`web@1a2b3c4d`), run IDs, scripts (`~/.config/hiiro/services/scripts/KEY/`), and Herdr tabs. Starting an instance that is already running is refused; starting one whose previous run ended replaces its record.

Each instance is an owned run (see [owned runs](owned-runs.md)) whose child runs in its own process group: `init` commands, then environment preparation, then `start` (which replaces the launcher, so the run's pid is the service). A failing `init` or preparation step ends the run with that exit status, shown as `failed exit N` by `ls` and `status`. `start` reports success only after the supervisor has started the process; a tab Herdr did not create or a command it did not run is reported as a failed start.

A service is `ready` only when its configured `ready` command exits 0; without one, the instance stays `started` and readiness is not claimed.

Commands that take a name accept an instance key, or a definition name when it has one instance (or exactly one in the current task and directory); otherwise they fail and list the keys.

## Synopsis

```bash
h service <subcommand> [args]
```

Service definitions, environment preparation, and process launch share one context. A configured relative `base_dir` is beneath its root (selected task code/home directory, otherwise invocation Git root/cwd); no `base_dir` uses the effective app/override directory. Stop and cleanup commands use the saved launch directory. Invalid directories and ambiguous service/group names fail before launch artifacts or runtime state change.

`t service TASK [--app APP] ...` and `h app service [--app APP] ...` pass that context into this implementation. The app selector precedes the child command, for example `h app service --app api start web`. Environment destinations use the same definition directory; generated preparation scripts retain the explicit config/root and do not join an app directory twice.

## Subcommands

### add

Add a new service via a YAML editor template. Opens your editor with a pre-filled template; saves on write.

**Examples**

```bash
h service add
```

---

### attach

Focus a running service's Herdr workspace and tab. With no name, opens a fuzzyfind selector.

**Examples**

```bash
h service attach my-rails
h service attach
```

---

### clean

Remove instances whose run has finished. Records from older Hiiro versions without a run are removed when their recorded Herdr pane no longer exists.

**Examples**

```bash
h service clean
```

---

### config

Open the services config file (`~/.config/hiiro/services.yml`) in your editor.

**Examples**

```bash
h service config
```

---

### env

Show env file configuration for a service: env files, their base templates, and the available variation values for each env var.

**Examples**

```bash
h service env my-rails
```

---

### groups

List all configured service groups and their member services.

**Examples**

```bash
h service groups
```

---

### ls / list

List all configured services and service groups, showing host:port and, under each definition, its instances with key, run state (`started pid 4242`, `ready`, `failed exit 3`), directory, and task/branch.

**Examples**

```bash
h service ls
h service list
```

---

### open

Open a service's URL in the browser (`open http://host:port`).

**Examples**

```bash
h service open my-rails
```

---

### port

Print a service's configured port number.

**Examples**

```bash
h service port my-rails
```

---

### reset

Clear an instance from the running state without stopping its process. Useful after stopping a process that Hiiro does not own (records from older versions). With no name, opens a fuzzyfind selector.

**Examples**

```bash
h service reset my-rails
```

---

### rm / remove

Remove a service from the config.

**Examples**

```bash
h service rm my-rails
h service remove my-rails
```

---

### start

Start a service or service group in new unfocused Herdr tabs, or as a detached process outside Herdr. Env files are prepared after `init` and before `start`, by copying the base template and injecting variation values. With no name, it opens a fuzzyfind selector.

**Options**

| Flag | Description |
|------|-------------|
| `--use VAR=variation` | Override an env var's variation (repeatable) |

**Examples**

```bash
h service start my-rails
h service start my-stack          # start a group
h service start my-rails --use GRAPHQL_URL=staging
h service start                   # fuzzyfind selector
```

---

### status

Show detailed status for a service: base dir, URL, readiness command, and for each instance its key, run state, directory, Herdr pane, task, variations, and start time. With no name, opens a fuzzyfind selector over running services.

**Examples**

```bash
h service status my-rails
h service status
```

---

### stop

Stop a running instance or group. Hiiro signals only the process its supervisor started, and only while that pid still has the recorded start time: it runs the configured `stop` command (with `$PID` replaced by the service pid), or sends SIGTERM to the service's process group. It then waits up to `stop_timeout` seconds (default 10) for the exit to be observed. Only then are `cleanup` commands run and the instance removed. A process that does not exit, or a failing `stop` command, leaves the instance recorded. A recorded pid that now belongs to another process is not signalled. Records from older versions without a run are refused; stop the process yourself and `reset` it. With no name, opens a fuzzyfind selector over running instances.

**Examples**

```bash
h service stop my-rails
h service stop my-stack
h service stop                    # fuzzyfind selector
```

---

### url

Print a service's URL (`http://host:port`).

**Examples**

```bash
h service url my-rails
```

---

## Config format

### Individual service

```yaml
my-rails:
  base_dir: apps/myapp             # relative to the selected context root
  host: localhost
  port: 3000
  init:                            # run once before start (e.g. bundle install)
    - bundle install
  start: bundle exec rails s -p 3000
  stop: ""                         # optional stop command ($PID = service pid); empty = SIGTERM to its process group
  stop_timeout: 10                 # seconds to wait for the observed exit
  ready: curl -sf localhost:3000   # optional; exit 0 marks the instance ready
  cleanup: []                      # commands to run after the observed exit
  env_file: .env.development       # destination in base_dir
  base_env: my-rails.env           # template in ~/.config/hiiro/env_templates/
  env_vars:
    GRAPHQL_URL:
      variations:
        local: http://localhost:4000/graphql
        staging: https://graphql.staging.example.com/graphql
```

### Multiple env files

Use `env_files` (array) instead of the single-env keys:

```yaml
my-rails:
  base_dir: apps/myapp
  start: bundle exec rails s
  env_files:
    - env_file: .env.development
      base_env: my-rails.env
      env_vars:
        GRAPHQL_URL:
          variations:
            local: http://localhost:4000/graphql
    - env_file: .env.test
      base_env: my-rails-test.env
```

### Service group

Distinguish groups by the `services:` key:

```yaml
my-stack:
  services:
    - name: my-rails
      use:
        GRAPHQL_URL: staging      # override variation for this member
    - name: my-graphql
```

When starting a group, each member gets its own unfocused Herdr tab in the same workspace.

## Env resolution

1. `base_env` template is copied from `~/.config/hiiro/env_templates/` to `base_dir/env_file`.
2. Each `env_vars` entry is injected into the env file, using the variation value (default: `local`, overridable with `--use`).
3. If a var already exists in the env file, it is replaced. Otherwise it is appended.
