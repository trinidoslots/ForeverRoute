-- Import: add a guide by pasting its text (RestedXP's plain text format: #name,
-- step, .goto, .accept ...). Imported guides are kept in the settings
-- (ForeverRouteDB.imports), registered again at every login and listed under
-- "Imported guides". The text is read by ForeverRoute's own parser only; no Lua
-- in it is ever run. (RestedXP's encoded guide bundles are not supported.)
local _, ns = ...
local FR = ns.FR

FR.IMPORT_GROUP = "Imported guides"

-- Pasted text -> guide text: optional "X.RegisterGuide([[ ... ]])" wrapper off,
-- the game version tag and the group set by us. The guide's own group is dropped,
-- except a group starting with "+": that marks a farming guide (gold mode) and stays.
-- Returns the text and the group it ends up in.
local function Prepare(raw)
	local text = raw:gsub("\r\n", "\n"):gsub("\r", "\n")
	local inner = text:match("RegisterGuide%(%s*%[=*%[(.-)%]=*%]%s*%)")
	if inner then text = inner end
	-- Does the header name a farming group?
	local group = FR.IMPORT_GROUP
	for line in (text .. "\n"):gmatch("(.-)\n") do
		local t = line:match("^%s*(.-)%s*$")
		if t:sub(1, 4) == "step" then break end
		local own = t:match("^#group%s+(%+.+)$")
		if own then group = (own:gsub("%s*<<.*$", "")) break end
	end
	local out, header = { "#forever", "#group " .. group }, true
	for line in (text .. "\n"):gmatch("(.-)\n") do
		local t = line:match("^%s*(.-)%s*$")
		if t:sub(1, 4) == "step" then header = false end
		if not (header and (t == "#group" or t:match("^#group%s"))) then out[#out + 1] = line end
	end
	return table.concat(out, "\n"), group
end

-- The name from the header, to find an earlier import of the same guide.
local function HeaderName(text)
	for line in text:gmatch("[^\n]+") do
		local t = line:match("^%s*(.-)%s*$")
		if t:sub(1, 4) == "step" then return nil end
		local name = t:match("^#name%s+(.+)$")
		if name then return (name:gsub("%s*<<.*$", "")) end
	end
end

-- Registers prepared text as a guide with this player's language. Returns the guide or nil and why.
local function Register(text)
	local prevLocale, prevFile = FR.loadingLocale, FR.guideFile
	FR.loadingLocale, FR.guideFile = FR:Language(), nil   -- not a file of ours: nothing to pair
	local ok, g, reason = pcall(FR.RegisterGuide, text)
	FR.loadingLocale, FR.guideFile = prevLocale, prevFile
	if not ok then return nil, tostring(g) end
	if g then g.imported = true end
	return g, reason
end

-- Adds a guide from pasted text. Returns the guide, or nil and a reason (already translated).
function FR:ImportGuideText(raw)
	local L = FR.L
	if type(raw) ~= "string" or raw:match("^%s*$") then return nil, L["There is no text to import."] end
	local text, group = Prepare(raw)
	local name = HeaderName(text)
	if not name then return nil, L["The guide has no #name line."] end

	-- The same guide again replaces the earlier import.
	local old = self.guidesByTitle[group .. "\\" .. name]
	if old and old.imported then self:UnregisterGuide(old) end

	local g, reason = Register(text)
	if not g then
		if reason == "already there" then return nil, L["A guide with this name already exists."] end
		return nil, reason or L["The guide could not be read."]
	end
	-- It has to read: at least one step, and no error while reading.
	local ok, steps = pcall(self.ParseGuide, self, g)
	if not ok or type(steps) ~= "table" or #steps == 0 then
		self:UnregisterGuide(g)
		return nil, ok and L["The guide has no steps."] or tostring(steps)
	end

	ForeverRouteDB.imports = ForeverRouteDB.imports or {}
	ForeverRouteDB.imports[g.title] = text
	return g
end

-- Registers the saved imports (at login, before the saved guide is opened).
function FR:LoadImports()
	local list = ForeverRouteDB and ForeverRouteDB.imports
	if not list then return end
	local titles = {}
	for title in pairs(list) do titles[#titles + 1] = title end
	table.sort(titles)   -- the same order every time
	for _, title in ipairs(titles) do Register(list[title]) end
end

function FR:ConfirmDeleteImport(g)
	self:Confirm(string.format(FR.L["Delete the imported guide %s?"], tostring(g.short)), function()
		FR:UnregisterGuide(g)
	end)
end

function FR:OpenImport()
	local L = FR.L
	FR.TextWindow({
		name = "Import",
		title = L["Import guide"],
		hint = L["Paste a guide in RestedXP's text format (#name, step, .goto, .accept ...) and click Import. It is saved and listed under Imported guides."],
		text = "",
		focus = true,
		acceptLabel = L["Import"],
		onAccept = function(text)
			local g, reason = FR:ImportGuideText(text)
			if not g then
				FR:Print(string.format(L["Import failed: %s"], tostring(reason)))
				return false
			end
			FR:Print(string.format(L["Imported: %s"], tostring(g.short)))
			FR:SetGuide(g.title, 1)
			FR:SetShown(true)
			return true
		end,
	})
end
