-- Tiny declarative Instance builder for the terminal UI.
--
-- create("Frame", { Size = ..., Children = { ... }, Parent = ... }) sets every property,
-- parents any Children, then parents the instance itself LAST (so the engine isn't
-- reflowing a live tree as each child is added). Two reserved keys: `Children` (an array
-- of instances to parent into this one) and `Parent` (applied last).

local RESERVED = { Children = true, Parent = true }

local function create(className: string, props: { [string]: any }?): Instance
	local inst = Instance.new(className)
	local p = props or {}
	for key, value in p do
		if not RESERVED[key] then
			(inst :: any)[key] = value
		end
	end
	if p.Children then
		for _, child in p.Children do
			child.Parent = inst
		end
	end
	if p.Parent then
		inst.Parent = p.Parent
	end
	return inst
end

return create
