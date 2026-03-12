-- tests/test_macro_ops.lua
-- Integration tests for macro create / update / clear operations.
--
-- These tests exercise the functions that touch both AtNameDB and the
-- (mocked) WoW macro API, so they cover the most business-critical paths.
--
-- Run with:  busted tests/test_macro_ops.lua
--            (or just `busted` from the repo root)

_TEST = true
require("tests.mock_wow_api")
dofile("AtName.lua")

local M = _G.AtNameInternal

-- Shorthand: set all three form inputs used by CreateFocusMacro
local function set_form(focus, name, body)
    _G["AtNameFocusInput"]:SetText(focus or "")
    _G["AtNameNameInput"]:SetText(name  or "")
    _G["AtNameBodyInput"]:SetText(body  or "")
end

-------------------------------------------------------------------------------
-- UpdateFocusMacros
-------------------------------------------------------------------------------

describe("UpdateFocusMacros", function()

    before_each(function()
        reset_wow_state()
        AtNameDB = { macros = {} }
    end)

    it("returns 0 immediately when focusName is empty", function()
        local count = M.UpdateFocusMacros("")
        assert.are.equal(0, count)
    end)

    it("updates a macro whose template contains {focus}", function()
        AtNameDB.macros["AN_Heal"] = {
            template  = "/cast [@{focus},exists] Flash Heal",
            focusName = "OldTarget",
        }
        seed_macro("AN_Heal", "/cast [@OldTarget,exists] Flash Heal")

        local count = M.UpdateFocusMacros("NewTarget")
        assert.are.equal(1, count)
        -- The in-game body should now use the new name
        local macros = get_mock_macros()
        assert.are.equal("/cast [@NewTarget,exists] Flash Heal", macros["AN_Heal"].body)
    end)

    it("skips macros whose template does NOT contain {focus}", function()
        AtNameDB.macros["AN_Static"] = {
            template  = "/cast Heal",   -- no {focus} placeholder
            focusName = "OldTarget",
        }
        seed_macro("AN_Static", "/cast Heal")

        local count = M.UpdateFocusMacros("NewTarget")
        assert.are.equal(0, count)
        -- Body should be untouched
        local macros = get_mock_macros()
        assert.are.equal("/cast Heal", macros["AN_Static"].body)
    end)

    it("removes a DB entry when the macro no longer exists in-game", function()
        -- DB knows about the macro but it was deleted from the game client
        AtNameDB.macros["AN_Ghost"] = {
            template  = "/cast [@{focus}] Heal",
            focusName = "OldTarget",
        }
        -- NOTE: do NOT seed_macro → GetMacroIndexByName returns 0

        M.UpdateFocusMacros("NewTarget")
        assert.is_nil(AtNameDB.macros["AN_Ghost"])
    end)

    it("returns the correct count when updating multiple macros", function()
        local body = "/cast [@{focus}] Heal"
        AtNameDB.macros = {
            AN_A = { template = body, focusName = "Old" },
            AN_B = { template = body, focusName = "Old" },
            AN_C = { template = "/cast Heal",  focusName = "Old" },  -- no {focus}
        }
        seed_macro("AN_A", "/cast [@Old] Heal")
        seed_macro("AN_B", "/cast [@Old] Heal")
        seed_macro("AN_C", "/cast Heal")

        local count = M.UpdateFocusMacros("New")
        assert.are.equal(2, count)
    end)

    it("updates AtNameDB.macros[].focusName for each updated macro", function()
        AtNameDB.macros["AN_Heal"] = {
            template  = "/cast [@{focus}] Heal",
            focusName = "Old",
        }
        seed_macro("AN_Heal", "/cast [@Old] Heal")

        M.UpdateFocusMacros("Updated")
        assert.are.equal("Updated", AtNameDB.macros["AN_Heal"].focusName)
    end)

end)

-------------------------------------------------------------------------------
-- CreateFocusMacro – input validation
-------------------------------------------------------------------------------

describe("CreateFocusMacro — validation", function()

    before_each(function()
        reset_wow_state()
        AtNameDB = { macros = {} }
    end)

    it("does not create a macro when focus name is empty", function()
        set_form("", "Heal", "/cast [@{focus}] Flash Heal")
        M.CreateFocusMacro()
        assert.are.equal(0, get_mock_macro_count())
        assert.is_nil(AtNameDB.macros["AN_Heal"])
    end)

    it("does not create a macro when macro name is empty", function()
        set_form("Alice", "", "/cast [@{focus}] Flash Heal")
        M.CreateFocusMacro()
        assert.are.equal(0, get_mock_macro_count())
    end)

    it("does not create a macro when body is empty", function()
        set_form("Alice", "Heal", "")
        M.CreateFocusMacro()
        assert.are.equal(0, get_mock_macro_count())
    end)

    it("still creates a macro when body has no {focus} (warning case)", function()
        -- A body without {focus} is unusual but not blocked; a warning is shown.
        set_form("Alice", "Static", "/cast Heal")
        M.CreateFocusMacro()
        -- Macro should have been created despite the missing placeholder
        assert.is_not_nil(get_mock_macros()["AN_Static"])
    end)

end)

-------------------------------------------------------------------------------
-- CreateFocusMacro – happy paths
-------------------------------------------------------------------------------

describe("CreateFocusMacro — creation", function()

    before_each(function()
        reset_wow_state()
        AtNameDB = { macros = {} }
    end)

    it("creates a new macro with the AN_ prefix", function()
        set_form("Alice", "Heal", "/cast [@{focus}] Flash Heal")
        M.CreateFocusMacro()
        assert.is_not_nil(get_mock_macros()["AN_Heal"])
    end)

    it("applies the template with the current focus name on creation", function()
        set_form("Alice", "Heal", "/cast [@{focus}] Flash Heal")
        M.CreateFocusMacro()
        local macros = get_mock_macros()
        assert.are.equal("/cast [@Alice] Flash Heal", macros["AN_Heal"].body)
    end)

    it("saves the template (with placeholder intact) to AtNameDB", function()
        set_form("Alice", "Heal", "/cast [@{focus}] Flash Heal")
        M.CreateFocusMacro()
        assert.is_not_nil(AtNameDB.macros["AN_Heal"])
        assert.are.equal("/cast [@{focus}] Flash Heal", AtNameDB.macros["AN_Heal"].template)
    end)

    it("saves the focus name to AtNameDB for the new macro", function()
        set_form("Alice", "Heal", "/cast [@{focus}] Flash Heal")
        M.CreateFocusMacro()
        assert.are.equal("Alice", AtNameDB.macros["AN_Heal"].focusName)
    end)

    it("truncates the user-supplied name to 13 characters", function()
        -- Macro prefix is "AN_" (3 chars). WoW macro names are max 16 chars.
        -- The name input is capped to 13 chars by SetMaxLetters, but the
        -- CreateFocusMacro sub() is the authoritative guard.
        set_form("Alice", "1234567890ABCDE", "/cast [@{focus}] Heal")
        M.CreateFocusMacro()
        -- rawName:sub(1,13) = "1234567890ABC" → key = "AN_1234567890ABC"
        assert.is_not_nil(get_mock_macros()["AN_1234567890ABC"])
    end)

    it("updates an existing in-game macro instead of creating a duplicate", function()
        seed_macro("AN_Heal", "/cast [@OldPlayer] Flash Heal")
        AtNameDB.macros["AN_Heal"] = {
            template  = "/cast [@{focus}] Flash Heal",
            focusName = "OldPlayer",
        }
        set_form("NewPlayer", "Heal", "/cast [@{focus}] Flash Heal")
        M.CreateFocusMacro()
        -- Still only one AN_Heal macro in the game
        assert.are.equal(1, get_mock_macro_count())
        local macros = get_mock_macros()
        assert.are.equal("/cast [@NewPlayer] Flash Heal", macros["AN_Heal"].body)
    end)

    it("refuses to create a macro when the 120-macro account limit is reached", function()
        -- Fill mock storage with 120 anonymous macros
        for i = 1, 120 do
            seed_macro("FILLER_" .. i, "")
        end
        set_form("Alice", "OverLimit", "/cast [@{focus}] Heal")
        M.CreateFocusMacro()
        assert.is_nil(get_mock_macros()["AN_OverLimit"])
        assert.is_nil(AtNameDB.macros["AN_OverLimit"])
    end)

end)

-------------------------------------------------------------------------------
-- ClearAddonMacros
-------------------------------------------------------------------------------

describe("ClearAddonMacros", function()

    before_each(function()
        reset_wow_state()
        AtNameDB = { macros = {} }
    end)

    it("deletes all AN_-prefixed macros from the game", function()
        seed_macro("AN_A", "body A")
        seed_macro("AN_B", "body B")
        AtNameDB.macros = {
            AN_A = { template = "body A", focusName = "X" },
            AN_B = { template = "body B", focusName = "X" },
        }
        M.ClearAddonMacros()
        assert.are.equal(0, get_mock_macro_count())
    end)

    it("clears AtNameDB.macros after deletion", function()
        seed_macro("AN_A", "body")
        AtNameDB.macros = { AN_A = { template = "body", focusName = "X" } }
        M.ClearAddonMacros()
        assert.is_table(AtNameDB.macros)
        assert.are.equal(0, (function()
            local n = 0
            for _ in pairs(AtNameDB.macros) do n = n + 1 end
            return n
        end)())
    end)

    it("leaves non-AtName macros untouched", function()
        seed_macro("AN_Heal",     "body1")
        seed_macro("SomeOtherMacro", "body2")
        AtNameDB.macros = { AN_Heal = { template = "body1", focusName = "X" } }

        M.ClearAddonMacros()
        local macros = get_mock_macros()
        assert.is_nil(macros["AN_Heal"])
        assert.is_not_nil(macros["SomeOtherMacro"])
    end)

    it("is safe to call when there are no AtName macros", function()
        assert.has_no.errors(function() M.ClearAddonMacros() end)
    end)

end)

-------------------------------------------------------------------------------
-- LoadTemplateIntoForm
-------------------------------------------------------------------------------

describe("LoadTemplateIntoForm", function()

    before_each(function()
        reset_wow_state()
        AtNameDB = {
            macros = {
                AN_LoH = {
                    template  = "/cast [@{focus},exists] Lay on Hands\n; Lay on Hands",
                    focusName = "Arthas",
                },
            },
        }
    end)

    it("populates the name input (without AN_ prefix)", function()
        M.LoadTemplateIntoForm("AN_LoH")
        assert.are.equal("LoH", _G["AtNameNameInput"]:GetText())
    end)

    it("populates the body input with the raw template", function()
        M.LoadTemplateIntoForm("AN_LoH")
        local body = _G["AtNameBodyInput"]:GetText()
        assert.are.equal(
            "/cast [@{focus},exists] Lay on Hands\n; Lay on Hands",
            body
        )
    end)

    it("populates the focus input with the stored focus name", function()
        M.LoadTemplateIntoForm("AN_LoH")
        assert.are.equal("Arthas", _G["AtNameFocusInput"]:GetText())
    end)

    it("is a no-op when the macro name is not in AtNameDB", function()
        -- Should not throw; form inputs stay at their current values
        assert.has_no.errors(function()
            M.LoadTemplateIntoForm("AN_NonExistent")
        end)
    end)

end)

-------------------------------------------------------------------------------
-- Slash command: /fn  (ATFOCUS)
-------------------------------------------------------------------------------

describe("Slash command /fn", function()

    before_each(function()
        reset_wow_state()
        AtNameDB = { macros = {} }
    end)

    it("shows the focus-confirm dialog when called with an explicit name", function()
        SlashCmdList["ATFOCUS"]("Alice")
        assert.is_true(_G["AtNameFocusDialog"]._shown)
    end)

    it("uses the current target name when called with no argument", function()
        set_target("Thrall")
        SlashCmdList["ATFOCUS"]("")
        assert.is_true(_G["AtNameFocusDialog"]._shown)
    end)

    it("prints an error and hides the dialog when there is no target and no name", function()
        -- No target, no argument
        SlashCmdList["ATFOCUS"]("")
        assert.is_false(_G["AtNameFocusDialog"]._shown)
        assert.are.equal(1, #DEFAULT_CHAT_FRAME.messages)
    end)

end)

-------------------------------------------------------------------------------
-- Slash command: /an  (ATNAME toggle)
-------------------------------------------------------------------------------

describe("Slash command /an", function()

    before_each(function()
        reset_wow_state()
        AtNameDB = { macros = {}, focusName = "Uther" }
    end)

    it("shows the main frame when it is hidden", function()
        _G["AtNameFrame"]._shown = false
        SlashCmdList["ATNAME"]("")
        assert.is_true(_G["AtNameFrame"]._shown)
    end)

    it("hides the main frame when it is visible", function()
        _G["AtNameFrame"]._shown = true
        SlashCmdList["ATNAME"]("")
        assert.is_false(_G["AtNameFrame"]._shown)
    end)

    it("restores the saved focus name into the focus input on open", function()
        _G["AtNameFrame"]._shown = false
        SlashCmdList["ATNAME"]("")
        assert.are.equal("Uther", _G["AtNameFocusInput"]:GetText())
    end)

end)
