-- Mock WoW Classic API for use with the busted test suite.
--
-- Load this BEFORE dofile("AtName.lua") in every test file:
--
--   _TEST = true
--   require("tests.mock_wow_api")
--   dofile("AtName.lua")
--
-- After loading, call reset_wow_state() in before_each() to wipe shared state.

-------------------------------------------------------------------------------
-- Lua compat shims (present in WoW but not in standard Lua 5.1/5.2/5.4)
-------------------------------------------------------------------------------

tinsert = table.insert

-------------------------------------------------------------------------------
-- Internal mock state
-------------------------------------------------------------------------------

local _macros = {}   -- name -> { icon, body }
local _target  = nil

-- Helpers for tests to inspect / seed mock state
function reset_wow_state()
    _macros = {}
    _target = nil
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME.messages = {} end
    AtNameDB = {}
end

function set_target(name)        _target = name end
function get_mock_macros()       return _macros end
function get_mock_macro_count()
    local n = 0
    for _ in pairs(_macros) do n = n + 1 end
    return n
end
function seed_macro(name, body)
    _macros[name] = { icon = "INV_Misc_QuestionMark", body = body }
end

-------------------------------------------------------------------------------
-- Macro API
-------------------------------------------------------------------------------

-- Returns (accountCount, charCount)
function GetNumMacros()
    local n = 0
    for _ in pairs(_macros) do n = n + 1 end
    return n, 0
end

-- Returns a stable 1-based index by sorted insertion order, or 0 if missing.
local function _macro_index(name)
    local keys = {}
    for k in pairs(_macros) do keys[#keys + 1] = k end
    table.sort(keys)
    for i, k in ipairs(keys) do
        if k == name then return i end
    end
    return 0
end

function GetMacroIndexByName(name)
    if _macros[name] then return _macro_index(name) end
    return 0
end

function GetMacroInfo(index)
    local keys = {}
    for k in pairs(_macros) do keys[#keys + 1] = k end
    table.sort(keys)
    local name = keys[index]
    if not name then return nil end
    local m = _macros[name]
    return name, m.icon, m.body
end

function CreateMacro(name, icon, body)
    _macros[name] = { icon = icon, body = body }
end

function EditMacro(index, name, icon, body)
    -- WoW EditMacro updates by index; find and overwrite the keyed entry.
    local keys = {}
    for k in pairs(_macros) do keys[#keys + 1] = k end
    table.sort(keys)
    local old_name = keys[index]
    if old_name then
        _macros[old_name] = nil
        _macros[name] = { icon = icon, body = body }
    end
end

function DeleteMacro(index)
    local keys = {}
    for k in pairs(_macros) do keys[#keys + 1] = k end
    table.sort(keys)
    local name = keys[index]
    if name then _macros[name] = nil end
end

function PickupMacro(name) end   -- no-op; side-effect is visual only

-------------------------------------------------------------------------------
-- Unit API
-------------------------------------------------------------------------------

function UnitName(unit)
    if unit == "target" then return _target end
    return nil
end

-------------------------------------------------------------------------------
-- MacroFrame (required by WithMacroFrame)
-------------------------------------------------------------------------------

MacroFrame = { _shown = false }
function MacroFrame:IsShown() return self._shown end

function LoadAddOn() end

function ShowUIPanel(f)
    if f == MacroFrame then MacroFrame._shown = true end
end

function HideUIPanel(f)
    if f == MacroFrame then MacroFrame._shown = false end
end

-------------------------------------------------------------------------------
-- Chat
-------------------------------------------------------------------------------

DEFAULT_CHAT_FRAME = {
    messages = {},
    AddMessage = function(self, msg) self.messages[#self.messages + 1] = msg end,
}

-------------------------------------------------------------------------------
-- FauxScrollFrame helpers
-------------------------------------------------------------------------------

function FauxScrollFrame_GetOffset(frame) return frame._offset or 0 end

function FauxScrollFrame_Update(frame, total, visible, height)
    frame._total   = total
    frame._visible = visible
end

function FauxScrollFrame_OnVerticalScroll(frame, offset, height, updateFn)
    frame._offset = math.floor(offset / height)
    if updateFn then updateFn() end
end

-------------------------------------------------------------------------------
-- Font / tooltip stubs
-------------------------------------------------------------------------------

local function noop() end
local function ret1() return 1 end

local _font_meta = {}
_font_meta.__index = {
    SetText        = function(self, t) self._text = t end,
    GetText        = function(self)    return self._text or "" end,
    SetPoint       = noop, SetWidth       = noop, SetHeight      = noop,
    SetJustifyH    = noop, SetJustifyV    = noop, SetSpacing     = noop,
    SetTextColor   = noop, SetFontObject  = noop,
}

local function new_fontstring()
    return setmetatable({ _text = "" }, _font_meta)
end

GameFontNormal      = {}
GameFontNormalSmall = {}
GameFontHighlight   = {}
ChatFontNormal      = {}

GameTooltip = {
    SetOwner = noop, SetText = noop, Show = noop, Hide = noop,
}

-------------------------------------------------------------------------------
-- Frame factory
-------------------------------------------------------------------------------

local _frame_meta = {}
_frame_meta.__index = {
    SetSize              = noop, SetPoint             = noop,
    SetMovable           = noop, EnableMouse          = noop,
    RegisterForDrag      = noop, StartMoving          = noop,
    StopMovingOrSizing   = noop,
    SetBackdrop          = noop, SetBackdropColor     = noop,
    SetBackdropBorderColor = noop,
    SetFrameStrata       = noop, SetFrameLevel        = noop,
    GetFrameLevel        = ret1,
    SetNormalFontObject  = noop, SetHighlightTexture  = noop,
    SetText              = function(self, t) self._text = t end,
    GetText              = function(self)    return self._text or "" end,
    SetAutoFocus         = noop, SetMaxLetters        = noop,
    SetMultiLine         = noop, SetFontObject        = noop,
    SetFocus             = noop, ClearFocus           = noop,
    SetScrollChild       = noop,
    GetWidth             = function() return 280 end,
    RegisterEvent        = noop, UnregisterEvent      = noop,
    RegisterForClicks    = noop,
    Show   = function(self) self._shown = true  end,
    Hide   = function(self) self._shown = false end,
    IsShown= function(self) return self._shown  end,
    SetScript = function(self, event, fn)
        self._scripts = self._scripts or {}
        self._scripts[event] = fn
    end,
    CreateFontString = function() return new_fontstring() end,
    -- Simulate a script trigger (used in tests to fire OnClick, OnEvent, etc.)
    FireScript = function(self, event, ...)
        if self._scripts and self._scripts[event] then
            self._scripts[event](self, event, ...)
        end
    end,
    -- Fake sub-frame referenced in BasicFrameTemplateWithInset
    TitleBg = setmetatable({}, {
        __index = { SetPoint = noop },
    }),
}

function CreateFrame(frameType, name, parent, template)
    local f = setmetatable({ _shown = false, _text = "", _scripts = {} }, _frame_meta)
    if name then _G[name] = f end
    return f
end

-- Convenience: fire the ADDON_LOADED init event during tests.
function fire_addon_loaded()
    local init = _G["AtNameInitFrame"]
    if init then
        init:FireScript("OnEvent", "ADDON_LOADED", "AtName")
    end
end
