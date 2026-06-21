-- the pure picker helpers: fuzzy matching (command palette) + reverse history search (ctrl+r)

local fw = require("./fwloader")
local Assert = require("./assert")

local Search = fw.get("Search")

return function(t)
	t.test("fuzzy matches a subsequence, rejects a miss", function()
		Assert.truthy(Search.fuzzy("wsp", "walkspeed") ~= nil, "subsequence matches")
		Assert.eq(Search.fuzzy("xyz", "walkspeed"), nil, "no match returns nil")
	end)

	t.test("empty query matches everything with a flat score", function()
		Assert.eq(Search.fuzzy("", "anything"), 0, "empty query scores 0")
	end)

	t.test("a prefix / consecutive match outscores a scattered one", function()
		local prefix = Search.fuzzy("wal", "walkspeed")
		local scattered = Search.fuzzy("wal", "wXaXl")
		Assert.truthy(prefix ~= nil and scattered ~= nil, "both match")
		Assert.truthy(prefix > scattered, "consecutive beats scattered")
	end)

	t.test("rank sorts by score and drops non-matches", function()
		local items = { "theme", "themes", "time", "ban" }
		local ranked = Search.rank("the", items)
		Assert.truthy(#ranked == 2, "only the two 'the' items survive")
		Assert.eq(ranked[1], "theme", "shorter exact-ish match first")
	end)

	t.test("rank can pull the match key from a table", function()
		local items = { { name = "walkspeed" }, { name = "jump" } }
		local ranked = Search.rank("ws", items, function(it)
			return it.name
		end)
		Assert.eq(ranked[1].name, "walkspeed", "matched by name field")
	end)

	t.test("history search walks back to the most recent match", function()
		local hist = { "echo a", "ban bob", "echo b", "kick joe", "echo c" }
		local line, idx = Search.history(hist, "echo", 1)
		Assert.eq(line, "echo c", "most recent echo")
		Assert.eq(idx, 5, "its index")
	end)

	t.test("history occurrence cycles to older matches", function()
		local hist = { "echo a", "ban bob", "echo b", "kick joe", "echo c" }
		Assert.eq((Search.history(hist, "echo", 2)), "echo b", "second most recent")
		Assert.eq((Search.history(hist, "echo", 3)), "echo a", "third")
		Assert.eq((Search.history(hist, "echo", 4)), nil, "past the end is nil")
	end)

	t.test("history search is case insensitive and substring based", function()
		local hist = { "Ban Bob", "echo hi" }
		Assert.eq((Search.history(hist, "ban", 1)), "Ban Bob", "case folded substring")
	end)
end
