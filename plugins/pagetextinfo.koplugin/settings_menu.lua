-- Quick settings menu: rows of buttons (font size, line spacing, margins, weight...)
-- Same look and gesture handling as the fonts menu.
--
-- Lives next to main.lua. Load it from main.lua, after PageTextInfo is defined:
--     require("settings_menu")(PageTextInfo)
--
-- It adds these methods to PageTextInfo:
--     onShowSettingsMenu, getFontXHeightInfo, applyFontSizePt
-- (plus empty stand-ins, so code in main.lua / the patches that still calls them
-- keeps working: isXHeightMode, applyDefaultXHeight, hasRemStyles,
-- reapplyFontCompensation, warmUpOnReady, warmUpCaches)
--
-- SIMPLE VERSION: sizes are set in pt only, exactly as chosen. The only
-- measurement left is the x-height of a font: ONE read of the value stored in the
-- font file (per face, cached), and x-height (mm) = that ratio * pt. Nothing is
-- measured on the page, nothing is asked to crengine, and there are no tables.

local Device = require("device")
local Font = require("ui/font")
local Screen = Device.screen

-- Debug logging: every message of this file starts with the same tag, so a
-- single grep shows the whole flow:
--     ./kodev run | grep -F "[PTI]"
-- Set DEBUG_LOG to false to silence it (warnings and errors are always logged).
local DEBUG_LOG = false
local PTI_TAG = "[PTI]"
local function dlog(...)
    if DEBUG_LOG then require("logger").dbg(PTI_TAG, ...) end
end

return function(PageTextInfo)

local WEIGHT_STEP = 0.5
local FONT_STEP_PT = 0.5          -- one tap of the fine size buttons

-- Width of a text in the "cfont" face at a given size (needed to find the biggest
-- font that fits a button). Widths never change during a session: measured once.
local _tw_cache, _tw_count = {}, 0
local function textWidth(text, size, bold)
    local key = size .. (bold and "b|" or "|") .. text
    local w = _tw_cache[key]
    if w then return w end
    local tw = require("ui/widget/textwidget"):new{
        text = text, face = Font:getFace("cfont", size), bold = bold and true or false }
    w = tw:getSize().w
    tw:free()
    if _tw_count >= 600 then _tw_cache, _tw_count = {}, 0 end
    _tw_cache[key] = w
    _tw_count = _tw_count + 1
    return w
end

-- Font sizes are in points and are the biggest wanted: the window lowers them
-- only as much as needed for its texts to fit.
local WINDOW_W_RATIO = 0.92            -- window width, as a fraction of the screen
local BTN_FONT_SIZE, BTN_FONT_MIN = 16, 10     -- buttons
local LABEL_FONT_SIZE, LABEL_FONT_MIN = 15, 9  -- section labels
local TITLE_FONT_SIZE, TITLE_FONT_MIN = 14, 9  -- title block

local CONTRAST_MIN, CONTRAST_MAX = 0, 56
local CONTRAST_DEFAULT = 15

-- Size presets, in pt. "Default" (also what "Reset defaults" applies) is fixed.
local PT_DEFAULT_SIZE = 9.5
local PT_SMALL, PT_BIG = 8.5, 11
local function defaultFontSize()
    return PT_DEFAULT_SIZE
end

-- Line spacing presets. All my Calibre books were converted so every
-- line-height is a unitless 1.2 (see the Calibre "Transform styles" rules).
-- KOReader's percentage multiplies on top of that, so 100% = the 1.2em
-- baseline, and the other steps are ~1.1em / 1.3em / 1.4em
-- (e.g. 1.1/1.2 = 92%, 1.3/1.2 = 108%, 1.4/1.2 = 117%). These are the same
-- values the fine step (stepLineSpacing) produces, so presets and steps agree.
-- Labels are only accurate with "Book styles" enabled in KOReader and for
-- books that went through that conversion.
local LINE_SPACINGS = {
    { percent = 92,  label = "1.1em" },
    { percent = 100, label = "1.2em" },
    { percent = 108, label = "1.3em" },
    { percent = 117, label = "1.4em" },
}

-- {left, top, right, bottom}: use the same units your margins option uses
local MARGIN_PRESETS = {
    { label = "Default (small)", value = { 15, 15, 15, 10 } },
    { label = "Slightly bigger", value = { 20, 40, 20, 35 } },
    { label = "Big",             value = { 50, 50, 50, 50 } },
    { label = "Bigger",          value = { 70, 70, 70, 70 } },
}
local DEFAULTS = { font_face = "Capita", line_spacing = 100, font_base_weight = 0,
                   margins = MARGIN_PRESETS[1].value }

local GAMMA_TABLE = { 0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9,
    0.95, 0.98, 1, 1.02, 1.05, 1.1, 1.15, 1.2, 1.25, 1.3, 1.35, 1.4, 1.45,
    1.5, 1.6, 1.7, 1.8, 1.9, 2, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9,
    3, 3.5, 4, 4.5, 5, 5.5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }

local function close(self)
    local UIManager = require("ui/uimanager")
    local d = self.settings_dialog
    self.settings_dialog = nil
    self.settings_offset = nil   -- the next time it opens it is at its place again
    dlog("settings menu closed")
    -- The window may have been moved: refresh where it is now
    if d then UIManager:close(d, "ui", (d.frame and d.frame.dimen) or d.frame_rect) end
end

-- The screen changed size (rotation): rebuild the window for the new size, once.
-- Called from the window's own resize event (so it is replaced BEFORE the first
-- paint at the new size) and, as a fallback, right after the rotation call.
local function rebuildIfResized(plugin, dlg)
    if plugin.settings_dialog ~= dlg or dlg.built_w == Screen:getWidth() then return end
    dlog("screen resized: rebuilding menu", dlg.built_w, "->", Screen:getWidth())
    -- the old offset belongs to the old orientation
    if dlg.movable then pcall(dlg.movable.setMovedOffset, dlg.movable, { x = 0, y = 0 }) end
    plugin:onShowSettingsMenu()
end

-- Actions ---------------------------------------------------------------

-- Name of the face the book is using now
local function currentFace(ui)
    return ui.font and ui.font.font_face
end

local function setFontFace(ui, face)
    if not face or face == "" then return end
    dlog("setFontFace:", face, "rolling=", ui.rolling and true or false)
    if ui.rolling then  -- only reflowable (CRE) documents support font faces
        ui.font:onSetFont(face)
    end
end

local function setFontSize(ui, pt)
    pt = math.floor(math.max(4, math.min(pt, 255)) * 100 + 0.5) / 100
    ui.font:onSetFontSize(pt, true)
    -- Keep both configurables in sync (harmless if they are the same table)
    ui.document.configurable.font_size = pt
    ui.font.configurable.font_size = pt
    dlog("setFontSize:", pt)
end

-- Fine step of the size: FONT_STEP_PT up or down
local function stepFontSize(ui, dir)
    local cur = ui.font.configurable.font_size or defaultFontSize()
    setFontSize(ui, cur + dir * FONT_STEP_PT)
end

local function setLineSpacing(ui, percent)
    dlog("setLineSpacing: percent=", percent)
    ui.document:setInterlineSpacePercent(percent)
    ui.document.configurable.line_spacing = percent
    ui:handleEvent(require("ui/event"):new("UpdatePos"))
end

-- Fine step of the line spacing: 0.05em up or down (100% = 1.2em, same
-- convention as LINE_SPACINGS), converted back to KOReader's percentage.
local SPACING_STEP_EM = 0.05
local SPACING_MIN, SPACING_MAX = 50, 200

local function stepLineSpacing(ui, dir)
    local cur = ui.document.configurable.line_spacing or 100
    -- Snap the current value to the 0.05em grid so presets (e.g. 109% = 1.308em)
    -- move to the neighbouring grid value instead of drifting
    local cur_em = math.floor(1.2 * cur / 100 / SPACING_STEP_EM + 0.5) * SPACING_STEP_EM
    local new_em = cur_em + dir * SPACING_STEP_EM
    local percent = math.floor(new_em * 100 / 1.2 + 0.5)
    percent = math.max(SPACING_MIN, math.min(percent, SPACING_MAX))
    dlog("stepLineSpacing: dir=", dir, "from", cur, "% to", percent, "%")
    setLineSpacing(ui, percent)
end

local function setMargins(ui, m)
    -- m = {left, top, right, bottom}. The event does not store them, so do it here
    dlog("setMargins: l,t,r,b=", m[1], m[2], m[3], m[4])
    local conf = ui.document.configurable
    conf.h_page_margins = { m[1], m[3] }
    conf.t_page_margin  = m[2]
    conf.b_page_margin  = m[4]
    ui.typeset:onSetPageMargins(m)
end

local function setWeight(ui, w)
    w = math.max(-3, math.min(w, 5))
    dlog("setWeight:", w)
    ui.document.configurable.font_base_weight = w
    ui.font:onSetFontBaseWeight(w)
end

-- `apply` is the change itself (it sends its own UpdatePos). It is batched, as KOReader
-- does for several changes, so the page is laid out ONCE and the input is inhibited
-- once, not twice (the change alone, then an extra UpdatePos of our own).
local function rerenderOnce(ui, apply)
    local UIManager = require("ui/uimanager")
    local Event = require("ui/event")
    UIManager:broadcastEvent(Event:new("BatchedUpdate"))
    local ok, err = pcall(apply)
    -- Always close the batch, or the page would never be laid out again
    UIManager:broadcastEvent(Event:new("BatchedUpdateDone"))
    if not ok then require("logger").warn("[PTI] rerenderOnce failed:", err) end
end

local function getContrast(ui)
    local conf = ui.document.configurable
    return conf.font_gamma
        or G_reader_settings:readSetting("copt_font_gamma")
        or CONTRAST_DEFAULT
end

-- Font hinting: 0 = off, 1 = native, 2 = auto (KOReader's "Font Hinting" option)
local function getHinting(ui)
    return ui.document.configurable.font_hinting
        or G_reader_settings:readSetting("copt_font_hinting")
        or 2
end

local function setHinting(ui, mode)
    dlog("setHinting:", mode)
    ui.document.configurable.font_hinting = mode
    ui.font.configurable.font_hinting = mode
    -- Same call KOReader's own option makes (applies it, reflows and shows a notification)
    rerenderOnce(ui, function() ui.font:onSetFontHinting(mode) end)
end

local function setContrast(ui, g)
    g = math.floor(math.max(CONTRAST_MIN, math.min(g, CONTRAST_MAX)) + 0.5)
    dlog("setContrast: index=", g, "gamma=", GAMMA_TABLE[g + 1])
    ui.document.configurable.font_gamma = g
    ui.font.configurable.font_gamma = g

    -- Same call KOReader's own handler makes (also shows its notification)
    rerenderOnce(ui, function() ui.font:onSetFontGamma(g) end)
end

-- One index at a time over KOReader's full gamma table (0..56)
local function stepContrast(ui, dir)
    setContrast(ui, getContrast(ui) + dir)
end

-- Save the current font face as KOReader's default for new books (what "Reset
-- defaults" and a new book then use). The size is not saved: it is always
-- PT_DEFAULT_SIZE. Returns face.
local function saveCurrentFontAsDefault(ui)
    local face = currentFace(ui)
    if not face then return nil end
    dlog("saveCurrentFontAsDefault: saving face=", face)
    G_reader_settings:saveSetting("cre_font", face)
    G_reader_settings:flush()
    return face
end

local function resetDefaults(ui)
    dlog("resetDefaults")
    -- Use the face saved with the long press; fall back to DEFAULTS.font_face
    setFontFace(ui, G_reader_settings:readSetting("cre_font") or DEFAULTS.font_face)
    setFontSize(ui, defaultFontSize())
    setLineSpacing(ui, DEFAULTS.line_spacing)
    setMargins(ui, DEFAULTS.margins)
    setWeight(ui, DEFAULTS.font_base_weight)
end


-- ASSUMPTION: "toggle screen layout" = swap portrait/landscape. Change it to
-- whatever you meant (e.g. footer toggle) in this one function.
local function toggleLayout(ui)
    local Event = require("ui/event")
    dlog("toggleLayout: SwapRotation")
    -- Batched, like the other changes: the book is laid out ONCE for the new
    -- orientation instead of once per step of the rotation
    rerenderOnce(ui, function() ui:handleEvent(Event:new("SwapRotation")) end)
end

-- Menu definition -------------------------------------------------------
-- Each button: text, callback(ui), active(ui) (optional, inverted when true)

local function approx(a, b) return a and b and math.abs(a - b) < 0.001 end

local function marginsMatch(conf, m)
    local h = conf.h_page_margins
    return h and approx(h[1], m[1]) and approx(h[2], m[3])
        and approx(conf.t_page_margin, m[2]) and approx(conf.b_page_margin, m[4])
end

-- KOReader style tweaks (Style tweaks menu) -------------------------------
-- Each tweak id is found at runtime by its title (all `needles` must appear in
-- the lowercase title), so no id is hard-coded. Everything is wrapped in pcall:
-- if the KOReader internals differ, a button just does nothing and logs why.
local TWEAK_BUTTONS = {
    -- Ignore font sizes / Reset main text size conflict in KOReader (conflicts_with):
    -- turning one on turns the other off first (same mechanism as left / justify)
    -- solo = true: the button gets a row of its own (full width)
    { label = "Reset main text size", needles = { "reset main text" },
      excludes = "Ignore font sizes", solo = true },
    { label = "Ignore font sizes",    needles = { "ignore", "font sizes" },
      excludes = "Reset main text size" },
    { label = "Ignore font families",  needles = { "ignore", "font families" } },
    { label = "Ignore page margins",   needles = { "ignore", "page margins" } },
    { label = "Indent first paragraph", needles = { "indent", "first" } },
    { label = "Left align text",       needles = { "left align" },
      excludes = "Justify text" },
    { label = "Justify text",          needles = { "justify most" },
      excludes = "Left align text" },
}
local _tweak_ids = {}   -- [label] = id, or false when not found

local function tweakId(def)
    if _tweak_ids[def.label] ~= nil then return _tweak_ids[def.label] or nil end
    local found = false
    local ok, tweaks = pcall(require, "ui/data/css_tweaks")
    if ok and type(tweaks) == "table" then
        local seen = {}
        local function walk(t)
            if seen[t] then return end
            seen[t] = true
            for _, v in pairs(t) do
                if type(v) == "table" then
                    if type(v.title) == "string" and v.id then
                        local title = v.title:lower()
                        local all = true
                        for _, n in ipairs(def.needles) do
                            if not title:find(n, 1, true) then all = false break end
                        end
                        if all then found = v.id return end
                    end
                    walk(v)
                    if found then return end
                end
            end
        end
        walk(tweaks)
    end
    _tweak_ids[def.label] = found
    dlog("tweakId:", def.label, "->", found)
    return found or nil
end

local function tweakActive(ui, def)
    local id = tweakId(def)
    local st = ui.styletweak
    if not (id and st) then return false end
    local t = st.doc_tweaks
    if t and t[id] ~= nil then return t[id] and true or false end
    t = st.global_tweaks
    return (t and t[id]) and true or false
end

local function setTweak(ui, id, want)
    local st = ui.styletweak
    if st.onToggleStyleTweak then
        st:onToggleStyleTweak(id, nil, want)
    else
        st.doc_tweaks = st.doc_tweaks or {}
        st.doc_tweaks[id] = want or nil
        if ui.doc_settings then ui.doc_settings:saveSetting("style_tweaks", st.doc_tweaks) end
        if st.updateCssText then st:updateCssText(true) end
    end
end

local function toggleTweak(ui, def)
    local id = tweakId(def)
    if not (id and ui.styletweak) then
        dlog("toggleTweak:", def.label, "tweak or ReaderStyleTweak not found")
        return
    end
    local want = not tweakActive(ui, def)
    local ok, err = pcall(setTweak, ui, id, want)
    dlog("toggleTweak:", def.label, "want=", want, "ok=", ok, err, "now=", tweakActive(ui, def))
end

local function buildRows(ui)
    local conf = ui.document.configurable
    local fs = ui.font.configurable.font_size

    -- The first button opens the fonts menu (font_selection_menu.lua). Handled in
    -- the dialog's onTap (open_fonts): the callback is not used, because the
    -- settings menu must NOT be reopened over the fonts menu afterwards.
    local font_preset_row = {
        { text = "Face",    open_fonts = true, callback = function() end },
    }
    for __, p in ipairs({
        { "Small",   PT_SMALL },
        { "Default", defaultFontSize() },
        { "Big",     PT_BIG },
    }) do
        table.insert(font_preset_row, {
            text = p[1],
            callback = function(u) setFontSize(u, p[2]) end,
            active = approx(fs, p[2]),
        })
    end
    local font_step_row = {
        { text = "▼", callback = function(u) stepFontSize(u, -1) end },
        { text = "▲", callback = function(u) stepFontSize(u,  1) end },
    }
    local spacing_row, margins_row = {}, {}
    local spacing_step_row = {
        { text = "▼", callback = function(u) stepLineSpacing(u, -1) end },
        { text = "▲", callback = function(u) stepLineSpacing(u,  1) end },
    }
    local weight_row = {
        { text = "▼", callback = function(u) setWeight(u, u.document.configurable.font_base_weight - WEIGHT_STEP) end },
        { text = "▲", callback = function(u) setWeight(u, u.document.configurable.font_base_weight + WEIGHT_STEP) end },
    }
    local contrast_row = {
        { text = "▼", callback = function(u) stepContrast(u, -1) end },
        { text = "▲", callback = function(u) stepContrast(u, 1) end },
    }
    local hinting_now = getHinting(ui)
    local hinting_row = {
        { text = "Off",    callback = function(u) setHinting(u, 0) end, active = hinting_now == 0 },
        { text = "Native", callback = function(u) setHinting(u, 1) end, active = hinting_now == 1 },
        { text = "Auto",   callback = function(u) setHinting(u, 2) end, active = hinting_now == 2 },
    }
    local rows = {
        { title = "General",
            { text = "Reset defaults",      callback = resetDefaults },
            -- rotate = true: handled in the dialog's onTap (close first, rotate,
            -- reopen once), so the menu is never drawn at the old size
            { text = "Toggle screen layout", rotate = true, callback = toggleLayout },
        },
        font_preset_row,
        font_step_row,
        spacing_row,
        spacing_step_row,
        margins_row,
        weight_row,
        contrast_row,
        hinting_row,
    }
    -- Section labels, shown to the left of each row (a row without a title
    -- gets none: it continues the one above)
    font_preset_row.title = "Font"
    font_step_row.title = "Fine size"
    spacing_row.title = "Line spacing"
    spacing_step_row.title = "Fine spacing"
    margins_row.title = "Margins"
    weight_row.title = "Weight"
    contrast_row.title = "Contrast"
    hinting_row.title = "Hinting"

    local ls = conf.line_spacing
    for __, spacing in ipairs(LINE_SPACINGS) do
        table.insert(spacing_row, {
            text = spacing.label,
            callback = function(u) setLineSpacing(u, spacing.percent) end,
            -- Presets use the same rounded percentages as the fine step, so an
            -- (almost) exact match is enough
            active = ls and math.abs(ls - spacing.percent) < 0.5,
        })
    end
    for __, p in ipairs(MARGIN_PRESETS) do
        table.insert(margins_row, {
            text = p.label,
            callback = function(u) setMargins(u, p.value) end,
            active = marginsMatch(conf, p.value) and true or false,
        })
    end

    -- KOReader style tweaks, two buttons per row. Left align / justify are
    -- exclusive in KOReader: turning one on turns the other off first.
    local tweak_row
    for i, def in ipairs(TWEAK_BUTTONS) do
        -- New row when there is none yet, the button is solo, the row above is solo
        -- or the row above is full (two buttons)
        if not tweak_row or def.solo or tweak_row.solo or #tweak_row >= 2 then
            tweak_row = { solo = def.solo }
            table.insert(rows, tweak_row)
            if i == 1 then tweak_row.title = "Style tweaks" end
        end
        table.insert(tweak_row, {
            text = def.label,
            callback = function(u)
                if def.excludes and not tweakActive(u, def) then
                    for __, other in ipairs(TWEAK_BUTTONS) do
                        if other.label == def.excludes and tweakActive(u, other) then
                            toggleTweak(u, other)
                        end
                    end
                end
                toggleTweak(u, def)
            end,
            active = tweakActive(ui, def),
        })
    end
    return rows
end

-- x-height of a font ------------------------------------------------------
-- The simplest measurement: the x-height stored in the font file (what
-- face.ftsize:getXHeight() returns), read ONCE per face and cached. It is a
-- fraction of the em, so for any size:  x-height (mm) = ratio * pt * 25.4 / 72.

local FontList = require("fontlist")
local _face_cache = {}   -- [family name] = path or guessed name

-- Real file of the Regular style of a family, found through KOReader's
-- font list. Falls back to the old "Name-Regular" guess.
local function resolveFace(raw_name)
    if _face_cache[raw_name] then return _face_cache[raw_name] end
    local function norm(s) return (s:gsub("%s+", ""):lower()) end
    local want = norm(raw_name)

    FontList:getFontList()   -- makes sure fontinfo is filled
    local best, any
    for path, info in pairs(FontList.fontinfo or {}) do
        for __, f in ipairs(info) do
            if f.name and norm(f.name) == want then
                -- tie-break on path so the result doesn't depend on pairs() order
                if not f.bold and not f.italic then
                    if not best or path < best then best = path end
                elseif not any or path < any then
                    any = path
                end
            end
        end
    end

    -- Only cache real matches. The "Name-Regular" guess is not cached
    -- (the font list may not be ready yet).
    if best or any then
        _face_cache[raw_name] = best or any
        return best or any
    end
    return (raw_name:gsub("%s+", "") .. "-Regular")
end

-- Font:getFace keeps every face it loads in Font.faces for good, and a face is a
-- whole font file mapped in memory. The face made only to read the x-height is
-- taken out of that cache right away.
local function releaseFace(face)
    if not face then return end
    local faces = Font.faces
    if type(faces) == "table" then
        for k, v in pairs(faces) do
            if v == face then faces[k] = nil; break end
        end
    end
end

local XH_READ_PX = 100
local _ratio_cache = {}   -- [font file] = x-height / em  (false when it can't be read)

local function xHeightRatioOfPath(path)
    local cached = _ratio_cache[path]
    if cached ~= nil then return cached or nil end
    local ratio = false
    local face = Font:getFace(path, XH_READ_PX, 0, true)
    if face and face.ftsize then
        local size = face.size or XH_READ_PX
        local ok, xh = pcall(function() return face.ftsize:getXHeight() end)
        if ok and xh and xh > 0 and size > 0 then
            ratio = ((xh < 1) and xh or (xh / size))
        end
    end
    releaseFace(face)
    _ratio_cache[path] = ratio
    dlog("xHeightRatio:", path, "->", ratio)
    return ratio or nil
end

-- Rows of the x-height as crengine draws them --------------------------------
-- What the eye sees is a whole number of pixel rows, not the design value of the
-- font file: crengine draws whole pixel sizes, and the hinting snaps the letters to
-- the pixel grid. So the number shown is the height in rows of the typical letters
-- (round ones included, the way the eye judges them), measured at the pixel size
-- really drawn and with the hinting in use:
--   1) asked to the engine itself (patched koreader-base: doc:getGlyphTops, only for
--      the face now in the book);
--   2) else FreeType, opened directly with the load flags crengine uses for the
--      hinting mode (shown with a "~");
--   3) else the design value ratio * px (also "~").

-- Letters whose top is at the x-height, with their frequency in English text (%)
local TYPICAL_LETTERS = {
    e = 12.7, a = 8.2, o = 7.5, n = 6.7, s = 6.3, r = 6.0, c = 2.8, u = 2.8,
    m = 2.4, w = 2.4, g = 2.0, y = 2.0, p = 1.9, v = 1.0, x = 0.15, q = 0.1, z = 0.07,
}

local function weightedMedian(tops)   -- tops: { { top, weight }, ... }
    if #tops == 0 then return nil end
    table.sort(tops, function(a, b) return a[1] < b[1] end)
    local total = 0
    for __, t in ipairs(tops) do total = total + t[2] end
    local acc = 0
    for __, t in ipairs(tops) do
        acc = acc + t[2]
        if acc >= total / 2 then return t[1] end
    end
    return tops[#tops][1]
end

-- The load flags crengine uses (lvfntman.cpp): [hinting mode] = flags
local FT_LOAD_NO_HINTING, FT_LOAD_RENDER = 0x2, 0x4
local FT_LOAD_FORCE_AUTOHINT, FT_LOAD_NO_AUTOHINT = 0x20, 0x8000
local FT_LOAD_TARGET_LIGHT = 0x10000
local HINT_LOAD_FLAGS = {
    [0] = FT_LOAD_RENDER + FT_LOAD_TARGET_LIGHT + FT_LOAD_NO_AUTOHINT + FT_LOAD_NO_HINTING,   -- off
    [1] = FT_LOAD_RENDER + FT_LOAD_TARGET_LIGHT + FT_LOAD_NO_AUTOHINT,                        -- native
    [2] = FT_LOAD_RENDER + FT_LOAD_TARGET_LIGHT + FT_LOAD_FORCE_AUTOHINT,                     -- auto
}

-- Same library KOReader's own ffi/freetype.lua uses; the load name changes with the
-- version / platform, so several are tried. Loaded and initialised once.
local _ft   -- { ffi, lib, library }, or false when FreeType can't be reached
local function getFreeType()
    if _ft ~= nil then return _ft or nil end
    _ft = false
    local ok = pcall(function()
        local ffi = require("ffi")
        require("ffi/freetype_h")   -- C declarations (FT_Library, FT_Face, ...)
        pcall(require, "ffi/loadlib")
        local lib
        for __, try in ipairs({
            function() return ffi.loadlib("freetype", "6") end,
            function() return ffi.load("freetype") end,
            function() return ffi.load("libs/libfreetype.so.6") end,
            function() return ffi.load("libfreetype.so.6") end,
        }) do
            local ok2, l = pcall(try)
            if ok2 and l then lib = l; break end
        end
        if not lib then return end
        local library = ffi.new("FT_Library[1]")   -- one for the whole session
        if lib.FT_Init_FreeType(library) == 0 then
            _ft = { ffi = ffi, lib = lib, library = library }
        end
    end)
    if not ok then _ft = false end
    return _ft or nil
end

local _rows_cache = {}   -- [key] = rows, or false when it can't be measured

-- Rows of the typical letters at `px`, loaded straight through FreeType
local function freeTypeRows(path, px, hint)
    local flags = HINT_LOAD_FLAGS[hint]
    if not flags or type(path) ~= "string" or not path:find("/", 1, true) then return nil end
    local key = path .. "|" .. hint .. "|" .. px .. "|ft"
    if _rows_cache[key] ~= nil then return _rows_cache[key] or nil end
    local rows = false
    pcall(function()
        local ft = getFreeType()
        if not ft then return end
        local face = ft.ffi.new("FT_Face[1]")
        pcall(function()
            if ft.lib.FT_New_Face(ft.library[0], path, 0, face) ~= 0 then return end
            if ft.lib.FT_Set_Pixel_Sizes(face[0], 0, px) ~= 0 then return end
            local tops = {}
            for ch, w in pairs(TYPICAL_LETTERS) do
                local gi = ft.lib.FT_Get_Char_Index(face[0], string.byte(ch))
                if gi ~= 0 and ft.lib.FT_Load_Glyph(face[0], gi, flags) == 0 then
                    local t = tonumber(face[0].glyph.bitmap_top)
                    if t and t > 0 then tops[#tops + 1] = { t, w } end
                end
            end
            rows = weightedMedian(tops) or false
        end)
        -- Always release the face, even if the measurement failed
        if face[0] ~= nil then pcall(function() ft.lib.FT_Done_Face(face[0]) end) end
    end)
    _rows_cache[key] = rows
    return rows or nil
end

-- Rows of the typical letters asked to the engine for the face now in the book
-- (needs the getGlyphTops patch; nil without it, or when the engine scaled the size)
local _letters
local function engineRows(ui, px, hint)
    local d = ui.document and ui.document._document
    if not (d and d.getGlyphTops) then
        dlog("engineRows: doc:getGlyphTops is NOT available")
        return nil
    end
    local weight = ui.document.configurable.font_base_weight or 0
    local key = tostring(ui.font and ui.font.font_face) .. "|" .. hint .. "|" .. px .. "|" .. weight .. "|eng"
    if _rows_cache[key] ~= nil then return _rows_cache[key] or nil end
    if not _letters then
        local l = {}
        for ch in pairs(TYPICAL_LETTERS) do l[#l + 1] = ch end
        _letters = table.concat(l)
    end
    local rows = false
    local ok, t, used = pcall(d.getGlyphTops, d, _letters, px)
    dlog("engineRows: asked px=", px, "used=", used, "ok=", ok)
    if ok and type(t) == "table" and used == px then
        local tops = {}
        for ch, w in pairs(TYPICAL_LETTERS) do
            local v = t[ch]
            if v and v > 0 then tops[#tops + 1] = { v, w } end
        end
        rows = weightedMedian(tops) or false
    end
    _rows_cache[key] = rows
    return rows or nil
end

-- Public method (used by the fonts menu in font_selection_menu.lua): x-height of a
-- face (by name) at the size now set in the book. Returns { ratio, mm, pt, px, rows,
-- estimated } or nil when it can't be read. `ratio` is the design x-height as a
-- fraction of the em (from the font file); `mm` is the one drawn (rows of pixels).
-- `estimated` is true when it did not come from the engine.
local function xHeightInfo(ui, face, scale)
    if not (ui and ui.document and face) then return nil end
    local ok, info = pcall(function()
        local path = resolveFace(face)
        local ratio = xHeightRatioOfPath(path)
        if not ratio then return nil end
        local pt = ui.font.configurable.font_size
        local dpi = Device:getDeviceScreenDPI() or Screen:getDPI()
        -- Pixel size really drawn (whole pixels, as crengine does it)
        local px
        local okp, n = pcall(function() return ui.document._document:getFontSize() end)
        if okp and n and n > 0 then px = n else px = math.floor(dpi * pt / 72 + 1e-6) end
        -- Book text in rem: the pixel size really drawn is the chosen one times the factor
        if scale then px = math.max(1, math.floor(px * scale + 0.5)) end
        local hint = getHinting(ui)
        local rows, estimated
        if face == currentFace(ui) then rows = engineRows(ui, px, hint) end
        if not rows then
            rows = freeTypeRows(path, px, hint)
            estimated = true
        end
        if not rows then rows = ratio * px end
        dlog("xHeightInfo:", face, "px=", px, "hint=", hint,
            "weight=", ui.document.configurable.font_base_weight, "rows=", rows,
            estimated and "(FreeType/design)" or "(engine)")
        return { ratio = ratio, mm = rows * 25.4 / dpi, pt = pt, px = px, rows = rows,
                 estimated = estimated and true or false }
    end)
    if not ok then
        require("logger").warn("[PTI] getFontXHeightInfo failed:", info)
        return nil
    end
    return info
end

-- rem scale of the book's main text ---------------------------------------------
-- Many epubs set the main text in rem (0.88rem, 0.75rem...), so what is really on
-- screen is smaller than the size chosen. The book's own style is read here (once
-- per book, cached): the stylesheets and a sample of the larger chapters of the epub.
-- The class most used by the main text (p, div, li, blockquote) with a font-size in rem
-- gives the factor. The x-height shown is multiplied by it, unless a style tweak that
-- puts the main text at the chosen size is on ("Reset main text font size" or
-- "Ignore publisher font sizes").
local REM_MIN_SHARE = 0.30   -- the class must be on at least 30% of the main text blocks

-- Pure calculation: htmls / csss are lists of texts. Returns the factor or nil.
local function bodyRemFromContent(htmls, csss)
    local MAIN = { p = true, div = true, li = true, blockquote = true }
    local counts, total = {}, 0
    for __, h in ipairs(htmls) do
        for raw_tag, attrs in h:gmatch("<(%a[%w]*)([^>]*)>") do
            local tag = raw_tag:lower()
            if MAIN[tag] then
                total = total + 1
                counts[tag] = (counts[tag] or 0) + 1
                local cls = attrs:match('%sclass%s*=%s*"([^"]*)"') or attrs:match("%sclass%s*=%s*'([^']*)'")
                if cls then
                    for c in cls:gmatch("%S+") do
                        counts["." .. c] = (counts["." .. c] or 0) + 1
                    end
                end
            end
        end
    end
    if total == 0 then return nil end

    local rules = {}    -- ".class" or "p" -> font-size in rem (the last rule wins)
    for __, css in ipairs(csss) do
        css = (css:gsub("/%*.-%*/", ""))
        for head, body in css:gmatch("([^{}]+){([^{}]*)}") do
            local v = body:match("font%-size%s*:%s*([%d%.]+)%s*rem")
            v = v and tonumber(v)
            if v then
                for sel in head:gmatch("[^,]+") do
                    local last = sel:match("([^%s>+~]+)%s*$")
                    if last and not last:find(":", 1, true) and not last:find("[", 1, true) then
                        local cls = last:match("^%a*%.([%w_-]+)$")      -- .x  or  p.x
                        local key = cls and ("." .. cls)
                            or (MAIN[last:lower()] and last:lower()) or nil
                        if key then rules[key] = v end
                    end
                end
            end
        end
    end

    local best_key, best_n
    for key in pairs(rules) do
        local n = counts[key] or 0
        if not best_n or n > best_n then best_key, best_n = key, n end
    end
    dlog("bodyRem: main blocks=", total, "best class=", best_key, "blocks=", best_n,
        "rem=", best_key and rules[best_key])
    if not best_key or best_n / total < REM_MIN_SHARE then return nil end
    local v = rules[best_key]
    if math.abs(v - 1) < 0.01 then return nil end
    return v
end

-- Reads the stylesheets and the largest chapters of the epub (KOReader's archiver).
local function loadEpubContent(path)
    local ok, Archiver = pcall(require, "ffi/archiver")
    if not ok then return nil end
    local arc = Archiver.Reader:new()
    if not arc:open(path) then return nil end
    local css_names, html_files = {}, {}
    for entry in arc:iterate() do
        if entry.mode == "file" then
            local low = entry.path:lower()
            if low:match("%.css$") and (entry.size or 0) < 2000000 then
                css_names[#css_names + 1] = entry.path
            elseif (low:match("%.xhtml$") or low:match("%.html?$")) and (entry.size or 0) > 3000 then
                html_files[#html_files + 1] = { path = entry.path, size = entry.size or 0 }
            end
        end
    end
    table.sort(html_files, function(a, b) return a.size > b.size end)
    local csss, htmls = {}, {}
    for __, name in ipairs(css_names) do
        csss[#csss + 1] = arc:extractToMemory(name) or ""
    end
    for i = 1, math.min(10, #html_files) do
        htmls[#htmls + 1] = arc:extractToMemory(html_files[i].path) or ""
    end
    arc:close()
    return htmls, csss
end

-- The factor comes first from the global calibre_data (loaded from calibre.lua, key =
-- file name; "rem" is the field written by executeGenerateCollections). The estimate
-- from the epub is only the fallback.
local function calibreRem(path)
    local data = _G.calibre_data
    local entry = type(data) == "table" and data[path:match("([^/]+)$")]
    local v = type(entry) == "table" and tonumber(entry.rem)
    if v and v > 0 and v <= 1.5 then return v end
    return nil
end

local _rem_cache = {}   -- [book path] = factor, or false when there is none
local function bookRemFactor(path)
    if type(path) ~= "string" or not path:lower():match("%.epub$") then return nil end
    local c = _rem_cache[path]
    if c == nil then
        c = false
        local from_calibre = calibreRem(path)
        if from_calibre then
            c = (from_calibre ~= 1) and from_calibre or false   -- 1.0 = no rem factor
        else
            local ok, scale = pcall(function()
                local htmls, csss = loadEpubContent(path)
                return htmls and bodyRemFromContent(htmls, csss)
            end)
            if ok and scale then c = scale
            elseif not ok then require("logger").warn("[PTI] book rem scale failed:", scale) end
        end
        dlog("bookRemFactor:", path, c, from_calibre and "(calibre)" or "(estimate)")
        _rem_cache[path] = c
    end
    return c or nil
end

local function bookRemScale(ui)
    local scale = bookRemFactor(ui and ui.document and ui.document.file)
    dlog("bookRemScale: factor=", scale, "styletweak=", ui and ui.styletweak ~= nil)
    if not scale then return nil end
    -- Tweaks that put the main text at the chosen size: the factor no longer applies
    local st = ui.styletweak
    if st and st.isTweakEnabled and st.enabled ~= false then
        for __, id in ipairs({ "font_size_most_reset", "font_size_all_inherit" }) do
            local ok, on = pcall(st.isTweakEnabled, st, id)
            if ok and on then dlog("bookRemScale: off,", id, "is on"); return nil end
        end
    end
    return scale
end
PageTextInfo.getBookRemScale = function(self) return bookRemScale(self.ui) end

function PageTextInfo:getFontXHeightInfo(face)
    local xi = xHeightInfo(self.ui, face)
    local scale = xi and bookRemScale(self.ui)
    if scale then
        -- Asked again to the engine at the size really drawn (chosen size x factor)
        local xs = xHeightInfo(self.ui, face, scale)
        if xs then
            xs.rem = scale                   -- shown as "(rem)"
            xs.mm_nominal = xi.mm            -- at the size chosen, without the book's scale
            return xs
        end
    end
    return xi
end

-- Readability rating of a font (HIGH / MEDIUM / LOW) -------------------------
-- Looked up in readability_table.lua, generated by generateFontsInformation.py
-- (main.lua loads it into PageTextInfo.readability_table). Nothing is measured here.
-- The keys the script writes are the file name without extension and, when the
-- font's own names are different, its family / full / PostScript names, each with
-- and without spaces and with and without "-Regular". Every one of those spellings
-- is tried, for the face name the book uses and for the font file.
-- Returns the text of the table ("HIGH: large x-height 52%, ...") or nil.
-- Same name with case, spaces, hyphens, underscores... ignored: "Gentium-Book-Plus" and
-- "gentiumbookplus" are the same key. Built once from the table (sorted, so a clash
-- always resolves to the same key).
local function normName(name)
    return (name:lower():gsub("[^%w]", ""))
end
local _norm_index, _norm_index_of
local function normalizedIndex(t)
    if _norm_index_of ~= t then
        local keys = {}
        for k in pairs(t) do if type(k) == "string" then keys[#keys + 1] = k end end
        table.sort(keys)
        _norm_index = {}
        for __, k in ipairs(keys) do
            local n = normName(k)
            if n ~= "" and _norm_index[n] == nil then _norm_index[n] = k end
        end
        _norm_index_of = t
    end
    return _norm_index
end

local function readabilityText(face, path)
    local t = PageTextInfo.readability_table
    if type(t) ~= "table" then return nil end
    local tried, cands = {}, {}
    local function add(name)
        if name and name ~= "" and not tried[name] then
            tried[name] = true
            cands[#cands + 1] = name
        end
    end
    local base
    if type(path) == "string" then
        base = path:match("([^/]+)$")
        if base then base = base:gsub("%.%w+$", "") end
        add(base)
    end
    if type(face) == "string" then
        local nospace = face:gsub("%s+", "")
        add(face); add(nospace)
        add(face .. "-Regular"); add(nospace .. "-Regular")
    end
    -- 1) the exact spellings the script writes
    for __, name in ipairs(cands) do
        if t[name] then return t[name] end
    end
    -- 2) the same, ignoring case and punctuation
    local idx = normalizedIndex(t)
    -- (explicit calls: ipairs would stop at a nil `base`)
    local function byNorm(name)
        if type(name) ~= "string" or name == "" then return nil end
        local n = normName(name)
        local key = idx[n] or idx[n .. "regular"]
        return key and t[key] or nil
    end
    return byNorm(base) or byNorm(face)
end

-- Just the rating word ("HIGH") and the reason, split from the table text
local function splitReadability(text)
    if not text then return nil end
    local rating, why = text:match("^(%u+):%s*(.+)$")
    return rating or text:match("^(%u+)") or text, why
end

-- Public method (fonts menu, popup): rating, reason of a face (by name, and file path
-- when known), or nil when the font is not in the table
function PageTextInfo:getFontReadability(face, path)
    return splitReadability(readabilityText(face, path))
end

-- Set the font size without a notification, keeping configurables in sync.
function PageTextInfo:applyFontSizePt(pt)
    dlog("applyFontSizePt:", pt)
    setFontSize(self.ui, pt)
end

-- Empty stand-ins for things that no longer exist (the x-height size mode, the
-- rem/em compensation, the cache warm-ups). They are only here so that code in
-- main.lua and in the patches that still calls them doesn't fail.
function PageTextInfo:isXHeightMode() return false end
function PageTextInfo:applyDefaultXHeight() end
function PageTextInfo:hasRemStyles() return false end
function PageTextInfo:reapplyFontCompensation() end
function PageTextInfo:warmUpOnReady() end
function PageTextInfo:warmUpCaches() end

-- New books: seed KOReader's own defaults for margins with DEFAULTS.margins,
-- so a book without settings of its own opens on them (and the matching preset
-- button shows as active). Nothing hooks into the book opening: this only
-- writes KOReader's global defaults, and ONLY when none of them has ever been
-- set, so margins the user later chooses as default in KOReader are not
-- overwritten on the next start.
do
    local m = DEFAULTS.margins
    local unset = G_reader_settings:readSetting("copt_h_page_margins") == nil
        and G_reader_settings:readSetting("copt_t_page_margin") == nil
        and G_reader_settings:readSetting("copt_b_page_margin") == nil
    if unset then
        dlog("default margins: not set yet, saving as KOReader defaults")
        G_reader_settings:saveSetting("copt_h_page_margins", { m[1], m[3] })
        G_reader_settings:saveSetting("copt_t_page_margin", m[2])
        G_reader_settings:saveSetting("copt_b_page_margin", m[4])
        G_reader_settings:flush()
    end
end

-- Title ------------------------------------------------------------------

-- Returns two lines, each a list of segments:
--   face, size and x-height  /  spacing, weight, contrast, hinting
local function buildTitleSegments(ui)
    local configurable = ui.document.configurable
    local pt = ui.font.configurable.font_size

    local line1 = {}
    local font_name = currentFace(ui)
    if font_name and font_name ~= "" then
        table.insert(line1, { text = font_name, bold = true })
        -- How good the font is: HIGH / MEDIUM / LOW (n/a when it is not in the table)
        local rating = splitReadability(readabilityText(font_name, resolveFace(font_name)))
        table.insert(line1, { text = " (" .. (rating or "n/a") .. ")" })
        table.insert(line1, { text = "  |  " })
    end
    table.insert(line1, { text = string.format("%gpt", pt), bold = true })
    table.insert(line1, { text = "  |  x-height " })
    -- Through getFontXHeightInfo, so the rem scale of the book's text is applied
    local info = PageTextInfo.getFontXHeightInfo({ ui = ui }, font_name)
    table.insert(line1, { text = info and string.format("%s%.2fmm%s", info.estimated and "~" or "", info.mm,
        info.rem and " (rem)" or "") or "n/a", bold = true })

    local line2 = {}
    local weight = configurable.font_base_weight or 0
    local idx = getContrast(ui)
    local gamma = GAMMA_TABLE[idx + 1]
    local hinting_names = { [0] = "off", [1] = "native", [2] = "auto" }
    -- Line spacing in em, same convention as LINE_SPACINGS (100% = 1.2em, as
    -- every line-height of the converted books is 1.2). Rounded to the 0.05em grid
    -- of the fine step; trailing zero dropped (1.10 -> 1.1, 1.25 stays)
    local spacing_em = 1.2 * (configurable.line_spacing or 100) / 100
    local em_txt = string.format("%.2f", math.floor(spacing_em / SPACING_STEP_EM + 0.5) * SPACING_STEP_EM)
    em_txt = em_txt:gsub("0$", "")
    table.insert(line2, { text = "spacing " .. em_txt .. "em", bold = true })
    table.insert(line2, { text = "  |  " })
    table.insert(line2, { text = string.format("weight %g", weight), bold = true })
    table.insert(line2, { text = "  |  " })
    table.insert(line2, { text = "contrast " .. (gamma and string.format("%g", gamma) or tostring(idx)), bold = true })
    table.insert(line2, { text = "  |  " })
    table.insert(line2, { text = "hinting " .. (hinting_names[getHinting(ui)] or "?"), bold = true })

    return { line1, line2 }
end

-- Dialog -----------------------------------------------------------------

function PageTextInfo:onShowSettingsMenu()
    local Blitbuffer = require("ffi/blitbuffer")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local Size = require("ui/size")
    local UIManager = require("ui/uimanager")
    local TextWidget = require("ui/widget/textwidget")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local VerticalSpan = require("ui/widget/verticalspan")
    local LineWidget = require("ui/widget/linewidget")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")

    local ui = self.ui
    if not ui or not ui.document or ui.paging or not ui.font or not ui.typeset then
        dlog("onShowSettingsMenu: skipped, not a reflowable book")
        return true
    end
    dlog("onShowSettingsMenu: open, reopen=", self.settings_dialog ~= nil)

    local old_dialog = self.settings_dialog
    -- The old window may have been moved: its real area is the one of its frame
    local old_area = old_dialog and ((old_dialog.frame and old_dialog.frame.dimen) or old_dialog.frame_rect)
    local old_region = old_area and old_area:copy()
    -- Keep the position while the menu is reopened after a button
    if old_dialog and old_dialog.movable then
        self.settings_offset = old_dialog.movable:getMovedOffset()
    end
    self.settings_dialog = nil

    local screen = Screen:getSize()

    -- Layout metrics (scaled to the screen DPI). Each row is a label on the left
    -- and the buttons on the right, so the section captions no longer take a
    -- line of their own and the buttons can be bigger.
    local frame_w = math.floor(screen.w * WINDOW_W_RATIO)
    local outer_pad = Screen:scaleBySize(8)
    -- Inner width available for rows (window width minus padding and border)
    local dialog_w = frame_w - 2 * (outer_pad + Size.border.window)
    local gap = Screen:scaleBySize(5)   -- space between buttons and between rows
    local thin = Screen:scaleBySize(1)
    local label_w = math.floor(dialog_w * 0.2)   -- column with the section labels
    local buttons_w = dialog_w - label_w - gap   -- width left for the buttons of a row
    local buttons = {}

    local menu_rows = buildRows(ui)
    -- The biggest font size at which every button text fits in its button. It is
    -- the same for all the buttons, so the menu looks even. Bold is measured
    -- because the active button is bold.
    local btn_size = BTN_FONT_SIZE
    for __, row_def in ipairs(menu_rows) do
        local n = #row_def
        if n > 0 then
            local max_w = math.floor((buttons_w - gap * (n - 1)) / n) - 2 * Size.padding.small
            for __, b in ipairs(row_def) do
                while btn_size > BTN_FONT_MIN do
                    if textWidth(b.text, btn_size, true) <= max_w then break end
                    btn_size = btn_size - 1
                end
            end
        end
    end
    -- The biggest label size at which every section label fits its column
    local label_size = LABEL_FONT_SIZE
    for __, row_def in ipairs(menu_rows) do
        if row_def.title then
            while label_size > LABEL_FONT_MIN do
                if textWidth(row_def.title, label_size, false) <= label_w - 2 * gap then break end
                label_size = label_size - 1
            end
        end
    end
    local font_px = Screen:scaleBySize(btn_size)
    local cell_h = math.floor(font_px * 1.8)   -- button height

    local dialog = InputContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h },
        -- Double tap off while this window is on top. KOReader works it out again
        -- every time a widget is closed (UIManager:close) from the topmost widget that
        -- states it, and this one stated nothing: the reader below (with double tap
        -- on) won, so after the window was reopened (show new, close old) taps were
        -- delayed and a second quick tap came as "double_tap", which nobody handled.
        disable_double_tap = true,
        ges_events = {
            Tap = { GestureRange:new{ ges = "tap",
                range = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h } } },
            Hold = { GestureRange:new{ ges = "hold",
                range = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h } } },
        },
        key_events = Device:hasKeys() and { Close = { { Device.input.group.Back } } } or {},
    }

    local label_face = Font:getFace("cfont", label_size)
    local btn_face = Font:getFace("cfont", btn_size)

    local grid = VerticalGroup:new{ align = "center" }
    for __, row_def in ipairs(menu_rows) do
        local n = #row_def
        if n > 0 then
            local cell_w = math.floor((buttons_w - gap * (n - 1)) / n)
            local row = HorizontalGroup:new{}

            -- Section label on the left (blank when the row continues the one above)
            if row_def.title then
                table.insert(row, LeftContainer:new{
                    dimen = Geom:new{ w = label_w, h = cell_h },
                    HorizontalGroup:new{
                        HorizontalSpan:new{ width = gap },
                        TextWidget:new{
                            text = row_def.title,
                            face = label_face,
                            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                            max_width = label_w - gap,
                        },
                    },
                })
            else
                table.insert(row, HorizontalSpan:new{ width = label_w })
            end
            table.insert(row, HorizontalSpan:new{ width = gap })

            for j, b in ipairs(row_def) do
                if j > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
                -- Rounded buttons. The active one is inverted (white text on black),
                -- which reads much better on e-ink than a thicker border.
                -- Shrink the font of a button whose text doesn't fit its cell, so
                -- a label is never cut
                local this_face = btn_face
                do
                    local avail = cell_w - 2 * Size.padding.small
                    local size = btn_size
                    while size > 8 do
                        if textWidth(b.text, size, b.active) <= avail then break end
                        size = size - 1
                    end
                    if size ~= btn_size then this_face = Font:getFace("cfont", size) end
                end
                local frame = FrameContainer:new{
                    bordersize = thin,
                    color = b.active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
                    background = b.active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
                    radius = Size.radius.button,
                    margin = 0,
                    padding = 0,
                    CenterContainer:new{
                        dimen = Geom:new{ w = cell_w - 2 * thin, h = cell_h - 2 * thin },
                        TextWidget:new{
                            text = b.text,
                            face = this_face,
                            fgcolor = b.active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
                            bold = b.active and true or false,
                            max_width = cell_w - 2 * Size.padding.small,
                        },
                    },
                }
                table.insert(row, frame)
                table.insert(buttons, { frame = frame, callback = b.callback, text = b.text,
                    open_fonts = b.open_fonts, rotate = b.rotate })
            end
            table.insert(grid, row)
            table.insert(grid, VerticalSpan:new{ width = gap })
        end
    end

    local title_lines = buildTitleSegments(ui)
    -- The biggest title size at which the longest line fits the window
    local title_size = TITLE_FONT_SIZE
    while title_size > TITLE_FONT_MIN do
        local widest = 0
        for __, line in ipairs(title_lines) do
            local w = 0
            for __, seg in ipairs(line) do
                w = w + textWidth(seg.text, title_size, seg.bold)
            end
            widest = math.max(widest, w)
        end
        if widest <= dialog_w - 2 * gap then break end
        title_size = title_size - 1
    end
    local title_face = Font:getFace("cfont", title_size)
    -- Line height of the title: it follows the title font, not the buttons
    local line_h = math.floor(Screen:scaleBySize(title_size) * 1.6 * 0.85)
    local title_rows = VerticalGroup:new{ align = "center" }
    for __, line in ipairs(title_lines) do
        local group = HorizontalGroup:new{}
        for __, seg in ipairs(line) do
            table.insert(group, TextWidget:new{
                text = seg.text,
                face = title_face,
                bold = seg.bold or false,
            })
        end
        table.insert(title_rows, CenterContainer:new{
            dimen = Geom:new{ w = dialog_w, h = line_h },
            group,
        })
    end
    -- Title block with a thin separator below it (tap / long press target)
    local title_frame = FrameContainer:new{
        bordersize = 0, margin = 0, padding = 0,
        VerticalGroup:new{
            align = "center",
            title_rows,
            VerticalSpan:new{ width = gap },
            LineWidget:new{
                dimen = Geom:new{ w = dialog_w, h = thin },
                background = Blitbuffer.COLOR_DARK_GRAY,
            },
            VerticalSpan:new{ width = gap },
        },
    }

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius = Size.radius.window,
        padding = outer_pad,
        margin = 0,
        VerticalGroup:new{
            align = "center",
            title_frame,
            grid,
        },
    }
    -- Anchored to the bottom of the screen so the top of the page stays visible
    -- while changing font / spacing / weight
    -- The window can be moved: swipe or drag it. (Hold is not used for moving, because a
    -- long press on the title saves the default font.)
    local BottomContainer = require("ui/widget/container/bottomcontainer")
    local MovableContainer = require("ui/widget/container/movablecontainer")
    local movable = MovableContainer:new{
        frame,
        ignore_events = { "hold", "hold_pan", "hold_release" },
    }
    if self.settings_offset then movable:setMovedOffset(self.settings_offset) end
    dialog[1] = BottomContainer:new{
        dimen = Geom:new{ w = screen.w, h = screen.h },
        movable,
    }
    dialog.movable = movable
    dialog.frame = frame

    local fsize = frame:getSize()
    local offset = movable:getMovedOffset()
    local frame_rect = Geom:new{
        x = math.floor((screen.w - fsize.w) / 2) + offset.x,
        y = screen.h - fsize.h + offset.y,
        w = fsize.w, h = fsize.h,
    }

    function dialog:onTap(arg, ges)
        -- Tap on the title: open the reference popup from typography_popup.lua
        if title_frame.dimen and ges.pos:intersectWith(title_frame.dimen) then
            -- A change is being applied: the book is not laid out yet and the x-height
            -- the popup would show (and keep in its cache) is not the final one
            if self.plugin.settings_busy then return true end
            local plugin_ui = self.plugin.ui
            if plugin_ui and plugin_ui.onShowTypographyReference then
                plugin_ui:onShowTypographyReference()
            else
                require("logger").warn("[PTI] onShowTypographyReference not available")
            end
            return true
        end

        for __, b in ipairs(buttons) do
            if b.frame.dimen and ges.pos:intersectWith(b.frame.dimen) then
                -- Font face: swap this window for the fonts menu
                if b.open_fonts then
                    local plugin = self.plugin
                    if plugin.onShowFonts then
                        close(plugin)
                        -- Tells the fonts menu to reopen this menu when it closes
                        plugin.fonts_from_settings = true
                        UIManager:nextTick(function() plugin:onShowFonts() end)
                    else
                        require("logger").warn("[PTI] onShowFonts not available (font_selection_menu not loaded)")
                    end
                    return true
                end
                -- Screen rotation: the window never disappears. The screen size is
                -- already the new one when the rotation call returns, so the new window
                -- is built right away (show new, close old, in one go) at its place.
                if b.rotate then
                    local plugin = self.plugin
                    if plugin.settings_busy then return true end
                    plugin.settings_busy = true
                    UIManager:tickAfterNext(function()
                        local ok, err = pcall(b.callback, plugin.ui)
                        dlog("settings menu rotate:", ok and "OK" or err)
                        -- Normally the window already rebuilt itself from the resize
                        -- event; this only catches the case where that event didn't come
                        rebuildIfResized(plugin, plugin.settings_dialog)
                        plugin.settings_busy = nil
                    end)
                    return true
                end
                -- A change is being applied: ignore the taps that come meanwhile. Kept in
                -- the plugin, because the dialog is replaced by a new one after every change.
                if self.plugin.settings_busy then return true end
                self.plugin.settings_busy = true
                -- Like KOReader's own config panel (ConfigDialog:onConfigChoose): the change
                -- is applied two ticks after the tap, not inside the tap handler, so the
                -- gesture is completely handled before the re-layout blocks and inhibits
                -- the input. The menu is rebuilt right after it (active state refreshed).
                local plugin, dlg = self.plugin, self
                UIManager:tickAfterNext(function()
                    local ok, err = pcall(b.callback, plugin.ui)
                    dlog("settings menu tap:", b.text, ok and "OK" or err)
                    -- The book is laid out again a couple of ticks from now, and the title
                    -- of this menu shows the x-height, which can only be measured once that
                    -- is done. So the menu is rebuilt from the timer, which is due after the
                    -- layout (it blocks the loop), not right here.
                    UIManager:scheduleIn(0.35, function()
                        -- closed meanwhile (tap outside): don't bring it back
                        if plugin.settings_dialog == dlg then
                            plugin:onShowSettingsMenu()
                            if plugin.view and plugin.view.topbar then
                                plugin.view.topbar:toggleBar()
                            end
                        end
                        plugin.settings_busy = nil
                    end)
                end)
                return true
            end
        end
        -- Tap outside the window (it may have been moved: use where it is painted)
        if not ges.pos:intersectWith(frame.dimen or frame_rect) then
            close(self.plugin)
        end
        return true
    end

    -- Long press inside the window: save the current font and size as the default
    function dialog:onHold(arg, ges)
        if not (title_frame.dimen and ges.pos:intersectWith(title_frame.dimen)) then
            return true
        end
        local plugin = self.plugin
        local ok, face = pcall(saveCurrentFontAsDefault, plugin.ui)
        local text
        if ok and face then
            text = string.format("Default font saved:\n%s\n(default size: %gpt)", face, PT_DEFAULT_SIZE)
        else
            -- face holds the error message when pcall fails
            require("logger").warn("[PTI] saveCurrentFontAsDefault failed:", face)
            text = "Could not save the default font"
        end

        -- Reopen the menu first, then show the message box on top of it in a
        -- later tick, so the menu can't be painted over the message
        UIManager:tickAfterNext(function()
            plugin:onShowSettingsMenu()
            UIManager:nextTick(function()
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{ text = text })
            end)
        end)
        return true
    end

    function dialog:onClose() close(self.plugin) return true end

    -- Screen rotated: replace this window before anything is painted at the new size
    function dialog:onScreenResize() rebuildIfResized(self.plugin, self) end
    function dialog:onSetDimensions() rebuildIfResized(self.plugin, self) end

    dialog.built_w = screen.w
    dialog.plugin = self
    dialog.frame_rect = frame_rect
    self.settings_dialog = dialog

    local region = frame_rect
    if old_region then region = region:combine(old_region) end
    UIManager:show(dialog, "ui", region)
    if old_dialog then UIManager:close(old_dialog, "ui", region) end
    return true
end

end -- return function(PageTextInfo)
