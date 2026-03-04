---
author: Hiiro
date: 2026-03-01
paging: "%d / %d"
---

# Hiiro

A lightweight CLI framework for Ruby

- Subcommand dispatch
- Abbreviation matching
- Plugin system

---

# Abbreviation Matching

Type just enough letters to be unambiguous.

Hiiro resolves prefixes at **every level** of the command tree.

```bash
h
```

> Press `Ctrl+E` to run

---

# Abbreviations in Action

`h to` resolves to `h todo`

```bash
h to
```

---

# Deep Abbreviations

Abbreviations work at every level.

`h to ls` resolves to `h todo ls`

```bash
h to ls
```

---

# Ambiguous Abbreviations

When a prefix matches multiple commands,
Hiiro shows the candidates.

`h s` matches several commands:

```bash
h s || true
```

---

# Narrowing Down

A longer prefix narrows the match.

`h se` gets closer:

```bash
h se || true
```

---

# More Examples

`h wi ls` = `h window ls`

```bash
h wi ls
```

---

# Even Shorter

`h br` = `h branch`

```bash
h br
```

---

# h task

Manage **worktree-based tasks** via the Tasks plugin.

```bash
h task
```

---

# h task ls

List current tasks:

```bash
h task ls || true
```

---

# Task Abbreviation

`h ta ls` = `h task ls`

```bash
h ta ls || true
```

---

# h subtask

Same interface as task, scoped to **subtasks**.

```bash
h subtask
```

---

# h subtask ls

List current subtasks:

```bash
h subtask ls || true
```

---

# Subtask Abbreviation

`h su ls` = `h subtask ls`

```bash
h su ls || true
```

---

# h queue

Background **job queue** management.

```bash
h queue
```

---

# h queue ls

List queued jobs:

```bash
h queue ls || true
```

---

# h queue status

Show queue status:

```bash
h queue status || true
```

---

# Queue Abbreviation

`h q ls` = `h queue ls`

```bash
h q ls || true
```

---

# Key Takeaways

- Type just enough letters to be unambiguous
- Abbreviations work at every level
- `h task` / `h subtask` - worktree-based workflows
- `h queue` - background job management

---

# Thanks!

```
github.com/unixsuperhero/hiiro
```
