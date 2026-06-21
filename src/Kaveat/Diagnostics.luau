-- a lightweight, heuristic Luau checker for the editor. it is NOT a full parser - it scans
-- tokens and flags the structural mistakes that bite most often: unbalanced brackets,
-- unterminated strings/comments, and mismatched block keywords (missing / extra `end`,
-- `repeat` without `until`). enough to catch a typo before you ship a kav to the server.
--
-- pure (no roblox), so it's unit-tested headlessly and reused by the editor's :check.

local Diagnostics = {}

export type Diagnostic = { line: number, message: string, severity: string }

-- block openers that each need a matching `end`. for/while/repeat are handled implicitly:
-- `for`/`while` are closed by the `do` they introduce, `repeat` by its `until`.
local OPENERS = { ["function"] = true, ["if"] = true, ["do"] = true }
local CLOSE = { [")"] = "(", ["]"] = "[", ["}"] = "{" }

local function isAlpha(b: number): boolean
	return (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95
end
local function isAlnum(b: number): boolean
	return isAlpha(b) or (b >= 48 and b <= 57)
end

-- check `source`, returning diagnostics sorted by line. empty list = looks structurally ok.
function Diagnostics.check(source: string): { Diagnostic }
	local diags: { Diagnostic } = {}
	local function add(line: number, message: string, severity: string?)
		table.insert(diags, { line = line, message = message, severity = severity or "error" })
	end

	local i, n = 1, #source
	local line = 1
	local depth = 0 -- function/if/do nesting
	local repeats = 0 -- repeat/until nesting
	local stack: { { char: string, line: number } } = {}

	local function sub(a: number, b: number): string
		return string.sub(source, a, b)
	end

	-- at a '[', return its long-bracket level (number of '=') if it opens one, else nil
	local function longLevel(idx: number): number?
		local j = idx + 1
		local eqs = 0
		while sub(j, j) == "=" do
			eqs += 1
			j += 1
		end
		if sub(j, j) == "[" then
			return eqs
		end
		return nil
	end

	-- skip a long bracket ([[ ... ]] / [=[ ... ]=]); i sits on the opening '['
	local function skipLong(level: number, what: string)
		local startLine = line
		i += level + 2
		local close = "]" .. string.rep("=", level) .. "]"
		while i <= n do
			local ch = sub(i, i)
			if ch == "\n" then
				line += 1
				i += 1
			elseif ch == "]" and sub(i, i + #close - 1) == close then
				i += #close
				return
			else
				i += 1
			end
		end
		add(startLine, "unterminated " .. what)
	end

	-- skip a short string; i sits on the opening quote
	local function skipShort(q: string)
		local startLine = line
		i += 1
		while i <= n do
			local ch = sub(i, i)
			if ch == "\\" then
				if sub(i + 1, i + 1) == "\n" then
					line += 1
				end
				i += 2
			elseif ch == q then
				i += 1
				return
			elseif ch == "\n" then
				add(startLine, "unterminated string")
				return -- leave the newline for the main loop to count
			else
				i += 1
			end
		end
		add(startLine, "unterminated string")
	end

	while i <= n do
		local c = sub(i, i)
		if c == "\n" then
			line += 1
			i += 1
		elseif c == "-" and sub(i + 1, i + 1) == "-" then
			i += 2
			local lvl = sub(i, i) == "[" and longLevel(i) or nil
			if lvl ~= nil then
				skipLong(lvl, "long comment")
			else
				while i <= n and sub(i, i) ~= "\n" do
					i += 1
				end
			end
		elseif c == '"' or c == "'" then
			skipShort(c)
		elseif c == "[" and longLevel(i) ~= nil then
			skipLong(longLevel(i) :: number, "long string")
		elseif isAlpha(string.byte(source, i)) then
			local j = i
			while j <= n and isAlnum(string.byte(source, j)) do
				j += 1
			end
			local word = sub(i, j - 1)
			if OPENERS[word] then
				depth += 1
			elseif word == "end" then
				depth -= 1
				if depth < 0 then
					add(line, "unexpected 'end'")
					depth = 0
				end
			elseif word == "repeat" then
				repeats += 1
			elseif word == "until" then
				repeats -= 1
				if repeats < 0 then
					add(line, "'until' without 'repeat'")
					repeats = 0
				end
			end
			i = j
		elseif c == "(" or c == "[" or c == "{" then
			table.insert(stack, { char = c, line = line })
			i += 1
		elseif c == ")" or c == "]" or c == "}" then
			local top = stack[#stack]
			if not top then
				add(line, `unexpected '{c}'`)
			elseif top.char ~= CLOSE[c] then
				add(line, `'{c}' doesn't match '{top.char}' opened on line {top.line}`)
				table.remove(stack)
			else
				table.remove(stack)
			end
			i += 1
		else
			i += 1
		end
	end

	for _, open in stack do
		add(open.line, `unclosed '{open.char}'`)
	end
	if depth > 0 then
		add(line, `{depth} block{depth == 1 and "" or "s"} left open (missing 'end')`)
	end
	if repeats > 0 then
		add(line, "'repeat' without 'until'")
	end

	table.sort(diags, function(a, b)
		return a.line < b.line
	end)
	return diags
end

return Diagnostics
