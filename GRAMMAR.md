# Karet — Grammar Specification

> The shell grammar for Karet. Tokenizer + parser + evaluator reference.
> Status: **design / pre-implementation**. Companion to [DESIGN.md](DESIGN.md).

Karet's shell is the Zsh-analogue layer of the
[stack](DESIGN.md#the-stack-mental-model) — not a separate sub-brand, it *is* Karet.
It turns a line of text into an AST that the evaluator runs against the command
registry. This document is the authoritative grammar; prose examples in DESIGN.md
defer to it.

## 1. The core idea: two contexts + token position

Every overloaded symbol in Karet's grammar (`/`, `&&`, `||`, `-`) means one thing in
**command context** and another in **expression context**. The context is a *parser*
state, not a raw bracket count — and that distinction matters:

> **`( )` opens an expression context.** But a `( )` whose body is a *command
> substitution* (§4) re-enters **command** context inside those parens — so `/Player`
> is a reference and `-s` is a flag even though they sit inside `( )`. A pure
> bracket-depth rule can't see this; the parser can, because it knows which production
> it is in.

`{ }` (and the top level) is always command context.

| Symbol | Command context | Expression context |
|---|---|---|
| `/` in **value** position | reference prefix (`/Player`) | reference prefix (`/Player`) |
| `/` in **operator** position | — | division |
| `//` | last-return reference | last-return reference *(one token — never division)* |
| `&&` `\|\|` | chain control (run-next / or-else) | boolean and / or |
| `&` | chain control (run regardless) | — (not valid alone in an expr) |
| `-name` (adjacent) | flag (`-s`) | unary minus + name |
| `--name` (adjacent) | directive (`--Dry-Run`) | — |
| `-` before a digit (adjacent) | negative number literal | unary minus / subtraction |

Note `/` is disambiguated by **token position** (does a value or an operator belong
here?), which is why it resolves identically in both contexts and inside command subs.
`-`/`--` are disambiguated by **adjacency** (no whitespace before the name) plus
context. The lexer reports adjacency; the parser decides.

## 2. Lexical grammar — the lexer is neutral

The lexer is **context-free**: it never tries to know whether it is in a command or an
expression. It emits the smallest tokens, records whether each was **preceded by
whitespace** (`spaceBefore`, so the parser can tell `-s` the flag from `- s` the
operator), and leaves *all* meaning assignment to the parser. This is what makes command
substitution inside `( )` work without a chicken-and-egg between lexer and registry.

```
NEWLINE     = "\n" | "\r\n"
WS          = (" " | "\t")+                 (* separator; sets spaceBefore on next token *)
STRING      = '"' { any - '"' | ESCAPE } '"' (* double-quoted; full Luau escape set:
                                               \n \t \r \" \\ \0 \xNN \u{...} etc. *)
NUMBER      = DIGIT { DIGIT } [ "." DIGIT { DIGIT } ]   (* unsigned; sign is a parser
                                               decision from a preceding adjacent '-' *)
BOOL        = "true" | "false"               (* recognised from an IDENT spelling *)
IDENT       = (LETTER | "_") { LETTER | DIGIT | "_" | "-" }
                                            (* '-' allowed *inside* an ident, so
                                               'Ignore-Errors' is one IDENT; a *leading*
                                               '-' is never part of an IDENT *)
```

Operator / punctuation tokens (longest match wins, so `&&` beats `&`, `>=` beats `>`,
`//` beats `/`, `--` beats `-`):

```
//  /  .  #  @  =  !  ~
&&  ||  &
==  !=  >=  <=  >  <
+   -   *   /   %
(  )  {  }  [  ]
@TYPE       (keyword; an '@' immediately followed by the bareword 'TYPE' then '[')
```

There is **no** `FLAG`, `DIRECTIVE`, `SLASH_REF`, or `SLASH_DIV` token. `-`, `--`, `/`,
and `//` are lexed as plain operator tokens; the parser turns `-`/`--` + adjacent IDENT
into a flag/directive (command context) or reads them as arithmetic (expression
context), and turns `/` + value into a reference or treats it as division by position.

## 3. Phrase grammar (EBNF)

Command context is the default start symbol.

```
(* ---------- Command context ---------- *)

Program     = [ Chain ] { NEWLINE [ Chain ] } ;

Chain       = Statement { ChainOp Statement } { Directive } ;
ChainOp     = "&&" | "||" | "&" ;

Statement   = Guarded | Command | ValueStmt ;

Guarded     = Guard Block ;
Guard       = GuardTerm { ("&&" | "||") GuardTerm } ;
GuardTerm   = [ "~" ] "(" Expr ")" ;
Block       = "{" Program "}" ;                 (* re-enters command context *)

Command     = Word { Argument } { Flag } ;
Word        = IDENT ;
Flag        = "-" IDENT ;                         (* adjacent, command ctx: "-s"; "-sp" expands *)
Directive   = "--" IDENT ;                        (* adjacent, command ctx: "--Ignore-Errors" *)

Argument    = Reference | TypeValue | VarRef | Group | Literal ;
Literal     = STRING | NUMBER | BOOL | Word ;    (* a bare word is a literal string *)

ValueStmt   = Reference | Group ;                (* bare ref/expr as a statement:
                                                   evaluate, display, push to pool *)

(* ---------- References & sigils (valid in both contexts) ---------- *)

Reference   = Head [ Index ] { "." IDENT } ;
Head        = "//" | "/" IDENT ;                 (* // = last return; /Name = by type/label *)
Index       = "#" NUMBER ;                        (* positional: /Player#2, //#2 *)
VarRef      = "@" IDENT { "." IDENT } ;          (* named variable; @x.UserId *)
TypeValue   = "@TYPE" "[" IDENT "]" ;            (* first-class type value for guards *)

(* ---------- Expression context ---------- *)

Group       = "(" GroupBody ")" ;                (* opens an expression context *)
GroupBody   = Assignment | CommandSub | Expr ;   (* resolved per §4 *)
Assignment  = IDENT "=" ( CommandSub | Expr ) ;
CommandSub  = Command ;                           (* a command, run for its return value *)

Expr        = OrExpr ;
OrExpr      = AndExpr { "||" AndExpr } ;
AndExpr     = CmpExpr { "&&" CmpExpr } ;
CmpExpr     = AddExpr [ CmpOp ( AddExpr | TypeValue ) ] ;
CmpOp       = "==" | "!=" | ">" | "<" | ">=" | "<=" ;
AddExpr     = MulExpr { ("+" | "-") MulExpr } ;
MulExpr     = Unary { ("*" | "/" | "%") Unary } ;
Unary       = "~" Unary | "-" Unary | Postfix ;  (* prefix "~" negates the operand/group *)
Postfix     = Primary { "!" | "~!" } ;           (* x! = is-nil; x~! = not-nil *)
Primary     = NUMBER | STRING | BOOL
            | VarRef | TypeValue | Reference
            | "(" GroupBody ")" ;
```

### Operator precedence (expression context), low → high

1. `||`  (boolean or)
2. `&&`  (boolean and)
3. `== != > < >= <=`  (comparison / type-satisfaction)
4. `+ -`
5. `* / %`
6. prefix unary `~` (not), prefix unary `-` (negate)
7. postfix `!` (is-nil) and `~!` (not-nil)

`~` has two roles, disambiguated by position: a **prefix** `~` before an operand/group
negates it (`~(@x + 2 == 4)`); a **postfix** `~!` after an operand is "not nil"
(`@x ~!`), where the `~` prefixes the `!`. `@x !` alone is "is nil". `@x == @TYPE[number]`
is comparison where a `TypeValue` on the right means **type satisfaction**, not equality.

## 4. Resolving `GroupBody`: literal vs expression vs command substitution

Inside `( )` the parser picks one of three shapes:

1. **Assignment** — the group begins `IDENT "="`. The right side is itself a
   `CommandSub` or `Expr`, resolved by the same rules.
2. **Command substitution vs expression** — decided by **juxtaposition**:
   - Expressions are operands joined by operators. If, after parsing the first
     operand, the next significant token is *another operand* (no operator between
     them), the group is a **command** (`word arg arg …`) — only commands juxtapose.
   - If the first operand is followed by an operator (or the group closes), it is an
     **expression**.
3. **Lone bare word** — `( now )` is structurally ambiguous (a no-arg command vs a
   one-word literal). **Resolved at eval time:** if the word is a registered command,
   it runs as a no-arg command substitution; otherwise it is a literal string.

```
(x = 5)               -- operand, closes        → literal 5
(x = @y + 2)          -- operand OP operand      → expression
(x = (GetPlayer me))  -- operand operand         → command substitution
(GetPlayer me)        -- word arg                → command substitution
(now)                 -- lone word               → sub if 'now' is a command, else "now"
```

> Rule 3 is the *only* registry-dependent parse decision in Karet. Everything else is
> resolvable from tokens + brackets alone, which keeps `Analyze` mostly static.

## 5. The return pool

Commands push results into a shared, ordered **return pool**; references read from it.
This replaces any positional stack — you reference returns by *what they are*.

### 5.1 Declaring returns

Commands declare a `Returns` schema parallel to `Args` (see
[DESIGN.md → Command definition](DESIGN.md#command-definition)):

```lua
Returns = {
    { Name = "player", Type = "Player" },
    { Name = "count",  Type = "Number" },
}
```

A handler emits values with `ctx.Return(...)`, positionally matched to the schema:

```lua
ctx.Return(targetPlayer, killCount)   -- → record{ player, Player }, record{ count, Number }
```

If a command declares no `Returns`, an emitted value is still pooled with its
**runtime-inferred** type and **no label** — type and positional references still work,
only label references are unavailable.

### 5.2 Record shape

Each successful return is one record, appended in order:

```
{ value, type, label, fromCommand, ok = true }
```

A link that **fails** contributes nothing — the pool is untouched, so the next
successful return takes "the last slot". (Carried over from DESIGN.)

### 5.3 Reference resolution

| Ref | Resolves to |
|---|---|
| `//` | value of the **last** record |
| `//.prop` / `//#2.prop` | property access on the resolved value |
| `/Type` | value of the **most recent** record whose `type == Type` (`/Player`) |
| `/label` | value of the most recent record whose `label == label` |
| `/X#n` / `//#n` | the **n-th most recent** matching record (1 = newest) — disambiguates multiples |
| `@name` | named variable (separate from the pool; see §6) |

Resolution order for a `/Name` head when a name could be both a label and a type:
**label match first, then type match.** Labels are author-chosen and more specific.

```
GetPlayer Kr3ativeKrayon && //.UserId        -- // = the player just returned
ban /Player.UserId "cheating" -p             -- grab the Player return by type
ban /target#2.UserId "alt account"           -- the 2nd-most-recent 'target' return
```

## 6. Variables

`@name` variables are bound by the assignment **expression** `(name = value)` — there is
no `set` keyword. Unlike `//`, a variable does not re-point; it holds its bound value
until rebound.

```
(x = (GetPlayer me))     -- bind once
give @x coins 500        -- still the same player even after later returns
```

Variable scope is open-decision #5 in DESIGN (per-line / per-session / cleared on close)
and is **not** settled by this spec.

## 7. Worked parse (sanity check)

```
~(@x + 2 == 4) && (@x == @TYPE[number]) { give @x coins 500 }
```

```
Guarded
├─ Guard
│  ├─ GuardTerm  ~( @x + 2 == 4 )          -- negate( (x+2)==4 )
│  └─ "&&"  GuardTerm ( @x == @TYPE[number] )  -- type-satisfaction
└─ Block { Program: Command(give, [@x, coins, 500]) }
```

`@x + 2 == 4` parses (by precedence) as `(@x + 2) == 4`, then the leading `~` negates
the whole comparison. Both guard terms are boolean-joined by `&&` (command context — but
each term is itself an `Expr`, so the comparisons inside are expression-context `==`).

## 8. Open items specific to the grammar

- **Combined short flags** — is `-sp` two flags (`-s -p`) or one flag `sp`? (Lean: expand,
  like getopt.) Not yet decided.
- **String escapes** — only `\"` is specified; `\n`, `\t`, etc. TBD.
- **Comments** — none in the shell today. `--` is the directive prefix, not a comment. If
  Kaveat scripts need comments, they'd use a distinct lexer rule (Luau `--` lives in the
  editor, not the shell).
- Inherited from DESIGN: directive naming (#4), variable scope (#5).
```