----------------------------------------------------------------
-- AUTO QUEST (WARAS + INVENTORY VERSION, CLEAN)
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Net = ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net

local Replion = require(ReplicatedStorage.Packages.Replion)
local Quests = require(ReplicatedStorage.Modules.Quests)

local LP = Players.LocalPlayer
local replion = Replion.Client:WaitReplion("Data")

local remote = {
	RF = {
		UpdateAutoFishingState = Net["RF/UpdateAutoFishingState"],
	}
}

local AutoQuest = {}

AutoQuest.enabled = false
AutoQuest.selectedQuest = nil
AutoQuest._thread = nil

----------------------------------------------------------------
-- INTERNAL: GET ACTIVE QUEST LIST
----------------------------------------------------------------
local function getActiveQuests()
	local out = {}

	local main = replion:GetExpect({"Quests","Mainline"}) or {}
	local event = replion:GetExpect({"Quests","Event"}) or {}

	for qName in pairs(main) do
		table.insert(out, qName)
	end

	for qName in pairs(event) do
		table.insert(out, qName)
	end

	table.sort(out)
	return out
end

----------------------------------------------------------------
-- INTERNAL: GET QUEST DEF + STATE
----------------------------------------------------------------
local function getQuestDefAndState(questName)
	local def =
		Quests.Mainline[questName]
		or Quests.Event[questName]

	if not def then
		return nil, nil
	end

	local state =
		replion:GetExpect({"Quests","Mainline",questName})
		or replion:GetExpect({"Quests","Event",questName})

	return def, state
end

----------------------------------------------------------------
-- INTERNAL: INVENTORY ACCESS (DEBUG FRIENDLY)
----------------------------------------------------------------
local function getInventory()
	local inv = replion:GetExpect({"Inventory"})
	return inv or {}
end

----------------------------------------------------------------
-- INTERNAL: CHECK REQUIRED ITEM (REAL-ish)
----------------------------------------------------------------
local function hasRequiredItem(obj)
	local inv = getInventory()

	warn("[AutoQuest] Inventory dump:", inv)

	local fishBag = inv.Fish or (inv.Items and inv.Items.Fish) or {}

	-- CASE 1: mutated fish
	if obj.Requirements
		and obj.Requirements.Metadata
		and obj.Requirements.Metadata.VariantId
	then
		local wantVariant = obj.Requirements.Metadata.VariantId
		for _, fish in pairs(fishBag) do
			if fish.Metadata and fish.Metadata.VariantId == wantVariant then
				warn("[AutoQuest] Found mutated fish. VariantId:", wantVariant)
				return true
			end
		end
		return false
	end

	-- CASE 2: specific fish
	if obj.AssociatedType == "Fish" and obj.AssociatedItem then
		for _, fish in pairs(fishBag) do
			if fish.Name == obj.AssociatedItem then
				warn("[AutoQuest] Found fish:", obj.AssociatedItem)
				return true
			end
		end
		return false
	end

	-- CASE 3: fish by id
	if obj.Requirements and obj.Requirements.Id then
		local wantId = obj.Requirements.Id
		for _, fish in pairs(fishBag) do
			if fish.Id == wantId then
				warn("[AutoQuest] Found fish id:", wantId)
				return true
			end
		end
		return false
	end

	return false
end

----------------------------------------------------------------
-- INTERNAL: HANDLE 1 OBJECTIVE
----------------------------------------------------------------
local SUPPORTED_TYPES = {
	Catch = true,
	Search = true,
	Exchange = true,
	SpeakWithNPC = true,
}

local function handleObjective(obj, st)
	if not SUPPORTED_TYPES[obj.Type] then
		warn("[AutoQuest] Manual objective type detected:", obj.Type)
		warn("[AutoQuest] Please complete this objective manually.")
		AutoQuest.Stop()
		return
	end

	if obj.Type == "Catch" then
		warn("[AutoQuest] Catch objective:", obj.Requirements)
		remote.RF.UpdateAutoFishingState:InvokeServer(true)

	elseif obj.Type == "Search" then
		warn("[AutoQuest] Search objective:", obj.Requirements)

	elseif obj.Type == "Exchange" then
		if hasRequiredItem(obj) then
			warn("[AutoQuest] Exchange ready → return to NPC")

		else
			warn("[AutoQuest] Exchange not ready → farming item first")

			if obj.Requirements
				and obj.Requirements.Metadata
				and obj.Requirements.Metadata.VariantId
			then
				warn("[AutoQuest] Farming mutated fish for exchange. VariantId:",
					obj.Requirements.Metadata.VariantId
				)
				remote.RF.UpdateAutoFishingState:InvokeServer(true)

			elseif obj.AssociatedType == "Fish"
				and obj.AssociatedItem
			then
				warn("[AutoQuest] Farming fish for exchange:", obj.AssociatedItem)
				remote.RF.UpdateAutoFishingState:InvokeServer(true)

			elseif obj.Requirements and obj.Requirements.Id then
				warn("[AutoQuest] Farming fish for exchange. Id:",
					obj.Requirements.Id
				)
				remote.RF.UpdateAutoFishingState:InvokeServer(true)

			else
				warn("[AutoQuest] Unknown exchange requirement:", obj.Requirements)
				AutoQuest.Stop()
			end
		end

	elseif obj.Type == "SpeakWithNPC" then
		warn("[AutoQuest] Return to NPC")
	end
end

----------------------------------------------------------------
-- INTERNAL: RUN 1 QUEST STEP
----------------------------------------------------------------
local function runQuestStep(questName)
	local def, state = getQuestDefAndState(questName)

	if not def or not state then
		warn("[AutoQuest] Quest not active anymore:", questName)
		AutoQuest.Stop()
		return
	end

	for i, obj in ipairs(def.Objectives) do
		local st = state.Objectives[i]
		if st and st.Progress < obj.Goal then
			handleObjective(obj, st)
			return
		end
	end

	warn("[AutoQuest] Quest finished:", questName)
	AutoQuest.Stop()
end

----------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------
function AutoQuest.RefreshQuestList()
	return getActiveQuests()
end

function AutoQuest.SetSelectedQuest(name)
	AutoQuest.selectedQuest = name
end

function AutoQuest.Start()
	if AutoQuest.enabled then return end
	if not AutoQuest.selectedQuest then
		warn("[AutoQuest] No quest selected")
		return
	end

	AutoQuest.enabled = true

	AutoQuest._thread = task.spawn(function()
		while AutoQuest.enabled do
			runQuestStep(AutoQuest.selectedQuest)
			task.wait(1)
		end
	end)

	warn("[AutoQuest] STARTED:", AutoQuest.selectedQuest)
end

function AutoQuest.Stop()
	if not AutoQuest.enabled then return end

	AutoQuest.enabled = false
	AutoQuest._thread = nil

	warn("[AutoQuest] STOPPED")
end

return AutoQuest
