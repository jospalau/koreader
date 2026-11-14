-- Quick settings menu: rows of buttons (font size, line spacing, margins, weight...)
-- Same look and gesture handling as the fonts menu.
--
-- Lives next to main.lua. Load it from main.lua, after PageTextInfo is defined:
--     require("settings_menu")(PageTextInfo)
--
-- It adds these methods to PageTextInfo:
--     onShowSettingsMenu, getXHeightMm, ptForXHeight, applyFontSizePt,
--     getFontReadability
-- (plus hasRemStyles / reapplyFontCompensation: empty stand-ins, so code in
-- main.lua that still calls them keeps working)
--
-- PLAIN VERSION: no "Scale by x-height" and no "Compensate rem/em". Font sizes
-- are applied exactly as set; the book's own font-size styles are never read.

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

dlog("settings_menu module loaded")


local WEIGHT_STEP = 0.5

local CONTRAST_MIN, CONTRAST_MAX = 0, 56
local CONTRAST_DEFAULT = 15

-- Forward declaration: assigned further down, but must be declared here
-- so every function below sees it as an upvalue (not a global).
local xHeightRatio


-- Line spacing presets. All my Calibre books were converted so every
-- line-height is a unitless 1.2 (see the Calibre "Transform styles" rules).
-- KOReader's percentage multiplies on top of that, so 100% = the 1.2em
-- baseline, and the other steps are ~1.1em / 1.3em / 1.4em
-- (e.g. 1.1/1.2 = 92%, 1.3/1.2 = 109%, 1.4/1.2 = 117%).
-- Labels are only accurate with "Book styles" enabled in KOReader and for
-- books that went through that conversion.
local LINE_SPACINGS = {
    { percent = 92,  label = "1.1em" },
    { percent = 100, label = "1.2em" },
    { percent = 109, label = "1.3em" },
    { percent = 117, label = "1.4em" },
}

-- {left, top, right, bottom}: use the same units your margins option uses
local MARGIN_PRESETS = {
    { label = "Default (small)", value = { 15, 15, 15, 10 } },
    { label = "Slightly bigger", value = { 20, 40, 20, 35 } },
    { label = "Big",             value = { 50, 50, 50, 50 } },
    { label = "Bigger",          value = { 70, 70, 70, 70 } },
}
local DEFAULTS = { font_face = "Capita", font_size = 9.5, line_spacing = 100, font_base_weight = 0,
                   margins = MARGIN_PRESETS[1].value }

local GAMMA_TABLE = { 0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9,
    0.95, 0.98, 1, 1.02, 1.05, 1.1, 1.15, 1.2, 1.25, 1.3, 1.35, 1.4, 1.45,
    1.5, 1.6, 1.7, 1.8, 1.9, 2, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9,
    3, 3.5, 4, 4.5, 5, 5.5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }

-- KOReader's configured default size; falls back to this file's DEFAULTS
local function defaultFontSize()
    return G_reader_settings:readSetting("copt_font_size") or DEFAULTS.font_size
end

local function fixedPresets()
    return { small = 8.5, normal = defaultFontSize(), big = 11 }
end

local function close(self)
    local UIManager = require("ui/uimanager")
    local d = self.settings_dialog
    self.settings_dialog = nil
    dlog("settings menu closed")
    if d then UIManager:close(d, "ui", d.frame_rect) end
end

-- Actions ---------------------------------------------------------------

local function setFontFace(ui, face)
    if not face or face == "" then return end
    dlog("setFontFace:", face, "rolling=", ui.rolling and true or false)
    if ui.rolling then  -- only reflowable (CRE) documents support font faces
        ui.font:onSetFont(face)
    end
end

local function setFontSize(ui, pt)
    local requested = pt
    pt = math.max(4, math.min(pt, 255))
    ui.font:onSetFontSize(pt, true)
    -- Keep both configurables in sync (harmless if they are the same table)
    ui.document.configurable.font_size = pt
    ui.font.configurable.font_size = pt
    dlog("setFontSize: requested=", requested, "applied=", pt,
        "cre size=", ui.document._document:getFontSize())
end

-- Size in px that crengine REALLY draws for the current font size: it only
-- draws whole pixels (the fraction is dropped). Every x-height shown must use
-- this, not the unrounded dpi * pt / 72, or two pt values that render the same
-- size would show different mm.
local function drawnPx(ui, pt, dpi)
    local ok, n = pcall(function() return ui.document._document:getFontSize() end)
    if ok and n and n > 0 then return n end
    return math.floor(dpi * pt / 72 + 1e-6)
end

-- Step the font size by `delta` pt, repeating until the rendering engine
-- actually changes size. CREngine only distinguishes discrete sizes, so a
-- small step (e.g. 0.1 pt) may leave the drawn size unchanged. Each call therefore
-- keeps adding `delta` (rounded to 0.01 to avoid float drift) until
-- getFontSize() reports a new value. The 40 iterations cap avoids an endless
-- loop when the minimum or maximum font size is reached.
local function stepFontSize(ui, delta)
    local function cre_size() return ui.document._document:getFontSize() end
    local before = cre_size()
    local pt = ui.font.configurable.font_size
    dlog("stepFontSize: delta=", delta, "start pt=", pt, "cre size=", before)
    local iterations = 0
    for __ = 1, 40 do
        iterations = iterations + 1
        pt = math.floor((pt + delta) * 100 + 0.5) / 100
        setFontSize(ui, pt)
        if cre_size() ~= before then break end
    end
    dlog("stepFontSize: end pt=", pt, "cre size=", cre_size(), "iterations=", iterations)
end

local function setLineSpacing(ui, percent)
    dlog("setLineSpacing: percent=", percent)
    ui.document:setInterlineSpacePercent(percent)
    ui.document.configurable.line_spacing = percent
    ui:handleEvent(require("ui/event"):new("UpdatePos"))
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

local function getContrast(ui)
    local conf = ui.document.configurable
    return conf.font_gamma
        or G_reader_settings:readSetting("copt_font_gamma")
        or CONTRAST_DEFAULT
end

local function setContrast(ui, g)
    g = math.floor(math.max(CONTRAST_MIN, math.min(g, CONTRAST_MAX)) + 0.5)
    dlog("setContrast: index=", g, "gamma=", GAMMA_TABLE[g + 1])
    ui.document.configurable.font_gamma = g
    ui.font.configurable.font_gamma = g

    -- Same call KOReader's own handler makes (also shows its notification)
    ui.font:onSetFontGamma(g)

    -- Gamma is applied when glyphs are drawn, but crengine caches the rendered
    -- page, so force it to render again and repaint.
    ui.document:clearCacheData()
    ui.document:getCurrentPos()
    ui:handleEvent(require("ui/event"):new("UpdatePos"))
    require("ui/uimanager"):setDirty("all", "full")
end

-- One index at a time over KOReader's full gamma table (0..56)
local function stepContrast(ui, dir)
    setContrast(ui, getContrast(ui) + dir)
end

-- Save the current font face and size as KOReader's defaults for new books
-- (what "Font default" and a new book then use). Returns face, pt.
local function saveCurrentFontAsDefault(ui)
    local face = ui.document._document:getFontFace()
    local pt = ui.font.configurable.font_size
    if not face or not pt then return nil end
    dlog("saveCurrentFontAsDefault: saving face=", face, "pt=", pt)
    G_reader_settings:saveSetting("cre_font", face)
    G_reader_settings:saveSetting("copt_font_size", pt)
    G_reader_settings:flush()
    return face, pt
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
    ui:handleEvent(Event:new("SwapRotation"))
end

-- Menu definition -------------------------------------------------------
-- Each button: text, callback(ui), active(ui) (optional, draws thick border)

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
    { label = "Ignore font sizes",    needles = { "ignore", "font sizes" } },
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
    dlog("settings menu state: font_size=", fs,
        "line_spacing=", conf.line_spacing, "weight=", conf.font_base_weight,
        "h_margins=", conf.h_page_margins and (conf.h_page_margins[1] .. "," .. conf.h_page_margins[2]) or "nil",
        "t=", conf.t_page_margin, "b=", conf.b_page_margin)

    -- "Active" border: two sizes are the same when crengine draws them at the
    -- same whole-pixel size, even if their pt differ (stepping up and down
    -- leaves a slightly different pt for the same drawn size).
    local dpi_now = Device:getDeviceScreenDPI() or Screen:getDPI()
    local function near(a, b)
        if not (a and b) then return false end
        return math.floor(dpi_now * a / 72 + 1e-6) == math.floor(dpi_now * b / 72 + 1e-6)
    end

    local fx = fixedPresets()
    local font_preset_row = {
        { text = "Font small",   callback = function(u) setFontSize(u, fx.small) end,  active = near(fs, fx.small) },
        { text = "Font default", callback = function(u) setFontSize(u, fx.normal) end, active = near(fs, fx.normal) },
        { text = "Font big",     callback = function(u) setFontSize(u, fx.big) end,    active = near(fs, fx.big) },
    }
    for __, b in ipairs(font_preset_row) do
        dlog("buildRows: preset button", b.text, "active=", b.active and true or false,
            "fs=", fs)
    end
    local spacing_row, margins_row = {}, {}
    local rows = {
        { title = "General",
            { text = "Reset defaults",      callback = resetDefaults },
            { text = "Toggle screen layout", callback = toggleLayout },
        },
        font_preset_row,
        {
            { text = "Font ▼", callback = function(u) stepFontSize(u, -0.1) end },
            { text = "Font ▲", callback = function(u) stepFontSize(u,  0.1) end },
        },
        spacing_row,
        margins_row,
        {
            { text = "Decrease weight", callback = function(u) setWeight(u, u.document.configurable.font_base_weight - WEIGHT_STEP) end },
            { text = "Increase weight", callback = function(u) setWeight(u, u.document.configurable.font_base_weight + WEIGHT_STEP) end },
        },
        {
            { text = "Decrease contrast", callback = function(u) stepContrast(u, -1) end },
            { text = "Increase contrast", callback = function(u) stepContrast(u, 1) end },
        },
    }
    -- Section captions (a row without a title gets none)
    font_preset_row.title = "Font presets"
    rows[3].title = "Font size (fine step)"
    spacing_row.title = "Line spacing"
    margins_row.title = "Margins"
    rows[6].title = "Weight"
    rows[7].title = "Contrast"

    local ls = conf.line_spacing
    for __, spacing in ipairs(LINE_SPACINGS) do
        table.insert(spacing_row, {
            text = spacing.label,
            callback = function(u) setLineSpacing(u, spacing.percent) end,
            active = approx(ls, spacing.percent),
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
        if i % 2 == 1 then
            tweak_row = {}
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

local _ratio_cache = {}   -- [face name] = x-height / size ratio


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
        dlog("resolveFace:", raw_name, "->", best or any, best and "(regular)" or "(non-regular)")
        return best or any
    end
    dlog("resolveFace:", raw_name, "-> not found, guessing Name-Regular")
    return (raw_name:gsub("%s+", "") .. "-Regular")
end

-- x-height / font size ratio of a face (the current one by default), measured
-- at a large size so hinting/rounding doesn't matter. Cached per face name.
-- Returns ratio, face_name (or nil if it can't be measured).
xHeightRatio = function(doc, raw_name)
    raw_name = raw_name or doc._document:getFontFace() or "?"
    local face_name = resolveFace(raw_name)
    if _ratio_cache[face_name] then return _ratio_cache[face_name], face_name end

    local face = Font:getFace(face_name, 200, 0, true)
    if not face or not face.ftsize then
        require("logger").warn("[PTI] xHeightRatio: cannot load face", raw_name, face_name)
        return nil
    end
    -- Divide by the size the face was really loaded at (it may be DPI-scaled)
    local real_size = face.size or 200
    -- Protected: a 0/nil x-height means the face can't be measured
    local okx, xh = pcall(function() return face.ftsize:getXHeight() end)
    if not okx or not xh or xh <= 0 then
        require("logger").warn("[PTI] xHeightRatio: no x-height for", face_name)
        return nil
    end
    local xh_px = (xh < 1) and (xh * real_size) or xh
    if xh_px <= 0 or real_size <= 0 then return nil end

    local ratio = xh_px / real_size
    dlog("xHeightRatio: measured face=", face_name, "ratio=", ratio, "real size=", real_size)
    _ratio_cache[face_name] = ratio
    return ratio, face_name
end

-- New books: make KOReader's own defaults for margins equal to DEFAULTS.margins,
-- so a book without settings of its own opens on them (and the matching preset
-- button shows as active). Nothing hooks into the book opening: this only
-- writes KOReader's global defaults, and only when they differ.
do
    local m = DEFAULTS.margins
    local h = G_reader_settings:readSetting("copt_h_page_margins")
    local same = h and approx(h[1], m[1]) and approx(h[2], m[3])
        and approx(G_reader_settings:readSetting("copt_t_page_margin"), m[2])
        and approx(G_reader_settings:readSetting("copt_b_page_margin"), m[4])
    if not same then
        dlog("default margins: saving as KOReader defaults")
        G_reader_settings:saveSetting("copt_h_page_margins", { m[1], m[3] })
        G_reader_settings:saveSetting("copt_t_page_margin", m[2])
        G_reader_settings:saveSetting("copt_b_page_margin", m[4])
        G_reader_settings:flush()
    end
end

-- Public methods (used by the fonts menu in main.lua) --------------------

-- Current x-height in mm of the font as it is drawn (whole pixels, like
-- crengine). Returns nil if the font can't be measured.
function PageTextInfo:getXHeightMm()
    local ui = self.ui
    local ok, mm = pcall(function()
        local dpi = Device:getDeviceScreenDPI() or Screen:getDPI()
        local ratio = xHeightRatio(ui.document)
        if not ratio then return nil end
        local px = drawnPx(ui, ui.document.configurable.font_size, dpi)
        local res = ratio * px / (dpi / 25.4)
        dlog("getXHeightMm: pt=", ui.document.configurable.font_size, "ratio=", ratio,
            "px drawn=", px, "-> mm=", res)
        return res
    end)
    return ok and mm or nil
end

-- Name that Font:getFace accepts for the current face (the one that worked in
-- xHeightRatio). Returns nil if the font can't be loaded.
function PageTextInfo:getFaceName()
    local ok, ratio, face_name = pcall(xHeightRatio, self.ui.document)
    return ok and ratio and face_name or nil
end

-- pt size that gives `target_mm` of x-height with the CURRENT face, rounded to
-- the whole-pixel size crengine really draws.
function PageTextInfo:ptForXHeight(target_mm)
    local ok, pt = pcall(function()
        local dpi = Device:getDeviceScreenDPI() or Screen:getDPI()
        local ratio = xHeightRatio(self.ui.document)
        if not ratio then return nil end
        local px = math.max(1, math.floor(target_mm * (dpi / 25.4) / ratio + 0.5))
        local res = math.ceil(px * 72 / dpi * 100 + 0.001) / 100
        return math.max(4, math.min(res, 255))
    end)
    return ok and pt or nil
end

-- Set the font size without a notification, keeping configurables in sync.
function PageTextInfo:applyFontSizePt(pt)
    dlog("applyFontSizePt:", pt)
    setFontSize(self.ui, pt)
end

-- Empty stand-ins for the removed rem/em compensation: they only exist so that
-- code in main.lua that still calls them doesn't fail. Delete them together
-- with the "Compensate rem/em" / "Scale by x-height" entries of main.lua.
function PageTextInfo:hasRemStyles() return false end
function PageTextInfo:reapplyFontCompensation() end

-- Does the book set font sizes in rem? Looks at the font-size declarations of
-- its style sheets (a rem value other than 1) and at a font-size in rem on the
-- <html> / <body> tag of the first text files (inline style). Cached per book.
-- Returns true / false, or nil if the book can't be read.
local _rem_cache = {}
local function bookUsesRem(doc)
    local file = doc.file
    if not file then return nil end
    if _rem_cache[file] ~= nil then return _rem_cache[file] end
    local ok, res = pcall(function()
        local Archiver = require("ffi/archiver")
        local arc = Archiver.Reader:new()
        if not arc:open(file) then return nil end
        local found, html_checked = false, 0
        local function hasRem(text)
            for v in text:gmatch("font%-size%s*:%s*([%d%.]+)%s*rem") do
                if math.abs((tonumber(v) or 1) - 1) > 0.001 then return true end
            end
            return false
        end
        for entry in arc:iterate() do
            if entry.mode == "file" then
                local path = entry.path:lower()
                if path:match("%.css$") then
                    local css = arc:extractToMemory(entry.path)
                    if css and hasRem((css:gsub("/%*.-%*/", ""))) then found = true; break end
                elseif html_checked < 3 and path:match("%.x?html?$") then
                    local html = arc:extractToMemory(entry.path)
                    if html then
                        html_checked = html_checked + 1
                        for tag in html:gmatch("<[hHbB][tToO][mMdD][lLyY][^>]*>") do
                            if hasRem(tag) then found = true; break end
                        end
                        if found then break end
                    end
                end
            end
        end
        arc:close()
        return found
    end)
    if not ok then dlog("bookUsesRem ERROR:", res) end
    if not ok or res == nil then return nil end
    _rem_cache[file] = res
    dlog("bookUsesRem:", file, "->", res)
    return res
end

-- Title ------------------------------------------------------------------

-- Font analysis (readability) -------------------------------------------------
-- Port of generateFontsInformation.py, so the rating no longer comes from the
-- precomputed readability_table.lua. The Python script measures the glyph
-- OUTLINES; here the same scanline measurements are made on the glyph BITMAP
-- rendered at a large size (FA.MEASURE_PX, which plays the role of the UPM), with
-- sub-pixel coverage, so results match the script within ~0.1% of the em.
-- Same thresholds, formula, rating and reason as the script (v4: hairline
-- visibility + contrast bonus). Results are cached per face.
local FA = {
    MEASURE_PX = 1000,          -- em size used for the measurements
    VISIBILITY_SAT = 0.05,     -- hairline >= 5% UPM = fully visible
    VIS_WEIGHT = 0.7,
    CONTRAST_WEIGHT = 0.5,
    CONTRAST_MIN = 1.0,
    CONTRAST_MAX = 2.6,
    RF_LOW_MAX = 0.80,         -- < 0.80 -> LOW
    RF_HIGH_MIN = 0.95,        -- >= 0.95 -> HIGH, in between MEDIUM
    SCAN_STEPS = 15,           -- scanlines per glyph
    SCAN_LO = 0.25, SCAN_HI = 0.75,   -- central zone of the glyph
    MIN_SPAN_RATIO = 0.003,    -- ignore crossings < 0.3% UPM
}

local function faMedian(t)
    local s = {}
    for i, v in ipairs(t) do s[i] = v end
    table.sort(s)
    local n = #s
    if n == 0 then return nil end
    if n % 2 == 1 then return s[(n + 1) / 2] end
    return (s[n / 2] + s[n / 2 + 1]) / 2
end

local function faRound(v, d)
    local m = 10 ^ d
    return math.floor(v * m + 0.5) / m
end

-- Rendered glyph of a character (nil if the face has no such glyph)
local function faGlyph(face, char)
    local ok, g = pcall(function()
        local code = char:byte()
        if not face.ftsize:hasGlyph(code) then return nil end
        return face.ftsize:renderGlyph(code)
    end)
    if ok and g and g.bb and g.bb:getWidth() > 0 and g.bb:getHeight() > 0 then return g end
    return nil
end

-- Widths (in pixels, with partial coverage) of the filled runs along one line
-- of the bitmap: a row (horizontal = true) or a column (horizontal = false)
local function faLineSpans(bb, idx, horizontal, min_span)
    local n = horizontal and bb:getWidth() or bb:getHeight()
    local spans, acc, inrun = {}, 0, false
    for i = 0, n - 1 do
        local px = horizontal and bb:getPixel(i, idx) or bb:getPixel(idx, i)
        local a = px:getColor8().a
        if a > 0 then
            acc = acc + a / 255
            inrun = true
        elseif inrun then
            if acc > min_span then table.insert(spans, acc) end
            acc, inrun = 0, false
        end
    end
    if inrun and acc > min_span then table.insert(spans, acc) end
    return spans
end

-- Spans of several lines in the central zone of the glyph, grouped by line
local function faCentralSpans(bb, horizontal, min_span)
    local extent = horizontal and bb:getHeight() or bb:getWidth()
    local rows = {}
    for k = 0, FA.SCAN_STEPS - 1 do
        local frac = FA.SCAN_LO + (FA.SCAN_HI - FA.SCAN_LO) * k / (FA.SCAN_STEPS - 1)
        local idx = math.max(0, math.min(extent - 1, math.floor(extent * frac)))
        local spans = faLineSpans(bb, idx, horizontal, min_span)
        if #spans > 0 then table.insert(rows, spans) end
    end
    return rows
end

-- Main vertical stroke: median of all the horizontal cross-sections of I, l, H, i
local function faStemWidth(face, min_span)
    for __, ch in ipairs({ "I", "l", "H", "i" }) do
        local g = faGlyph(face, ch)
        if g then
            local all = {}
            for __, row in ipairs(faCentralSpans(g.bb, true, min_span)) do
                for __, s in ipairs(row) do table.insert(all, s) end
            end
            if #all > 0 then return faMedian(all) end
        end
    end
    return nil
end

-- Thinnest horizontal strokes (crossbar of e / H), measured on vertical lines
local function faThinWidth(face, min_span)
    local best
    for __, ch in ipairs({ "e", "H" }) do
        local g = faGlyph(face, ch)
        if g then
            local mins = {}
            for __, row in ipairs(faCentralSpans(g.bb, false, min_span)) do
                local m = row[1]
                for __, s in ipairs(row) do if s < m then m = s end end
                table.insert(mins, m)
            end
            if #mins > 0 then
                local v = faMedian(mins)
                if not best or v < best then best = v end
            end
        end
    end
    return best
end

-- Height in pixels of the first of these characters that exists
local function faGlyphHeight(face, chars)
    for __, ch in ipairs(chars) do
        local g = faGlyph(face, ch)
        if g then return g.bb:getHeight() end
    end
    return nil
end

local function faAdjustedRatio(stem, thin)
    local r = stem / thin
    if r < 2.0 then return r end
    if r < 4.0 then return 2.0 + (r - 2.0) * 0.3 end
    return 2.6
end

local function faClassify(value)
    if value < FA.RF_LOW_MAX then return "LOW" end
    if value < FA.RF_HIGH_MIN then return "MEDIUM" end
    return "HIGH"
end

-- Short reason of the rating: LOW -> weak points, HIGH -> strong points (+ the
-- catch, if any), MEDIUM -> both
local function faReason(rating, xh_ratio, thin_ratio, raw_contrast, adj_contrast)
    if not xh_ratio or not thin_ratio then return "" end
    local xh_pct = string.format("%.0f%%", xh_ratio * 100)
    local th_pct = string.format("%.1f%%", thin_ratio * 100)
    local weak, strong = {}, {}
    if xh_ratio < 0.45 then
        table.insert(weak, "low x-height " .. xh_pct)
    elseif xh_ratio >= 0.50 then
        table.insert(strong, "large x-height " .. xh_pct)
    end
    if thin_ratio < 0.03 then
        table.insert(weak, "thin hairline " .. th_pct)
    elseif thin_ratio >= FA.VISIBILITY_SAT then
        table.insert(strong, "sturdy hairline " .. th_pct)
    end
    if raw_contrast and adj_contrast then
        if adj_contrast >= 2.0 then
            table.insert(strong, string.format("good contrast %.1f", raw_contrast))
        elseif adj_contrast < 1.5 then
            table.insert(weak, string.format("flat contrast %.1f", raw_contrast))
        end
    end
    -- If nothing is clearly weak / strong, pick the weaker / stronger of x-height and hairline
    local xh_score = xh_ratio / 0.50
    local th_score = math.min(thin_ratio / FA.VISIBILITY_SAT, 1.0)
    local weakest = xh_score <= th_score and ("borderline x-height " .. xh_pct)
        or ("borderline hairline " .. th_pct)
    local strongest = xh_score > th_score and ("x-height " .. xh_pct) or ("hairline " .. th_pct)

    if rating == "LOW" then
        return table.concat(#weak > 0 and weak or { weakest }, ", ")
    end
    if rating == "HIGH" then
        local text = table.concat(#strong > 0 and strong or { strongest }, ", ")
        if #weak > 0 then return text .. ", but " .. table.concat(weak, ", ") end
        return text
    end
    return table.concat(#strong > 0 and strong or { strongest }, ", ")
        .. ", but " .. table.concat(#weak > 0 and weak or { weakest }, ", ")
end

-- Measures a face and returns "RATING: reason" (or "RATING"), nil if it can't
-- be measured. `face_path` is the name/path Font:getFace accepts.
local function faAnalyze(face_path)
    local face = Font:getFace(face_path, FA.MEASURE_PX, 0, true)
    if not face or not face.ftsize then return nil end
    local upm = face.size or FA.MEASURE_PX
    local min_span = FA.MIN_SPAN_RATIO * upm

    local stem = faStemWidth(face, min_span)
    local thin = faThinWidth(face, min_span)
    local xh = faGlyphHeight(face, { "x", "n", "e" })
    if not (stem and thin and xh and stem > 0 and thin > 0 and xh > 0) then return nil end

    local xh_ratio, thin_ratio = xh / upm, thin / upm
    local visibility = math.min(thin_ratio / FA.VISIBILITY_SAT, 1.0)
    local contrast_norm = (faAdjustedRatio(stem, thin) - FA.CONTRAST_MIN)
        / (FA.CONTRAST_MAX - FA.CONTRAST_MIN)
    contrast_norm = math.max(0.0, math.min(contrast_norm, 1.0))
    local factor = faRound(xh_ratio * (1 + FA.VIS_WEIGHT * visibility
        + FA.CONTRAST_WEIGHT * visibility * contrast_norm), 3)
    local rating = faClassify(factor)

    -- The script builds the reason from the rounded values of its table
    local reason = faReason(rating,
        faRound(xh_ratio * 100, 2) / 100, faRound(thin_ratio * 100, 2) / 100,
        faRound(stem / thin, 2), faRound(faAdjustedRatio(stem, thin), 3))
    dlog("faAnalyze:", face_path, "stem%=", stem / upm * 100, "thin%=", thin_ratio * 100,
        "xh%=", xh_ratio * 100, "factor=", factor, rating, reason)
    return reason ~= "" and (rating .. ": " .. reason) or rating
end

local _fa_cache = {}   -- [face path] = "RATING: reason" | false

-- Readability of a font file, computed here (no precomputed table):
-- "RATING: reason", or "N/A" if the font can't be measured. Cached per path.
local function readabilityOfPath(path)
    local cached = _fa_cache[path]
    if cached == nil then
        local ok, res = pcall(faAnalyze, path)
        if not ok then
            require("logger").warn("[PTI] faAnalyze failed:", res)
            res = nil
        end
        cached = res or false
        _fa_cache[path] = cached
    end
    return cached or "N/A"
end

-- Readability of a face given by its name (as used by the document)
local function faceReadability(ui, face_name)
    return readabilityOfPath(resolveFace(face_name))
end

-- Public method (used by the fonts menu info window in font_selection_menu.lua):
-- readability of a font file path, "RATING: reason" or "N/A".
function PageTextInfo:getFontReadability(path)
    if not path then return "N/A" end
    return readabilityOfPath(path)
end

-- Returns three lines, each a list of segments: { font line, angle line, leading line }
local function buildTitleSegments(ui)
    local doc = ui.document
    local configurable = doc.configurable
    local display_dpi = Device:getDeviceScreenDPI() or Screen:getDPI()
    local reading_distance_mm = 400

    local na = {
        { { text = "Angle @40cm: N/A" } },
        { { text = "Leading: N/A" } },
    }

    local pt = configurable.font_size
    local ratio, face_name = xHeightRatio(doc)
    if not ratio then return na end
    local px = drawnPx(ui, pt, display_dpi)   -- whole px, as drawn by crengine
    local face_base = Font:getFace(face_name, px, 0, true)
    if not face_base or not face_base.ftsize then return na end

    local xh_px = ratio * px
    if xh_px <= 0 then return na end

    local xh_mm = xh_px * 25.4 / display_dpi
    local angle = math.deg(2 * math.atan(xh_mm / (2 * reading_distance_mm))) * 60
    local angle_class = angle < 12 and "Below critical size" or "Fluent range"

    -- Line 1: font (readability) and size, rem
    local line1 = {}
    local font_name = doc._document:getFontFace()
    if font_name and font_name ~= "" then
        table.insert(line1, { text = string.format("%s (%s) ", font_name, faceReadability(ui, font_name)) })
    end
    table.insert(line1, { text = string.format("%gpt", pt), bold = true })
    -- Does the book size its text in rem?
    table.insert(line1, { text = "  |  " })
    local uses = bookUsesRem(doc)
    local rem_txt = uses == nil and "rem: ?" or (uses and "rem: yes" or "rem: no")
    table.insert(line1, { text = rem_txt, bold = true })

    -- Line 2: angle, x-height, class
    local angle_line = {
        { text = string.format("Angle @40cm: %.1f′, %.2fmm ", angle, xh_mm) },
        { text = "[" .. angle_class .. "]", bold = true },
    }

    -- Line 3: leading, weight, contrast
    local line2 = { { text = "Leading: " } }
    local line_spacing_factor = (configurable.line_spacing or 100) / 100
    local ok, xh2, ascender, descender = pcall(function()
        return face_base.ftsize:getAscDesc()
    end)
    if ok and xh2 and ascender and descender then
        local leading_factor = (1.2 * px * line_spacing_factor) / xh_px
        local safe_min = (ascender + descender) / xh2
        local leading_class
        if leading_factor < safe_min then
            leading_class = "Collision"
        elseif leading_factor < safe_min + 0.15 then
            leading_class = "Compact"
        elseif leading_factor < safe_min + 0.4 then
            leading_class = "Balanced"
        elseif leading_factor < safe_min + 0.6 then
            leading_class = "Airy"
        else
            leading_class = "Very airy"
        end
        table.insert(line2, { text = string.format("%.2f× ", leading_factor) })
        table.insert(line2, { text = "[" .. leading_class .. "]", bold = true })
    else
        table.insert(line2, { text = "N/A" })
    end

    local weight = configurable.font_base_weight or 0
    local idx = getContrast(ui)
    local gamma = GAMMA_TABLE[idx + 1]
    table.insert(line2, { text = "  |  " })
    table.insert(line2, { text = string.format("weight %g", weight), bold = true })
    table.insert(line2, { text = "  |  " })
    table.insert(line2, { text = "contrast " .. (gamma and string.format("%g", gamma) or tostring(idx)), bold = true })

    dlog("title: pt=", pt, "face=", font_name, "x-height mm=", xh_mm, "angle'=", angle,
        "line spacing=", configurable.line_spacing,
        "weight=", weight, "contrast index=", idx, "gamma=", gamma)
    return { line1, angle_line, line2 }
end

-- Size combinations --------------------------------------------------------

-- crengine only draws whole pixels, so every pt size maps to a px size and
-- many pt values share the same px. Each distinct px size is one real
-- "combination": the smallest pt that produces it, the px drawn, the x-height
-- in mm and the visual angle at 40 cm. Shown in a popup (double tap on the
-- title) for every px size from the critical print size (CPS: the x-height
-- seen at COMBO_CPS_ARCMIN arc minutes from COMBO_DIST_MM) up to COMBO_MM_MAX.
-- If everything fits on the screen there are no scroll buttons; otherwise swipe
-- up/down (or the arrows) to scroll. Tap a row to apply it.
local TITLE_DOUBLE_TAP_S = 0.4   -- max time between the two taps on the title
-- Rows marked "◆" are the sizes where this font renders best: the x-height that
-- FreeType really gives at that px size (hinted, measured per row) differs from
-- the ideal one (ratio * px) by at most COMBO_RENDER_TOL px, so hinting has
-- almost nothing to round. If the measurement fails, the row falls back to the
-- estimate (distance of ratio * px to a whole number).
local COMBO_RENDER_TOL = 0.10
local COMBO_RENDER_SHARE = 0.25   -- fraction of the rows (the best ones) that get the mark
local COMBO_CPS_ARCMIN = 12
local COMBO_DIST_MM = 400
local COMBO_MM_MAX = 2.25

-- Returns a list of { pt, px, mm, angle, current } (ascending), or nil if the
-- font can't be measured.
local function buildSizeCombos(ui)
    local doc = ui.document
    local dpi = Device:getDeviceScreenDPI() or Screen:getDPI()
    local ratio, face_name = xHeightRatio(doc)
    if not ratio then return nil end

    local mm_per_px = ratio * 25.4 / dpi
    local cur_px = drawnPx(ui, doc.configurable.font_size, dpi)
    -- x-height that subtends COMBO_CPS_ARCMIN at COMBO_DIST_MM (about 1.40 mm)
    local cps_mm = 2 * COMBO_DIST_MM * math.tan(math.rad(COMBO_CPS_ARCMIN / 60 / 2))
    local first = math.max(1, math.ceil(cps_mm / mm_per_px - 1e-6))
    local last = math.floor(COMBO_MM_MAX / mm_per_px + 1e-6)

    local combos = {}
    for px = first, last do
        -- Smallest pt that crengine draws at this px (same formula as ptForXHeight)
        local pt = math.max(4, math.min(math.ceil(px * 72 / dpi * 100 + 0.001) / 100, 255))
        local mm = mm_per_px * px
        local xh_ideal = ratio * px   -- x-height in pixels, before hinting
        -- Real x-height at this px size, as FreeType gives it (hinted)
        local xh_real
        local okf, face = pcall(Font.getFace, Font, face_name, px, 0, true)
        if okf and face and face.ftsize then
            local okx, xh = pcall(function() return face.ftsize:getXHeight() end)
            if okx and xh and xh > 0 then
                local size = face.size or px
                xh_real = (xh < 1) and (xh * size) or xh
            end
        end
        -- Fallback when it can't be measured: distance of the ideal to a whole px
        local sweet = (not xh_real)
            and math.abs(xh_ideal - math.floor(xh_ideal + 0.5)) <= COMBO_RENDER_TOL
        dlog("combo px=", px, "xh ideal=", xh_ideal, "xh real=", xh_real)
        table.insert(combos, {
            pt = pt, px = px, mm = mm,
            xh_px = xh_real or xh_ideal,
            xh_ideal = xh_ideal,
            diff = xh_real and (xh_real - xh_ideal) or nil,
            sweet = sweet,
            angle = math.deg(2 * math.atan(mm / (2 * 400))) * 60,
            current = (px == cur_px),
        })
    end
    -- The hinted x-height may be systematically a bit above/below the ideal one
    -- (rounding up, overshoot...). What matters is how much it moves from row to
    -- row, so the typical difference (median) is removed before comparing.
    local diffs = {}
    -- KOReader's "Font hinting" option: 0 = off, 1 = native, 2 = auto. When it
    -- can't be read, it is guessed below from the measured x-heights.
    local hint = doc.configurable.font_hinting
    if hint == nil then hint = G_reader_settings:readSetting("copt_font_hinting") end
    local HINT_NAMES = { [0] = "off", [1] = "native", [2] = "auto" }
    local hint_name = HINT_NAMES[hint]
    local unhinted = (hint == 0)
    for __, c in ipairs(combos) do
        if c.diff then table.insert(diffs, c.diff) end
    end
    if #diffs > 0 then
        table.sort(diffs)
        local median = diffs[math.floor(#diffs / 2) + 1]
        -- Deviation of every row from the typical difference; the best
        -- COMBO_RENDER_SHARE of the rows are marked (plus any under the tolerance),
        -- so there are always several sizes to choose from.
        -- Without hinting the real x-height equals the ideal one at every size
        -- (differences ~0): then the hinting criterion says nothing, and what
        -- matters is how far the x-height edge is from a whole pixel (a half
        -- pixel gives a blurry grey edge).
        local max_abs = 0
        for __, c in ipairs(combos) do
            if c.diff then max_abs = math.max(max_abs, math.abs(c.diff)) end
        end
        if hint == nil then
            unhinted = max_abs < 0.05
            hint_name = unhinted and "off?" or "on?"
        end
        local devs = {}
        for __, c in ipairs(combos) do
            if c.diff then
                if unhinted then
                    c.dev = math.abs(c.xh_ideal - math.floor(c.xh_ideal + 0.5))
                else
                    c.dev = math.abs(c.diff - median)
                end
                table.insert(devs, c.dev)
            end
        end
        table.sort(devs)
        local limit = math.max(COMBO_RENDER_TOL, devs[math.max(1, math.ceil(#devs * COMBO_RENDER_SHARE))])
        for __, c in ipairs(combos) do
            if c.dev then c.sweet = c.dev <= limit end
        end
        dlog("buildSizeCombos: median diff real-ideal=", median, "limit=", limit,
            "unhinted=", unhinted)
    end
    dlog("buildSizeCombos: cur_px=", cur_px, "first px=", first, "last px=", last)
    return combos, unhinted, hint_name or "?"
end

-- `start` = index of the first visible row (nil: centre on the current size);
-- `old` = the previous combos dialog, replaced when scrolling.
local function showSizeCombos(plugin, start, old)
    local Blitbuffer = require("ffi/blitbuffer")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local Size = require("ui/size")
    local UIManager = require("ui/uimanager")
    local TextWidget = require("ui/widget/textwidget")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local LineWidget = require("ui/widget/linewidget")

    local ui = plugin.ui
    local all, unhinted, hint_name = buildSizeCombos(ui)
    if not all then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = "Size combinations: N/A" })
        return
    end

    local screen = Screen:getSize()
    local frame_w = math.floor(screen.w * 0.8)
    local outer_pad = Screen:scaleBySize(8)
    local inner_w = frame_w - 2 * (outer_pad + Size.border.window)
    local gap = Screen:scaleBySize(3)
    local thin = Screen:scaleBySize(1)
    local face = Font:getFace("cfont", 14)
    local small_face = Font:getFace("cfont", 11)
    local title_face = Font:getFace("cfont", 16)
    local row_h = math.floor(Screen:scaleBySize(14) * 1.7)
    local head_h = math.floor(Screen:scaleBySize(11) * 1.6)
    local title_h = math.floor(Screen:scaleBySize(16) * 1.5)
    local nav_h = row_h

    -- How many rows fit on the screen
    local base = title_h + head_h * 5 + gap * 8 + outer_pad * 2
    local n = #all
    if n == 0 then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = "Size combinations: N/A" })
        return
    end
    local fit_rows = math.floor((screen.h * 0.9 - base) / (row_h + gap))
    local needs_nav = n > fit_rows   -- no scroll buttons when everything fits
    local visible = n
    if needs_nav then
        visible = math.max(3, math.floor((screen.h * 0.9 - base - nav_h - gap * 2) / (row_h + gap)))
        visible = math.min(visible, n)
    end

    local cur_idx = 1
    for i, c in ipairs(all) do if c.current then cur_idx = i end end
    start = start or (cur_idx - math.floor(visible / 2))
    start = math.max(1, math.min(start, n - visible + 1))
    local stop = start + visible - 1

    -- Columns: pt | px | x-height | angle | bar
    local row_w = inner_w - 2 * thin
    local col_w = {
        math.floor(row_w * 0.18), math.floor(row_w * 0.14),
        math.floor(row_w * 0.20), math.floor(row_w * 0.20),
    }
    col_w[5] = row_w - col_w[1] - col_w[2] - col_w[3] - col_w[4]
    local bar_pad = Screen:scaleBySize(10)
    local bar_max_w = col_w[5] - 2 * bar_pad
    local max_mm = all[n].mm   -- bars are scaled on the whole list, so they don't change when scrolling

    local function cell(text, w, h, f, fg, bold)
        return CenterContainer:new{
            dimen = Geom:new{ w = w, h = h },
            TextWidget:new{ text = text, face = f, fgcolor = fg, bold = bold or false,
                max_width = w - 2 * Size.padding.small },
        }
    end

    local grid = VerticalGroup:new{ align = "center" }

    -- Title + subtitle (font, dpi)
    local face_name = ui.document._document:getFontFace() or "?"
    local dpi = Device:getDeviceScreenDPI() or Screen:getDPI()
    table.insert(grid, cell("Size combinations", inner_w, title_h, title_face, Blitbuffer.COLOR_BLACK, true))
    -- Size of one step: crengine draws whole pixels, so 1 px = this much pt / x-height
    local step_mm = all[1].mm / all[1].px
    local xh_ratio = step_mm * dpi / 25.4   -- x-height as a fraction of the font size (em)
    local readability = faceReadability(ui, face_name)
    table.insert(grid, cell(string.format("%s (%s) (x-height %.3fem)", face_name, readability, xh_ratio),
        inner_w, head_h, small_face, Blitbuffer.COLOR_DARK_GRAY))
    table.insert(grid, cell(string.format("step: 1px = %.2fpt = %.3fmm @%ddpi", 72 / dpi, step_mm, dpi),
        inner_w, head_h, small_face, Blitbuffer.COLOR_DARK_GRAY))
    table.insert(grid, VerticalSpan:new{ width = gap })

    -- Column headers
    local head = HorizontalGroup:new{}
    local labels = { "pt", "px", "x-height", "x-height px", "" }
    for i, t in ipairs(labels) do
        table.insert(head, cell(t, col_w[i], head_h, small_face, Blitbuffer.COLOR_DARK_GRAY))
    end
    table.insert(grid, CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = head_h }, head })
    table.insert(grid, LineWidget:new{
        dimen = Geom:new{ w = inner_w, h = thin }, background = Blitbuffer.COLOR_DARK_GRAY })
    table.insert(grid, VerticalSpan:new{ width = gap })

    -- Rows: the current one is inverted (white on black), like active buttons
    local rows = {}
    for i = start, stop do
        local c = all[i]
        local sweet = c.sweet
        local bs = thin
        local ch = row_h - 2 * bs
        local fg = c.current and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        local bar_w = math.max(1, math.floor(bar_max_w * c.mm / max_mm + 0.5))
        local inner = HorizontalGroup:new{
            cell(string.format("%s%.2fpt", sweet and "◆ " or "", c.pt), col_w[1], ch, face, fg, c.current),
            cell(string.format("%dpx", c.px), col_w[2], ch, face, fg, c.current),
            cell(string.format("%.2fmm", c.mm), col_w[3], ch, face, fg, c.current),
            cell(string.format("%.2fpx", c.xh_px), col_w[4], ch, face, fg, c.current),
            LeftContainer:new{
                dimen = Geom:new{ w = col_w[5], h = ch },
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = bar_pad },
                    LineWidget:new{
                        dimen = Geom:new{ w = bar_w, h = math.floor(row_h * 0.35) },
                        background = fg,
                    },
                },
            },
        }
        local frame = FrameContainer:new{
            bordersize = bs,
            color = c.current and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
            background = c.current and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
            radius = Size.radius.button,
            margin = 0, padding = 0,
            inner,
        }
        table.insert(grid, frame)
        table.insert(grid, VerticalSpan:new{ width = gap })
        table.insert(rows, { frame = frame, pt = c.pt })
    end

    -- Scroll buttons, only when the list doesn't fit (greyed out at its ends)
    local page = math.max(1, visible - 1)
    local can_up, can_down = needs_nav and start > 1, needs_nav and stop < n
    local up_btn, down_btn
    if needs_nav then
        local nav_w = math.floor((row_w - gap) / 2)
        local function navButton(text, enabled)
            return FrameContainer:new{
                bordersize = thin,
                color = enabled and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_LIGHT_GRAY,
                background = Blitbuffer.COLOR_WHITE,
                radius = Size.radius.button,
                margin = 0, padding = 0,
                cell(text, nav_w - 2 * thin, nav_h - 2 * thin, face,
                    enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY),
            }
        end
        up_btn = navButton("▲  smaller", can_up)
        down_btn = navButton("larger  ▼", can_down)
        table.insert(grid, CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = nav_h },
            HorizontalGroup:new{ up_btn, HorizontalSpan:new{ width = gap }, down_btn },
        })
        table.insert(grid, VerticalSpan:new{ width = gap })
    end

    table.insert(grid, LineWidget:new{
        dimen = Geom:new{ w = inner_w, h = thin }, background = Blitbuffer.COLOR_DARK_GRAY })
    local footer
    if needs_nav then
        footer = string.format("%.2f–%.2fmm  (%d–%d of %d)  ·  swipe or ▲▼ to scroll  ·  tap a row to apply",
            all[start].mm, all[stop].mm, start, stop, n)
    else
        footer = string.format("%.2f–%.2fmm  ·  tap a row to apply",
            all[1].mm, all[n].mm)
    end
    table.insert(grid, cell(footer, inner_w, head_h, small_face, Blitbuffer.COLOR_DARK_GRAY))
    local legend = unhinted
        and "◆ x-height edge closest to a whole pixel"
        or "◆ least hinting distortion"
    legend = legend .. "  [hinting: " .. hint_name .. "]"
    table.insert(grid, cell(string.format("%s (best %d%% of the sizes)  ·  tap outside to close",
        legend, math.floor(COMBO_RENDER_SHARE * 100 + 0.5)), inner_w, head_h, small_face, Blitbuffer.COLOR_DARK_GRAY))

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius = Size.radius.window,
        padding = outer_pad,
        margin = 0,
        grid,
    }

    local full = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h }
    local dialog = InputContainer:new{
        dimen = full,
        ges_events = {
            Tap = { GestureRange:new{ ges = "tap", range = full } },
            Swipe = { GestureRange:new{ ges = "swipe", range = full } },
        },
        key_events = Device:hasKeys() and { Close = { { Device.input.group.Back } } } or {},
    }
    dialog[1] = CenterContainer:new{ dimen = Geom:new{ w = screen.w, h = screen.h }, frame }

    local fsize = frame:getSize()
    local frame_rect = Geom:new{
        x = math.floor((screen.w - fsize.w) / 2),
        y = math.floor((screen.h - fsize.h) / 2),
        w = fsize.w, h = fsize.h,
    }

    local function closeCombos()
        UIManager:close(dialog, "ui", frame_rect)
    end

    -- Redraw the window with another first row (the old one is replaced)
    local function scrollTo(new_start)
        new_start = math.max(1, math.min(new_start, n - visible + 1))
        if new_start == start then return end
        dlog("size combos: scroll", start, "->", new_start)
        showSizeCombos(plugin, new_start, dialog)
    end

    function dialog:onTap(arg, ges)
        dlog("size combos tap:", ges.pos.x, ges.pos.y, "start=", start, "stop=", stop, "n=", n,
            "can_up=", can_up, "can_down=", can_down)
        if can_up and up_btn.dimen and ges.pos:intersectWith(up_btn.dimen) then
            scrollTo(start - page)
            return true
        end
        if can_down and down_btn.dimen and ges.pos:intersectWith(down_btn.dimen) then
            scrollTo(start + page)
            return true
        end
        for __, r in ipairs(rows) do
            if r.frame.dimen and ges.pos:intersectWith(r.frame.dimen) then
                local ok, err = pcall(setFontSize, ui, r.pt)
                dlog("size combos tap: pt=", r.pt, ok and "OK" or err)
                closeCombos()
                -- Reopen the settings menu after the reflow (refreshes its title)
                UIManager:nextTick(function()
                    plugin:onShowSettingsMenu()
                    if plugin.view and plugin.view.topbar then
                        plugin.view.topbar:toggleBar()
                    end
                end)
                return true
            end
        end
        if not ges.pos:intersectWith(frame_rect) then closeCombos() end
        return true
    end

    -- Swipe up = show larger sizes, swipe down = smaller (like paging a list)
    function dialog:onSwipe(arg, ges)
        local dir = ges.direction
        if dir == "north" then
            scrollTo(start + page)
        elseif dir == "south" then
            scrollTo(start - page)
        end
        return true
    end

    function dialog:onClose() closeCombos() return true end

    UIManager:show(dialog, "ui", frame_rect)
    if old then UIManager:close(old, "ui", frame_rect) end
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
    local CenterContainer = require("ui/widget/container/centercontainer")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local VerticalSpan = require("ui/widget/verticalspan")
    local LineWidget = require("ui/widget/linewidget")
    local LeftContainer = require("ui/widget/container/leftcontainer")

    local ui = self.ui
    if not ui or not ui.document or ui.paging or not ui.font or not ui.typeset then
        dlog("onShowSettingsMenu: skipped, not a reflowable book")
        return true
    end
    dlog("onShowSettingsMenu: open, reopen=", self.settings_dialog ~= nil)

    local old_dialog = self.settings_dialog
    local old_region = old_dialog and old_dialog.frame_rect and old_dialog.frame_rect:copy()
    self.settings_dialog = nil

    local screen = Screen:getSize()

    -- Layout metrics (scaled to the screen DPI)
    local frame_w = math.floor(screen.w * 0.8)
    local outer_pad = Screen:scaleBySize(5)
    -- Inner width available for rows (window width minus padding and border)
    local dialog_w = frame_w - 2 * (outer_pad + Size.border.window)
    local BTN_FONT_SIZE = 14            -- button text size (compact layout)
    local font_px = Screen:scaleBySize(BTN_FONT_SIZE)
    local cell_h = math.floor(font_px * 1.85)
    local gap = Screen:scaleBySize(3)   -- space between buttons and between rows
    local thin = Screen:scaleBySize(1)
    local buttons = {}

    local dialog = InputContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h },
        ges_events = {
            Tap = { GestureRange:new{ ges = "tap",
                range = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h } } },
            DoubleTap = { GestureRange:new{ ges = "double_tap",
                range = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h } } },
            Hold = { GestureRange:new{ ges = "hold",
                range = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h } } },
        },
        key_events = Device:hasKeys() and { Close = { { Device.input.group.Back } } } or {},
    }

    local label_face = Font:getFace("cfont", 11)
    local label_h = math.floor(Screen:scaleBySize(11) * 1.4)

    local grid = VerticalGroup:new{ align = "center" }
    for i, row_def in ipairs(buildRows(ui)) do
        local n = #row_def
        if n > 0 then
            local cell_w = math.floor((dialog_w - gap * (n - 1)) / n)

            -- Section caption, left aligned
            if row_def.title then
                table.insert(grid, LeftContainer:new{
                    dimen = Geom:new{ w = dialog_w, h = label_h },
                    HorizontalGroup:new{
                        HorizontalSpan:new{ width = gap },
                        TextWidget:new{
                            text = row_def.title,
                            face = label_face,
                            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                        },
                    },
                })
            end

            local row = HorizontalGroup:new{}
            for j, b in ipairs(row_def) do
                if j > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
                -- Rounded buttons. The active one is inverted (white text on black),
                -- which reads much better on e-ink than a thicker border.
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
                            face = Font:getFace("cfont", BTN_FONT_SIZE),
                            fgcolor = b.active and Blitbuffer.COLOR_WHITE
                                or (b.disabled and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK),
                            bold = b.active and true or false,
                            max_width = cell_w - 2 * Size.padding.small,
                        },
                    },
                }
                table.insert(row, frame)
                table.insert(buttons, { frame = frame, callback = b.callback, text = b.text })
            end
            table.insert(grid, row)
            table.insert(grid, VerticalSpan:new{ width = gap })
        end
    end

    local title_face = Font:getFace("cfont", 12)
    local line_h = math.floor(cell_h * 0.75)
    local title_rows = VerticalGroup:new{ align = "center" }
    for __, line in ipairs(buildTitleSegments(ui)) do
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
    dialog[1] = CenterContainer:new{
        dimen = Geom:new{ w = screen.w, h = screen.h },
        frame,
    }

    local fsize = frame:getSize()
    local frame_rect = Geom:new{
        x = math.floor((screen.w - fsize.w) / 2),
        y = math.floor((screen.h - fsize.h) / 2),
        w = fsize.w, h = fsize.h,
    }

    function dialog:onTap(arg, ges)
        dlog("settings tap", ges.pos.x, ges.pos.y)

        -- Tap on the title: open the reference popup from typography_popup.lua
        if title_frame.dimen and ges.pos:intersectWith(title_frame.dimen) then
            -- Double tap detection done here (KOReader's own "tap" fires first and
            -- would open the reference before the double tap is seen): the single
            -- tap action waits TITLE_DOUBLE_TAP_S; a second tap in that time
            -- cancels it and opens the size combinations instead.
            if self.title_tap_fn then
                UIManager:unschedule(self.title_tap_fn)
                self.title_tap_fn = nil
                dlog("settings: second tap on the title -> size combinations")
                showSizeCombos(self.plugin)
                return true
            end
            local dlg = self
            self.title_tap_fn = function()
                dlg.title_tap_fn = nil
                dlog("settings: tap on the title -> typography reference")
                local plugin_ui = dlg.plugin.ui
                if plugin_ui and plugin_ui.onShowTypographyReference then
                    plugin_ui:onShowTypographyReference()
                else
                    require("logger").warn("[PTI] onShowTypographyReference not available")
                end
            end
            UIManager:scheduleIn(TITLE_DOUBLE_TAP_S, self.title_tap_fn)
            return true
        end

        for __, b in ipairs(buttons) do
            if b.frame.dimen and ges.pos:intersectWith(b.frame.dimen) then
                local ok, err = pcall(b.callback, self.plugin.ui)
                dlog("settings menu tap:", b.text, ok and "OK" or err)
                -- Reopen after the reflow so the active state is refreshed
                UIManager:nextTick(function()
                    local plugin = self.plugin
                    plugin:onShowSettingsMenu()
                    if plugin.view and plugin.view.topbar then
                        plugin.view.topbar:toggleBar()
                    end
                end)
                return true
            end
        end
        if not ges.pos:intersectWith(frame_rect) then
            close(self.plugin)
        end
        return true
    end

    -- Double tap on the title: pt -> px -> x-height combinations
    function dialog:onDoubleTap(arg, ges)
        if title_frame.dimen and ges.pos:intersectWith(title_frame.dimen) then
            dlog("settings: double tap on the title -> size combinations")
            if self.title_tap_fn then
                UIManager:unschedule(self.title_tap_fn)
                self.title_tap_fn = nil
            end
            showSizeCombos(self.plugin)
        end
        return true
    end

    -- Long press inside the window: save the current font as the default
    function dialog:onHold(arg, ges)
        if not (title_frame.dimen and ges.pos:intersectWith(title_frame.dimen)) then
            return true
        end
        dlog("settings: long press on the title -> save current font as default")
        local plugin = self.plugin
        local ok, face, pt = pcall(saveCurrentFontAsDefault, plugin.ui)
        local text
        if ok and face then
            local mm = plugin:getXHeightMm()
            text = mm
                and string.format("Default font saved:\n%s, %.2fpt (%.2fmm)", face, pt, mm)
                or string.format("Default font saved:\n%s, %.2fpt", face, pt)
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
