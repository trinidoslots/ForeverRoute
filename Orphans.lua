-- /fr quests: the quests in your log that the rest of the guide no longer mentions (no turn-in, no
-- objective, no "abandon" line in the steps from here on, in this guide and the ones that follow it).
-- Meant to answer "I accepted this quest and the guide never comes back to it".
local _, ns = ...
local FR = ns.FR

local MAX_GUIDES = 8

local function Collect(steps, from, mentioned)
	for i = from, #steps do
		for _, e in ipairs(steps[i].elements) do
			if e.qid and (e.kind == "turnin" or e.kind == "complete" or e.kind == "collect" or e.kind == "abandon") then
				mentioned[e.qid] = true
			end
		end
	end
end

function FR:PrintOrphans()
	local g = self.current
	if not (g and g.steps) then self:Print(FR.L["No guide selected"]) return end
	local mentioned = {}
	Collect(g.steps, self.stepIndex or 1, mentioned)
	local seen, count, cur = { [g] = true }, 1, g
	while count < MAX_GUIDES do
		local ref = cur.next and cur.next:match("^([^;]+)")
		local nxt = ref and self:FindGuide(ref, cur.group, cur.lang)
		if not nxt or seen[nxt] then break end
		seen[nxt] = true
		Collect(self:ParseGuide(nxt), 1, mentioned)
		cur, count = nxt, count + 1
	end
	local list = {}
	for _, q in ipairs(FR.LoggedQuests()) do
		if not mentioned[q.id] and not (FR.IsGivenUp and FR.IsGivenUp(q.id)) then list[#list + 1] = q end
	end
	self:Print(string.format(FR.L["Quests in your log that the next %d guide(s) do not mention: %d"], count, #list))
	for _, q in ipairs(list) do
		DEFAULT_CHAT_FRAME:AddMessage(string.format("   %s |cff888888(%d)%s|r", tostring(q.title or "?"), q.id, q.complete and ", complete" or ""))
	end
end
