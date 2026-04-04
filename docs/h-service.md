# h service

Manage background development services with tmux integration, env file management, and service groups.

Config lives in `~/.config/hiiro/services.yml`. Runtime state is tracked in `~/.config/hiiro/services/running.yml`.

## Synopsis

```bash
h service <subcommand> [args]
```

## Subcommands

### ls / list

List all configured services and service groups, showing running status, host:port, and the associated task/branch if running.

**Examples**

```bash
h service ls
h service list
```

---

### start

Start a service or service group in a new tmux window. Prepares env files before starting (copies base template and injects variation values). With no name, opens a fuzzyfind selector.

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

### stop

Stop a running service or group. Sends `C-c` to the tmux pane, or runs the configured `stop` command. With no name, opens a fuzzyfind selector over running services.

**Examples**

```bash
h service stop my-rails
h service stop my-stack
h service stop                    # fuzzyfind selector
```

---

### reset

Clear a service from the running state without actually stopping the process. Useful when the tmux pane is already dead. With no name, opens a fuzzyfind selector.

**Examples**

```bash
h service reset my-rails
```

---

### clean

Remove all stale services from the running state (services whose tmux pane no longer exists).

**Examples**

```bash
h service clean
```

---

### attach

Switch to a running service's tmux window/pane. With no name, opens a fuzzyfind selector.

**Examples**

```bash
h service attach my-rails
h service attach
```

---

### open

Open a service's URL in the browser (`open http://host:port`).

**Examples**

```bash
h service open my-rails
```

---

### url

Print a service's URL (`http://host:port`).

**Examples**

```bash
h service url my-rails
```

---

### port

Print a service's configured port number.

**Examples**

```bash
h service port my-rails
```

---

### status

Show detailed status for a service: base dir, URL, running state, PID, tmux pane, associated task, and start time. With no name, opens a fuzzyfind selector over running services.

**Examples**

```bash
h service status my-rails
h service status
```

---

### add

Add a new service via a YAML editor template. Opens your editor with a pre-filled template; saves on write.

**Examples**

```bash
h service add
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

### config

Open the services config file (`~/.config/hiiro/services.yml`) in your editor.

**Examples**

```bash
h service config
```

---

### groups

List all configured service groups and their member services.

**Examples**

```bash
h service groups
```

---

### env

Show env file configuration for a service: env files, their base templates, and the available variation values for each env var.

**Examples**

```bash
h service env my-rails
```

---

## Config format

### Individual service

```yaml
my-rails:
  base_dir: apps/myapp             # relative to git root
  host: localhost
  port: 3000
  init:                            # run once before start (e.g. bundle install)
    - bundle install
  start: bundle exec rails s -p 3000
  stop: ""                         # optional stop command; empty = send C-c
  cleanup: []                      # commands to run after stop
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

When starting a group, each member gets its own tmux pane in a shared window, laid out with `even-vertical`.

## Env resolution

1. `base_env` template is copied from `~/.config/hiiro/env_templates/` to `base_dir/env_file`.
2. Each `env_vars` entry is injected into the env file, using the variation value (default: `local`, overridable with `--use`).
3. If a var already exists in the env file, it is replaced. Otherwise it is appended.
