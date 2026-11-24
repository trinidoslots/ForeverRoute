-- Accepts and turns in the quests of the current steps automatically, like
-- RestedXP. Only quests the guide asks for right now (the shown steps and
-- the next two) are touched. Hold Shift while talking to an NPC to do it by
-- hand. Quests with a choice of rewards are left to the player.
local _, ns = ...
local FR = ns.FR

local LOOKAHEAD = 2

-- Quest ids the guide wants accepted / turned in right now.
local function Wanted()
	local accept, turnin = {}, {}
	local g = FR.current
	if not (g and g.steps) then return accept, turnin end
	local steps = {}
	for _, s in ipairs(FR:GetActiveSteps()) do steps[#steps + 1] = s end
	local i = FR.stepIndex
	for _ = 1, LOOKAHEAD do
		i = FR:NextVisibleIndex(i)
		if not i then break end
		steps[#steps + 1] = g.steps[i]
	end
	for _, s in ipairs(steps) do
		if not FR:IsStepSkipped(s) then
			for _, e in ipairs(s.elements) do
				if e.kind == "accept" and e.qid then accept[e.qid] = true
				elseif e.kind == "turnin" and e.qid then turnin[e.qid] = true end
			end
		end
	end
	return accept, turnin
end

local function Enabled(key)
	return ForeverRouteDB and FR:Get(key) and not (IsShiftKeyDown and IsShiftKeyDown())
end

local function TitleOf(qid)
	local t = FR.QuestTitle(qid)
	if t then return t end
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local ok, title = pcall(C_QuestLog.GetTitleForQuestID, qid)
		if ok and title then return title end
	end
end

-- Id from a list entry, or the wanted id whose title matches.
local function Match(id, title, wanted)
	if id and id > 0 then return wanted[id] and id or nil end
	if not title then return nil end
	for qid in pairs(wanted) do
		if TitleOf(qid) == title then return qid end
	end
end

local function CurrentQuestID()
	local id = GetQuestID and GetQuestID()
	return (id and id > 0) and id or nil
end

local handlers = {}

-- Id of the NPC whose talk window is open.
local function NpcId()
	local kind, id = FR.UnitNpcId("npc")
	if not kind then kind, id = FR.UnitNpcId("target") end
	if kind == "Creature" or kind == "Vehicle" then return id end
end

-- Gossip automation, like RestedXP: the steps on screen can ask for options
-- of the talk window (.skipgossip / .skipgossipid). Hold Shift to do it by hand.
local function SelectGossip()
	if not Enabled("autoGossip") then return false end
	local G = C_GossipInfo
	if not (G and G.GetOptions and G.SelectOption) then return false end
	local options = G.GetOptions() or {}
	if #options == 0 then return false end
	local quests = 0
	if G.GetAvailableQuests then quests = quests + #(G.GetAvailableQuests() or {}) end
	if G.GetActiveQuests then quests = quests + #(G.GetActiveQuests() or {}) end
	local npc = NpcId()
	local function Pick(i)
		local o = options[i]
		if o and o.gossipOptionID then G.SelectOption(o.gossipOptionID, "", true) return true end
		return false
	end
	for _, s in ipairs(FR:GetActiveSteps()) do
		if not FR:IsStepSkipped(s) then
			for _, e in ipairs(s.elements) do
				if e.gossipIds then
					for _, id in ipairs(e.gossipIds) do
						for _, o in ipairs(options) do
							if o.gossipOptionID == id then
								G.SelectOption(id, "", true)
								if e.timer and FR.StartTimer then FR:StartTimer(e.timer, e.timerText) end
								return true
							end
						end
					end
				elseif e.gossipId then
					-- ".gossipoption id": pick it and tick the line.
					for _, o in ipairs(options) do
						if o.gossipOptionID == e.gossipId then
							G.SelectOption(e.gossipId, "", true)
							FR:SetMarked(s, e, true)
							FR:QueueRefresh()
							return true
						end
					end
				elseif e.gossip then
					local args = e.gossip.args
					local n, id = #args, args[1]
					if n == 0 then
						if quests == 0 and Pick(1) then return true end
					elseif n == 1 then
						local index
						if npc and npc == id then index = 1 elseif id and id <= 9 then index = id end
						if index and quests == 0 and Pick(index) then return true end
					elseif npc and (id == npc or id == 0) then
						-- Several options for the same NPC: one more each time it is opened.
						e.gossipIndex = e.gossipIndex and (((e.gossipIndex - 1) % (n - 1)) + 2) or 2
						local option = args[e.gossipIndex]
						if option and Pick(option) then return true end
					end
				end
			end
		end
	end
	return false
end

-- A closed talk window starts the option cycle of ".skipgossip npc,1,2,..." over.
local function ResetGossipCycle()
	for _, s in ipairs(FR:GetActiveSteps()) do
		for _, e in ipairs(s.elements) do e.gossipIndex = nil end
	end
end

-- NPC with a gossip window: pick a finished quest to hand in, else a quest to take.
function handlers.GOSSIP_CLOSED() ResetGossipCycle() end

function handlers.GOSSIP_SHOW()
	local G = C_GossipInfo
	if not G then return end
	if SelectGossip() then return end
	local accept, turnin = Wanted()
	if Enabled("autoTurnin") and G.GetActiveQuests then
		for _, q in ipairs(G.GetActiveQuests() or {}) do
			if q.isComplete and Match(q.questID, q.title, turnin) then
				G.SelectActiveQuest(q.questID)
				return
			end
		end
	end
	if Enabled("autoAccept") and G.GetAvailableQuests then
		for _, q in ipairs(G.GetAvailableQuests() or {}) do
			if Match(q.questID, q.title, accept) then
				G.SelectAvailableQuest(q.questID)
				return
			end
		end
	end
end

-- NPC without gossip that offers several quests.
function handlers.QUEST_GREETING()
	local accept, turnin = Wanted()
	if Enabled("autoTurnin") and GetNumActiveQuests then
		for i = 1, GetNumActiveQuests() do
			local title, done = GetActiveTitle(i)
			local id = GetActiveQuestID and GetActiveQuestID(i)
			if done ~= false and Match(id, title, turnin) then
				SelectActiveQuest(i)
				return
			end
		end
	end
	if Enabled("autoAccept") and GetNumAvailableQuests then
		for i = 1, GetNumAvailableQuests() do
			local title = GetAvailableTitle(i)
			local id = GetAvailableQuestID and GetAvailableQuestID(i)
			if Match(id, title, accept) then
				SelectAvailableQuest(i)
				return
			end
		end
	end
end

function handlers.QUEST_DETAIL()
	if not Enabled("autoAccept") then return end
	local id = CurrentQuestID()
	local accept = Wanted()
	if not (id and accept[id]) then return end
	if QuestGetAutoAccept and QuestGetAutoAccept() then
		if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
	else
		AcceptQuest()
	end
end

function handlers.QUEST_PROGRESS()
	if not Enabled("autoTurnin") then return end
	local id = CurrentQuestID()
	local _, turnin = Wanted()
	if id and turnin[id] and IsQuestCompletable and IsQuestCompletable() then CompleteQuest() end
end

function handlers.QUEST_COMPLETE()
	if not Enabled("autoTurnin") then return end
	local id = CurrentQuestID()
	local _, turnin = Wanted()
	if not (id and turnin[id]) then return end
	local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
	if choices <= 1 then GetQuestReward(choices) end
end

local ev = CreateFrame("Frame")
for event in pairs(handlers) do pcall(ev.RegisterEvent, ev, event) end
ev:SetScript("OnEvent", function(_, event)
	if not FR.current then return end
	-- The quest log may be a moment behind; read it fresh.
	if FR.InvalidateQuestLog then FR:InvalidateQuestLog() end
	local ok, err = pcall(handlers[event])
	if not ok and FR.debug then FR:Print(tostring(err)) end
end)
