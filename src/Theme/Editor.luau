-- the live theme editor panel. opens an Iris window full of colour pickers for the active
-- palette; edits apply to the whole UI in real time (every surface subscribes to Theme), and
-- you can save the result as a named theme that sticks on your profile.
--
-- Editor.panel(Karet) returns a panel def for the extension platform (open it with: open theme).

local Editor = {}

-- the groups worth hand-editing. the rest of the palette (Cursor, Prompt, Ghost, ...) is
-- re-derived from these by Theme.derive, so a handful of colours still yields a full theme.
local GROUPS = {
	"Background",
	"Surface",
	"Foreground",
	"Muted",
	"Border",
	"Selection",
	"Accent",
	"AccentAlt",
	"Comment",
	"String",
	"Number",
	"Keyword",
	"Function",
	"Type",
	"Operator",
	"Error",
	"Warn",
	"Info",
	"Success",
}

function Editor.panel(Karet: any): any
	return {
		Name = "theme",
		Description = "live theme editor (colour pickers, save as your own)",
		Open = function(ctx: any)
			local Theme = Karet.Theme
			-- full active palette, our starting point and what unedited groups keep
			local current = Theme.Get()

			local w = ctx.Window({ title = "theme editor" })
			w:Label("edit colours - the whole UI recolours live")
			w:Separator()

			local pickers: { [string]: any } = {}
			for _, g in GROUPS do
				pickers[g] = w:Color(g, current[g])
			end

			w:Separator()
			local nameField = w:Input("save as", Theme.Name() or "custom")

			-- build the palette = the original (so unedited groups survive) overridden with the
			-- picker values
			local function build(): { [string]: Color3 }
				local p = table.clone(current)
				for _, g in GROUPS do
					p[g] = pickers[g].get()
				end
				return p
			end

			-- apply on change. OnRender runs each frame while the window is open; we only push a
			-- Theme.Set when an edited colour actually moved, so it's cheap and doesn't loop.
			local lastApplied: { [string]: Color3 }? = nil
			w:OnRender(function()
				local changed = lastApplied == nil
				if not changed then
					for _, g in GROUPS do
						if pickers[g].get() ~= lastApplied[g] then
							changed = true
							break
						end
					end
				end
				if changed then
					local p = build()
					lastApplied = p
					Theme.Set(p)
				end
			end)

			w:Separator()
			w:Button("save & apply", function()
				local name = nameField.get()
				if name == "" then
					name = "custom"
				end
				Theme.Define(name, build())
				Theme.Set(name)
				Karet.Profile.CurrentTheme = name
				if Karet.Toast then
					Karet.Toast(`saved theme '{name}'`, { group = "Success", title = "theme" })
				end
			end)
			w:Button("reset", function()
				for _, g in GROUPS do
					pickers[g].set(current[g])
				end
				lastApplied = nil
				Theme.Set(current)
			end)
			w:Button("close", function()
				w:Close()
			end)
		end,
	}
end

return Editor
