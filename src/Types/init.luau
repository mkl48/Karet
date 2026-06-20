-- Karet's argument type system. A type knows how to Parse a raw token into a value, and
-- to Validate that value. `coerce` tries a union of types left-to-right (the first that
-- parses AND validates wins - GRAMMAR/DESIGN), so handlers never type-check. `satisfies`
-- answers @TYPE[name] guards.
--
-- Built-in types that touch Roblox services (Player, Team, ...) reach for them lazily
-- INSIDE Parse/Validate, so this module loads fine headlessly; only calling those paths
-- needs a live game.

local Types = {}
Types.__index = Types

export type Definition = {
	Parse: (raw: any) -> (any, string?), -- (value, errorMessage)
	Validate: ((value: any) -> (boolean | string))?, -- true | error message
	Autocomplete: ((raw: string) -> { string })?,
	Display: ((value: any) -> string)?,
	Multi: boolean?,
	Searchable: boolean?,
}

-- ---------------------------------------------------------------------------
-- built-in type definitions
-- ---------------------------------------------------------------------------

local function parseNumber(raw: any): (number?, string?)
	if type(raw) == "number" then
		return raw, nil
	end
	local n = tonumber(raw)
	if n == nil then
		return nil, `'{tostring(raw)}' is not a number`
	end
	return n, nil
end

-- Short duration units -> seconds. "m" is minutes (Cmdr convention); weeks supported.
local DURATION_UNITS = { s = 1, m = 60, h = 3600, d = 86400, w = 604800 }

local function set(words: { string }): { [string]: boolean }
	local out = {}
	for _, w in words do
		out[w] = true
	end
	return out
end

local TRUTHY = set({ "true", "t", "yes", "y", "on", "enable", "enabled", "1", "+" })
local FALSY = set({ "false", "f", "no", "n", "off", "disable", "disabled", "0", "-" })

local BUILTINS: { [string]: Definition } = {
	String = {
		Parse = function(raw)
			return tostring(raw), nil
		end,
		Validate = function(v)
			return type(v) == "string" or "expected a string"
		end,
	},

	Number = {
		Parse = parseNumber,
		Validate = function(v)
			return type(v) == "number" or "expected a number"
		end,
	},

	Integer = {
		Parse = function(raw)
			local n, err = parseNumber(raw)
			if not n then
				return nil, err
			end
			if n % 1 ~= 0 then
				return nil, `'{tostring(raw)}' is not a whole number`
			end
			return n, nil
		end,
		Validate = function(v)
			return (type(v) == "number" and v % 1 == 0) or "expected an integer"
		end,
	},

	-- Rich truthy/falsy spellings (inspired by Cmdr).
	Boolean = {
		Parse = function(raw)
			if type(raw) == "boolean" then
				return raw, nil
			end
			local s = string.lower(tostring(raw))
			if TRUTHY[s] then
				return true, nil
			elseif FALSY[s] then
				return false, nil
			end
			return nil, `'{tostring(raw)}' is not true/false`
		end,
		Validate = function(v)
			return type(v) == "boolean" or "expected a boolean"
		end,
		Autocomplete = function()
			return { "true", "false" }
		end,
	},

	-- bare seconds, or compound short units: "30s", "5m", "1h30m", "2d", "1w" (inspired by
	-- Cmdr's multi-component durations).
	Duration = {
		Parse = function(raw)
			if type(raw) == "number" then
				return raw, nil
			end
			local s = string.gsub(tostring(raw), "%s+", "")
			if s == "" then
				return nil, "empty duration"
			end
			if string.match(s, "^%d+%.?%d*$") then
				return tonumber(s), nil -- a bare number is seconds
			end
			local total, matched = 0, false
			for num, unit in string.gmatch(s, "(%d+%.?%d*)(%a+)") do
				local mult = DURATION_UNITS[string.lower(unit)]
				if not mult then
					return nil, `unknown duration unit '{unit}'`
				end
				total += tonumber(num) * mult
				matched = true
			end
			-- reject leftovers (e.g. "1h?") that the component pattern didn't consume
			local leftover = string.gsub(s, "(%d+%.?%d*)(%a+)", "")
			if not matched or leftover ~= "" then
				return nil, `'{tostring(raw)}' is not a duration (e.g. 30s, 5m, 1h30m, 2d)`
			end
			return total, nil
		end,
		Validate = function(v)
			return type(v) == "number" or "expected a duration"
		end,
		Autocomplete = function()
			return { "30s", "5m", "1h", "1d", "1w" }
		end,
		Display = function(v)
			return `{v}s`
		end,
	},

	Player = {
		Parse = function(raw)
			if typeof(raw) == "Instance" and raw:IsA("Player") then
				return raw, nil
			end
			local Players = game:GetService("Players")
			local name = string.lower(tostring(raw))
			local exact = Players:FindFirstChild(tostring(raw))
			if exact and exact:IsA("Player") then
				return exact, nil
			end
			for _, p in Players:GetPlayers() do
				if string.sub(string.lower(p.Name), 1, #name) == name or string.sub(string.lower(p.DisplayName), 1, #name) == name then
					return p, nil
				end
			end
			return nil, `no player matching '{tostring(raw)}'`
		end,
		Validate = function(v)
			return (typeof(v) == "Instance" and v:IsA("Player")) or "expected a Player"
		end,
		Autocomplete = function()
			local names = {}
			for _, p in game:GetService("Players"):GetPlayers() do
				table.insert(names, p.Name)
			end
			return names
		end,
	},

	-- comma-separated players, or "all"/"others"/"me" selectors
	Players = {
		Multi = true,
		Searchable = true,
		Parse = function(raw)
			if type(raw) == "table" then
				return raw, nil
			end
			local Players = game:GetService("Players")
			local out = {}
			for token in string.gmatch(tostring(raw), "([^,]+)") do
				token = string.gsub(token, "^%s*(.-)%s*$", "%1")
				if string.lower(token) == "all" or token == "*" then
					return Players:GetPlayers(), nil
				end
				local p = Players:FindFirstChild(token)
				if p and p:IsA("Player") then
					table.insert(out, p)
				else
					return nil, `no player matching '{token}'`
				end
			end
			if #out == 0 then
				return nil, "no players matched"
			end
			return out, nil
		end,
		Validate = function(v)
			return type(v) == "table" or "expected a list of players"
		end,
	},

	Team = {
		Parse = function(raw)
			if typeof(raw) == "Instance" and raw:IsA("Team") then
				return raw, nil
			end
			local team = game:GetService("Teams"):FindFirstChild(tostring(raw))
			if team and team:IsA("Team") then
				return team, nil
			end
			return nil, `no team named '{tostring(raw)}'`
		end,
		Validate = function(v)
			return (typeof(v) == "Instance" and v:IsA("Team")) or "expected a Team"
		end,
	},

	-- a hex string ("#ff0000" / "ff0000") or a Color3
	Color = {
		Parse = function(raw)
			if typeof(raw) == "Color3" then
				return raw, nil
			end
			local hex = string.gsub(tostring(raw), "^#", "")
			if not string.match(hex, "^%x%x%x%x%x%x$") then
				return nil, `'{tostring(raw)}' is not a hex colour`
			end
			return Color3.fromHex(hex), nil
		end,
		Validate = function(v)
			return typeof(v) == "Color3" or "expected a Color3"
		end,
	},

	-- "x,y,z"
	Vector3 = {
		Parse = function(raw)
			if typeof(raw) == "Vector3" then
				return raw, nil
			end
			local s = string.gsub(tostring(raw), "%s", "")
			local x, y, z = string.match(s, "^(-?%d+%.?%d*),(-?%d+%.?%d*),(-?%d+%.?%d*)$")
			if not x then
				return nil, `'{tostring(raw)}' is not an x,y,z vector`
			end
			return Vector3.new(tonumber(x), tonumber(y), tonumber(z)), nil
		end,
		Validate = function(v)
			return typeof(v) == "Vector3" or "expected a Vector3"
		end,
		Autocomplete = function()
			return { "0,0,0" }
		end,
	},
}

-- ---------------------------------------------------------------------------

function Types.new()
	local self = setmetatable({ defs = {} :: { [string]: Definition } }, Types)
	for name, def in BUILTINS do
		self.defs[name] = def
	end
	return self
end

-- Register a custom type (à la Cmdr/Conch DefineType).
function Types:Define(name: string, def: Definition)
	assert(type(name) == "string" and name ~= "", "Karet.DefineType: name must be a non-empty string")
	assert(type(def.Parse) == "function", `Karet.DefineType('{name}'): a Parse function is required`)
	self.defs[name] = def
end

function Types:get(name: string): Definition?
	return self.defs[name]
end

function Types:has(name: string): boolean
	return self.defs[name] ~= nil
end

-- Coerce a raw value against a union of type names. Returns (typedValue, nil) for the
-- first type that parses AND validates, or (nil, lastError) if none do.
function Types:coerce(raw: any, typeNames: { string }): (any, string?)
	local lastErr: string? = "no matching type"
	for _, name in typeNames do
		local def = self.defs[name]
		if not def then
			lastErr = `unknown type '{name}'`
		else
			local value, perr = def.Parse(raw)
			if perr ~= nil or value == nil then
				lastErr = perr or `not a {name}`
			elseif def.Validate then
				local ok = def.Validate(value)
				if ok == true then
					return value, nil
				end
				lastErr = (type(ok) == "string" and ok) or `invalid {name}`
			else
				return value, nil
			end
		end
	end
	return nil, lastErr
end

-- Does a value satisfy a named type? Drives @TYPE[name] guards.
function Types:satisfies(value: any, typeName: string): boolean
	local def = self.defs[typeName]
	if not def then
		return false
	end
	if def.Validate then
		return def.Validate(value) == true
	end
	local _, err = self:coerce(value, { typeName })
	return err == nil
end

-- Autocomplete suggestions for a partial token against a type, or {} if unsupported.
function Types:autocomplete(typeName: string, raw: string): { string }
	local def = self.defs[typeName]
	if def and def.Autocomplete then
		return def.Autocomplete(raw)
	end
	return {}
end

return Types
