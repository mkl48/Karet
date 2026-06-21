-- pure helpers for the input pickers: fuzzy matching (command palette) and reverse history
-- search (ctrl+r). no roblox in here so it gets unit tested. the actual overlay lives in Input.

local Search = {}

-- subsequence fuzzy match: do all of `query`s chars appear in `text` in order? returns a
-- score (higher is better) or nil for no match. consecutive runs and a hit on the very first
-- char score extra, and shorter candidates edge ahead on a tie.
function Search.fuzzy(query: string, text: string): number?
	if query == "" then
		return 0
	end
	local q = string.lower(query)
	local t = string.lower(text)
	local qi = 1
	local score = 0
	local streak = 0
	local prev = -2
	for ti = 1, #t do
		if qi > #q then
			break
		end
		if string.sub(t, ti, ti) == string.sub(q, qi, qi) then
			if ti == prev + 1 then
				streak += 1
			else
				streak = 0
			end
			score += 10 + streak * 5
			if ti == 1 then
				score += 15
			end
			prev = ti
			qi += 1
		end
	end
	if qi <= #q then
		return nil -- ran out of text before matching every query char
	end
	return score - #t * 0.1
end

-- rank `items` by fuzzy score against `query`, dropping non-matches. `key` pulls the string
-- to match from each item (defaults to the item itself). stable on ties by that string.
function Search.rank<T>(query: string, items: { T }, key: ((T) -> string)?): { T }
	local function textOf(item: T): string
		return key and key(item) or (item :: any)
	end
	local scored = {}
	for _, item in items do
		local s = Search.fuzzy(query, textOf(item))
		if s ~= nil then
			table.insert(scored, { item = item, score = s, text = textOf(item) })
		end
	end
	table.sort(scored, function(a, b)
		if a.score == b.score then
			return a.text < b.text
		end
		return a.score > b.score
	end)
	local out = {}
	for _, s in scored do
		table.insert(out, s.item)
	end
	return out
end

-- reverse history search: the `occurrence`th most-recent line that contains `query` as a
-- case-insensitive substring. occurrence is 1-based. returns (line, index) or nil.
function Search.history(history: { string }, query: string, occurrence: number?): (string?, number?)
	local want = math.max(1, occurrence or 1)
	local q = string.lower(query)
	local seen = 0
	for i = #history, 1, -1 do
		local line = history[i]
		if q == "" or string.find(string.lower(line), q, 1, true) then
			seen += 1
			if seen == want then
				return line, i
			end
		end
	end
	return nil, nil
end

return Search
