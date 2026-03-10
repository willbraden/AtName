-- AtName: Focus target simulation for WoW Classic
-- Usage: /atname or /an to open the panel
-- Use {focus} in your macro body as a placeholder for the focus player name.
--
-- AtNameDB.focusName          = string
-- AtNameDB.macros[macroName]  = template string  (saved per-macro template)

AtNameDB = AtNameDB or {}

local ADDON_NAME   = "AtName"
local MACRO_PREFIX = "AN_"
local ROWS_VISIBLE = 3
local ROW_HEIGHT   = 18

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function Trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function ApplyTemplate(template, name)
    -- {focus} = global focus (updated by /focus); {target} = per-macro target (updated by @ button)
    -- Both are substituted with whatever name is passed to this function
    return (template:gsub("{focus}", name):gsub("{target}", name))
end

-- Classic Era requires MacroFrame open to call Create/Edit/DeleteMacro.
local function WithMacroFrame(fn)
    local wasOpen = MacroFrame and MacroFrame:IsShown()
    if not wasOpen then
        LoadAddOn("Blizzard_MacroUI")
        ShowUIPanel(MacroFrame)
    end
    fn()
    if not wasOpen then
        HideUIPanel(MacroFrame)
    end
end

local function GetSortedTemplates()
    local list = {}
    for name in pairs(AtNameDB.macros or {}) do
        tinsert(list, name)
    end
    table.sort(list)
    return list
end

-------------------------------------------------------------------------------
-- Focus confirmation button
-- EditMacro is a protected function that requires a hardware event (button click).
-- When /focus is typed, we store the pending name and show this button for the user to click.
-------------------------------------------------------------------------------

local pendingFocus = nil
local UpdateFocusMacros  -- forward declaration (defined after main frame)

-- Dialog frame
local focusDialog = CreateFrame("Frame", "AtNameFocusDialog", UIParent, "BackdropTemplate")
focusDialog:SetSize(280, 140)
focusDialog:SetPoint("CENTER")
focusDialog:SetFrameStrata("DIALOG")
focusDialog:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
focusDialog:SetMovable(true)
focusDialog:EnableMouse(true)
focusDialog:RegisterForDrag("LeftButton")
focusDialog:SetScript("OnDragStart", focusDialog.StartMoving)
focusDialog:SetScript("OnDragStop", focusDialog.StopMovingOrSizing)
focusDialog:Hide()

local dialogTitle = focusDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
dialogTitle:SetPoint("TOP", focusDialog, "TOP", 0, -16)
dialogTitle:SetText("Set Focus")

local dialogDivider = focusDialog:CreateTexture(nil, "ARTWORK")
dialogDivider:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
dialogDivider:SetSize(256, 32)
dialogDivider:SetPoint("TOP", focusDialog, "TOP", 0, 4)

local dialogBody = focusDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
dialogBody:SetPoint("TOP", dialogTitle, "BOTTOM", 0, -12)
dialogBody:SetWidth(240)
dialogBody:SetJustifyH("CENTER")
dialogBody:SetText("")  -- filled in by ShowFocusConfirm

local dialogOk = CreateFrame("Button", nil, focusDialog, "UIPanelButtonTemplate")
dialogOk:SetSize(80, 22)
dialogOk:SetPoint("BOTTOMRIGHT", focusDialog, "BOTTOM", -6, 14)
dialogOk:SetText("Okay")
dialogOk:SetScript("OnClick", function()
    if not pendingFocus then return end
    -- Hardware event — EditMacro is allowed here
    local count = UpdateFocusMacros(pendingFocus)
    AtNameDB.focusName = pendingFocus
    if _G["AtNameFocusInput"] then _G["AtNameFocusInput"]:SetText(pendingFocus) end
    AtNameListScrollUpdate()
    local msg = "|cffffcc00AtName focus \226\134\146 " .. pendingFocus .. "|r"
    if count > 0 then
        msg = msg .. "  |cff888888(" .. count .. " macro(s) updated)|r"
    end
    DEFAULT_CHAT_FRAME:AddMessage(msg)
    pendingFocus = nil
    focusDialog:Hide()
end)

local dialogCancel = CreateFrame("Button", nil, focusDialog, "UIPanelButtonTemplate")
dialogCancel:SetSize(80, 22)
dialogCancel:SetPoint("BOTTOMLEFT", focusDialog, "BOTTOM", 6, 14)
dialogCancel:SetText("Cancel")
dialogCancel:SetScript("OnClick", function()
    pendingFocus = nil
    focusDialog:Hide()
end)

local function ShowFocusConfirm(name)
    pendingFocus = name
    dialogBody:SetText(
        "Update all |cffffcc00{focus}|r macros to:\n\n" ..
        "|cffffcc00" .. name .. "|r"
    )
    focusDialog:Show()
end

-------------------------------------------------------------------------------
-- Main frame
-------------------------------------------------------------------------------

local frame = CreateFrame("Frame", "AtNameFrame", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(320, 310)
frame:SetPoint("CENTER")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0)
frame.title:SetText("AtName - Focus Simulator")

-------------------------------------------------------------------------------
-- Help overlay
-------------------------------------------------------------------------------

local helpOverlay = CreateFrame("Frame", nil, frame, "BackdropTemplate")
helpOverlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -22)
helpOverlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
helpOverlay:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 32, edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
helpOverlay:SetBackdropColor(0.05, 0.05, 0.10, 0.97)
helpOverlay:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)
helpOverlay:SetFrameLevel(frame:GetFrameLevel() + 10)
helpOverlay:Hide()

local helpText = helpOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
helpText:SetPoint("TOPLEFT", helpOverlay, "TOPLEFT", 14, -14)
helpText:SetPoint("BOTTOMRIGHT", helpOverlay, "BOTTOMRIGHT", -14, 36)
helpText:SetJustifyH("LEFT")
helpText:SetJustifyV("TOP")
helpText:SetSpacing(3)
helpText:SetText(
    "|cffffcc00Slash Commands|r\n" ..
    "|cff88ff88/fn|r  — set focus to current target\n" ..
    "|cff88ff88/fn|r |cffaaaaaa[name]|r  — set focus by name\n" ..
    "|cff88ff88/atfocus|r  — same as /fn\n" ..
    "|cff88ff88/an|r  — toggle this window\n" ..
    "\n" ..
    "|cffffcc00Creating a Macro|r\n" ..
    "1. Set |cff88ff88Focus|r (type a name or click From Target)\n" ..
    "2. Enter a short |cff88ff88Name|r (becomes AN_Name)\n" ..
    "3. Write the |cff88ff88Body|r — use |cffffcc00{focus}|r where you\n" ..
    "   want the player name substituted\n" ..
    "4. Click |cff88ff88Make Macro|r — drag it to your bar\n" ..
    "\n" ..
    "|cffffcc00Example body|r\n" ..
    "|cffaaaaaa#showtooltip\n" ..
    "/cast [@{focus},exists] Lay on Hands\n" ..
    "; Lay on Hands|r\n" ..
    "\n" ..
    "|cffffcc00Template List Buttons|r\n" ..
    "|cff88ff88[row click]|r  Load into form\n" ..
    "|cff88ff88@|r  Retarget this macro to current target\n" ..
    "|cff88ccffG|r  Grab macro onto cursor → click action bar\n" ..
    "|cffff4444x|r  Remove from saved list\n" ..
    "\n" ..
    "|cffffcc00Placeholders|r\n" ..
    "|cffffcc00{focus}|r  Updated by |cff88ff88/focus|r (all at once)\n" ..
    "|cffffcc00{target}|r  Updated only by the |cff88ff88@|r row button\n" ..
    "\n" ..
    "|cffffcc00Tip:|r |cff88ff88/fn|r shows a button on screen —\n" ..
    "click it once to apply. (WoW requires a click\n" ..
    "to edit macros.)"
)

local helpClose = CreateFrame("Button", nil, helpOverlay, "UIPanelButtonTemplate")
helpClose:SetSize(80, 22)
helpClose:SetPoint("BOTTOM", helpOverlay, "BOTTOM", 0, 10)
helpClose:SetText("Close")
helpClose:SetScript("OnClick", function() helpOverlay:Hide() end)

-- ? button in title bar
local helpBtn = CreateFrame("Button", nil, frame)
helpBtn:SetSize(18, 18)
helpBtn:SetPoint("RIGHT", frame.TitleBg, "RIGHT", -22, 0)
helpBtn:SetNormalFontObject(GameFontNormal)
helpBtn:SetText("|cff88ccff?|r")
helpBtn:SetScript("OnClick", function()
    if helpOverlay:IsShown() then
        helpOverlay:Hide()
    else
        helpOverlay:Show()
    end
end)
helpBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Show help & instructions")
    GameTooltip:Show()
end)
helpBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-------------------------------------------------------------------------------
-- Focus row
-------------------------------------------------------------------------------

local focusLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
focusLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -34)
focusLabel:SetText("Focus:")

local focusInput = CreateFrame("EditBox", "AtNameFocusInput", frame, "InputBoxTemplate")
focusInput:SetSize(140, 20)
focusInput:SetPoint("LEFT", focusLabel, "RIGHT", 6, 0)
focusInput:SetAutoFocus(false)
focusInput:SetMaxLetters(64)

local btnFromTarget = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
btnFromTarget:SetSize(80, 22)
btnFromTarget:SetPoint("LEFT", focusInput, "RIGHT", 4, 0)
btnFromTarget:SetText("@ Target")

-------------------------------------------------------------------------------
-- Saved templates list
-------------------------------------------------------------------------------

local listLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
listLabel:SetPoint("TOPLEFT", focusLabel, "BOTTOMLEFT", 0, -12)
listLabel:SetText("Saved Templates:")

-- Background for the list
local listBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
listBg:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
listBg:SetBackdropColor(0, 0, 0, 0.4)
listBg:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
listBg:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -2)
listBg:SetSize(288, ROWS_VISIBLE * ROW_HEIGHT + 4)

local listScroll = CreateFrame("ScrollFrame", "AtNameListScroll", listBg,
    "FauxScrollFrameTemplate")
listScroll:SetPoint("TOPLEFT", listBg, "TOPLEFT", 2, -2)
listScroll:SetSize(265, ROWS_VISIBLE * ROW_HEIGHT)
listScroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT,
        function() _G["AtNameListScrollUpdate"]() end)
end)

-- Row frames (reused, virtualised)
local listRows = {}
for i = 1, ROWS_VISIBLE do
    local row = CreateFrame("Frame", nil, listBg)
    row:SetSize(265, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", listBg, "TOPLEFT", 2, -2 - (i - 1) * ROW_HEIGHT)

    -- Invisible load button covering the whole row (minus delete btn)
    local loadBtn = CreateFrame("Button", nil, row)
    loadBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    loadBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -70, 0)
    loadBtn:RegisterForClicks("LeftButtonUp")
    loadBtn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    -- Macro name (left side)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", row, "LEFT", 6, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWidth(90)

    -- Arrow separator
    local arrow = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("LEFT", nameText, "RIGHT", 2, 0)
    arrow:SetTextColor(0.4, 0.4, 0.4)
    arrow:SetText("\226\134\146")  -- →

    -- Focus player name (right of arrow)
    local focusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    focusText:SetPoint("LEFT", arrow, "RIGHT", 2, 0)
    focusText:SetJustifyH("LEFT")
    focusText:SetWidth(88)
    focusText:SetTextColor(1, 0.82, 0)  -- gold

    -- Target button — retargets this macro to current target
    local targetBtn = CreateFrame("Button", nil, row)
    targetBtn:SetPoint("RIGHT", row, "RIGHT", -52, 0)
    targetBtn:SetSize(22, ROW_HEIGHT - 2)
    targetBtn:SetNormalFontObject(GameFontNormalSmall)
    targetBtn:SetText("|cff88ff88@|r")
    targetBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    targetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Set target\nUpdates this macro to your\ncurrent target.", nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    targetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Grab button — puts macro on cursor so user can click an action bar slot
    local grabBtn = CreateFrame("Button", nil, row)
    grabBtn:SetPoint("RIGHT", row, "RIGHT", -28, 0)
    grabBtn:SetSize(22, ROW_HEIGHT - 2)
    grabBtn:SetNormalFontObject(GameFontNormalSmall)
    grabBtn:SetText("|cff88ccff\240\159\150\x8E|r")  -- 🖎 grab cursor icon fallback
    grabBtn:SetText("|cff88ccffG|r")
    grabBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    grabBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Grab macro\nClick to attach to cursor,\nthen click an action bar slot.", nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    grabBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Delete button
    local delBtn = CreateFrame("Button", nil, row)
    delBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    delBtn:SetSize(22, ROW_HEIGHT - 2)
    delBtn:SetNormalFontObject(GameFontNormalSmall)
    delBtn:SetText("|cffff4444x|r")
    delBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")

    row.loadBtn   = loadBtn
    row.nameText  = nameText
    row.focusText = focusText
    row.targetBtn = targetBtn
    row.grabBtn   = grabBtn
    row.delBtn    = delBtn
    row:Hide()
    listRows[i] = row
end

-- Forward-declared so UpdateTemplateList can reference itself by name
function AtNameListScrollUpdate() end  -- placeholder, overwritten below

-------------------------------------------------------------------------------
-- Name row
-------------------------------------------------------------------------------

local nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
nameLabel:SetPoint("TOPLEFT", listBg, "BOTTOMLEFT", 0, -8)
nameLabel:SetText("Name:")

local nameInput = CreateFrame("EditBox", "AtNameNameInput", frame, "InputBoxTemplate")
nameInput:SetSize(140, 20)
nameInput:SetPoint("LEFT", nameLabel, "RIGHT", 8, 0)
nameInput:SetAutoFocus(false)
nameInput:SetMaxLetters(13)   -- AN_ uses 3 of 16

local nameHint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
nameHint:SetPoint("LEFT", nameInput, "RIGHT", 4, 0)
nameHint:SetTextColor(0.55, 0.55, 0.55)
nameHint:SetText("→ AN_...")

-------------------------------------------------------------------------------
-- Body textarea
-------------------------------------------------------------------------------

local bodyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bodyLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -10)
bodyLabel:SetText("Body  ({focus} or {target})")

local scrollBorder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
scrollBorder:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
scrollBorder:SetBackdropColor(0, 0, 0, 0.4)
scrollBorder:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
scrollBorder:SetPoint("TOPLEFT", bodyLabel, "BOTTOMLEFT", 0, -2)
scrollBorder:SetSize(288, 62)

local scrollFrame = CreateFrame("ScrollFrame", nil, scrollBorder, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", scrollBorder, "TOPLEFT", 4, -4)
scrollFrame:SetPoint("BOTTOMRIGHT", scrollBorder, "BOTTOMRIGHT", -24, 4)

local bodyInput = CreateFrame("EditBox", "AtNameBodyInput", scrollFrame)
bodyInput:SetSize(scrollFrame:GetWidth(), 400)
bodyInput:SetMultiLine(true)
bodyInput:SetAutoFocus(false)
bodyInput:SetMaxLetters(255)
bodyInput:SetFontObject(ChatFontNormal)
bodyInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
scrollFrame:SetScrollChild(bodyInput)

-------------------------------------------------------------------------------
-- Status text
-------------------------------------------------------------------------------

local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 34)
statusText:SetWidth(290)
statusText:SetJustifyH("LEFT")
statusText:SetText("")

local function SetStatus(msg, isError)
    statusText:SetTextColor(isError and 1 or 0.3, isError and 0.3 or 1, 0.3)
    statusText:SetText(msg)
end

-------------------------------------------------------------------------------
-- Template list logic
-------------------------------------------------------------------------------

local function LoadTemplateIntoForm(macroName)
    local entry = AtNameDB.macros and AtNameDB.macros[macroName]
    if not entry then return end
    nameInput:SetText(macroName:sub(#MACRO_PREFIX + 1))
    bodyInput:SetText(entry.template or "")
    focusInput:SetText(entry.focusName or "")
    SetStatus("Loaded: " .. macroName)
end

local function DeleteTemplate(macroName)
    if AtNameDB.macros then
        AtNameDB.macros[macroName] = nil
    end
    AtNameListScrollUpdate()
    SetStatus("Removed template: " .. macroName)
end

function AtNameListScrollUpdate()
    local templates = GetSortedTemplates()
    local offset    = FauxScrollFrame_GetOffset(listScroll)
    FauxScrollFrame_Update(listScroll, #templates, ROWS_VISIBLE, ROW_HEIGHT)

    for i = 1, ROWS_VISIBLE do
        local idx  = i + offset
        local row  = listRows[i]
        local name = templates[idx]
        if name then
            local entry = AtNameDB.macros[name] or {}
            row.nameText:SetText(name:sub(#MACRO_PREFIX + 1))
            row.focusText:SetText(entry.focusName or "")
            row.loadBtn:SetScript("OnClick", function() LoadTemplateIntoForm(name) end)
            row.targetBtn:SetScript("OnClick", function()
                local target = UnitName("target")
                if not target then SetStatus("No target selected.", true) return end
                local e = AtNameDB.macros[name]
                if not e then return end
                WithMacroFrame(function()
                    local idx = GetMacroIndexByName(name)
                    if idx and idx > 0 then
                        EditMacro(idx, name, "INV_Misc_QuestionMark",
                            ApplyTemplate(e.template, target))
                    end
                end)
                e.focusName = target
                AtNameListScrollUpdate()
                SetStatus(name:sub(#MACRO_PREFIX + 1) .. " \226\134\146 " .. target)
            end)
            row.grabBtn:SetScript("OnClick", function() PickupMacro(name) end)
            row.delBtn:SetScript("OnClick",  function() DeleteTemplate(name) end)
            row:Show()
        else
            row:Hide()
        end
    end
end

-------------------------------------------------------------------------------
-- Core macro operations
-------------------------------------------------------------------------------

-- Updates only macros whose template contains {focus}, using the global focus name.
UpdateFocusMacros = function(focusName)
    if focusName == "" then return 0 end
    local db    = AtNameDB.macros or {}
    local icon  = "INV_Misc_QuestionMark"
    local count = 0
    WithMacroFrame(function()
        for macroName, entry in pairs(db) do
            if entry.template and entry.template:find("{focus}") then
                local idx = GetMacroIndexByName(macroName)
                if idx and idx > 0 then
                    EditMacro(idx, macroName, icon, ApplyTemplate(entry.template, focusName))
                    entry.focusName = focusName
                    count = count + 1
                else
                    db[macroName] = nil
                end
            end
        end
    end)
    return count
end

local function ApplyFocus(newName)
    newName = Trim(newName)
    if newName == "" then SetStatus("Enter a focus name.", true) return end
    focusInput:SetText(newName)
    AtNameDB.focusName = newName
    SetStatus("Focus set to: " .. newName .. "  (click Make Macro to apply)")
end

local function CreateFocusMacro()
    local focusName = Trim(focusInput:GetText())
    local rawName   = Trim(nameInput:GetText())
    local template  = Trim(bodyInput:GetText())

    if focusName == "" then SetStatus("Enter a focus name first.", true) return end
    if rawName   == "" then SetStatus("Enter a macro name.",       true) return end
    if template  == "" then SetStatus("Enter a macro body.",       true) return end

    if not template:find("{focus}") then
        SetStatus("Warning: body has no {focus} — won't auto-update.", false)
    end

    local macroName = MACRO_PREFIX .. rawName:sub(1, 13)
    local macroBody = ApplyTemplate(template, focusName)
    local icon      = "INV_Misc_QuestionMark"
    local result    = ""

    WithMacroFrame(function()
        local existingIndex = GetMacroIndexByName(macroName)
        if existingIndex and existingIndex > 0 then
            EditMacro(existingIndex, macroName, icon, macroBody)
            result = "Updated: " .. macroName
        else
            local numAcct = select(1, GetNumMacros())
            if numAcct >= 120 then result = "LIMIT" return end
            CreateMacro(macroName, icon, macroBody, false)
            result = "Created: " .. macroName
        end
    end)

    if result == "LIMIT" then SetStatus("Macro limit reached (120 global).", true) return end

    AtNameDB.macros = AtNameDB.macros or {}
    AtNameDB.macros[macroName] = { template = template, focusName = focusName }
    AtNameDB.focusName = focusName
    SetStatus(result)
    AtNameListScrollUpdate()
end

local function ClearAddonMacros()
    local count = 0
    WithMacroFrame(function()
        local toDelete = {}
        local acctMacros = select(1, GetNumMacros())
        for i = 1, acctMacros do
            local mName = GetMacroInfo(i)
            if mName and mName:sub(1, #MACRO_PREFIX) == MACRO_PREFIX then
                tinsert(toDelete, mName)
            end
        end
        for _, mName in ipairs(toDelete) do
            local idx = GetMacroIndexByName(mName)
            if idx and idx > 0 then DeleteMacro(idx) count = count + 1 end
        end
    end)
    AtNameDB.macros = {}
    AtNameListScrollUpdate()
    SetStatus("Deleted " .. count .. " AtName macro(s).")
end

-------------------------------------------------------------------------------
-- Buttons
-------------------------------------------------------------------------------

local btnCreate = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
btnCreate:SetSize(100, 22)
btnCreate:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 10)
btnCreate:SetText("Make Macro")
btnCreate:SetScript("OnClick", CreateFocusMacro)

local btnClear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
btnClear:SetSize(80, 22)
btnClear:SetPoint("LEFT", btnCreate, "RIGHT", 6, 0)
btnClear:SetText("Clear All")
btnClear:SetScript("OnClick", ClearAddonMacros)

btnFromTarget:SetScript("OnClick", function()
    local target = UnitName("target")
    if target then ApplyFocus(target)
    else SetStatus("No target selected.", true) end
end)

-------------------------------------------------------------------------------
-- Keyboard handlers
-------------------------------------------------------------------------------

focusInput:SetScript("OnEnterPressed", function(self)
    ApplyFocus(self:GetText())
    self:ClearFocus()
end)

nameInput:SetScript("OnEnterPressed", function(self)
    bodyInput:SetFocus()
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

-- /fn [name] or /atfocus [name]  — set global focus, update all {focus} macros
-- (/focus conflicts with the game client or other addons, so we use /fn)
SLASH_ATFOCUS1 = "/fn"
SLASH_ATFOCUS2 = "/atfocus"
SlashCmdList["ATFOCUS"] = function(msg)
    local name = Trim(msg)
    if name == "" then
        name = UnitName("target") or ""
    end
    if name == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00AtName:|r No target and no name given.")
        return
    end
    -- Can't call EditMacro directly from slash command (not a hardware event).
    -- Show a confirm button the user clicks to apply.
    ShowFocusConfirm(name)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00AtName:|r Click the on-screen button to apply focus \226\134\146 |cffffcc00" .. name .. "|r  |cffaaaaaa(/fn or /atfocus)|r")
end

SLASH_ATNAME1 = "/atname"
SLASH_ATNAME2 = "/an"
SlashCmdList["ATNAME"] = function()
    if frame:IsShown() then
        frame:Hide()
    else
        focusInput:SetText(AtNameDB.focusName or "")
        AtNameListScrollUpdate()
        frame:Show()
    end
end

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addon)
    if addon == ADDON_NAME then
        AtNameDB        = AtNameDB or {}
        AtNameDB.macros = AtNameDB.macros or {}
        -- Migrate old plain-string entries to { template, focusName } format
        for k, v in pairs(AtNameDB.macros) do
            if type(v) == "string" then
                AtNameDB.macros[k] = { template = v, focusName = AtNameDB.focusName or "" }
            end
        end
        focusInput:SetText(AtNameDB.focusName or "")
        AtNameListScrollUpdate()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
