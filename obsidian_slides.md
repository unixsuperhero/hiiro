## `hiiro`

New AI Workflow Utilities
---
#### Pain Points

Thanks to AI, some pain points are becoming increasingly more common.

I've added some new features to `hiiro` that help to relieve some of the pain related to these issues.

---
#### Pain Points (cont'd)

- **Context switching** - increased cognitive load jumping from task to task
	- `h queue`
	- `h task queue` - integrated into task management
- **Managing Servers/Services**
	- `h service`

---
#### hiiro recap

hiiro is...

- a ruby lib for quickly making cli tools that are:
	- subcommand driven
	- infinitely extensible
- discoverable

```ruby
#!/usr/bin/env ruby

require "hiiro"

Hiiro.run do
  add_subcmd(:hello) {
    puts "hello world"
  }
end
```

---
#### `h task` & `h subtask`

abstracts away git worktrees and tmux sessions
as tasks

- no need to...
	- manually manage git worktrees
	- or use tmux to create/switch to different sessions

each tmux session is:
- automatically scoped to the associated worktree
- no need to remember where different worktrees are located


---
#### `h task` & `h subtask` (cont'd)

main commands:

- `h task ls`
- `h task start TASK_NAME [APP_NAME]`
- `h task switch TASK_NAME`
- `h task stop TASK_NAME`
- `h task cd APP_NAME`

---
### `h queue` - Context Switching

I recently added `h queue`

It is basically a daemon that watches for new "prompts"
to hit the queue.  When it has one, it kicks off a
new claude session with that prompt.

The sessions are added as new windows to the `hq`
tmux session.

Easily switch to that tmux session with: `h queue session`

---
### `h queue` (cont'd)

main subcommands:

- `h queue watch` - start the daemon
- `h queue ls` - list prompts and their status
- `h queue add [optional_prompt]` - open tempfile in EDITOR, on quit, queue prompt
- `h queue attach` - jump to active claude session from a list
- `h queue session` - jump to main tmux session with default queue

task integration:

- `h task queue [-t TASK_NAME] queue_command`
- `h task queue add` - queue prompt in current task (worktree/tmux session)

---
### `h queue` (cont'd)

How does this help with context switching?

You don't have to leave what you're doing to generate a prompt in a specific
context.

I can be in vim, looking at files, and kick off a prompt without leaving vim.

I can be in one task, and fire prompts specific to another task's
worktree/branch and not have to worry about explicitly giving that info to
claude.


---
#### `h service`

If I'm ever asked to demo something...I immediately get nervous.  A million
questions start running thru my head.

- Do I already have a server running?
- If so, what worktree/branch is it using?
- Which tmux session/window/pane is it in?

Because, if there is a server running but...
it's in the wrong worktree or branch...
then i have to find it and kill it

when you have 60 tmux panes...broken out into
8 different tmux sessions...just finding it
to kill it will take time.

And then to test something like the SA Form,
you then have to spin up 3-4 services:
- ipp web
- mesh
- customers backend rpc
- partners rpc

---
#### `h service` (cont'd)

the second issue with services is...

only running one instance of each service (for now)

if an instance a service is already running
and you try to start a new one, then either:

1. it will listen on the next available port
2. it will error and not start the service

the ports of other services are configured via
`.env` files.  so it will likely talk to the 
wrong services

so...

`h service` will only spawn one instance of each service

if ppl want to run multiple instances, then
i can setup pooling to affect .env values

---
#### `h service` (cont'd)

the third minor issue with services is...

different configurations.

- sometimes we want to use staging as an endpoint
- other times we want to use a local server

ideally, choosing which variation should be easy

---
#### service groups

it's also really easy to configure service groups
and specify which .env variation you want

---
#### main commands

- `h service ls`
- `h service start SERVICE_NAME`
- `h service stop [SERVICE_NAME]`
- `h service reset [SERVICE_NAME]`
- `h service attach [SERVICE_NAME]`
- `h service config`
- `h service add`
- `h service rm` # or remove
