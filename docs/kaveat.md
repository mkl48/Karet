---
sidebar_position: 5
---

# Kaveat

Kaveat is Karet's built-in Luau editor: tabs, a tree, syntax highlighting, autocomplete, an output pane and a vim-ish modeline. Enable it with `Start({ Kaveat = true })` and open it with the `kaveat` command (alias `kav`).

## Running code

Kavs run on the **server** via `loadstring` (gated for safety - see below). Their `print`/`warn` are captured and replayed in the output pane.

| Key | Does |
| --- | --- |
| `Ctrl+Enter` | run the whole buffer |
| `Ctrl+Shift+Enter` | run just the selected text |

## Modeline commands

Press `:` then type a command:

```
:w        save        :run      run the buffer
:q        close tab   :check    lint the buffer
:e <f>    open file   :server   server context
:ls       list kavs   :client   client context
```

`:w` also surfaces any structural problems it finds.

## Diagnostics

`:check` (alias `:lint`) runs a heuristic Luau check and flags the mistakes that bite most: unbalanced brackets, unterminated strings and comments, missing or extra `end`, and `repeat` without `until`, each with a line number. It is a heuristic, not a full parser - it skips strings and comments so keywords inside them don't false-fire.

## Modules

One kav can `require` another by name, ModuleScript-style:

```lua
-- util.luau
return { greet = function(n) return "hi " .. n end }

-- main.luau
local u = require("util")
print(u.greet("bob"))
```

Modules run once, their return value is cached, and require cycles error cleanly instead of hanging. The `.luau` suffix is optional. Requiring a real `ModuleScript` or asset id still works as normal.

## Enabling server execution

Running arbitrary Luau on the server is gated. Studio is always allowed; on a live game you opt in:

```lua
-- server
Karet.Start({ KaveatExec = true })
-- or per player:
Karet.Start({ KaveatExec = function(player) return player:GetRankInGroup(123) >= 250 end })
```

:::warning
Enabling `KaveatExec` on a live game lets allowed clients run arbitrary server code. Gate it to people you trust.
:::
