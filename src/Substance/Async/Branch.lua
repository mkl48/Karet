-- Substance
-- Async/Branch.lua
-- Plinko Labs

export type BranchTable = {[string]: (any) -> any}

local Branch = {}

function Branch.Resolve(value: any, table: BranchTable): any
	if type(value) == "string" and table[value] then
		return table[value](value)
	end

	if type(value) == "table" and type(value.Branch) == "string" and table[value.Branch] then
		return table[value.Branch](value)
	end

	if table.Default then
		return table.Default(value)
	end

	return nil
end

return Branch
