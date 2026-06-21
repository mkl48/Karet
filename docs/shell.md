---
sidebar_position: 4
---

# The shell

Karet's input is a real shell, not a chat-command parser. Lines are tokenized, parsed into an AST, type-checked, then run.

## Chains

Run commands in sequence and branch on success:

```
greet A && greet B      # run B only if A succeeded
greet A || greet B      # run B only if A failed
greet A & greet B       # run both regardless
echo one; echo two      # ; (or a newline) separates statements
```

## Pipes

Thread one command's return value into the next:

```
echo hello | shout      # shout receives "hello" as its first arg + ctx.Input
```

The piped value auto-fills the next command's first missing required argument, and is also available as `ctx.Input`.

## Variables

The `@name` store. Set, read, and use them in expressions:

```
set hp 100
echo @hp
incr hp 5
(@hp > 50) { notify "healthy" }   # a guarded block
```

## Guards and type checks

Parenthesised expressions guard a block, and `@TYPE[...]` checks a value's type:

```
(x = 5) && (@x == @TYPE[number]) { echo "x is a number" }
```

## Functions

Name a sequence of commands and run it like a builtin:

```
function hi "echo hello; echo there"
hi
functions          # list them
unfunction hi
```

Functions show up in `help` and completion, work inside chains and pipes, can call each other, and persist with `Persist = true`.

## Background jobs

```
every 5s jump      # run a command on a loop
jobs               # list (click a row to stop it)
stop 1             # or: stop all
watch health "notify ouch"   # run when an expression changes
```

## The HUD

Pin a value to an always-on overlay (visible with the terminal closed):

```
pin health         # live value + sparkline
pins               # list (click to unpin)
unpin all
```

## Keyboard

| Key | Does |
| --- | --- |
| `Tab` | accept the autocomplete suggestion |
| `Up` / `Down` | history, or move the suggestion |
| `Ctrl+R` | reverse history search |
| `Ctrl+Shift+P` | fuzzy command palette |
| `Ctrl` `+` / `-` / `0` | zoom |
