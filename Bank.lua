-- Bank automation, like RestedXP's: a step with ".bankdeposit <items>" or ".bankwithdraw <items>" moves
-- those items between the bags and the bank as soon as the bank window is open. Whole stacks only, no
-- counts (the guides give item ids only). The line is done when none of the items is left in the bags
-- (deposit) or in the bank (withdraw). Setting "autoBank"; hold Shift to do it by hand.
--
-- This file also holds the small bag API shared with Inventory.lua (FR.Bag).
local _, ns = ...
local FR = ns.FR

-- Bag API ------------------------------------------------------------------------------------------
-- C_Container on new clients, the global functions on old ones.

local function Container(name)
	local c = C_Container and C_Container[name]
	return c or _G[name]
end

local Bag = {}
FR.Bag = Bag

function Bag.Slots(bag)
	local f = Container("GetContainerNumSlots")
	local ok, n = pcall(f or error, bag)
	return ok and type(n) == "number" and n or 0
end

function Bag.ItemID(bag, slot)
	local f = Container("GetContainerItemID")
	local ok, id = pcall(f or error, bag, slot)
	return ok and type(id) == "number" and id or nil
end

-- count, locked, quality, link of what is in the slot (nil for an empty slot).
function Bag.ItemInfo(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
		if ok and type(info) == "table" then
			return info.stackCount or 1, info.isLocked and true or false, info.quality, info.hyperlink
		end
		return nil
	end
	if GetContainerItemInfo then
		local ok, _, count, locked, quality, _, _, link = pcall(GetContainerItemInfo, bag, slot)
		if ok and count then return count, locked and true or false, quality, link end
	end
end

-- free slots, bag type (0 = a bag that takes anything)
function Bag.Free(bag)
	local f = Container("GetContainerNumFreeSlots")
	local ok, free, kind = pcall(f or error, bag)
	if ok then return free or 0, kind or 0 end
	return 0, 0
end

function Bag.Pickup(bag, slot)
	local f = Container("PickupContainerItem")
	if f then f(bag, slot) end
end

local NUM_BAGS = NUM_BAG_SLOTS or 4
Bag.FIRST = BACKPACK_CONTAINER or 0
Bag.LAST = NUM_BAG_FRAMES or NUM_BAGS

-- The bank: its main container and the bags bought for it.
local function BankBags()
	local list = { BANK_CONTAINER or (Enum and Enum.BagIndex and Enum.BagIndex.Bank) or -1 }
	for b = NUM_BAGS + 1, NUM_BAGS + (NUM_BANKBAGSLOTS or 7) do list[#list + 1] = b end
	return list
end
Bag.BankBags = BankBags

local function Name(id)
	local name = GetItemInfo and GetItemInfo(id)
	return name or ("item:" .. id)
end
local function Link(id)
	local _, link = GetItemInfo and GetItemInfo(id)
	return link or Name(id)
end
Bag.ItemLink = Link

-- What is in the bags, and what was in the bank the last time it was open ------------------------------

local bagCounts, bagDirty, bagsReady = {}, true, false

local function BagCounts()
	if bagDirty then
		bagDirty = false
		for k in pairs(bagCounts) do bagCounts[k] = nil end
		for bag = Bag.FIRST, Bag.LAST do
			for slot = 1, Bag.Slots(bag) do
				local id = Bag.ItemID(bag, slot)
				if id then bagCounts[id] = (bagCounts[id] or 0) + (Bag.ItemInfo(bag, slot) or 1) end
			end
		end
	end
	return bagCounts
end

local bankOpen = false
function FR.BankIsOpen() return bankOpen end

local function SaveBankSnapshot()
	if not (bankOpen and ForeverRouteCharDB) then return end
	local snap, any = {}, false
	for _, bag in ipairs(BankBags()) do
		local n = Bag.Slots(bag)
		if n > 0 then any = true end
		for slot = 1, n do
			local id = Bag.ItemID(bag, slot)
			if id then snap[id] = (snap[id] or 0) + (Bag.ItemInfo(bag, slot) or 1) end
		end
	end
	if not any then return end   -- the bank could not be read (yet): keep the old snapshot
	ForeverRouteCharDB.bank = snap
end

-- Is the line done? Deposit: none of the items is in the bags. Withdraw: none of them was in the bank
-- at the last visit (nil snapshot = never opened: not done). Not before the bags are known after login.
function FR.BankLineDone(e)
	if e.mode == "withdraw" then
		local snap = ForeverRouteCharDB and ForeverRouteCharDB.bank
		if not snap then return false end
		for _, id in ipairs(e.items) do if (snap[id] or 0) > 0 then return false end end
		return true
	end
	if not bagsReady then return false end
	local have = BagCounts()
	for _, id in ipairs(e.items) do if (have[id] or 0) > 0 then return false end end
	return true
end

-- Moving ---------------------------------------------------------------------------------------------

-- The bank lines of the steps on screen that still have something to move: { deposit = set, withdraw = set }.
local function Wanted()
	local want = { deposit = {}, withdraw = {} }
	local any = false
	for _, step in ipairs(FR:GetActiveSteps()) do
		if not FR:IsStepSkipped(step) then
			for _, e in ipairs(step.elements) do
				if e.kind == "bank" and e.items and #e.items > 0 and not FR:IsMarked(step, e) and not FR.BankLineDone(e) then
					local set = want[e.mode == "withdraw" and "withdraw" or "deposit"]
					for _, id in ipairs(e.items) do set[id] = true; any = true end
				end
			end
		end
	end
	return any and want or nil
end

-- A slot that was tried five times without the item leaving it is left alone until the bank is opened again.
local tries, blocked = {}, {}

-- The next stack to move: { bag, slot, id, count, deposit = bool } or nil.
local function NextMove(want)
	if next(want.deposit) then
		for bag = Bag.FIRST, Bag.LAST do
			for slot = 1, Bag.Slots(bag) do
				local id = Bag.ItemID(bag, slot)
				if id and want.deposit[id] and not blocked[bag .. ":" .. slot] then
					local count, locked = Bag.ItemInfo(bag, slot)
					if not locked then return { bag = bag, slot = slot, id = id, count = count or 1, deposit = true } end
				end
			end
		end
	end
	if next(want.withdraw) then
		for _, bag in ipairs(BankBags()) do
			for slot = 1, Bag.Slots(bag) do
				local id = Bag.ItemID(bag, slot)
				if id and want.withdraw[id] and not blocked[bag .. ":" .. slot] then
					local count, locked = Bag.ItemInfo(bag, slot)
					if not locked then return { bag = bag, slot = slot, id = id, count = count or 1, deposit = false } end
				end
			end
		end
	end
end

-- The first empty slot of a bag that takes anything, in the bank (deposit) or the bags (withdraw).
local function EmptySlot(deposit)
	local bags = {}
	if deposit then
		bags = BankBags()
	else
		for bag = Bag.FIRST, Bag.LAST do bags[#bags + 1] = bag end
	end
	for _, bag in ipairs(bags) do
		local free, kind = Bag.Free(bag)
		if free > 0 and kind == 0 then
			for slot = 1, Bag.Slots(bag) do
				if not Bag.ItemID(bag, slot) then
					local _, locked = Bag.ItemInfo(bag, slot)
					if not locked then return bag, slot end
				end
			end
		end
	end
end

local pumping, warnedFull = false, false

local function CanRun()
	if not (bankOpen and ForeverRouteDB and FR:Get("autoBank")) then return false end
	if IsShiftKeyDown and IsShiftKeyDown() then return false end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false end
	if InCombatLockdown and InCombatLockdown() then return false end
	if GetCursorInfo and GetCursorInfo() then return false end
	return true
end

-- One stack per call, then again after a moment: the game needs the cursor free in between.
local function Pump()
	pumping = false
	SaveBankSnapshot()
	if not CanRun() then return end
	local want = Wanted()
	if not want then FR:QueueRefresh() return end
	local move = NextMove(want)
	if not move then FR:QueueRefresh() return end
	local bag, slot = EmptySlot(move.deposit)
	if not bag then
		if not warnedFull then
			warnedFull = true
			FR:Print(FR.L[move.deposit and "The bank has no room left." or "Your bags have no room left."])
		end
		return
	end
	local key = move.bag .. ":" .. move.slot
	tries[key] = (tries[key] or 0) + 1
	if tries[key] > 5 then blocked[key] = true end
	Bag.Pickup(move.bag, move.slot)
	if GetCursorInfo and GetCursorInfo() then
		Bag.Pickup(bag, slot)
		if GetCursorInfo and GetCursorInfo() and ClearCursor then ClearCursor() end
		FR:Print(string.format(FR.L[move.deposit and "Deposited %s" or "Withdrew %s"], Link(move.id) .. (move.count > 1 and (" x" .. move.count) or "")))
	end
	bagDirty = true
	FR:QueueRefresh()
	pumping = true
	C_Timer.After(0.2, Pump)
end

local function Schedule(delay)
	if pumping then return end
	pumping = true
	C_Timer.After(delay or 0.2, Pump)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED",
	"PLAYERBANKBAGSLOTS_CHANGED" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
	if event == "BANKFRAME_OPENED" then
		bankOpen, warnedFull = true, false
		tries, blocked = {}, {}
		Schedule(0.4)   -- the bank's contents are readable a moment after the window opens
	elseif event == "BANKFRAME_CLOSED" then
		bankOpen = false
		FR:QueueRefresh()
	elseif event == "BAG_UPDATE" then
		bagDirty = true
	elseif event == "BAG_UPDATE_DELAYED" then
		bagDirty = true
		if not bagsReady then
			bagsReady = true
			FR:QueueRefresh()   -- the deposit lines can be judged now
		end
		if bankOpen then Schedule(0.2) end
	elseif bankOpen then   -- PLAYERBANKSLOTS_CHANGED, PLAYERBANKBAGSLOTS_CHANGED
		Schedule(0.2)
	end
end)
