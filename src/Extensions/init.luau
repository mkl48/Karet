-- Extensions - the plugin registry that turns Karet from a fixed set of tools into a
-- platform. an extension bundles commands, types, and dockable panels under a name; a panel
-- is a named view that opens into the shell (typically an Iris window via ctx.Window). the
-- umbrella wires Commands/Types into the real registries; this module just tracks the panels
-- and the extension metadata so `panels` / `open` / `extensions` can list and launch them.
--
-- Pure (no Roblox), so it's headless-testable.

local Extensions = {}
Extensions.__index = Extensions

local function key(name: string): string
	return string.lower(tostring(name))
end

export type Panel = {
	Name: string,
	Description: string?,
	Open: (ctx: any) -> (), -- called with the command ctx; usually builds a ctx.Window
}

export type Extension = {
	Name: string,
	Description: string?,
	Commands: { any }?,
	Types: { [string]: any }?,
	Panels: { Panel }?,
	Init: ((karet: any) -> ())?,
}

function Extensions.new()
	return setmetatable({
		panels = {} :: { [string]: Panel },
		extensions = {} :: { [string]: any },
	}, Extensions)
end

function Extensions:registerPanel(panel: Panel): Panel
	assert(type(panel) == "table", "Karet.RegisterPanel: expected a table")
	assert(type(panel.Name) == "string" and panel.Name ~= "", "Karet.RegisterPanel: a panel needs a Name")
	assert(type(panel.Open) == "function", `Karet.RegisterPanel('{panel.Name}'): a panel needs an Open function`)
	self.panels[key(panel.Name)] = panel
	return panel
end

function Extensions:getPanel(name: string): Panel?
	return self.panels[key(name)]
end

function Extensions:listPanels(): { Panel }
	local out = {}
	for _, panel in self.panels do
		table.insert(out, panel)
	end
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end

-- Record an extension's metadata (after its commands/types/panels were wired by the umbrella).
function Extensions:addExtension(meta: any)
	self.extensions[key(meta.Name)] = meta
end

function Extensions:listExtensions(): { any }
	local out = {}
	for _, ext in self.extensions do
		table.insert(out, ext)
	end
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end

return Extensions
