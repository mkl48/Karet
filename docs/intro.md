---
sidebar_position: 1
---

# Introduction

Karet is an in-game command framework and terminal for Roblox. It is three things in one:

- a **terminal** - a ScreenGui CLI surface you toggle with a key
- a **shell** - a real grammar with typed arguments, chains, pipes, guards and functions
- a **command framework** - register typed commands that run on the client, the server, or both, validated on both realms

On top of that it ships a Luau editor (Kaveat), a theme engine, devtools, an admin suite, an extension platform, and DataStore persistence.

```lua
local Karet = require(game.ReplicatedStorage.Karet)

Karet.Start({
    Toggle = "Semicolon",
    Theme = "tokyonight",
    Kaveat = true,
})
```

The same `require` works on the client and the server. `Start` boots the terminal on the client and the command listener on the server; behaviour diverges internally by `RunService`.

## Where to go next

- [Getting started](./getting-started) - install and boot Karet
- [Writing commands](./commands) - register your own typed commands
- [The shell](./shell) - chains, pipes, guards, variables and functions
- [Kaveat](./kaveat) - the in-game Luau editor

The full API reference lives under the **API** tab.
