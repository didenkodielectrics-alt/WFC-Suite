local _, ns = ...
local WFC = WFC

-- Quick keyboard controls for quest dialogs:
--   * SPACE: Accept quest, Continue completable quest progress, or Complete quest turn-in
--            (also picks the first completable/available quest on Greeting/Gossip frames).
--   * F1, F2, F3, ...: Select between quest reward choices on the reward panel.
-- Uses temporary override bindings only while QuestFrame/GossipFrame is open out of combat,
-- and clears them immediately when the dialog closes or combat starts.

local Questing = ns.Questing
local QuickDialog = {}
ns.QuickDialog = QuickDialog

local MAX_CHOICES = 10
local bindFrame = CreateFrame("Frame", "WFC_QuestQuickBindFrame", UIParent)
local spaceBtn = CreateFrame("Button", "WFC_QuestQuickSpaceButton", bindFrame)
local choiceBtns = {}
local pendingClear = false

local function isEnabled()
    return Questing.settings == nil or Questing.settings.quickKeys ~= false
end

local function getChoiceButton(i)
    if QuestInfoRewardsFrame and QuestInfoRewardsFrame.RewardButtons and QuestInfoRewardsFrame.RewardButtons[i] then
        return QuestInfoRewardsFrame.RewardButtons[i]
    end
    local b = _G["QuestInfoRewardsFrameQuestInfoItem" .. i]
    if b then return b end
    if QuestInfo_GetRewardButton and QuestInfoRewardsFrame then
        local ok, rb = pcall(QuestInfo_GetRewardButton, QuestInfoRewardsFrame, i)
        if ok and rb then return rb end
    end
    return _G["QuestRewardItem" .. i] or _G["QuestInfoItem" .. i]
end

local function updateRewardBadges()
    local showBadges = isEnabled()
        and QuestFrame and QuestFrame:IsShown()
        and QuestFrameRewardPanel and QuestFrameRewardPanel:IsShown()
    local numChoices = (showBadges and GetNumQuestChoices and GetNumQuestChoices()) or 0

    for i = 1, MAX_CHOICES do
        local btn = getChoiceButton(i)
        if btn then
            if showBadges and numChoices > 1 and i <= numChoices then
                if not btn._wfcKeyBadge then
                    local badge = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    local icon = btn.Icon or _G[(btn:GetName() or "") .. "IconTexture"] or btn
                    badge:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
                    badge:SetShadowOffset(1, -1)
                    badge:SetShadowColor(0, 0, 0, 1)
                    btn._wfcKeyBadge = badge
                end
                btn._wfcKeyBadge:SetText(("|cffffd100[F%d]|r"):format(i))
                btn._wfcKeyBadge:Show()
            elseif btn._wfcKeyBadge then
                btn._wfcKeyBadge:Hide()
            end
        end
    end
end

local function selectChoice(i)
    if not isEnabled() then return end
    if not (QuestFrame and QuestFrame:IsShown() and QuestFrameRewardPanel and QuestFrameRewardPanel:IsShown()) then
        return
    end
    local numChoices = GetNumQuestChoices and GetNumQuestChoices() or 0
    if i < 1 or i > numChoices then return end

    local btn = getChoiceButton(i)
    if btn then
        if btn.Click then
            pcall(btn.Click, btn, "LeftButton")
        elseif QuestInfoItem_OnClick then
            pcall(QuestInfoItem_OnClick, btn)
        end
    end
    if QuestInfoFrame then QuestInfoFrame.itemChoice = i end
    if QuestFrameRewardPanel then QuestFrameRewardPanel.itemChoice = i end
end

local function onSpacePressed()
    if not isEnabled() then return end
    if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then return end

    -- 1. QuestFrame panels
    if QuestFrame and QuestFrame:IsShown() then
        -- Reward panel: complete quest
        if QuestFrameRewardPanel and QuestFrameRewardPanel:IsShown() then
            local numChoices = GetNumQuestChoices and GetNumQuestChoices() or 0
            local choice = (QuestInfoFrame and QuestInfoFrame.itemChoice)
                or (QuestFrameRewardPanel and QuestFrameRewardPanel.itemChoice) or 0
            if numChoices <= 0 then
                if GetQuestReward then
                    GetQuestReward(nil)
                elseif QuestFrameCompleteQuestButton and QuestFrameCompleteQuestButton.Click then
                    QuestFrameCompleteQuestButton:Click()
                end
            elseif numChoices == 1 then
                selectChoice(1)
                if GetQuestReward then
                    GetQuestReward(1)
                elseif QuestFrameCompleteQuestButton and QuestFrameCompleteQuestButton.Click then
                    QuestFrameCompleteQuestButton:Click()
                end
            else
                if choice and choice > 0 and GetQuestReward then
                    GetQuestReward(choice)
                elseif QuestFrameCompleteQuestButton and QuestFrameCompleteQuestButton.Click then
                    QuestFrameCompleteQuestButton:Click()
                end
            end
            return
        end

        -- Progress panel: continue completable quest
        if QuestFrameProgressPanel and QuestFrameProgressPanel:IsShown() then
            if IsQuestCompletable and IsQuestCompletable() then
                if CompleteQuest then
                    CompleteQuest()
                elseif QuestFrameCompleteButton and QuestFrameCompleteButton.Click then
                    QuestFrameCompleteButton:Click()
                end
            end
            return
        end

        -- Detail panel: accept quest
        if QuestFrameDetailPanel and QuestFrameDetailPanel:IsShown() then
            if QuestFrameAcceptButton and QuestFrameAcceptButton:IsShown() and QuestFrameAcceptButton:IsEnabled() then
                QuestFrameAcceptButton:Click()
            elseif AcceptQuest then
                AcceptQuest()
            end
            return
        end

        -- Greeting panel: pick first completable active quest, else first available quest
        if QuestFrameGreetingPanel and QuestFrameGreetingPanel:IsShown() then
            local numActive = GetNumActiveQuests and GetNumActiveQuests() or 0
            for i = 1, numActive do
                local _, isComplete = GetActiveTitle(i)
                if isComplete and SelectActiveQuest then
                    SelectActiveQuest(i)
                    return
                end
            end
            local numAvail = GetNumAvailableQuests and GetNumAvailableQuests() or 0
            if numAvail > 0 and SelectAvailableQuest then
                SelectAvailableQuest(1)
                return
            end
        end
    end

    -- 2. GossipFrame: pick first completable active quest, else first available quest
    if GossipFrame and GossipFrame:IsShown() and C_GossipInfo then
        if C_GossipInfo.GetActiveQuests then
            for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
                if q.isComplete and q.questID and C_GossipInfo.SelectActiveQuest then
                    C_GossipInfo.SelectActiveQuest(q.questID)
                    return
                end
            end
        end
        if C_GossipInfo.GetAvailableQuests then
            local avail = C_GossipInfo.GetAvailableQuests() or {}
            if #avail > 0 and avail[1].questID and C_GossipInfo.SelectAvailableQuest then
                C_GossipInfo.SelectAvailableQuest(avail[1].questID)
                return
            end
        end
    end
end

spaceBtn:SetScript("OnClick", onSpacePressed)

for i = 1, MAX_CHOICES do
    local b = CreateFrame("Button", "WFC_QuestQuickChoiceButton" .. i, bindFrame)
    b:SetScript("OnClick", function() selectChoice(i) end)
    choiceBtns[i] = b
end

local function clearBindings()
    if InCombatLockdown() then
        pendingClear = true
        return
    end
    pendingClear = false
    if ClearOverrideBindings then
        ClearOverrideBindings(bindFrame)
    end
    updateRewardBadges()
end

local function syncBindings()
    if InCombatLockdown() then return end
    if not isEnabled() then
        clearBindings()
        return
    end

    local questOpen = QuestFrame and QuestFrame:IsShown()
    local gossipOpen = GossipFrame and GossipFrame:IsShown()
    if not (questOpen or gossipOpen) then
        clearBindings()
        return
    end

    ClearOverrideBindings(bindFrame)
    SetOverrideBindingClick(bindFrame, true, "SPACE", spaceBtn:GetName(), "LeftButton")

    if questOpen and QuestFrameRewardPanel and QuestFrameRewardPanel:IsShown() then
        local numChoices = GetNumQuestChoices and GetNumQuestChoices() or 0
        for i = 1, math.min(numChoices, MAX_CHOICES) do
            SetOverrideBindingClick(bindFrame, true, "F" .. i, choiceBtns[i]:GetName(), "LeftButton")
        end
    end

    updateRewardBadges()
end

function QuickDialog:Sync()
    syncBindings()
end

WFC:RegisterEvent("PLAYER_LOGIN", function()
    local panels = {
        QuestFrame, QuestFrameDetailPanel, QuestFrameProgressPanel,
        QuestFrameRewardPanel, QuestFrameGreetingPanel, GossipFrame,
    }
    for _, f in ipairs(panels) do
        if f and f.HookScript then
            pcall(f.HookScript, f, "OnShow", syncBindings)
            pcall(f.HookScript, f, "OnHide", syncBindings)
        end
    end
end)

WFC:RegisterEvent("QUEST_DETAIL", syncBindings)
WFC:RegisterEvent("QUEST_PROGRESS", syncBindings)
WFC:RegisterEvent("QUEST_COMPLETE", syncBindings)
WFC:RegisterEvent("QUEST_GREETING", syncBindings)
WFC:RegisterEvent("GOSSIP_SHOW", syncBindings)
WFC:RegisterEvent("QUEST_FINISHED", clearBindings)
WFC:RegisterEvent("GOSSIP_CLOSED", syncBindings)

WFC:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if ClearOverrideBindings then
        pcall(ClearOverrideBindings, bindFrame)
    end
end)

WFC:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if pendingClear then clearBindings() end
    syncBindings()
end)
