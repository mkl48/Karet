-- works out what to suggest for the current line, plus the signature of the command
-- youre typing and whether a word is a real command (for colouring). give it the
-- registry + types, get back { suggest, signature, isCommand }.
-- v1 is whitespace based, works on the last command in the line.

local Complete = {}

-- the bit after the last chain op / newline, thats the command were on
local function lastSegment(text: string): string
	local cut = 0
	for _, pat in { "&&", "||", "&", ";", "\n" } do
		local s = 1
		while true do
			local i = string.find(text, pat, s, true)
			if not i then
				break
			end
			cut = math.max(cut, i + #pat - 1)
			s = i + 1
		end
	end
	return string.sub(text, cut + 1)
end

local function tokens(seg: string): { string }
	local out = {}
	for word in string.gmatch(seg, "%S+") do
		table.insert(out, word)
	end
	return out
end

export type Suggestion = { text: string, detail: string, insert: string }
export type Signature = { name: string, args: { { label: string, current: boolean } } }

function Complete.build(registry: any, types: any)
	local function suggest(text: string): { Suggestion }
		local seg = lastSegment(text)
		local words = tokens(seg)
		local trailingSpace = string.match(seg, "%s$") ~= nil
		local out: { Suggestion } = {}

		if #words == 0 then
			return out
		end

		if #words == 1 and not trailingSpace then
			local prefix = string.lower(words[1])
			for _, name in registry:list() do
				if string.sub(string.lower(name), 1, #prefix) == prefix then
					local def = registry:get(name)
					table.insert(out, { text = name, detail = (def and def.Description) or "", insert = name })
				end
			end
			return out
		end

		local def = registry:get(words[1])
		if not def then
			return out
		end
		local partial = trailingSpace and "" or words[#words]

		if string.sub(partial, 1, 1) == "-" then
			local p = string.lower((string.gsub(partial, "^%-+", "")))
			for _, attr in def.Attributes or {} do
				local short = attr.Short
				if string.sub(string.lower(attr.Name), 1, #p) == p or (short and string.lower(short) == p) then
					local flag = "-" .. (short or attr.Name)
					table.insert(out, { text = flag, detail = attr.Description or attr.Name, insert = flag })
				end
			end
			return out
		end

		local argIndex = (#words - 1) + (trailingSpace and 1 or 0)
		local spec = (def.Args or {})[argIndex]
		if spec then
			local lower = string.lower(partial)
			for _, typeName in spec.Types do
				for _, s in types:autocomplete(typeName, partial) do
					if string.sub(string.lower(s), 1, #lower) == lower then
						table.insert(out, { text = s, detail = typeName, insert = s })
					end
				end
			end
		end
		return out
	end

	-- which command + arg youre on right now, nil if the first word isnt a command
	local function signature(text: string): Signature?
		local seg = lastSegment(text)
		local words = tokens(seg)
		if #words == 0 then
			return nil
		end
		local def = registry:get(words[1])
		if not def then
			return nil
		end
		local trailingSpace = string.match(seg, "%s$") ~= nil
		local argIndex = (#words - 1) + (trailingSpace and 1 or 0)
		local args = {}
		for i, spec in def.Args or {} do
			local req = spec.Required and "" or "?"
			table.insert(args, {
				label = `{spec.Name}: {table.concat(spec.Types, "|")}{req}`,
				current = i == argIndex,
			})
		end
		return { name = def.Name, args = args }
	end

	local function isCommand(word: string): boolean
		return registry:get(word) ~= nil
	end

	return { suggest = suggest, signature = signature, isCommand = isCommand }
end

return Complete
