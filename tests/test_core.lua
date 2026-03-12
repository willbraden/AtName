-- tests/test_core.lua
-- Unit tests for pure helper functions and database operations.
--
-- Run with:  busted tests/test_core.lua
--            (or just `busted` from the repo root)

_TEST = true
require("tests.mock_wow_api")
dofile("AtName.lua")

local M = _G.AtNameInternal

-------------------------------------------------------------------------------
-- Trim
-------------------------------------------------------------------------------

describe("Trim", function()

    it("removes leading whitespace", function()
        assert.are.equal("hello", M.Trim("   hello"))
    end)

    it("removes trailing whitespace", function()
        assert.are.equal("hello", M.Trim("hello   "))
    end)

    it("removes both leading and trailing whitespace", function()
        assert.are.equal("hello world", M.Trim("  hello world  "))
    end)

    it("returns empty string unchanged", function()
        assert.are.equal("", M.Trim(""))
    end)

    it("does not modify a string with no surrounding whitespace", function()
        assert.are.equal("already clean", M.Trim("already clean"))
    end)

    it("handles a string that is entirely whitespace", function()
        assert.are.equal("", M.Trim("   "))
    end)

end)

-------------------------------------------------------------------------------
-- ApplyTemplate
-------------------------------------------------------------------------------

describe("ApplyTemplate", function()

    it("substitutes a single {focus} placeholder", function()
        local result = M.ApplyTemplate("/cast [@{focus},exists] Flash Heal", "Arthas")
        assert.are.equal("/cast [@Arthas,exists] Flash Heal", result)
    end)

    it("substitutes a single {target} placeholder", function()
        local result = M.ApplyTemplate("/cast [@{target},exists] Lay on Hands", "Thrall")
        assert.are.equal("/cast [@Thrall,exists] Lay on Hands", result)
    end)

    it("substitutes both {focus} and {target} placeholders", function()
        local tmpl   = "[@{focus}] ; [@{target}]"
        local result = M.ApplyTemplate(tmpl, "Bob")
        assert.are.equal("[@Bob] ; [@Bob]", result)
    end)

    it("returns template unchanged when no placeholders are present", function()
        assert.are.equal("/cast Heal", M.ApplyTemplate("/cast Heal", "Anyone"))
    end)

    it("replaces multiple occurrences of the same placeholder", function()
        local tmpl   = "[@{focus}] [@{focus}]"
        local result = M.ApplyTemplate(tmpl, "Alice")
        assert.are.equal("[@Alice] [@Alice]", result)
    end)

    it("works with an empty name (edge case)", function()
        local result = M.ApplyTemplate("/cast [@{focus}] Heal", "")
        assert.are.equal("/cast [@] Heal", result)
    end)

    it("handles a realistic multi-line macro body", function()
        local tmpl = "#showtooltip\n/cast [@{focus},exists] Lay on Hands\n; Lay on Hands"
        local result = M.ApplyTemplate(tmpl, "Uther")
        assert.are.equal(
            "#showtooltip\n/cast [@Uther,exists] Lay on Hands\n; Lay on Hands",
            result
        )
    end)

end)

-------------------------------------------------------------------------------
-- GetSortedTemplates
-------------------------------------------------------------------------------

describe("GetSortedTemplates", function()

    before_each(function()
        reset_wow_state()
        AtNameDB = { macros = {} }
    end)

    it("returns an empty list when there are no saved macros", function()
        local result = M.GetSortedTemplates()
        assert.are.equal(0, #result)
    end)

    it("returns a list with one entry for a single saved macro", function()
        AtNameDB.macros = { AN_Solo = { template = "#showtooltip", focusName = "X" } }
        local result = M.GetSortedTemplates()
        assert.are.equal(1, #result)
        assert.are.equal("AN_Solo", result[1])
    end)

    it("returns names sorted alphabetically", function()
        AtNameDB.macros = {
            AN_Zebra   = { template = "z", focusName = "X" },
            AN_Alpha   = { template = "a", focusName = "X" },
            AN_Mango   = { template = "m", focusName = "X" },
        }
        local result = M.GetSortedTemplates()
        assert.are.equal(3, #result)
        assert.are.equal("AN_Alpha", result[1])
        assert.are.equal("AN_Mango", result[2])
        assert.are.equal("AN_Zebra", result[3])
    end)

    it("handles a nil AtNameDB.macros gracefully (returns empty list)", function()
        AtNameDB.macros = nil
        local result = M.GetSortedTemplates()
        assert.are.equal(0, #result)
    end)

end)

-------------------------------------------------------------------------------
-- ADDON_LOADED data-migration
--
-- Old format: AtNameDB.macros[name] = "template string"
-- New format: AtNameDB.macros[name] = { template = "...", focusName = "..." }
-------------------------------------------------------------------------------

describe("ADDON_LOADED data migration", function()

    before_each(function()
        reset_wow_state()
    end)

    it("migrates a plain-string entry to the table format", function()
        AtNameDB = {
            focusName = "OldFocus",
            macros    = { AN_Heal = "/cast [@{focus}] Flash Heal" },
        }
        fire_addon_loaded()
        assert.is_table(AtNameDB.macros.AN_Heal)
        assert.are.equal("/cast [@{focus}] Flash Heal", AtNameDB.macros.AN_Heal.template)
        assert.are.equal("OldFocus",                    AtNameDB.macros.AN_Heal.focusName)
    end)

    it("leaves a table-format entry unchanged during migration", function()
        AtNameDB = {
            focusName = "SomeFocus",
            macros    = {
                AN_Heal = { template = "/cast [{focus}] Heal", focusName = "SomeFocus" },
            },
        }
        fire_addon_loaded()
        assert.is_table(AtNameDB.macros.AN_Heal)
        assert.are.equal("/cast [{focus}] Heal", AtNameDB.macros.AN_Heal.template)
    end)

    it("initialises AtNameDB.macros to an empty table when absent", function()
        AtNameDB = {}
        fire_addon_loaded()
        assert.is_table(AtNameDB.macros)
        assert.are.equal(0, #AtNameDB.macros)
    end)

    it("migrates multiple old-style entries in one pass", function()
        AtNameDB = {
            focusName = "Focus1",
            macros = {
                AN_A = "body A",
                AN_B = "body B",
            },
        }
        fire_addon_loaded()
        assert.is_table(AtNameDB.macros.AN_A)
        assert.is_table(AtNameDB.macros.AN_B)
        assert.are.equal("body A", AtNameDB.macros.AN_A.template)
        assert.are.equal("body B", AtNameDB.macros.AN_B.template)
        assert.are.equal("Focus1", AtNameDB.macros.AN_A.focusName)
        assert.are.equal("Focus1", AtNameDB.macros.AN_B.focusName)
    end)

    it("uses empty string for focusName when AtNameDB.focusName is nil", function()
        AtNameDB = { macros = { AN_Heal = "body" } }
        fire_addon_loaded()
        assert.are.equal("", AtNameDB.macros.AN_Heal.focusName)
    end)

end)

-------------------------------------------------------------------------------
-- DeleteTemplate
-------------------------------------------------------------------------------

describe("DeleteTemplate", function()

    before_each(function()
        reset_wow_state()
        AtNameDB = {
            macros = {
                AN_HolyLight = { template = "/cast [@{focus}] Holy Light", focusName = "X" },
                AN_LoH       = { template = "/cast [@{focus}] Lay on Hands", focusName = "X" },
            },
        }
    end)

    it("removes the specified macro from AtNameDB", function()
        M.DeleteTemplate("AN_HolyLight")
        assert.is_nil(AtNameDB.macros.AN_HolyLight)
    end)

    it("does not affect other saved macros", function()
        M.DeleteTemplate("AN_HolyLight")
        assert.is_not_nil(AtNameDB.macros.AN_LoH)
    end)

    it("is a no-op when the macro does not exist", function()
        M.DeleteTemplate("AN_NonExistent")
        assert.are.equal(2, (function()
            local n = 0
            for _ in pairs(AtNameDB.macros) do n = n + 1 end
            return n
        end)())
    end)

end)
