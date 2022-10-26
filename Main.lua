local _, CGM = ...

-- Variables.
local GetStepIndexFromQuestID = {}

-- Localized globals.
local IsQuestFlaggedCompleted, IsOnQuest, GetQuestObjectives, GetQuestInfo = C_QuestLog.IsQuestFlaggedCompleted, C_QuestLog.IsOnQuest, C_QuestLog.GetQuestObjectives, C_QuestLog.GetQuestInfo
local UnitXP, UnitLevel = UnitXP, UnitLevel
local GetItemCount, GetItemInfo = GetItemCount, GetItemInfo

-- Processes all tags in the given guide and replaces them with the proper strings.
local function ProcessTags(guide)
    for i = 1, #guide do
        local step = guide[i]
        if step.text then
            for tag in step.text:gmatch("{(%w+)}") do
                local tagLower = tag:lower()
                if tagLower:find("questname") then
                    if step.isMultiStep then
                        local n = tonumber(tag:match("%a+(%d+)"))
                        if n then
                            local questID = step.questIDs[n]
                            if questID then
                                local questName = GetQuestInfo(questID)
                                if questName then
                                    step.text = step.text:gsub("{" .. tag .. "}", questName)
                                end
                            end
                        end
                    elseif step.questID then
                        local questName = GetQuestInfo(step.questID)
                        if questName then
                            step.text = step.text:gsub("{" .. tag .. "}", questName)
                        end
                    end
                elseif tagLower:find("itemname") then
                    local n = tonumber(tag:match("%a+(%d+)"))
                    if n then
                        local itemID = step.itemIDs[n]
                        if itemID then
                            local itemName = GetItemInfo(itemID)
                            if itemName then
                                step.text = step.text:gsub("{" .. tag .. "}", itemName)
                            end
                        end
                    end
                elseif tagLower == "x" then
                    if step.x then
                        step.text = step.text:gsub("{" .. tag .. "}", step.x)
                    end
                elseif tagLower == "y" then
                    if step.y then
                        step.text = step.text:gsub("{" .. tag .. "}", step.y)
                    end
                else
                    -- give error message here
                end
            end
        end
    end
end

-- Sets the current step to the given index.
function CGM:SetCurrentStep(index, shouldScroll)
    if CGM:IsStepAvailable(index) and not CGM:IsStepCompleted(index) and CGM.currentStepIndex ~= index then
        CGM.currentStepIndex = index
        CGMOptions.savedStepIndex[CGM.currentGuideName] = index
        local step = CGM.currentGuide[index]
        CGM.currentStep = step
        CGM:SetGoal(step.x / 100, step.y / 100, step.mapID)
        if shouldScroll then
            CGMSlider:SetValue(index - 1)
        end
    end
end

-- Attempts to mark the step with the given index as completed.
function CGM:MarkStepCompleted(index, completed)
    -- TODO: check that it can be marked incomplete here (i.e. if its been handed in already etc) -- temp
    -- if marking a step incomplete here makes the current step unavailable, should go back to step index #currentStep.requiredSteps (the last step in that table) or if that is unvailable
    -- then go to #currentStep.requiredSteps - 1 etc. (see OnItemUpdate)
    CGMOptions.completedSteps[CGM.currentGuideName][index] = completed or nil
end

-- Checks if the step with the given index in the currently selected guide is completed. Returns true if so, false otherwise.
function CGM:IsStepCompleted(index)
    if CGMOptions.completedSteps[CGM.currentGuideName][index] then
        return true
    end
    local step = CGM.currentGuide[index]
    local type = step.type
    local questID = step.questID
    if type == CGM.Types.Accept then -- Check if the quest is completed, if it isn't, check if it's in the quest log.
        if not (IsQuestFlaggedCompleted(questID) or IsOnQuest(questID)) then
            return false
        end
    elseif type == CGM.Types.Item and not IsQuestFlaggedCompleted(questID) then -- First check if the player has completed the associated quest, then check if the items are in the player's bags.
        local itemIDs = step.itemIDs
        for i = 1, #itemIDs do
            if GetItemCount(itemIDs[i]) <= 0 then
                return false
            end
        end
    elseif type == CGM.Types.Do then -- Check if quest is complete in quest log, and if not then check if the player has completed all objectives of the quest(s).
        local questObjectives
        if step.isMultiStep then
            for i = 1, #step.questIDs do
                if not (IsQuestComplete(step.questIDs[i]) or IsQuestFlaggedCompleted(step.questIDs[i])) then -- Not all quests have been completed.
                    return false
                else
                    questObjectives = GetQuestObjectives(step.questIDs[i])
                    if questObjectives then -- If this is nil, can assume the quest is a simple "go talk to this guy" quest.
                        -- Need to explicitly check for nil AND false since if questObjectives isn't nil but empty, we can assume the same as above.
                        if questObjectives.finished ~= nil and not questObjectives.finished then
                            return false
                        end
                    end
                end
            end
        else
            questObjectives = GetQuestObjectives(questID)
            if not (IsQuestComplete(questID) or IsQuestFlaggedCompleted(questID) or (questObjectives and questObjectives.finished ~= nil and questObjectives.finished)) then
                return false
            end
        end
    elseif type == CGM.Types.Deliver then -- Simply check if the quest has been completed.
        if not IsQuestFlaggedCompleted(questID) then
            return false
        end
    elseif type == CGM.Types.Grind then -- Check for level/xp.
        if not (UnitLevel("player") >= step.level and UnitXP("player") >= step.xp) then
            return false
        end
    elseif type == CGM.Types.Coordinate then -- First check if the quest has been completed, then check if the next step has been completed and return that.
        if not (IsQuestFlaggedCompleted(questID) or (CGM.currentGuideName[index + 1] and CGM:IsStepCompleted(index + 1))) then
            return false
        end
    end
    if type ~= CGM.Types.Item or (type == CGM.Types.Item and IsQuestFlaggedCompleted(questID)) then -- If the player removes an item from bags, this should return false.
        CGM:MarkStepCompleted(index, true)
    end
    return true
end

-- Returns true if the given step index is available to the player, false otherwise.
function CGM:IsStepAvailable(index)
    local step = CGM.currentGuide[index]
    local questID = step.questID or step.questIDs
    local requiresSteps = step.requiresSteps
    local lockedBySteps = step.lockedBySteps
    local requiresLevel = step.requiresLevel
    if requiresLevel then
        if UnitLevel("player") < requiresLevel then
            return false
        end
    end
    if lockedBySteps then
        for i = 1, #lockedBySteps do
            if CGM:IsStepCompleted(lockedBySteps[i]) then
                return false
            end
        end
    end
    local type = step.type
    -- This should always be checking backward, never forward.
    if type == CGM.Types.Deliver then -- If the quest isn't marked "complete" in the quest log, return false.
        return IsQuestComplete(questID)
    elseif type == CGM.Types.Do then
        if step.isMultiStep then
            for i = 1, #questID do
                if IsOnQuest(questID[i]) then
                    return true
                end
            end
            return false
        else
            return IsOnQuest(questID)
        end
    elseif requiresSteps and (type == CGM.Types.Accept or type == CGM.Types.Item) then
        for i = 1, #requiresSteps do
            if not self:IsStepCompleted(requiresSteps[i]) then
                return false
            end
        end
    end
    return true -- No requirements for this step.
end

-- Called on ITEM_UPDATE. Checks if the item that was just added or removed was an item required by the current step.
function CGM:OnItemUpdate()
    if CGM.currentStep.type == CGM.Types.Item and CGM:IsStepCompleted(CGM.currentStepIndex) then
        CGM:ScrollToNextIncomplete() -- Calls UpdateStepFrames.
    else
        CGM:UpdateStepFrames()
    end
    -- If by deleting an item, it made another step unavailable.
    local requiresSteps = CGM.currentStep.requiresSteps
    if not CGM:IsStepAvailable(CGM.currentStepIndex) then
        if requiresSteps then
            for i = #requiresSteps, 1, -1 do -- Go backwards until the first available step in requiredSteps.
                if CGM:IsStepAvailable(requiresSteps[i]) then
                    CGM:ScrollToIndex(requiresSteps[i]) -- Calls UpdateStepFrames.
                end
            end
        end
    end
end

-- Called on QUEST_ACCEPTED (when the player has accepted a quest).
function CGM:OnQuestAccepted(_, questID)
    -- No need to check any steps for the quest ID since we check for step completion dynamically when scrolling. Just update current steps.
    -- We should only scroll if the current step is of type Accept and has the same questID as this one.
    local currentStep = CGM.currentStep
    if currentStep.type == CGM.Types.Accept and currentStep.questID == questID then
        CGM:ScrollToNextIncomplete() -- Calls UpdateStepFrames().
    else
        if CGM:IsStepAvailable(CGM.currentStepIndex) then
            CGM:UpdateStepFrames()
        else
            CGM:ScrollToNextIncomplete() -- If the current step gets locked because the player picked up another quest, should scroll to next.
        end
    end
end

-- Called on QUEST_TURNED_IN (when the player has handed in a quest).
function CGM:OnQuestTurnedIn(questID)
    -- Quests aren't instantly marked as complete so need to manually mark them.
    -- Should simply just mark all steps containing this quest ID to completed, except if its a multi-step, in which case we check all the quests in that step before marking.
    local stepIndeces = GetStepIndexFromQuestID(questID)
    if stepIndeces then -- If the quest actually exists in the guide.
        for i = 1, #stepIndeces do
            local step = CGM.currentGuide[stepIndeces[i]]
            if step.isMultiStep then
                local isComplete = true
                for j = 1, #step.questIDs do
                    local currQuestID = step.questIDs[j]
                    isComplete = currQuestID ~= questID and not IsQuestFlaggedCompleted(currQuestID) -- Important to not check given quest ID since it will not be completed yet.
                end
                CGM:MarkStepCompleted(stepIndeces[i], isComplete)
            else
                CGM:MarkStepCompleted(stepIndeces[i], true)
            end
        end
        CGM:ScrollToNextIncomplete() -- Won't scroll if current step is incomplete.
    end
end

-- Called on QUEST_REMOVED (when a quest has been removed from the player's quest log).
function CGM:OnQuestRemoved(questID)
    -- If the player abandonded a quest, it's assumed the player didn't want to do that part of the guide, so skip ahead to the next available quest (if the current step is now unavailable).
    local stepIndeces = GetStepIndexFromQuestID(questID)
    if stepIndeces then -- If the quest actually exists in the guide.
        for i = 1, #stepIndeces do
            local step = CGM.currentGuide[stepIndeces[i]]
            if step.type == CGM.Types.Accept then
                if not IsQuestFlaggedCompleted(step.questID) then
                    CGM:MarkStepCompleted(stepIndeces[i], false)
                end
            elseif step.type == CGM.Types.Do then
                CGM:MarkStepCompleted(stepIndeces[i], CGM:IsStepCompleted(stepIndeces[i]))
            end
        end
        if not CGM:IsStepAvailable(CGM.currentStepIndex) then
            CGM:ScrollToNextIncomplete() -- Calls UpdateStepFrames.
        else
            CGM:UpdateStepFrames()
        end
    end
end

-- Called on UNIT_QUESTLOG_CHANGED (when a quest's objectives are changed [and at other times]).
function CGM:OnUnitQuestLogChanged(unit)
    -- This function is a special case. If the player is not on all quests of the step (if multistep) then scroll to next, except don't mark the step as completed.
    if unit == "player" then
        local currentStep = CGM.currentStep
        if currentStep.type == CGM.Types.Do then
            if CGM:IsStepCompleted(CGM.currentStepIndex) then
                CGM:ScrollToNextIncomplete(fromStep) -- Calls UpdateStepFrames.
            else
                CGM:UpdateStepFrames() -- Updates the objective text on the step frame. Gets called for a second time here if picking up a quest while on "Do" step, but that's fine.
            end
        end
        
        
        -- local isPartialDone = true
        -- local isDone = true
        -- if not CGMOptions.completedSteps[CGM.currentGuideName][index] then
            -- local currentStep = CGM.currentStep
            -- if currentStep and currentStep.type == CGM.Types.Do then
                -- if currentStep.isMultiStep then
                    -- for i = 1, #currentStep.questIDs do -- Quest objectives can be non-nil and non-empty for quests the player is not on.
                        -- local objectives = GetQuestObjectives(currentStep.questIDs[i])
                        -- if objectives then
                            -- for j = 1, #objectives do
                                -- isDone = IsOnQuest(currentStep.questIDs[i]) and objectives.finished or false -- 'finished' can be nil.
                                -- isPartialDone = not objectives.finished and false or true
                            -- end
                        -- end
                    -- end  
                -- elseif IsOnQuest(currentStep.questID) then
                    -- local objectives = GetQuestObjectives(currentStep.questID)
                    -- if objectives then
                        -- for i = 1, #objectives do
                            -- isDone = IsOnQuest(currentStep.questID) and objectives.finished or false -- 'finished' can be nil.
                            -- isPartialDone = objectives.finished or false
                        -- end
                    -- end
                -- end
                -- CGM:MarkStepCompleted(CGM.currentStepIndex, isDone)
                -- if isPartialDone or isDone then
                    -- CGM:ScrollToNextIncomplete(CGM.currentStepIndex + 1)
                -- end
            -- end
        -- end
    end
end

-- Called on PLAYER_XP_UPDATE (when the player receives XP).
function CGM:OnPlayerXPUpdate()
    local currentStep = CGM.currentStep
    if currentStep.type == CGM.Types.Grind and CGM:IsStepCompleted(CGM.currentStepIndex) then
        if CGM:IsStepCompleted(CGM.currentStepIndex) then
            CGM:ScrollToNextIncomplete()
        end
    else
        CGM:UpdateStepFrames()
    end
end

-- Called on COORDINATES_REACHED (when the player has reached the current step coordinates).
function CGM:OnCoordinatesReached()
    local currentStep = CGM.currentStep
    if currentStep.type == CGM.Types.Coordinate then
        CGM:MarkStepCompleted(CGM.currentStepIndex, true)
        CGM:ScrollToNextIncomplete()
    end
end

-- Called on MERCHANT_SHOW (whenever the player visits a vendor). Sells any items in the player's bags that are specified by the guide.
function CGM:OnMerchantShow()
    local itemsToSell = CGM.currentGuide.itemsToSell
    if itemsToSell then
        for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
            for slot = 1, GetContainerNumSlots(bag) do
                local _, itemCount, _, _, _, _, itemLink, _, _, itemID = GetContainerItemInfo(bag, slot)
                if itemID and itemsToSell[itemID] then
                    CGM:Message("selling " .. itemLink .. (itemCount > 1 and "x" .. itemCount or ""))
                    UseContainerItem(bag, slot)
                end
            end
        end
    end
end

-- Register a new guide for the addon.
function CGM:RegisterGuide(guide)
    -- this function should check each step to make sure it has legal fields (i.e. there cant be any multistep Deliver steps etc)
    if guide.name then
        if CGM.Guides[guide.name] then
            print("ClassicGuideMaker: Guide with that name is already registered. Name must be unique.")
        else
            ProcessTags(guide)
            CGM.Guides[guide.name] = guide
        end
    else
        print("ClassicGuideMaker: The guide has no name! To help you identify which guide it is, here is the first step description:\n" .. guide[1].text)
    end
end

-- Sets the currently displayed guide to the given guide (has to have been registered first).
function CGM:SetGuide(guideName)
    if CGM.Guides[guideName] then
        CGMOptions.completedSteps[guideName] = CGMOptions.completedSteps[guideName] or {}
        CGM.currentGuideName = guideName
        CGM.currentGuide = CGM.Guides[guideName]
        if CGM.currentGuide.itemsToSell then
            CGM:RegisterWowEvent("MERCHANT_SHOW", CGM.OnMerchantShow)
        else
            CGM:UnregisterWowEvent("MERCHANT_SHOW")
        end
        if CGM.currentGuide.itemsToDelete then
            CGM:RegisterWowEvent("BAG_UPDATE", CGM.OnBagUpdate)
            for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
                CGM:ScanBag(bag)
            end
        else
            CGM:UnregisterWowEvent("BAG_UPDATE")
        end
        CGMFrame:SetTitleText(CGM.currentGuideName)
        CGM:UpdateSlider()
        if CGMOptions.savedStepIndex[guideName] then
            CGM:SetCurrentStep(CGMOptions.savedStepIndex[guideName], true)
            CGM:UpdateStepFrames()
        else
            CGM:ScrollToFirstIncomplete()
        end
        -- Map quest IDs to step indeces so we don't have to iterate all steps to find them.
        for i = 1, #CGM.currentGuide do
            local questID = CGM.currentGuide[i].questID or CGM.currentGuide[i].questIDs
            if questID then
                if CGM.currentGuide[i].isMultiStep then
                    for j = 1, #questID do
                        GetStepIndexFromQuestID[questID[j]] = GetStepIndexFromQuestID[questID[j]] or {}
                        GetStepIndexFromQuestID[questID[j]][#GetStepIndexFromQuestID[questID[j]] + 1] = i
                    end
                else
                    GetStepIndexFromQuestID[questID] = GetStepIndexFromQuestID[questID] or {}
                    GetStepIndexFromQuestID[questID][#GetStepIndexFromQuestID[questID] + 1] = i
                end
            end
        end
        setmetatable(GetStepIndexFromQuestID, {
            __call = function(self, questID)
                return self[questID]
            end
        })
    else
        print("CGMompanion: guide \"" .. guideName .. "\" hasn't been registered yet! Can't set the guide.")
    end
end
