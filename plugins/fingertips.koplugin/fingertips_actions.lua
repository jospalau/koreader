--[[
FingerTips: the actions offered in the action bar.

They are exactly the buttons of KOReader's own highlight popup, including the
ones other plugins add to it. FingerTips only stores which of them are on the
bar and in what order (by the popup's own button ids, e.g. "03_copy").
]]

local ffiUtil = require("ffi/util")
local logger = require("logger")
local _ = require("gettext")

local Actions = {}

local ORDER_KEY = "fingertips_bar_order"
local HIDDEN_KEY = "fingertips_bar_hidden"
local ROWS_KEY = "fingertips_bar_rows"

local function makeButton(hl, id)
    local fn = hl._highlight_buttons and hl._highlight_buttons[id]
    if type(fn) ~= "function" then return nil end
    local ok, button = pcall(fn, hl, nil)
    if ok and type(button) == "table" then return button end
    if not ok then logger.warn("FingerTips: popup button", id, "failed:", button) end
end

local function labelOf(button, id)
    if button.text then return button.text end
    if button.text_func then
        local ok, text = pcall(button.text_func)
        if ok and text then return text end
    end
    return id
end

-- Every popup button: { id, label, conditional }, in KOReader's own order.
-- conditional: it only shows up when it applies (a link, a single word...).
function Actions.all(hl)
    local list = {}
    if type(hl._highlight_buttons) ~= "table" then return list end
    for id in ffiUtil.orderedPairs(hl._highlight_buttons) do
        local button = makeButton(hl, id)
        if button then
            table.insert(list, {
                id = id,
                label = labelOf(button, id),
                conditional = button.show_in_highlight_dialog_func ~= nil,
            })
        end
    end
    return list
end

-- The saved arrangement applied to what exists now: shown ids in bar order,
-- and hidden ids. Buttons FingerTips hasn't seen before go at the end of the
-- shown ones, where they can be moved or unticked.
function Actions.arrangement(hl)
    local all = Actions.all(hl)
    local exists = {}
    for _, a in ipairs(all) do exists[a.id] = true end
    local saved_order = G_reader_settings:readSetting(ORDER_KEY) or {}
    local saved_hidden = G_reader_settings:readSetting(HIDDEN_KEY) or {}
    local placed, shown, hidden = {}, {}, {}
    for _, id in ipairs(saved_hidden) do
        if exists[id] and not placed[id] then
            placed[id] = true
            table.insert(hidden, id)
        end
    end
    for _, id in ipairs(saved_order) do
        if exists[id] and not placed[id] then
            placed[id] = true
            table.insert(shown, id)
        end
    end
    for _, a in ipairs(all) do
        if not placed[a.id] then
            placed[a.id] = true
            table.insert(shown, a.id)
        end
    end
    return shown, hidden, all
end

-- Saves an arrangement. Ids that aren't available right now (say, View HTML
-- while a PDF is open) keep their saved place at the end of their list.
function Actions.save(hl, shown, hidden)
    local exists = {}
    for _, a in ipairs(Actions.all(hl)) do exists[a.id] = true end
    local function merge(list, key)
        local out, seen = {}, {}
        for _, id in ipairs(list) do
            if not seen[id] then seen[id] = true; table.insert(out, id) end
        end
        for _, id in ipairs(G_reader_settings:readSetting(key) or {}) do
            if not exists[id] and not seen[id] then
                seen[id] = true
                table.insert(out, id)
            end
        end
        return out
    end
    G_reader_settings:saveSetting(ORDER_KEY, merge(shown, ORDER_KEY))
    G_reader_settings:saveSetting(HIDDEN_KEY, merge(hidden, HIDDEN_KEY))
end

function Actions.rows()
    return G_reader_settings:readSetting(ROWS_KEY, 1) == 2 and 2 or 1
end

function Actions.setRows(rows)
    G_reader_settings:saveSetting(ROWS_KEY, rows)
end

-- How many actions each set holds, given how many there are in all: with
-- room for everything, one set; otherwise every set saves a spot for More.
function Actions.perSet(rows, count)
    local slots = rows * 4
    if count <= slots then return slots, false end
    return slots - 1, true
end

-- The buttons to put on the bar right now, as KOReader would build them for
-- its popup, in the user's order, leaving out those that don't apply.
function Actions.forBar(hl)
    local shown = Actions.arrangement(hl)
    local list = {}
    for _, id in ipairs(shown) do
        local button = makeButton(hl, id)
        if button then
            local applies = true
            if button.show_in_highlight_dialog_func then
                local ok, res = pcall(button.show_in_highlight_dialog_func)
                applies = ok and res and true or false
            end
            if applies then
                table.insert(list, { id = id, button = button })
            end
        end
    end
    return list
end

Actions.MORE = _("More")

return Actions
