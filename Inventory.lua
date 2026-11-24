-- Inventory Manager, after RestedXP's: finds junk in the bags and can show it (a coin on the item), sell it
-- when a vendor window opens, delete the cheapest piece when every bag is full, and lets you mark items as
-- junk / useful yourself (modified right click). Everything is off unless "Enable Inventory Manager" is on,
-- and each part has its own switch (Settings > Inventory).
--
-- Junk = grey items, plus the items you marked, minus the ones you marked as useful (ForeverRouteCharDB.discardPile:
-- [itemID] = true junk / false useful). Never junk: the Hearthstone. Not ported from RestedXP: ammo sorting,
-- auto-opening containers, the delete key binding, net worth.
local _, ns = ...
local FR = ns.FR
local Bag = FR.Bag

local SOUL_SHARD = 6265
local COIN = "Interface\\Icons\\INV_Misc_Coin_01"
local POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
local exceptions = { [6196] = true }                     -- grey, but not junk
local exclusions = { [6948] = true, [184871] = true, [260221] = true }   -- Hearthstone and friends: never junk

local function On() return ForeverRouteDB ~= nil and FR:Get("enableInventoryManager") and true or false end
FR.InventoryManagerOn = On

local function Pile(create)
	local db = ForeverRouteCharDB
	if not db then return nil end
	if create and not db.discardPile then db.discardPile = {} end
	return db.discardPile
end

local function Money(copper)
	return GetCoinTextureString and GetCoinTextureString(copper) or (tostring(copper) .. "c")
end

-- Junk -------------------------------------------------------------------------------------------------

-- Soul shards (one to a slot) in the bags before this slot: the ones past the maximum are junk.
local function ShardsBefore(bag, slot)
	local n = 0
	for b = Bag.FIRST, Bag.LAST do
		local last = (b == bag) and (slot - 1) or Bag.Slots(b)
		for s = 1, last do
			if Bag.ItemID(b, s) == SOUL_SHARD then n = n + 1 end
		end
		if b == bag then break end
	end
	return n
end

function FR.IsJunk(id, bag, slot)
	if not On() or not id then return false end
	if id == SOUL_SHARD then
		if not (bag and slot) then return false end
		local _, kind = Bag.Free(bag)
		if bit and bit.band(kind or 0, 0x4) ~= 0 then return false end   -- a soul bag
		return ShardsBefore(bag, slot) >= (tonumber(FR:Get("maxSoulShards")) or 100)
	end
	if exclusions[id] then return false end
	local pile = Pile()
	local marked = pile and pile[id]
	if marked ~= nil then return marked and true or false end
	local _, _, quality = GetItemInfo(id)
	return quality == POOR and not exceptions[id]
end

local function RefreshBaganator()
	local api = _G.Baganator and _G.Baganator.API
	if api and api.RequestItemButtonsRefresh then pcall(api.RequestItemButtonsRefresh) end
end

local function Toggle(id, bag, slot)
	if not On() or not id or exclusions[id] then return end
	local junk = FR.IsJunk(id, bag, slot)
	local pile = Pile(true)
	if not pile then return end
	pile[id] = not junk
	FR:Print(string.format(FR.L[junk and "Set %s as useful" or "Set %s as junk"], Bag.ItemLink(id)))
	FR:RefreshJunkIcons()
end

function FR:ResetJunk()
	if ForeverRouteCharDB then ForeverRouteCharDB.discardPile = {} end
	self:RefreshJunkIcons()
	self:Print(FR.L["The junk list was reset."])
end

-- The items you marked, and what junk the bags hold (for /fr junk).
function FR:PrintJunk()
	local junk, useful = {}, {}
	for id, v in pairs(Pile() or {}) do
		local list = v and junk or useful
		list[#list + 1] = Bag.ItemLink(id)
	end
	self:Print(string.format("%s: %s", FR.L["Marked as junk"], #junk > 0 and table.concat(junk, ", ") or "-"))
	self:Print(string.format("%s: %s", FR.L["Marked as useful"], #useful > 0 and table.concat(useful, ", ") or "-"))
	local items, value = 0, 0
	for bag = Bag.FIRST, Bag.LAST do
		for slot = 1, Bag.Slots(bag) do
			local id = Bag.ItemID(bag, slot)
			if id and FR.IsJunk(id, bag, slot) then
				local count = Bag.ItemInfo(bag, slot) or 1
				local price = select(11, GetItemInfo(id))
				items = items + count
				if type(price) == "number" then value = value + price * count end
			end
		end
	end
	self:Print(string.format(FR.L["Junk in your bags: %d items, worth %s"], items, Money(value)))
	if not On() then self:Print(FR.L["The Inventory Manager is off (Settings > Inventory)."]) end
end

-- The coin on junk items, and the modified right click ---------------------------------------------------

local hookedButtons, hookedFrames = {}, {}

local function ModifierDown()
	local mod = FR:Get("rightClickMod")
	local ctrl = IsControlKeyDown and IsControlKeyDown()
	local alt = IsAltKeyDown and IsAltKeyDown()
	if mod == "ALT" then return alt and not ctrl end
	if mod == "CTRL+ALT" then return ctrl and alt end
	return ctrl and not alt
end

local function ButtonLocation(button)
	local bag = button.GetBagID and button:GetBagID()
	local slot = button.GetID and button:GetID()
	if not bag then
		local parent = button:GetParent()
		bag = parent and parent.GetID and parent:GetID()
	end
	return bag, slot
end

local function OnItemClick(button, mouse)
	if mouse ~= "RightButton" or not On() or not FR:Get("rightClickJunk") or not ModifierDown() then return end
	local bag, slot = ButtonLocation(button)
	if type(bag) ~= "number" or type(slot) ~= "number" then return end
	Toggle(Bag.ItemID(bag, slot), bag, slot)
end

local function UpdateButton(button)
	local bag, slot = ButtonLocation(button)
	if type(bag) ~= "number" or type(slot) ~= "number" or bag < Bag.FIRST or bag > Bag.LAST or slot < 1 then return end
	if not hookedButtons[button] and button.HookScript then
		hookedButtons[button] = true
		button:HookScript("OnClick", OnItemClick)
	end
	local show = On() and FR:Get("showJunkIcon") and FR.IsJunk(Bag.ItemID(bag, slot), bag, slot)
	if show then
		if not button.FRJunk then
			local t = button:CreateTexture(nil, "OVERLAY")
			t:SetTexture(COIN)
			t:SetSize(16, 16)
			t:SetPoint("TOPLEFT", 1, -1)
			button.FRJunk = t
		end
		button.FRJunk:Show()
	elseif button.FRJunk then
		button.FRJunk:Hide()
	end
end

local function UpdateFrame(frame)
	if not (frame and frame.GetChildren) then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		if child.GetID and (child.GetBagID or child.OnClick) then pcall(UpdateButton, child) end
	end
end

-- The game's bags: each container frame refreshes its buttons through UpdateItems (older clients:
-- ContainerFrame_Update). Frames can appear late, so this is tried again whenever bags change.
local legacyHooked = false
local function HookFrames()
	local names = { "ContainerFrameCombinedBags" }
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do names[#names + 1] = "ContainerFrame" .. i end
	for _, name in ipairs(names) do
		local f = _G[name]
		if f and not hookedFrames[f] and f.UpdateItems and hooksecurefunc then
			hookedFrames[f] = true
			hooksecurefunc(f, "UpdateItems", function() UpdateFrame(f) end)
		end
	end
	if not legacyHooked and ContainerFrame_Update and hooksecurefunc then
		legacyHooked = true
		hooksecurefunc("ContainerFrame_Update", function(frame) UpdateFrame(frame) end)
	end
end

function FR:RefreshJunkIcons()
	HookFrames()
	for f in pairs(hookedFrames) do UpdateFrame(f) end
	if _G.ContainerFrame_UpdateAll and On() then pcall(_G.ContainerFrame_UpdateAll) end
	RefreshBaganator()
end

-- Baganator draws the icon itself once a junk plugin is registered, and only when the player chose
-- "ForeverRoute" as the junk plugin in Baganator. Baganator would pick a newly registered plugin by itself
-- whenever the chosen one is its virtual default "poor_quality" (API/Main.lua AutoSet), which overwrote the
-- player's setting. So before registering we put ourselves on its ignore list, and once we undo a switch
-- that an earlier version of this addon made.
local baganatorDone = false
local PLUGIN = "ForeverRoute"

local function KeepBaganatorSetting()
	local config = _G.BAGANATOR_CONFIG
	local profiles = type(config) == "table" and config.Profiles
	local profile = type(profiles) == "table" and profiles[_G.BAGANATOR_CURRENT_PROFILE or "DEFAULT"]
	if type(profile) ~= "table" then return end
	if profile.junk_plugin == PLUGIN then
		-- Switched by the automatic choice of an earlier version: back to Baganator's default, once.
		local db = ForeverRouteDB
		if db and not db.baganatorJunkRestored then
			db.baganatorJunkRestored = true
			profile.junk_plugin = "poor_quality"
		end
	end
	if profile.junk_plugin ~= PLUGIN then
		if type(profile.junk_plugin_ignored) ~= "table" then profile.junk_plugin_ignored = {} end
		profile.junk_plugin_ignored[PLUGIN] = true
	end
end

local function HookBaganator()
	if baganatorDone then return end
	local api = _G.Baganator and _G.Baganator.API
	if api and api.RegisterJunkPlugin then
		baganatorDone = true
		pcall(KeepBaganatorSetting)
		pcall(api.RegisterJunkPlugin, "ForeverRoute", "ForeverRoute", function(bagID, slotID, itemID)
			return On() and itemID and FR.IsJunk(itemID, bagID, slotID) or false
		end)
	end
end

-- Selling ------------------------------------------------------------------------------------------------

local selling, startMoney, sellTries = false, 0, {}

local function EndSale()
	selling = false
	local gained = (GetMoney() or 0) - startMoney
	if gained > 0 then FR:Print(string.format(FR.L["Sold junk items for %s"], Money(gained))) end
end

local function SellStep()
	if not (On() and FR:Get("autoSellJunk") and MerchantFrame and MerchantFrame:IsShown()
		and (MerchantFrame.selectedTab or 1) == 1) then
		if selling then C_Timer.After(0.3, EndSale) end
		return
	end
	if GetCursorInfo and GetCursorInfo() then C_Timer.After(0.2, SellStep) return end
	local best, bestQuality, bestValue
	for bag = Bag.FIRST, Bag.LAST do
		for slot = 1, Bag.Slots(bag) do
			local id = Bag.ItemID(bag, slot)
			local key = bag .. ":" .. slot
			if id and (sellTries[key] or 0) < 3 and FR.IsJunk(id, bag, slot) then
				local count, locked, quality = Bag.ItemInfo(bag, slot)
				local price = select(11, GetItemInfo(id))
				if not locked and type(price) == "number" and price > 0 then
					local value = price * (count or 1)
					quality = quality or 0
					if not best or quality < bestQuality or (quality == bestQuality and value < bestValue) then
						best, bestQuality, bestValue = { bag = bag, slot = slot, key = key }, quality, value
					end
				end
			end
		end
	end
	if not best then C_Timer.After(0.3, EndSale) return end
	sellTries[best.key] = (sellTries[best.key] or 0) + 1
	Bag.Pickup(best.bag, best.slot)
	if PickupMerchantItem then PickupMerchantItem() end
	if GetCursorInfo and GetCursorInfo() and ClearCursor then ClearCursor() end
	C_Timer.After(0.12, SellStep)
end

local function StartSale()
	if selling or not (On() and FR:Get("autoSellJunk")) then return end
	selling, startMoney, sellTries = true, GetMoney() or 0, {}
	SellStep()
end

-- Deleting the cheapest junk when every bag is full -------------------------------------------------------

local function BagsFull()
	for bag = Bag.FIRST, Bag.LAST do
		local free, kind = Bag.Free(bag)
		if kind == 0 and free > 0 then return false end
	end
	return true
end

local discardPending = false
local function DiscardStep()
	discardPending = false
	if not (On() and FR:Get("autoDiscardItems")) then return end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
	if GetCursorInfo and GetCursorInfo() then return end
	if MerchantFrame and MerchantFrame:IsShown() then return end
	if FR.BankIsOpen and FR.BankIsOpen() then return end
	if not BagsFull() then return end
	local best, bestValue
	for bag = Bag.FIRST, Bag.LAST do
		local _, kind = Bag.Free(bag)
		if kind <= 2 then   -- ordinary bags and quivers, not the other special bags
			for slot = 1, Bag.Slots(bag) do
				local id = Bag.ItemID(bag, slot)
				if id and FR.IsJunk(id, bag, slot) then
					local count, locked = Bag.ItemInfo(bag, slot)
					local _, _, _, _, _, _, _, stackMax, _, _, price = GetItemInfo(id)
					local value = ((stackMax or 1) + (count or 1)) * (price or 0) / 2
					if not locked and (not best or value < bestValue) then
						best, bestValue = { bag = bag, slot = slot, id = id, count = count or 1 }, value
					end
				end
			end
		end
	end
	if not best then return end
	Bag.Pickup(best.bag, best.slot)
	if GetCursorInfo and GetCursorInfo() and DeleteCursorItem then
		DeleteCursorItem()
		FR:Print(string.format(FR.L["Inventory is full, deleting %s x%d"], Bag.ItemLink(best.id), best.count))
	end
end

local function ScheduleDiscard()
	if discardPending then return end
	discardPending = true
	C_Timer.After(0.3, DiscardStep)
end

-- Events ---------------------------------------------------------------------------------------------------

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "MERCHANT_SHOW", "UI_ERROR_MESSAGE" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a, b)
	if event == "PLAYER_LOGIN" then
		HookBaganator()
		HookFrames()
		for _, name in ipairs({ "OpenAllBags", "ToggleAllBags", "ToggleBackpack", "OpenBackpack", "ToggleBag", "OpenBag" }) do
			if _G[name] and hooksecurefunc then
				hooksecurefunc(name, function() C_Timer.After(0, function() FR:RefreshJunkIcons() end) end)
			end
		end
	elseif event == "MERCHANT_SHOW" then
		C_Timer.After(0.3, StartSale)
	elseif event == "BAG_UPDATE_DELAYED" then
		HookFrames()
		ScheduleDiscard()
	elseif event == "UI_ERROR_MESSAGE" then
		if (a == ERR_INV_FULL or b == ERR_INV_FULL) then ScheduleDiscard() end
	end
end)
