---
sidebar_position: 3
---

# Writing commands

Register a command with `Karet.Register`. Every command has a `Name`, a `Network` realm, and an `On` table of handlers.

```lua
Karet.Register({
    Name = "give",
    Description = "give a player coins",
    Network = "Server", -- runs authoritatively on the server
    Args = {
        { Name = "who", Types = { "Player" }, Required = true },
        { Name = "amount", Types = { "Integer" }, Required = true },
    },
    On = {
        Server = function(ctx)
            local plr = ctx.Args.who
            -- ... give them ctx.Args.amount coins ...
            ctx.Success(`gave {plr.Name} {ctx.Args.amount} coins`)
        end,
    },
})
```

## Realms

`Network` decides where the handler runs:

| Network | Runs on |
| --- | --- |
| `Client` | the client only |
| `Server` | shipped to the server and run there |
| `Shared` | the client, with no server round trip |
| `Context` | a bridge: `On.Client` commits a payload, `On.Server` acts on it |

Arguments are resolved and **type-checked on both realms** - the client validates for fast feedback, the server re-validates authoritatively before your handler runs.

## Args, Flags, Modifiers

```lua
Args = { { Name = "target", Types = { "Player" }, Required = true } },
Flags = { { Name = "silent", Short = "s" } },          -- boolean: -s
Modifiers = { { Name = "reason", Types = { "String" } } }, -- valued: --reason=spam
```

Read them in the handler as `ctx.Args.target`, `ctx.Flags.silent`, `ctx.Modifiers.reason`.

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

## Builder form

If you prefer a fluent style:

```lua
Karet.Command("ping")
    :Description("pong")
    :Network("Client")
    :On("Client", function(ctx) ctx.Print("pong") end)
    :Register()
```

## Permissions

Gate a command by role, or globally:

```lua
Karet.Register({ Name = "ban", Permission = "Admin", --[[ ... ]] })
Karet.SetRoleHook(function(player) return isAdmin(player) and "Admin" or "User" end)
```

See [Permissions](/api/Karet#SetRoleHook) on the Karet class.
