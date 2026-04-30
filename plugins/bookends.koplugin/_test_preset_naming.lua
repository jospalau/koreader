-- Dev-box test runner for preset_naming.lua. Pure Lua, no KOReader deps.
-- Usage: cd into the plugin dir, then `lua _test_preset_naming.lua`.
-- Exits non-zero on failure.

local PresetNaming = dofile("preset_naming.lua")

local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        pass = pass + 1
    else
        fail = fail + 1
        io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n")
    end
end

local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "")
            .. " expected=" .. string.format("%q", tostring(expected))
            .. " got="      .. string.format("%q", tostring(actual)), 2)
    end
end

test("empty list returns bare stem", function()
    eq(PresetNaming.nextUntitledName({}, "Untitled"), "Untitled")
end)

test("unrelated presets do not block bare stem", function()
    local presets = { {name = "Minimal"}, {name = "Classic"} }
    eq(PresetNaming.nextUntitledName(presets, "Untitled"), "Untitled")
end)

test("bare stem taken returns numbered suffix", function()
    local presets = { {name = "Untitled"} }
    eq(PresetNaming.nextUntitledName(presets, "Untitled"), "Untitled 2")
end)

test("contiguous suffixes return next integer", function()
    local presets = {
        {name = "Untitled"},
        {name = "Untitled 2"},
        {name = "Untitled 3"},
    }
    eq(PresetNaming.nextUntitledName(presets, "Untitled"), "Untitled 4")
end)

test("gap in suffixes reclaims bare stem", function()
    local presets = { {name = "Untitled 5"} }
    eq(PresetNaming.nextUntitledName(presets, "Untitled"), "Untitled")
end)

test("gap at position 2 reclaims Untitled 2", function()
    local presets = { {name = "Untitled"}, {name = "Untitled 3"} }
    eq(PresetNaming.nextUntitledName(presets, "Untitled"), "Untitled 2")
end)

test("custom stem respected", function()
    local presets = { {name = "New"} }
    eq(PresetNaming.nextUntitledName(presets, "New"), "New 2")
end)

test("presets with similar-but-not-matching names ignored", function()
    local presets = {
        {name = "Untitled Saga"},
        {name = "My Untitled"},
        {name = "UntitledX"},
    }
    eq(PresetNaming.nextUntitledName(presets, "Untitled"), "Untitled")
end)

test("looksLikeDefaultName: empty / nil counts as default", function()
    eq(PresetNaming.looksLikeDefaultName("",  {"My setup"}, {"Untitled"}), true)
    eq(PresetNaming.looksLikeDefaultName(nil, {"My setup"}, {"Untitled"}), true)
end)

test("looksLikeDefaultName: exact match against default-name list", function()
    eq(PresetNaming.looksLikeDefaultName("My setup", {"My setup"}, {"Untitled"}), true)
end)

test("looksLikeDefaultName: localized default also matches", function()
    eq(PresetNaming.looksLikeDefaultName("Mi configuración",
        {"My setup", "Mi configuración"}, {"Untitled"}), true)
end)

test("looksLikeDefaultName: bare Untitled prefix", function()
    eq(PresetNaming.looksLikeDefaultName("Untitled",   {"My setup"}, {"Untitled"}), true)
    eq(PresetNaming.looksLikeDefaultName("Untitled 3", {"My setup"}, {"Untitled"}), true)
end)

test("looksLikeDefaultName: any name starting with Untitled gated", function()
    -- Per spec: literal prefix match. A user can briefly rename to bypass.
    eq(PresetNaming.looksLikeDefaultName("Untitled hero theme",
        {"My setup"}, {"Untitled"}), true)
end)

test("looksLikeDefaultName: Untitled mid-string is fine", function()
    eq(PresetNaming.looksLikeDefaultName("Pre-Untitled", {"My setup"}, {"Untitled"}), false)
end)

test("looksLikeDefaultName: case-sensitive", function()
    eq(PresetNaming.looksLikeDefaultName("untitled 3", {"My setup"}, {"Untitled"}), false)
    eq(PresetNaming.looksLikeDefaultName("my setup",   {"My setup"}, {"Untitled"}), false)
end)

test("looksLikeDefaultName: distinct user-chosen name passes", function()
    eq(PresetNaming.looksLikeDefaultName("Cool preset", {"My setup"}, {"Untitled"}), false)
end)

test("looksLikeDefaultName: pattern-magic in prefix is treated literally", function()
    -- Guards against a translation that happens to contain Lua pattern characters.
    eq(PresetNaming.looksLikeDefaultName("Untitled%2", {"My setup"}, {"Untitled%"}), true)
    eq(PresetNaming.looksLikeDefaultName("Untitled 2", {"My setup"}, {"Untitled%"}), false)
end)

test("looksLikeDefaultName: nil lists tolerated", function()
    eq(PresetNaming.looksLikeDefaultName("Anything", nil, nil), false)
    eq(PresetNaming.looksLikeDefaultName("",        nil, nil), true)
end)

test("looksLikeDefaultDescription: empty / nil counts as default", function()
    eq(PresetNaming.looksLikeDefaultDescription("",  {"Imported"}), true)
    eq(PresetNaming.looksLikeDefaultDescription(nil, {"Imported"}), true)
end)

test("looksLikeDefaultDescription: migration placeholder rejected", function()
    local D = "Imported from your earlier Bookends settings"
    eq(PresetNaming.looksLikeDefaultDescription(D, {D}), true)
end)

test("looksLikeDefaultDescription: distinct description passes", function()
    eq(PresetNaming.looksLikeDefaultDescription("My great preset",
        {"Imported from your earlier Bookends settings"}), false)
end)

io.stdout:write(string.format("%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
