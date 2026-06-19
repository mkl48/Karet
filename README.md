<div align="center">

# Karet

**An in-game command framework and terminal for Roblox.**

<img src="https://img.shields.io/badge/Karet-v0.1.0-7aa2f7?style=for-the-badge&logoColor=white" alt="version" />
<img src="https://img.shields.io/badge/Luau-Roblox-00A2FF?style=for-the-badge&logoColor=white" alt="luau" />
<img src="https://img.shields.io/badge/License-MIT-9ece6a?style=for-the-badge" alt="license" />
<img src="https://img.shields.io/badge/Status-Early-e0af68?style=for-the-badge" alt="status" />
<img src="https://img.shields.io/badge/Tests-90%20passing-1abc9c?style=for-the-badge" alt="tests" />

Typed arguments validated on both realms · a real shell grammar · one Neovim-style theme through the whole UI.

Built on [Switch](https://github.com/mkl48/Switch) (input) and [Substance](https://github.com/mkl48/Substance) (networking).

</div>

---

Karet is a terminal you drop into a Roblox game. You open a window, type commands in a
real shell grammar, get typed argument validation, and run authoritative actions across
the client/server boundary - all themed by a single semantic colorscheme.

It sits deliberately between [**Cmdr**](https://eryn.io/Cmdr/) (typed args, registry,
hooks) and [**Conch**](https://github.com/alicesaidhi/conch) (the console as a full
language). Karet borrows the *ideas*, not the code - its only runtime dependencies are
Switch and Substance.

> **Status: early.** The shell, theme, terminal, and command framework are built and
> tested (90 headless specs). Kaveat (the Luau editor), per-command windows, multi-value
> pickers, and as-you-type highlighting are designed but not yet built. See
> [DESIGN.md](DESIGN.md) for the full vision and [GRAMMAR.md](GRAMMAR.md) for the shell spec.

## Features

- **Typed arguments** - union types tried left-to-right, validated before your handler
  runs. Built-ins: `String Number Integer Boolean Player Players Team Color Vector3 Duration`,
  plus `Karet.DefineType` for your own.
- **A real shell**, not an argument splitter - chain operators (`&&`, `||`, `&`), a return
  pool (`//`, `/Player`, `/target#2`), variables (`@x`), expressions and guards. Full spec
  in [GRAMMAR.md](GRAMMAR.md).
- **Four networking modes** over Substance - `Shared`, `Client`, `Server`, `Context`
  (client confirms → server acts), with server-authoritative auth.
- **One semantic theme** piped through every surface - swap `tokyonight` → `gruvbox` and
  the whole UI recolors live. Ships Tokyonight, Gruvbox, Catppuccin, and Nord.
- **Two ways to install** - Wally for a Rojo workflow, or a single paste-into-the-command-bar
  installer with no toolchain at all.

## Installation

Switch, Substance, and Iris are **vendored inside `src/`** (MIT, attribution kept), so Karet
ships with everything it needs - no separate dependency install.

### Wally

```toml
# wally.toml
[dependencies]
Karet = "kr3ative/karet@0.1.0"
```

```sh
wally install
```

### Command-bar installer (no toolchain)

Paste [`dist/install.luau`](dist/install.luau) into the Roblox Studio command bar - it
recreates the whole `Karet` module tree (deps included) under `ReplicatedStorage`. Nothing
else to set up.

Regenerate it from source any time with:

```sh
lune run scripts/build-installer
```

## Quick start

**Client** - `LocalScript` in `StarterPlayerScripts`:

```lua
local Karet = require(game.ReplicatedStorage.Karet)

Karet.Command("echo")
    :Description("print your text back")
    :Network("Client")
    :Arg({ Name = "text", Types = { "String" }, Required = true })
    :On("Client", function(ctx)
        ctx.Print(ctx.Args.text)
    end)
    :Register()

Karet.Start({
    Toggle = "Semicolon",            -- press ; to open/close the terminal
    Theme  = Karet.Theme.Tokyonight,
})
```

**Server** - `Script` in `ServerScriptService`:

```lua
local Karet = require(game.ReplicatedStorage.Karet)

Karet.SetRoleHook(function(player)
    if player.UserId == OWNER_ID then return "Owner" end
    return "User"
end)

Karet.Start({ DefaultRole = "User" })
```

## Defining commands

Two equivalent styles - the table is the canonical record, the builder is sugar.

```lua
-- Table style
Karet.Register({
    Name        = "ban",
    Aliases     = { "b" },
    Network     = "Context",   -- Shared | Client | Server | Context
    Permission  = "Admin",
    Args = {
        { Name = "target",   Types = { "Player" },   Required = true },
        { Name = "duration", Types = { "Duration" }, Required = false, Default = 86400 },
    },
    Attributes = {
        { Name = "permanent", Short = "p", Description = "permanent ban" },
    },
    Returns = {
        { Name = "target", Type = "Player" },
    },
    On = {
        Client = function(ctx)
            ctx.Commit({ TargetId = ctx.Args.target.UserId,
                         Duration = ctx.Attributes.permanent and -1 or ctx.Args.duration })
        end,
        Server = function(ctx, payload)
            local target = game.Players:GetPlayerByUserId(payload.TargetId)
            if target then target:Kick("banned") end
            ctx.Reply(payload.TargetId .. " banned")
        end,
    },
})
```

```lua
-- Builder style
Karet.Command("ban")
    :Alias("b")
    :Network("Context")
    :Permission("Admin")
    :Arg({ Name = "target", Types = { "Player" }, Required = true })
    :Attribute({ Name = "permanent", Short = "p" })
    :On("Client", function(ctx) ctx.Commit({ TargetId = ctx.Args.target.UserId }) end)
    :On("Server", function(ctx, payload) --[[ ... ]] end)
    :Register()
```

### Custom types

```lua
Karet.DefineType("Color", {
    Parse    = function(raw) return Color3.fromHex(raw) end,
    Validate = function(value) return typeof(value) == "Color3" or "expected a colour" end,
    Autocomplete = function() return { "ff0000", "00ff00", "0000ff" } end,
})
```

## The `ctx` object

| Field | Description |
|---|---|
| `ctx.Player` / `ctx.Command` / `ctx.RawInput` | who / what / the original line |
| `ctx.Args` / `ctx.Attributes` | parsed + validated args / boolean flags |
| `ctx.IsServer` / `ctx.IsClient` / `ctx.Role` | realm + resolved role |
| `ctx.Print / Warn / Err / Info / Reply(msg)` | write to the caller's console |
| `ctx.Return(...)` | push values to the return pool (matched to `Returns`) |
| `ctx.Commit(payload)` | `Context` only - hand off from `On.Client` to `On.Server` |
| `ctx.Abort(msg)` | cancel mid-handler |

## Auth & middleware

```lua
Karet.SetRoleHook(function(player) return "Admin" end)
Karet.SetAuthHook(function(player, command) return true end)
Karet.AllowPlayer(userId) ; Karet.DenyPlayer(userId)
Karet.SetRoles({ User = 1, Admin = 2, Owner = 3 })  -- Permission ordering

Karet.PreExecute(function(ctx) if ctx.Player.AccountAge < 7 then return false end end)
Karet.PostExecute(function(ctx, result) --[[ audit ]] end)
Karet.OnErr(function(ctx, err) warn(err) end)
Karet.OnConnect(function(player) --[[ welcome ]] end)
```

Auth is checked **server-side** before any `Server`/`Context` handler runs; the server
re-validates every argument - the client is never trusted.

## Theming

A theme is a set of *semantic highlight groups*, not raw frame colors - like a Neovim
colorscheme. Switching one recolors the terminal, output, and pickers at once.

```lua
Karet.Theme.Set("gruvbox")               -- a built-in by name
Karet.Theme.Set(Karet.Theme.Catppuccin)  -- or a palette value

Karet.Theme.Define("mytheme", {           -- partial palettes derive the rest
    Background = Color3.fromHex("11111b"),
    Foreground = Color3.fromHex("cdd6f4"),
    Accent     = Color3.fromHex("89b4fa"),
})
Karet.Theme.Set("mytheme")
```

## Public API

```lua
-- shell
Karet.Tokenize(raw) ; Karet.Parse(raw) ; Karet.Analyze(source)
-- commands & types
Karet.Register(def) ; Karet.Command(name) ; Karet.DefineType(name, def)
-- auth & middleware
Karet.SetRoleHook / SetAuthHook / SetGroupHook / SetRoles / SetDefaultRole
Karet.AllowPlayer / DenyPlayer
Karet.PreExecute / PostExecute / OnErr / OnConnect
-- theme & lifecycle
Karet.Theme ; Karet.Terminal ; Karet.Start(opts)
```

## Development

```sh
rokit install        # rojo, wally, lune
wally install        # Switch + Substance
lune run tests/run   # 90 headless specs (shell, types, registry, host pipeline, theme)
rojo serve place.project.json   # dev place: ReplicatedStorage.Karet + examples
```

Pure-Luau logic (shell, types, registry, the command pipeline) is covered by the headless
suite; the Roblox-facing surfaces (terminal rendering, Switch toggle, Substance networking)
are verified in Studio.

## License

[MIT](LICENSE) - © kr3ative
