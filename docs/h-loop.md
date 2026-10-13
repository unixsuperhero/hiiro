# h loop

Recurring loop recipes. Each cycle is one owned run under [h schedule](h-schedule.md); its outcome and output are recorded, and the views read those records.

## Synopsis

```bash
h loop ls                 # loops, enabled or not, last outcome
h loop add                # new recipe through a YAML editor
h loop rm NAME…           # disable, then delete the recipe
h loop start [NAME…]      # h schedule enable loop-NAME
h loop stop [NAME…]       # h schedule disable loop-NAME
h loop restart [NAME…]
h loop run NAME           # one cycle now
h loop status NAME        # recent cycles and the last completed output (prs and slack are shortcuts)
h loop render             # write ~/ai/home.html from the records
h loop ui                 # outcome screen for loop-* schedules, refreshed in the background
```

## Recipes

Recipes stay where they always were, `~/ai/loops/NAME/config.yml`:

```yaml
name: prs
frequency: 10m
# Deterministic work, no agent:
# command: [h, pr-monitor, --once]
# Or an agent that interprets the prompt (explicit opt-in):
agent: [claude, -p, --model, sonnet]
prompt: |
  Summarize my open PRs and what needs my attention.
```

- `command:` runs that argv each cycle. `agent:` runs that argv with the prompt as its last argument. A prompt with neither is listed as invalid (`a prompt loop needs an explicit agent: argv …`) and never runs, so an existing recipe keeps its prompt but starts no agent until you add `agent:`.
- Permission-bypass flags are refused. Nothing adds them for you.
- `timeout`, `notify`, `cwd`, `env`, `artifacts`, and `keep_logs` work as in [h schedule](h-schedule.md). A loop keeps every cycle's log by default, because the output is the result.

## What changed

Loops used to run as long-lived `claude --dangerously-skip-permissions` sessions in a tmux `loops` session, and each prompt told the agent to rewrite `status.json` and run `h-loop render` after every cycle. Now:

- each cycle is a separate, bounded run whose exit status and output are recorded (`h schedule status loop-NAME`);
- `status`, `ls`, `render`, and `ui` read those records; nothing reads `status.json` or `info.json`, and the agent is never asked to regenerate a dashboard (existing files are left on disk, unread);
- `render` is an explicit view operation, and the page no longer reloads itself;
- the `tmux` subcommand and the tmux session are gone.

## See also

[h schedule](h-schedule.md)
