local _, WOTLKC = ...

-- Constants.
local TAG_QUESTNAME = "{questname}"
local TAG_X = "{x}"
local TAG_Y = "{y}"

-- Variables.
local GetStepIndexFromQuestID = {}

-- Localized globals.
local IsQuestFlaggedCompleted, IsOnQuest, GetQuestObjectives, GetQuestInfo = C_QuestLog.IsQuestFlaggedCompleted, C_QuestLog.IsOnQuest, C_QuestLog.GetQuestObjectives, C_QuestLog.GetQuestInfo
local UnitXP, UnitLevel = UnitXP, UnitLevel

-- Sets the current step to the given index.
function WOTLKC:SetCurrentStep(index, shouldScroll)
    WOTLKC.currentStep = index
    WOTLKCOptions.savedStepIndex[WOTLKC.currentGuideName] = index
    if WOTLKC:IsStepAvailable(index) and not WOTLKC:IsStepCompleted(index) and WOTLKC.currentStep ~= index then
        local step = WOTLKC.currentGuide[WOTLKC.currentStep]
        WOTLKC.UI.Arrow:SetGoal(step.x / 100, step.y / 100, step.map)
        if shouldScroll then
            WOTLKCSlider:SetValue(index)
        end
    end
end

-- Attempts to mark the step with the given index as completed.
function WOTLKC:MarkStepCompleted(index, completed)
    -- TODO: check that it can be marked incomplete here (i.e. if its been handed in already etc)
    WOTLKCOptions.completedSteps[WOTLKC.currentGuideName][index] = completed or nil
end

-- Checks if the step with the given index in the currently selected guide is completed. Returns true if so, false otherwise.
function WOTLKC:IsStepCompleted(index)
    if WOTLKCOptions.completedSteps[WOTLKC.currentGuideName][index] then
        return true
    end
    local step = WOTLKC.currentGuide[index]
    local type = step.type
    local questID = step.questID
    if type == WOTLKC.Types.Accept then -- Check if the quest(s) is completed, if it isn't, check if it's in the quest log.
        if step.isMultiStep then
            for i = 1, #step.questIDs do
                if not (IsQuestFlaggedCompleted(step.questIDs[i]) or IsOnQuest(step.questIDs[i])) then
                    return false
                end
            end
            return true -- Player has either completed all quests or is on them.
        elseif not (IsQuestFlaggedCompleted(questID) or IsOnQuest(questID)) then
            return false
        end
    elseif type == WOTLKC.Types.Do then -- Check if quest is complete in quest log, and if not then check if the player has completed all objectives of the quest(s).
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
    elseif type == WOTLKC.Types.Deliver then -- Simply check if the quest has been completed.
        if step.isMultiStep then
            for i = 1, #step.questIDs do
                if not IsQuestFlaggedCompleted(step.questIDs[i]) then
                    return false
                end
            end
        elseif not IsQuestFlaggedCompleted(questID) then
            return false
        end
    elseif type == WOTLKC.Types.Grind then -- Check for level/xp.
        if not (UnitLevel("player") >= step.level and UnitXP("player") >= step.xp) then
            return false
        end
    elseif type == WOTLKC.Types.Coordinate then -- First check if the quest has been completed, then check if the next step has been completed and return that.
        if not (IsQuestFlaggedCompleted(questID) or (WOTLKC.currentGuideName[index + 1] and WOTLKC:IsStepCompleted(index + 1))) then
            return false
        end
    end
    WOTLKC:MarkStepCompleted(index, true)
    return true
end

-- Returns true if the given step index is available to the player, false otherwise.
function WOTLKC:IsStepAvailable(index)
    local step = WOTLKC.currentGuide[index]
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
            if WOTLKC:IsStepCompleted(lockedBySteps[i]) then
                return false
            end
        end
    end
    -- This should always be checking backward, never forward.
    if step.type == WOTLKC.Types.Deliver then -- If the quest isn't marked "complete" in the quest log, return false.
        return IsQuestComplete(questID)
    elseif step.type == WOTLKC.Types.Do then
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
    elseif step.type == WOTLKC.Types.Accept and requiresSteps then
        for i = 1, #requiresSteps do
            if not self:IsStepCompleted(requiresSteps[i]) then
                return false
            end
        end
    end
    return true -- No requirements for this step.
end

-- Called on QUEST_ACCEPTED (when the player has accepted a quest).
function WOTLKC.Events:OnQuestAccepted(_, questID)
    -- No need to check any steps for the quest ID since we check for step completion dynamically when scrolling. Just update current steps.
    -- We should only scroll if the current step is of type Accept and has the same questID as this one.
    local currentStep = WOTLKC.currentGuide[WOTLKC.currentStep]
    if currentStep.type == WOTLKC.Types.Accept and currentStep.questID == questID then
        WOTLKC.UI.Main:ScrollToNextIncomplete() -- Calls UpdateStepFrames().
    else
        if WOTLKC:IsStepAvailable(WOTLKC.currentStep) then
            WOTLKC.UI.StepFrame:UpdateStepFrames()
        else
            WOTLKC.UI.Main:ScrollToNextIncomplete() -- If the current step gets locked because the player picked up another quest, should scroll to next.
        end
    end
end

-- Called on QUEST_TURNED_IN (when the player has handed in a quest).
function WOTLKC.Events:OnQuestTurnedIn(questID)
    -- Quests aren't instantly marked as complete so need to manually mark them.
    -- Should simply just mark all steps containing this quest ID to completed, except if its a multi-step, in which case we check all the quests in that step before marking.
    local stepIndeces = GetStepIndexFromQuestID(questID)
    if stepIndeces then -- If the quest actually exists in the guide.
        for i = 1, #stepIndeces do
            local step = WOTLKC.currentGuide[stepIndeces[i]]
            if step.isMultiStep then
                local isComplete = true
                for j = 1, #step.questIDs do
                    local currQuestID = step.questIDs[j]
                    isComplete = currQuestID ~= questID and not IsQuestFlaggedCompleted(currQuestID) -- Important to not check given quest ID since it will not be completed yet.
                end
                WOTLKC:MarkStepCompleted(stepIndeces[i], isComplete)
            else
                WOTLKC:MarkStepCompleted(stepIndeces[i], true)
            end
        end
        WOTLKC.UI.Main:ScrollToNextIncomplete() -- Won't scroll if current step is incomplete.
    end
end

-- Called on QUEST_REMOVED (when a quest has been removed from the player's quest log).
function WOTLKC.Events:OnQuestRemoved(questID)
    -- If the player abandonded a quest, it's assumed the player didn't want to do that part of the guide, so skip ahead to the next available quest (if the current step is now unavailable).
    local stepIndeces = GetStepIndexFromQuestID(questID)
    if stepIndeces then -- If the quest actually exists in the guide.
        for i = 1, #stepIndeces do
            local step = WOTLKC.currentGuide[stepIndeces[i]]
            if step.type == WOTLKC.Types.Accept then
                if not IsQuestFlaggedCompleted(step.questID) then
                    WOTLKC:MarkStepCompleted(stepIndeces[i], false)
                end
            elseif step.type == WOTLKC.Types.Do then
                WOTLKC:MarkStepCompleted(stepIndeces[i], WOTLKC:IsStepCompleted(stepIndeces[i]))
            end
        end
        if not WOTLKC:IsStepAvailable(WOTLKC.currentStep) then
            WOTLKC.UI.Main:ScrollToNextIncomplete() -- Calls UpdateStepFrames.
        else
            WOTLKC.UI.StepFrame:UpdateStepFrames()
        end
    end
end

-- Called on UNIT_QUESTLOG_CHANGED (when a quest's objectives are changed [and at other times]).
function WOTLKC.Events:OnUnitQuestLogChanged(unit)
    -- This function is a special case. If the player is not on all quests of the step (if multistep) then scroll to next, except don't mark the step as completed.
    if unit == "player" then
        local currentStep = WOTLKC.currentGuide[WOTLKC.currentStep]
        if currentStep.type == WOTLKC.Types.Do then
            if WOTLKC:IsStepCompleted(WOTLKC.currentStep) then
                WOTLKC.UI.Main:ScrollToNextIncomplete(fromStep) -- Calls UpdateStepFrames.
            else
                WOTLKC.UI.StepFrame:UpdateStepFrames() -- Updates the objective text on the step frame. Gets called for a second time here if picking up a quest while on "Do" step, but that's fine.
            end
        end
        
        
        -- local isPartialDone = true
        -- local isDone = true
        -- if not WOTLKCOptions.completedSteps[WOTLKC.currentGuideName][index] then
            -- local step = WOTLKC.currentGuide[WOTLKC.currentStep]
            -- if step and step.type == WOTLKC.Types.Do then
                -- if step.isMultiStep then
                    -- for i = 1, #step.questIDs do -- Quest objectives can be non-nil and non-empty for quests the player is not on.
                        -- local objectives = GetQuestObjectives(step.questIDs[i])
                        -- if objectives then
                            -- for j = 1, #objectives do
                                -- isDone = IsOnQuest(step.questIDs[i]) and objectives.finished or false -- 'finished' can be nil.
                                -- isPartialDone = not objectives.finished and false or true
                            -- end
                        -- end
                    -- end  
                -- elseif IsOnQuest(step.questID) then
                    -- local objectives = GetQuestObjectives(step.questID)
                    -- if objectives then
                        -- for i = 1, #objectives do
                            -- isDone = IsOnQuest(step.questID) and objectives.finished or false -- 'finished' can be nil.
                            -- isPartialDone = objectives.finished or false
                        -- end
                    -- end
                -- end
                -- WOTLKC:MarkStepCompleted(WOTLKC.currentStep, isDone)
                -- if isPartialDone or isDone then
                    -- WOTLKC.UI.Main:ScrollToNextIncomplete(WOTLKC.currentStep + 1)
                -- end
            -- end
        -- end
    end
end

-- Called on PLAYER_XP_UPDATE (when the player receives XP).
function WOTLKC.Events:OnPlayerXPUpdate()
    local currentStep = WOTLKC.currentGuide[WOTLKC.currentStep]
    if currentStep.type == WOTLKC.Types.Grind and WOTLKC:IsStepCompleted(WOTLKC.currentStep) then
        if WOTLKC:IsStepCompleted(WOTLKC.currentStep) then
            WOTLKC.UI.Main:ScrollToNextIncomplete()
        end
    else
        WOTLKC.UI.StepFrame:UpdateStepFrames()
    end
end

-- Called on COORDINATES_REACHED (when the player has reached the current step coordinates).
function WOTLKC.Events:OnCoordinatesReached()
    local currentStep = WOTLKC.currentGuide[WOTLKC.currentStep]
    if currentStep.type == WOTLKC.Types.Coordinate then
        WOTLKC:MarkStepCompleted(WOTLKC.currentStep, true)
        WOTLKC.UI.Main:ScrollToNextIncomplete()
    end
end

-- Called on MERCHANT_SHOW (whenever the player visits a vendor). Sells any items in the player's bags that are specified by the guide.
function WOTLKC.Events:OnMerchantShow()
    local itemsToSell = WOTLKC.currentGuide.itemsToSell
    if itemsToSell then
        for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
            for slot = 1, GetContainerNumSlots(bag) do
                local _, itemCount, _, _, _, _, itemLink, _, _, itemID = GetContainerItemInfo(bag, slot)
                if itemID and itemsToSell[itemID] then
                    WOTLKC.Logging:Message("selling " .. itemLink .. (itemCount > 1 and "x" .. itemCount or ""))
                    UseContainerItem(bag, slot)
                end
            end
        end
    end
end

-- Register a new guide for the addon.
function WOTLKC:RegisterGuide(guide)
    -- this function should check each step to make sure it has legal fields (i.e. there cant be any multistep Deliver steps etc)
    if guide.name then
        if WOTLKC.Guides[guide.name] then
            print("WOTLKCompanion: Guide with that name is already registered. Name must be unique.")
        else
            for i = 1, #guide do
                local step = guide[i]
                if step.text then
                    for tag in step.text:gmatch("{%a+}") do
                        if tag:lower() == TAG_QUESTNAME then
                            if step.isMultiStep then
                                -- what to do if step is multistep? (ie "Do" type)
                            else
                                if step.questID then
                                    step.text = step.text:gsub(tag, GetQuestInfo(step.questID))
                                end
                            end
                        elseif tag:lower() == TAG_X then
                            if step.x then
                                step.text = step.text:gsub(tag, step.x)
                            end
                        elseif tag:lower() == TAG_Y then
                            if step.y then
                                step.text = step.text:gsub(tag, step.y)
                            end
                        end
                    end
                end
            end
            WOTLKC.Guides[guide.name] = guide
        end
    else
        print("WOTLKCompanion: The guide has no name! To help you identify which guide it is, here is the first step description:\n" .. guide[1].text)
    end
end

-- Sets the currently displayed guide to the given guide (has to have been registered first).
function WOTLKC:SetGuide(guideName)
    if WOTLKC.Guides[guideName] then
        WOTLKCOptions.completedSteps[guideName] = WOTLKCOptions.completedSteps[guideName] or {}
        WOTLKC.currentGuideName = guideName
        WOTLKC.currentGuide = WOTLKC.Guides[guideName]
        if WOTLKC.currentGuide.itemsToSell then
            WOTLKC.Events:RegisterWowEvent("MERCHANT_SHOW", WOTLKC.Events.OnMerchantShow)
        else
            WOTLKC.Events:UnregisterWowEvent("MERCHANT_SHOW")
        end
        if WOTLKC.currentGuide.itemsToDelete then
            WOTLKC.Events:RegisterWowEvent("BAG_UPDATE", WOTLKC.Events.OnBagUpdate)
            for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
                WOTLKC:ScanBag(bag)
            end
        else
            WOTLKC.Events:UnregisterWowEvent("BAG_UPDATE")
        end
        WOTLKCFrame:SetTitleText(WOTLKC.currentGuideName)
        WOTLKC.UI.Main:UpdateSlider()
        if WOTLKCOptions.savedStepIndex[guideName] then
            WOTLKC:SetCurrentStep(WOTLKCOptions.savedStepIndex[guideName], true)
            WOTLKC.UI.StepFrame:UpdateStepFrames()
        else
            WOTLKC.UI.Main:ScrollToFirstIncomplete()
        end
        -- Map quest IDs to step indeces so we don't have to iterate all steps to find them.
        for i = 1, #WOTLKC.currentGuide do
            local questID = WOTLKC.currentGuide[i].questID or WOTLKC.currentGuide[i].questIDs
            if questID then
                if WOTLKC.currentGuide[i].isMultiStep then
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
        print("WOTLKCompanion: guide \"" .. guideName .. "\" hasn't been registered yet! Can't set the guide.")
    end
end

-- Initializes the UI.
function WOTLKC.UI:Init()
    WOTLKC.UI.Main:InitFrames()
    WOTLKC.UI.Arrow:InitArrow()
end
