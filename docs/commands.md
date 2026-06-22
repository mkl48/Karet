---
sidebar_position: 3
---

# Writing commands

Define a command with `Karet.Command(name, def)`. Every command has a `Network` realm, optional
`Args` / `Flags` / `Modifiers`, and a handler per realm (`Server` / `Client` / `Shared`).

```lua
type GiveArgs = { who: Player, amount: number }

Karet.Command("give", {
    Description = "give a player coins",
    Network = "Server", -- runs authoritatively on the server
    Args = {
        { Name = "who", Type = "Player", Required = true },
        { Name = "amount", Type = "Integer", Required = true },
    },
    Server = function(ctx: Karet.Context<GiveArgs>)
        local plr = ctx.Args.who          -- typed as Player
        -- ... give them ctx.Args.amount coins (typed as number) ...
        ctx.Success(`gave {plr.Name} {ctx.Args.amount} coins`)
    end,
})
```

## Typed args

Declare a record type for the command's args and annotate the handler's `ctx` with
`Karet.Context<...>`. Then `ctx.Args` is fully typed and autocompleted in your editor:

```lua
type BanArgs = { target: Player, reason: string? }

Karet.Command("ban", {
    Network = "Server",
    Args = {
        { Name = "target", Type = "Player" },
        { Name = "reason", Type = "String", Required = false },
    },
    Server = function(ctx: Karet.Context<BanArgs>)
        ctx.Args.target  -- Player
        ctx.Args.reason  -- string?
    end,
})
```

The keys of your arg record should match the `Name` of each declared arg; the type of each field is
the runtime type the arg parses to (`"Player"` -> `Player`, `"Integer"`/`"Number"` -> `number`,
`"Boolean"` -> `boolean`, ...). Without the annotation, `ctx.Args` is a loose `{ [string]: any }`.

`Type` autocompletes from the built-in type names. For a custom type registered with
`Karet.DefineType`, write `Type = "MyType" :: any`.

## Realms

`Network` decides where the handler runs:

| Network | Runs on |
| --- | --- |
| `Client` | the client only |
| `Server` | shipped to the server and run there |
| `Shared` | the client, with no server round trip |
| `Context` | a bridge: the `Client` handler commits a payload, the `Server` handler acts on it |

Arguments are resolved and **type-checked on both realms** - the client validates for fast feedback,
the server re-validates authoritatively before your handler runs.

## Args, Flags, Modifiers

```lua
Args = { { Name = "target", Type = "Player", Required = true } },
Flags = { { Name = "silent", Short = "s" } },            -- boolean: -s
Modifiers = { { Name = "reason", Type = "String" } },    -- valued: --reason=spam
```

Read them in the handler as `ctx.Args.target`, `ctx.Flags.silent`, `ctx.Modifiers.reason`. An arg can
accept a union of types by passing a list: `Type = { "Player", "Vector3" }` (first that parses wins).

## The context

Every handler gets a [Context](/api/Context) (`ctx`). The essentials:

```lua
ctx.Args, ctx.Flags, ctx.Modifiers   -- resolved input
ctx.Print(text)  ctx.Success(text)   -- themed output
ctx.Warn(text)   ctx.Err(text)
ctx.Return(value)                    -- push a value to the return pool (and into pipes)
ctx.Abort("nope")                    -- cancel mid-handler
ctx.UI.Table{ ... }                  -- rich output (tables, panels, toasts, links)
ctx.Window{ title = "x" }            -- an Iris window
```

## Loading commands from a folder

Keep each command in its own ModuleScript that calls `Karet.Command(...)`, then point `Start` at the
containing folder - Karet requires and registers every module under it (on both realms):

```lua
-- ReplicatedStorage/Commands/ping.luau
local Karet = require(game.ReplicatedStorage.Karet)
return Karet.Command("ping", {
    Network = "Client",
    Client = function(ctx) ctx.Print("pong") end,
})
```

```lua
Karet.Start({ Commands = game.ReplicatedStorage.Commands })
```

`Commands` also accepts a list of ModuleScripts, or a list of ready-made def tables (each carrying a
`Name`). A module that fails to load warns and doesn't stop the rest of the batch.

## Permissions

Gate a command by role, or globally:

```lua
Karet.Command("ban", { Permission = "Admin", Network = "Server", --[[ ... ]] })
Karet.SetRoleHook(function(player) return isAdmin(player) and "Admin" or "User" end)
```

See [Permissions](/api/Karet#SetRoleHook) on the Karet class.
