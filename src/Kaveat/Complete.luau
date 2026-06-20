-- a practical luau completer for the editor. not a real language server: it offers
-- roblox globals + a curated api + keywords, and scans your buffer for locals, functions
-- and class methods (function Class:method / Class.field =) so your own stuff completes.
-- after a . or : it shows members for known bases, your class methods, else common instance
-- methods.

local Complete = {}

local GLOBALS = {
	"game", "workspace", "script", "Enum", "Instance", "task", "math", "string", "table",
	"os", "wait", "print", "warn", "error", "assert", "pcall", "xpcall", "tick", "typeof",
	"type", "require", "next", "ipairs", "pairs", "select", "tonumber", "tostring", "unpack",
	"setmetatable", "getmetatable", "rawget", "rawset", "newproxy", "coroutine", "utf8",
	"Vector3", "Vector2", "CFrame", "Color3", "UDim2", "UDim", "Ray", "Region3", "TweenInfo",
	"NumberRange", "NumberSequence", "ColorSequence", "BrickColor", "Rect", "Random",
}

local KEYWORDS = {
	"local", "function", "end", "if", "then", "else", "elseif", "for", "in", "do", "while",
	"repeat", "until", "return", "and", "or", "not", "true", "false", "nil", "break", "continue",
}

-- members offered right after base. / base:
local MEMBERS = {
	game = {
		"GetService", "Workspace", "Players", "ReplicatedStorage", "ServerScriptService",
		"ServerStorage", "StarterGui", "Lighting", "SoundService", "Teams", "GetChildren",
		"FindFirstChild", "WaitForChild", "JobId", "PlaceId",
	},
	workspace = { "CurrentCamera", "FindFirstChild", "WaitForChild", "GetChildren", "Raycast", "Gravity" },
	task = { "wait", "spawn", "defer", "delay", "cancel", "synchronize", "desynchronize" },
	Instance = { "new", "fromExisting" },
	Enum = { "KeyCode", "Material", "Font", "UserInputType", "HumanoidStateType", "PartType", "EasingStyle" },
	math = { "floor", "ceil", "abs", "clamp", "min", "max", "random", "huge", "pi", "round", "sqrt", "sin", "cos" },
	string = { "format", "sub", "gsub", "match", "find", "split", "len", "lower", "upper", "rep", "byte", "char" },
	table = { "insert", "remove", "find", "concat", "sort", "clear", "create", "clone", "freeze", "unpack" },
	os = { "time", "clock", "date", "difftime" },
}

-- fallback after any : (we cant infer the type, these cover most instances)
local INSTANCE = {
	"FindFirstChild", "FindFirstChildOfClass", "FindFirstChildWhichIsA", "FindFirstAncestor",
	"WaitForChild", "GetChildren", "GetDescendants", "Clone", "Destroy", "IsA", "Clear",
	"GetAttribute", "SetAttribute", "GetPropertyChangedSignal", "Parent", "Name", "ClassName",
}

export type Suggestion = { text: string, detail: string, insert: string }

local function scan(source: string)
	local locals, funcs = {}, {}
	local classes: { [string]: { string } } = {}
	for name in string.gmatch(source, "local%s+([%a_][%w_]*)") do
		table.insert(locals, name)
	end
	for name in string.gmatch(source, "function%s+([%a_][%w_]*)%s*%(") do
		table.insert(funcs, name)
	end
	for cls, m in string.gmatch(source, "function%s+([%a_][%w_]*)[:.]([%a_][%w_]*)") do
		classes[cls] = classes[cls] or {}
		table.insert(classes[cls], m)
	end
	for cls, f in string.gmatch(source, "([%a_][%w_]*)%.([%a_][%w_]*)%s*=") do
		classes[cls] = classes[cls] or {}
		table.insert(classes[cls], f)
	end
	return locals, funcs, classes
end

-- complete at a cursor position (1-based, the index where the next char goes)
function Complete.complete(source: string, pos: number): { Suggestion }
	local before = string.sub(source, 1, math.max(0, (pos or #source + 1) - 1))
	local out: { Suggestion } = {}
	local locals, funcs, classes = scan(source)

	-- member access: base . word  or  base : word
	local base, sep, word = string.match(before, "([%a_][%w_]*)%s*([:.])%s*([%w_]*)$")
	if base and sep then
		local members = {}
		if MEMBERS[base] then
			for _, m in MEMBERS[base] do
				table.insert(members, m)
			end
		end
		if classes[base] then
			for _, m in classes[base] do
				table.insert(members, m)
			end
		end
		if #members == 0 then
			members = INSTANCE
		end
		local lower = string.lower(word)
		local seen = {}
		for _, m in members do
			if not seen[m] and string.sub(string.lower(m), 1, #lower) == lower then
				seen[m] = true
				table.insert(out, { text = m, detail = sep == ":" and "method" or "member", insert = m })
			end
		end
		return out
	end

	-- plain identifier
	local typed = string.match(before, "([%a_][%w_]*)$")
	if not typed then
		return out
	end
	local lower = string.lower(typed)
	local seen = { [typed] = true }
	local function add(name: string, detail: string)
		if not seen[name] and string.sub(string.lower(name), 1, #lower) == lower then
			seen[name] = true
			table.insert(out, { text = name, detail = detail, insert = name })
		end
	end
	for _, g in GLOBALS do
		add(g, "global")
	end
	for _, s in locals do
		add(s, "local")
	end
	for _, s in funcs do
		add(s, "function")
	end
	for cls in classes do
		add(cls, "class")
	end
	for _, k in KEYWORDS do
		add(k, "keyword")
	end
	return out
end

return Complete
