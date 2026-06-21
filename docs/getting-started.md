---
sidebar_position: 2
---

# Getting started

## Install

Drop the `Karet` module into `ReplicatedStorage` (via Rojo, Wally, or the HTTP bootstrap installer), then require it from both a client and a server script.

```lua
-- both realms
local Karet = require(game.ReplicatedStorage.Karet)
```

## Boot it

Call `Karet.Start` once per realm. The options are the same on both sides; each realm uses the ones that apply to it.

```lua
Karet.Start({
    Toggle = "Semicolon",   -- key (or "LeftControl+Semicolon") to open the terminal
    Theme = "tokyonight",   -- a built-in theme name, or a palette table
    Placement = "Window",   -- Window | Top | Bottom | Middle
    Kaveat = true,          -- enable the Luau editor
    Persist = true,         -- save history/vars/themes/aliases/functions to DataStores
    Admin = true,           -- kick/ban/mute/audit + a dashboard
})
```

See [StartConfig](/api/Karet#StartConfig) for every option.

## Try it

Open the terminal with your toggle key and type:

```
help
echo hello
theme gruvbox
neofetch
```

Press `Ctrl+Shift+P` for the command palette, or `Ctrl+R` to search history.

## Next

Head to [Writing commands](./commands) to add your own.
