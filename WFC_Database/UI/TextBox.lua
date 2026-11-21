local _, ns = ...
local WFC = ns.WFC

-- Minimal copy/paste window for export and import strings.
-- Built from Forever's native frame template when available (design.md §4.1).

WFC.UI = WFC.UI or {}

local box

local function create()
    local ok, frame = pcall(CreateFrame, "Frame", "WFC_TextBox", UIParent, "ButtonFrameTemplate")
    if not ok then
        frame = CreateFrame("Frame", "WFC_TextBox", UIParent, "BackdropTemplate")
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
        })
        frame:SetBackdropColor(0.086, 0.094, 0.11, 0.95)
        frame:SetBackdropBorderColor(0.23, 0.25, 0.28, 1)
    elseif ButtonFrameTemplate_HidePortrait then
        ButtonFrameTemplate_HidePortrait(frame)
    end
    frame:SetSize(520, 320)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "WFC_TextBox")

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -32)
    scroll:SetPoint("BOTTOMRIGHT", -34, 44)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(460)
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    scroll:SetScrollChild(edit)
    frame.edit = edit

    local accept = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    accept:SetSize(110, 22)
    accept:SetPoint("BOTTOMRIGHT", -14, 12)
    frame.accept = accept

    frame.titleText = frame.TitleText or frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not frame.TitleText then frame.titleText:SetPoint("TOP", 0, -8) end
    return frame
end

--- Shows text to copy (onAccept nil) or an input to paste into (onAccept(text) on Accept).
function WFC.UI:ShowTextBox(title, text, onAccept)
    box = box or create()
    box.titleText:SetText(title)
    box.edit:SetText(text or "")
    box.accept:SetText(onAccept and ACCEPT or CLOSE)
    box.accept:SetScript("OnClick", function()
        if onAccept then onAccept(box.edit:GetText()) end
        box:Hide()
    end)
    box:Show()
    box.edit:SetFocus()
    if not onAccept then box.edit:HighlightText() end
end
