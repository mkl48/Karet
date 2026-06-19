-- Minimal test harness: register tests, run them under pcall, collect failures.

export type Registrar = {
	passed: number,
	failed: number,
	failures: { { name: string, err: any } },
	test: (name: string, fn: () -> ()) -> (),
}

local Harness = {}

function Harness.new(): Registrar
	local self: Registrar = {
		passed = 0,
		failed = 0,
		failures = {},
		test = function() end,
	}
	self.test = function(name, fn)
		local ok, err = pcall(fn)
		if ok then
			self.passed += 1
		else
			self.failed += 1
			table.insert(self.failures, { name = name, err = err })
		end
	end
	return self
end

return Harness
