-- Prompt - the dangerous-command confirmation in "window" mode (Iris). The terminal handles
-- the "text" mode itself (Terminal:promptText); this is the graphical y/n modal.
--
-- Iris is immediate-mode, so we Init once, keep a single pending question in module state,
-- and a connected render fn draws the modal whenever something is pending. Prompt.window()
-- parks the calling thread until a button resolves it. Client-only (Iris is client-only);
-- callers should fall back to text mode when Prompt.available() is false.

local deps = require(script.Parent.deps)

local Prompt = {}

local iris: any = nil
local started = false
local pending: { question: string, resolve: (boolean) -> () }? = nil

-- Is the Iris dependency present? (lets the caller pick text mode when it isn't)
function Prompt.available(): boolean
	return deps.Iris() ~= nil
end

local function render()
	if not pending then
		return
	end
	local q = pending
	local ok = pcall(function()
		-- no close/collapse, so the only way out is a button (otherwise the command hangs)
		local args = iris.Args.Window
		iris.Window({ "Karet", [args.NoClose] = true, [args.NoCollapse] = true })
		iris.Text({ q.question })
		iris.Text({ "" })
		iris.SameLine()
		local yes = iris.Button({ "Yes" })
		local no = iris.Button({ "No, cancel" })
		iris.End()
		iris.End()
		-- resolve once, after the row is built, so both handles are valid
		if yes.clicked() then
			pending = nil
			q.resolve(true)
		elseif no.clicked() then
			pending = nil
			q.resolve(false)
		end
	end)
	if not ok and pending then
		-- if Iris blew up, don't hang the command forever
		pending = nil
		q.resolve(false)
	end
end

local function ensureStarted(parent: Instance?)
	if started then
		return
	end
	iris = deps.Iris()
	-- allowMultipleInits = true so we never error if the host game also uses Iris
	pcall(iris.Init, parent, nil, true)
	iris:Connect(render)
	started = true
end

-- Show a yes/no modal and yield until the user answers. Returns true only on "Yes".
function Prompt.window(question: string, parent: Instance?): boolean
	if not Prompt.available() then
		return true -- no Iris: treat as confirmed rather than blocking the command
	end
	ensureStarted(parent)
	local thread = coroutine.running()
	pending = {
		question = question,
		resolve = function(v: boolean)
			task.spawn(thread, v)
		end,
	}
	return coroutine.yield()
end

return Prompt
