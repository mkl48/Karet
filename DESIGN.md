# Karet — Design

> An in-game command framework and terminal for Roblox.
> Revival and redesign of *Repcl*. Status: **design / pre-implementation**.

Karet is a terminal you drop into a Roblox game. You open a window, type commands
in a real shell grammar, get typed argument validation as you type, and run
authoritative actions across the client/server boundary. It also ships a built-in
multi-line script editor.

## Influences

Karet sits deliberately between two existing Roblox projects:

- **[Cmdr](https://eryn.io/Cmdr/)** — typed arguments validated on *both* client and
  server, real-time validation as you type, a `Registry`, and `Hooks` for
  permissions/middleware. Karet keeps this rigor: by the time a handler runs, every
  argument is present and correctly typed.
- **[Conch](https://github.com/alicesaidhi/conch)** — treats the console as a
  *full language*: variables, control flow, `analyze(source)` for tooling, replicated
  types registered on both sides, and roles/`super-user` permissions. Karet takes the
  ambition: Karet's shell is a real shell, not just an argument splitter.

Karet's bet: Cmdr's type safety + Conch's shell power + a first-class terminal/editor
UI with one unified theme.

> **Inspiration only.** Karet does **not** fork, depend on, wrap, or re-export Conch or
> Cmdr. It borrows *ideas*, not code. Its only runtime dependencies are **Switch**
> (input) and **Substance** (networking).

## The stack (mental model)

Modeled on a real terminal stack — each Karet layer maps to a real-world analogue:

| Karet layer | Analogue | Role |
|---|---|---|
| **Karet** | Alacritty + Zsh | The terminal *and* the shell — window, input, rendering, output, **and** the tokenizer/parser/evaluator of the command grammar |
| **Kaveat** | Neovim + neo-tree | The built-in multi-line script editor + buffer/file tree |
| **Theme** | Neovim colorscheme | One semantic palette piped through every surface |

The shell is not a separate sub-brand — it *is* Karet. (See [GRAMMAR.md](GRAMMAR.md)
for the full grammar.) Built on two dependencies:
- **Switch** — input detection (keybinds, terminal toggle).
- **Substance** — networking (the client/server/bridge transport).

```
Karet              -- umbrella: lifecycle, registry, shell, UI, output, auth
 ├─ Karet.Theme    -- colorscheme system (define / set / get)
 └─ Karet.Kaveat   -- Kaveat: the built-in script editor (Neovim + neo-tree analogue)
```

One entry point on both realms: `require(ReplicatedStorage.Karet)`. Behavior diverges
by `RunService` internally.

## Bootstrapping

Unlike Repcl, Karet owns input (via Switch) and theming at start — no hand-wiring
`UserInputService`.

**Client** (`LocalScript` in `StarterPlayerScripts`):

```lua
local Karet = require(game.ReplicatedStorage.Karet)

Karet.Start({
    Toggle      = "Semicolon",            -- Switch binding to open/close the terminal
    Kaveat      = true,                   -- enable Kaveat, the built-in editor
    Theme       = Karet.Theme.Tokyonight, -- a built-in Neovim palette
})
```

**Server** (`Script` in `ServerScriptService`) — auth + registration:

```lua
local Karet = require(game.ReplicatedStorage.Karet)

Karet.SetRoleHook(function(player)
    if player.UserId == OWNER_ID then return "Owner" end
    if player:GetRankInGroup(GROUP_ID) >= 100 then return "Admin" end
    return "User"
end)

Karet.Start({
    DefaultRole = "User",
    RateLimit   = { MaxCalls = 10, Window = 5 },
})
```

## Command definition

Two equivalent styles. The table style is the canonical record; the builder is sugar.

### Table style

```lua
Karet.Register({
    Name        = "ban",
    Aliases     = { "b" },
    Description = "Ban a player",
    Network     = "Context",   -- Shared | Client | Server | Context (the bridge type)
    Permission  = "Admin",

    Args = {
        { Name = "target",   Types = { "Player" },   Required = true },
        { Name = "duration", Types = { "Duration" }, Required = false, Default = 86400 },
        { Name = "reason",   Types = { "String" },   Required = false, Default = "no reason" },
    },
    Attributes = {
        { Name = "silent",    Short = "s", Description = "suppress broadcast" },
        { Name = "permanent", Short = "p", Description = "permanent ban" },
    },
    Returns = {
        { Name = "target", Type = "Player" },   -- pooled for /target and /Player refs
    },

    -- Handlers always live under On, keyed by realm. A Context (bridge) command uses
    -- Client + Server; single-realm commands use just one key (Client / Server / Shared).
    On = {
        Client = function(ctx)
            ctx.Commit({
                TargetId = ctx.Args.target.UserId,
                Duration = ctx.Attributes.permanent and -1 or ctx.Args.duration,
                Reason   = ctx.Args.reason,
            })
        end,
        Server = function(ctx, payload)
            local target = game.Players:GetPlayerByUserId(payload.TargetId)
            if target then target:Kick("banned -- " .. payload.Reason) end
            ctx.Reply(tostring(payload.TargetId) .. " banned")
        end,
    },
})
```

### Builder style

```lua
Karet.Command("ban")
    :Alias("b")
    :Description("Ban a player")
    :Network("Context")
    :Permission("Admin")
    :Arg({ Name = "target",   Types = { "Player" }, Required = true })
    :Arg({ Name = "duration", Types = { "Duration" }, Required = false, Default = 86400 })
    :Attribute({ Name = "silent", Short = "s" })
    :On("Client", function(ctx) ctx.Commit({ TargetId = ctx.Args.target.UserId }) end)
    :On("Server", function(ctx, payload) --[[ ... ]] end)
    :Register()
```

> **Open influence from Conch:** Conch declares arguments as a *typed function*
> (`arguments: () -> T...`) for full Luau inference. We may offer a third, fully-typed
> registration form later; the table form stays the default for ergonomics.

## Networking types (over Substance)

A command's `Network` field picks one of four types; **Substance** is the transport
underneath. Handlers live under `On`, keyed by realm.

| `Network` | `On` keys | Behaviour |
|---|---|---|
| `Shared` | `Shared` | Registered on both, runs wherever it is called from |
| `Client` | `Client` | Runs locally on client, never touches server |
| `Server` | `Server` | Client sends the invocation to the server (Substance), server executes |
| `Context` | `Client` + `Server` | Client runs `On.Client` first, calls `ctx.Commit(payload)` to hand off to `On.Server` |

`Context` (the former "Bridge") is for commands where the client does confirmation/UI and
the server does the authoritative action. **Auth is always checked server-side before any
Server/Context handler runs.**

**Open decision — payload schemas.** Because Substance supports typed, validated
payloads, `ctx.Commit` could take a *declared schema* per command rather than a loose
table (Repcl's approach). Typed = safer + free validation/batching; loose = simpler.
Leaning typed-optional: loose by default, declarable when you want it.

## Argument types

`Types` is a **union** tried left-to-right; the first that parses *and* validates wins.
If none pass, the command is rejected before the handler fires — handlers never type-check.

Built-ins: `String Number Integer Boolean Player Players Team Color Vector3 Duration`.

Custom types (registered on both realms, à la Cmdr/Conch):

```lua
Karet.DefineType("Duration", {
    Parse        = function(raw) --[[ "30s" -> 30 ]] end,
    Validate     = function(value) return value ~= nil or "invalid duration" end,
    Autocomplete = function(raw) return { "30s", "5m", "1h", "1d" } end,
    Display      = function(value) return value .. "s" end,
    Multi        = false,   -- true -> floating multi-value picker in the terminal
    Searchable   = false,   -- adds a filter input to that picker
})
```

## The shell grammar

Karet's shell grammar is what makes it a *shell* and not a command list. It is the Repcl
chain language, formalized, with room to grow toward Conch's full-language ambitions.
The authoritative spec is **[GRAMMAR.md](GRAMMAR.md)**; this section is the overview.

### Chain operators

| Op | Behaviour |
|---|---|
| `&`  | run next regardless of result |
| `&&` | abort chain if current fails |
| `\|\|` | run next only if current failed |

```
give PlayerTwo coins 500 && kick PlayerTwo "cleaned up"
```

### References — returns & variables

There is **no positional stack** to count. Commands declare a `Returns` schema and push
one or more values into a shared **return pool**; you reference them by *what they are*.

| Ref | Meaning |
|---|---|
| `//` | the last returned value ("it") |
| `/Name` | a returned item grabbed by its **label** (then **type**), e.g. `/target`, `/Player` |
| `/Name#2` / `//#2` | the *n*-th most recent matching return — disambiguates two of a kind |
| `//.UserId` / `/Player.UserId` | property access on any reference |
| `@name` | named variable, bound with the assignment expression `(name = …)` |

A failed link that was meant to return does **not** pollute the pool — the next
successful return takes the slot. Handlers emit returns with `ctx.Return(...)`, matched
positionally to the command's `Returns` schema. **Full grammar + pool semantics:
[GRAMMAR.md](GRAMMAR.md).**

```
GetPlayer Kr3ativeKrayon && //.UserId      -- // = the returned player
ban /Player.UserId "cheating" -p            -- grab the Player return by type
```

> **Parser note:** `/` is a reference prefix in arg position (`/Player`, `//`) but
> division inside an expression (`(@x / 2)`). Context disambiguates: a `/` followed by a
> name or another `/` is a reference; a `/` between operands is division.

**Assignment is an expression**, not a keyword — there is no `set`. You bind a variable
with `(name = value)`, and like every computed thing it lives inside `( )`. The value is
itself an expression; a **command used as a value is wrapped in its own parens**
(command substitution), which disambiguates it from a literal arg:

```
(x = 5)                     -- literal
(x = @y + 2)                -- expression (already in eval context)
(x = (GetPlayer me))        -- command substitution: run GetPlayer, bind its result
```

Named variables persist as the chain runs — unlike `//`, which always re-points at the
most recent return:

```
(x = (GetPlayer me))
give @x coins 500
```

### Flags & directives

Two kinds of dash-prefixed modifiers can trail a command:

- **Flags** (`-s`, `-p`) — short, per-command boolean toggles declared in the command's
  `Attributes`. Read in the handler via `ctx.Attributes.silent`. Always boolean.
- **Directives** (`--Ignore-Errors`, `--Dry-Run`, `--Verbose`) — long, **chain-level**
  modifiers that change *how Karet runs the line* rather than what one command does.
  Handled by Karet itself, not the command handler. *(Term TBD — placeholder name.)*

```
ban PlayerTwo 1d "grief" -s -p
GetPlayer x && ban //.UserId "x" --Ignore-Errors
```

### Type values

`@TYPE[name]` is a first-class value for any registered Karet type, usable in guards:

```
(@x == @TYPE[number])     -- true if @x satisfies the "number" type
(@x != @TYPE[Player])
```

### Expressions

Bare tokens are literal args. **Anything computed is wrapped in `( )`** — parens tell
Karet "evaluate this" rather than "pass it literally."

```
(@x - 2)               math:        + - * / %
(@x + 2 == 4)          comparison:  == != > < >= <=
(@x == @TYPE[number])  type guard
(@x !)                 nil test:    ! = "is nil"
(@x ~!)                not nil:     ~ = "not", so ~! = "not nil"
~(@x + 2 == 4)         negate a whole group
```

Operator primitives: `!` (is nil) · `~` (logical NOT, prefixes a group or `!`) ·
`== != > < >= <=` (compare) · `&&` `||` (boolean and/or **inside** a guard).

### Control flow — guards & blocks

A parenthesized condition followed by `{ }` is an `if`. This **replaces** Repcl's inline
`~`/`!` continue-operators with real, composable blocks:

```
(@x ~!){ ban @x.UserId "cheating" -p }

~(@x + 2 == 4) && (@x == @TYPE[number]) {
    give @x coins 500
}
```

Form: `<guard> { <commands> }`, where `<guard>` is one or more parenthesized conditions
joined by `&& || ~`. The block (a full chain) runs only if the guard is truthy.

> **`&&` / `||` are context-overloaded:** between commands they are *chain control*
> (run-next / or-else); inside `( )` or a guard they are *boolean* and/or. Parens scope
> the meaning.

### Static analysis

**`Karet.Analyze(source)`** does one static pass over a line or script — tokens,
the resolved command, the expected next arg, type errors, and completions. It powers
as-you-type validation in the terminal. (Idea borrowed from Conch's `analyze`; not a
dependency.) Note: this analyzes the *Karet shell* grammar, not Luau — Kaveat's Luau
editor has its own highlighting/autocomplete.

### Shell API (power users)

```lua
Karet.Tokenize(raw)
Karet.Parse(raw)                 -- -> AST
Karet.Eval(ast, runFn)
Karet.Analyze(source)            -- -> diagnostics / completion info
Karet.DefineToken(symbol, config)
Karet.DefineResolver(name, fn)
Karet.ResolvePoolRef(ref, pool)  -- resolve a /ref against the return pool
Karet.EvalMath(expr, pool)
```

## Auth & roles

Server-authoritative, modeled on Cmdr hooks + Conch roles.

```lua
Karet.SetAuthHook(function(player, commandName) return ... end)
Karet.SetRoleHook(function(player) return "Owner" | "Admin" | "User" end)
Karet.SetGroupHook(function(player) return player:GetRankInGroup(GROUP_ID) end)
Karet.AllowPlayer(userId) ; Karet.DenyPlayer(userId)
Karet.SetDefaultRole("User")
```

Auth is checked server-side before any Server/Context command runs. Client-only commands
are not framework-gated — restrict those inside the handler.

## Middleware

```lua
Karet.PreExecute(function(ctx) if ctx.Player.AccountAge < 7 then ctx.Abort("too new") end end)
Karet.PostExecute(function(ctx, result) --[[ audit log ]] end)
Karet.OnErr(function(ctx, err) Karet.Err(ctx.Command .. " failed -- " .. err) end)
Karet.OnConnect(function(player) Karet.PrintTo(player, "welcome " .. player.Name) end)
```

`PreExecute` returning `false` cancels; `ctx.Abort(msg)` cancels mid-handler.

## `ctx` reference

| Field | Description |
|---|---|
| `ctx.Player` / `ctx.Command` / `ctx.RawInput` | who / what / original input |
| `ctx.Args` / `ctx.Attributes` | parsed+validated args / boolean flags |
| `ctx.IsServer` / `ctx.IsClient` / `ctx.ExecutedAt` | context + `os.clock()` at dispatch |
| `ctx.Role` / `ctx.Rank` | from role/group hooks |
| `ctx.Print/Warn/Err/Reply(msg)` | write to caller's console |
| `ctx.Abort(msg)` | cancel with message |
| `ctx.Return(...)` | push values to the return pool, matched to the `Returns` schema |
| `ctx.Commit(payload)` | **`Context` (bridge) only** — hand off from `On.Client` to `On.Server` |

## Theme — one colorscheme, everywhere

You want the *same Neovim palette through the whole UI*, so a theme is a set of
**semantic highlight groups**, not raw frame colors. Swapping a theme recolors the
terminal, editor, windows, autocomplete ghost text, and pickers at once — like
`:colorscheme` in Neovim.

```lua
Karet.Theme.Define("tokyonight", {
    Background = Color3.fromHex("1a1b26"),
    Foreground = Color3.fromHex("c0caf5"),
    Comment    = Color3.fromHex("565f89"),
    Accent     = Color3.fromHex("7aa2f7"),
    String     = Color3.fromHex("9ece6a"),
    Number     = Color3.fromHex("ff9e64"),
    Keyword    = Color3.fromHex("bb9af7"),
    Error      = Color3.fromHex("f7768e"),
    Warn       = Color3.fromHex("e0af68"),
    -- ...remaining highlight groups
})
Karet.Theme.Set("tokyonight")
```

Ship a few built-in ports (Tokyonight, Gruvbox, Catppuccin, Nord) so it feels like
Neovim out of the box.

## Kaveat — the built-in editor

Kaveat is the Neovim-analogue: a **full Luau script editor**, not a snippet box. It runs
arbitrary Luau against the live game, with the editor itself enforcing realm safety.

**Editing experience**
- Multi-line editing with a buffer / file tree (neo-tree analogue).
- **Luau** syntax highlighting and grammar — this is *Luau*, not the Karet shell grammar.
  (`Karet.Analyze` drives the terminal's as-you-type validation; Kaveat highlights Luau.)
- Autocomplete and `require` of real `ModuleScript`s.
- **Live-updating against the game hierarchy** — autocomplete and instance resolution
  reflect the actual DataModel as it changes, so paths and children stay accurate.

**Contexts & realm restriction**
- Each buffer declares a **Context: Client or Server.**
- **Client context is genuinely restricted:** anything that requires the server realm is
  keyed out — both hidden from autocomplete *and* rejected at run. Server context is the
  inverse (client-only APIs keyed out).

**Execution via `loadstring` — why everything routes through the server**
- Roblox `loadstring` only runs on the **server** (and only with `LoadStringEnabled`).
  So Kaveat **always sends source to the server to be compiled**, regardless of the
  buffer's declared context.
- That makes the **server the single gatekeeper**: it compiles the source, enforces the
  declared context (blocking / stripping non-context-respective access), and runs it. The
  client can never smuggle server-realm code past it, because the client can't `loadstring`
  in the first place.

> **Open technical item — client-context *execution*.** The server is the only place that
> can compile, but client-context code ultimately needs to *run on the client*. Since the
> client can't `loadstring`, we need a runner story: e.g. server validates + ships vetted
> source to a client-side evaluator, or client-context runs in a client-shaped sandbox
> server-side, or Karet ships its own mini-interpreter. **Undecided.**

## Windows

- **WWI (Wrapped Window Interface):** optional per-command windows that dispatch through
  the *same* auth + run pipeline as the terminal. Built on the theme tokens.

## Open decisions

1. **Payload schemas** — typed (Substance) vs loose tables. *Leaning: loose default,
   typed-optional.*
2. **UI backend** — keep **Iris** (fast) vs custom native UI (clean unified theming).
   *Leaning: custom, for the colorscheme story.*
3. ~~**`/Name` reference keying**~~ — **resolved.** Commands declare a `Returns` schema;
   `/Name` matches **label first, then type**, with `/Name#n` for positional
   disambiguation. See [GRAMMAR.md §5](GRAMMAR.md).
4. **Directive term** — the real name for chain-level `--Ignore-Errors` modifiers
   (currently placeholdered as "directives").
5. **Variable scope** — are `@vars` per-line, per-session, or cleared when Karet closes?
6. **Argument declaration** — add Conch-style typed-function form alongside the table form?

## Feature comparison

| Feature | Karet | Conch | Cmdr |
|---|---|---|---|
| Typed args, validated both sides | ✓ | ✓ | ✓ |
| Custom types + autocomplete | ✓ | ✓ | ✓ |
| Full shell language (chain/stack/conditionals/math) | ✓ | ✓ | ✗ |
| Named variables / control flow | planned | ✓ | ✗ |
| Shared / Client / Server / Context networking | ✓ | partial | partial |
| Multi-value picker (Players) | ✓ | ✗ | ✗ |
| Built-in script editor | ✓ | ✗ | ✗ |
| Per-command windows (WWI) | ✓ | ✗ | ✗ |
| Unified Neovim-style theming | ✓ | partial | partial |
| Middleware hooks | ✓ | ✓ | ✓ |
| Rate limiting + cooldowns | ✓ | ? | ✗ |
| Fluent builder API | ✓ | ✗ | ✗ |

---

*Built on Switch (input) and Substance (networking). MIT licensed.*
