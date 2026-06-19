local loader = require("./loader")
local Assert = require("./assert")

local ReturnPool = loader.get("ReturnPool")

return function(t)
	t.test("// resolves the last return; #n walks back", function()
		local pool = ReturnPool.new()
		pool:push(1, "Number", nil, "a")
		pool:push(2, "Number", nil, "b")
		pool:push(3, "Number", nil, "c")
		Assert.eq((pool:resolve({ last = true, path = {} })), 3, "// is newest")
		Assert.eq((pool:resolve({ last = true, index = 2, path = {} })), 2, "//#2")
		Assert.eq((pool:resolve({ last = true, index = 3, path = {} })), 1, "//#3")
	end)

	t.test("/Type matches by type, most recent first", function()
		local pool = ReturnPool.new()
		pool:push({ UserId = 10 }, "Player", nil, "GetPlayer")
		pool:push(500, "Number", nil, "Count")
		pool:push({ UserId = 20 }, "Player", nil, "GetPlayer")
		local v = pool:resolve({ name = "Player", path = {} })
		Assert.eq(v.UserId, 20, "newest Player")
		local v2 = pool:resolve({ name = "Player", index = 2, path = {} })
		Assert.eq(v2.UserId, 10, "/Player#2 is the older one")
	end)

	t.test("label wins over type on a name clash", function()
		local pool = ReturnPool.new()
		pool:push({ UserId = 1 }, "Player", "Player", "x") -- label literally "Player"
		pool:push({ UserId = 2 }, "Player", "target", "y")
		-- /target -> by label
		Assert.eq((pool:resolve({ name = "target", path = {} })).UserId, 2, "/target by label")
		-- /Player -> there IS a record whose label == "Player", so label wins
		Assert.eq((pool:resolve({ name = "Player", path = {} })).UserId, 1, "/Player prefers label")
	end)

	t.test("property path access", function()
		local pool = ReturnPool.new()
		pool:push({ UserId = 42, Data = { Coins = 7 } }, "Player", "target", "GetPlayer")
		Assert.eq((pool:resolve({ name = "target", path = { "UserId" } })), 42, "/target.UserId")
		Assert.eq((pool:resolve({ last = true, path = { "Data", "Coins" } })), 7, "//.Data.Coins")
	end)

	t.test("missing return and bad index report errors", function()
		local pool = ReturnPool.new()
		local v, err = pool:resolve({ name = "Player", path = {} })
		Assert.eq(v, nil, "no value")
		Assert.truthy(err, "error message for missing return")

		pool:push(5, "Number", nil, "n")
		local _, err2 = pool:resolve({ last = true, path = { "Nope", "Deep" } })
		Assert.truthy(err2, "error reading property of nil")
	end)
end
