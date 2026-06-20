-- a profile holds the per user stuff, history, the theme they picked, saved kav scripts
-- and any custom commands. its just in memory for now, can hook it to a datastore later

local Profile = {}
Profile.__index = Profile

export type Profile = {
	Name: string,
	Commands: { [string]: any },
	CurrentTheme: string,
	History: { string },
	Kavs: { [string]: string },
}

function Profile.new(name: string?): Profile
	return setmetatable({
		Name = name or "default",
		Commands = {},
		CurrentTheme = "",
		History = {},
		Kavs = {},
	}, Profile) :: any
end

return Profile
