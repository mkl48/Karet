-- Alias - leading-word command aliases. `alias ll commands` makes `ll` expand to `commands`
-- before the line is parsed, so `ll -a` becomes `commands -a`. Expansion is recursive (an
-- alias can point at another alias) with a depth cap so a cycle can't hang the shell.
--
-- Pure (no Roblox), so it's shared by the terminal submit path and the `run` service and is
-- headless-testable. Only the FIRST word of the line is expanded (v1).

local Alias = {}

-- Expand a leading alias in `line` against the `aliases` map. Returns the expanded line
-- (unchanged if the first word isn't an alias).
function Alias.expand(line: string, aliases: { [string]: string }?, depth: number?): string
	if not aliases then
		return line
	end
	depth = depth or 0
	if depth > 16 then
		return line -- cycle guard
	end
	local lead, word, rest = string.match(line, "^(%s*)(%S+)(.*)$")
	if not word then
		return line
	end
	local replacement = aliases[word]
	if replacement == nil then
		return line
	end
	return Alias.expand(lead .. replacement .. rest, aliases, depth + 1)
end

return Alias
