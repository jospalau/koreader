-- Quick settings menu: rows of buttons (font size, line spacing, margins, weight...)
-- Same look and gesture handling as the fonts menu.
--
-- Lives next to main.lua. Load it from main.lua, after PageTextInfo is defined:
--     require("settings_menu")(PageTextInfo)
--
-- It adds these methods to PageTextInfo:
--     onShowSettingsMenu, getXHeightMm, ptForXHeight, applyFontSizePt

local Device = require("device")
local Font = require("ui/font")
local Screen = Device.screen

return function(PageTextInfo)

-- Font presets: EFFECTIVE x-height in millimetres (same "mm" shown in the menu title).
-- small / big: used as is.
-- normal: only a fallback. Normally it is taken from KOReader's configured
-- default font and size (see presetMm).

local FONT_PRESETS = { small = 1.45, normal = 1.65, big = 1.90 }
local FONT_FALLBACK = { small = 8.5, normal = 9.5, big = 11 }

local WEIGHT_STEP = 0.5

local CONTRAST_MIN, CONTRAST_MAX = 0, 56
local CONTRAST_DEFAULT = 15

-- Forward declarations: assigned further down, but must be declared here
-- so every function below sees them as upvalues (not globals).
local ptForXHeight
local bookScale
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

-- Book font-size factor (rem/em/%), 1 if unknown.
-- Only a factor read from the book's CSS counts: without rem/em styles the
-- compensation does nothing (factor 1).
local function remScale(ui)
    local ok, scale = pcall(function()
        local __, face_name = xHeightRatio(ui.document)
        if not face_name then return 1 end
        local factor, source = bookScale(ui, Font:getFace(face_name, 100, 0, true))
        if source ~= "css" then return 1 end
        return factor
    end)
    return ok and scale or 1
end

-- pt to apply so the EFFECTIVE size (pt x book factor) equals `pt`
local function compensate(ui, pt)
    return math.floor(pt / remScale(ui) * 100 + 0.5) / 100
end

-- pt to apply for a desired pt, according to the active mode
local function presetPtFor(ui, pt)
    if PageTextInfo:isCompensateRem() then
        return compensate(ui, pt)
    end
    return pt
end

local function close(self)
    local UIManager = require("ui/uimanager")
    local d = self.settings_dialog
    self.settings_dialog = nil
    if d then UIManager:close(d, "ui", d.frame_rect) end
end

-- Actions ---------------------------------------------------------------

local function setFontFace(ui, face)
    if not face or face == "" then return end
    if ui.rolling then  -- only reflowable (CRE) documents support font faces
        ui.font:onSetFont(face)
    end
end

local function setFontSize(ui, pt)
    pt = math.max(4, math.min(pt, 255))
    ui.font:onSetFontSize(pt, true)
    -- Keep both configurables in sync (harmless if they are the same table)
    ui.document.configurable.font_size = pt
    ui.font.configurable.font_size = pt
end

-- Step the font size by `delta` pt, repeating until the rendering engine
-- actually changes size. CREngine only distinguishes discrete sizes, so a
-- small step (e.g. 0.1 pt, or the fractional values produced by the rem/em
-- compensation) may leave the effective size unchanged. Each call therefore
-- keeps adding `delta` (rounded to 0.01 to avoid float drift) until
-- getFontSize() reports a new value. The 40 iterations cap avoids an endless
-- loop when the minimum or maximum font size is reached.
local function stepFontSize(ui, delta)
    local function cre_size() return ui.document._document:getFontSize() end
    local before = cre_size()
    local pt = ui.font.configurable.font_size
    for __ = 1, 40 do
        pt = math.floor((pt + delta) * 100 + 0.5) / 100
        setFontSize(ui, pt)
        if cre_size() ~= before then break end
    end
end

local function setLineSpacing(ui, percent)
    ui.document:setInterlineSpacePercent(percent)
    ui.document.configurable.line_spacing = percent
    ui:handleEvent(require("ui/event"):new("UpdatePos"))
end

local function setMargins(ui, m)
    -- m = {left, top, right, bottom}. The event does not store them, so do it here
    local conf = ui.document.configurable
    conf.h_page_margins = { m[1], m[3] }
    conf.t_page_margin  = m[2]
    conf.b_page_margin  = m[4]
    ui.typeset:onSetPageMargins(m)
end

local function setWeight(ui, w)
    w = math.max(-3, math.min(w, 5))
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

-- Save the current font face and size as KOReader's defaults for new books.
-- These are the same settings configuredXHeightMm reads, so "Font default"
-- then follows the x-height of what was just saved.
-- Returns face, pt.
local function saveCurrentFontAsDefault(ui)
    local face = ui.document._document:getFontFace()
    local pt = ui.font.configurable.font_size
    if not face or not pt then return nil end
    G_reader_settings:saveSetting("cre_font", face)
    G_reader_settings:saveSetting("copt_font_size", pt)
    G_reader_settings:flush()
    return face, pt
end

-- Effective x-height (mm) of KOReader's configured default font and size,
-- in the current book. Returns nil if it can't be measured.
local function configuredXHeightMm(ui)
    local ok, res = pcall(function()
        -- Default face and size as set in KOReader (fall back to this file's DEFAULTS)
        -- No default face saved: don't force DEFAULTS.font_face. If the saved
        -- face can't be measured (e.g. not installed), use the current one.
        local face = G_reader_settings:readSetting("cre_font")
        local pt = G_reader_settings:readSetting("copt_font_size") or DEFAULTS.font_size

        local ratio, face_name = xHeightRatio(ui.document, face)
        if not ratio then ratio, face_name = xHeightRatio(ui.document) end
        if not ratio then return nil end
        local scale = bookScale(ui, Font:getFace(face_name, 100, 0, true))

        -- x_mm = ratio * scale * px / px_per_mm, with px = dpi * pt / 72,
        -- so the dpi cancels out
        return ratio * scale * pt * 25.4 / 72
    end)
    if ok then return res end
    require("logger").warn("configuredXHeightMm failed:", res)
    return nil
end

-- Target x-height in mm for a preset. "normal" follows KOReader's configured
-- size; small/big use the fixed values in FONT_PRESETS.
local function presetMm(ui, name)
    if name == "normal" then
        return configuredXHeightMm(ui) or FONT_PRESETS.normal
    end
    return FONT_PRESETS[name]
end

local function resetDefaults(ui)
    -- Use the face saved with the long press; fall back to DEFAULTS.font_face
    setFontFace(ui, G_reader_settings:readSetting("cre_font") or DEFAULTS.font_face)
    if PageTextInfo:isScaleByXHeight() then
        -- Use the mm-based "normal" preset; fall back to the fixed pt value
        setFontSize(ui, (ptForXHeight and ptForXHeight(ui, presetMm(ui, "normal"))) or defaultFontSize())
    else
        setFontSize(ui, presetPtFor(ui, defaultFontSize()))
    end
    setLineSpacing(ui, DEFAULTS.line_spacing)
    setMargins(ui, DEFAULTS.margins)
    setWeight(ui, DEFAULTS.font_base_weight)
end

-- ASSUMPTION: "toggle screen layout" = swap portrait/landscape. Change it to
-- whatever you meant (e.g. footer toggle) in this one function.
local function toggleLayout(ui)
    local Event = require("ui/event")
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

local function buildRows(ui)
    local conf = ui.document.configurable
    local fs = ui.font.configurable.font_size
    require("logger").dbg("settings menu state: font_size=", fs,
        "line_spacing=", conf.line_spacing, "weight=", conf.font_base_weight,
        "h_margins=", conf.h_page_margins and (conf.h_page_margins[1] .. "," .. conf.h_page_margins[2]) or "nil",
        "t=", conf.t_page_margin, "b=", conf.b_page_margin)

    -- Resolve each preset to the closest achievable pt on the current face.
    -- Also returns the achieved x-height (mm) to show it on the button.
    local function presetPt(name)
        local target_mm = presetMm(ui, name)
        local pt, mm = ptForXHeight(ui, target_mm)
        require("logger").dbg("font preset", name, "target mm=", target_mm,
            "-> pt=", pt, "achieved mm=", mm)
        return pt or FONT_FALLBACK[name], mm
    end
    local pts, mms = {}, {}
    if PageTextInfo:isScaleByXHeight() then
        for __, name in ipairs({ "small", "normal", "big" }) do
            pts[name], mms[name] = presetPt(name)
        end
    end

    -- Button text with the x-height in mm (plain text if it couldn't be measured)
    -- "(pt)" marks a preset that couldn't be measured (fixed pt fallback used)
    local function withMm(text, mm)
        return mm and string.format("%s %.2f mm", text, mm) or (text .. " (pt)")
    end

    -- Tight comparison for the "active" border (pt values have 0.01 resolution)
    local function near(a, b) return a and b and math.abs(a - b) < 0.011 end

    local font_preset_row
    if PageTextInfo:isScaleByXHeight() then
        font_preset_row = {
            { text = withMm("Font small", mms.small),
              callback = function(u) setFontSize(u, pts.small) end,
              active = near(fs, pts.small) },
            { text = withMm("Font default", mms.normal),
              callback = function(u) setFontSize(u, pts.normal) end,
              active = near(fs, pts.normal) },
            { text = withMm("Font big", mms.big),
              callback = function(u) setFontSize(u, pts.big) end,
              active = near(fs, pts.big) },
        }
    else
        local fx = fixedPresets()
        fx.small  = presetPtFor(ui, fx.small)
        fx.normal = presetPtFor(ui, fx.normal)
        fx.big    = presetPtFor(ui, fx.big)
        font_preset_row = {
            { text = "Font small",   callback = function(u) setFontSize(u, fx.small) end,  active = near(fs, fx.small) },
            { text = "Font default", callback = function(u) setFontSize(u, fx.normal) end, active = near(fs, fx.normal) },
            { text = "Font big",     callback = function(u) setFontSize(u, fx.big) end,    active = near(fs, fx.big) },
        }
    end
    local rows = {
        { -- 1
            { text = "Reset defaults",      callback = resetDefaults },
            { text = "Toggle screen layout", callback = toggleLayout },
        },
            font_preset_row, -- 2
        { -- 3
            { text = "Font ▼", callback = function(u) stepFontSize(u, -0.1) end },
            { text = "Font ▲", callback = function(u) stepFontSize(u,  0.1) end },
        },
        {}, -- 4: line spacing (filled below)
        {}, -- 5: margins (filled below)
        { -- 6
            { text = "Decrease weight", callback = function(u) setWeight(u, u.document.configurable.font_base_weight - WEIGHT_STEP) end },
            { text = "Increase weight", callback = function(u) setWeight(u, u.document.configurable.font_base_weight + WEIGHT_STEP) end },
        },
        {
            { text = "Decrease contrast", callback = function(u) stepContrast(u, -1) end },
            { text = "Increase contrast", callback = function(u) stepContrast(u, 1) end },
        },
    }

    local ls = conf.line_spacing
    for __, spacing in ipairs(LINE_SPACINGS) do
        table.insert(rows[4], {
            text = spacing.label,
            callback = function(u) setLineSpacing(u, spacing.percent) end,
            active = approx(ls, spacing.percent),
        })
    end
    for __, p in ipairs(MARGIN_PRESETS) do
        table.insert(rows[5], {
            text = p.label,
            callback = function(u) setMargins(u, p.value) end,
            active = marginsMatch(conf, p.value) and true or false,
        })
    end
    return rows
end

-- Measures the book font-size factor from the words visible on the page:
-- (width drawn by crengine) / (width expected at the plain face size).
local function effectiveScale(ui, face_base)
    local doc = ui.document
    local RenderText = require("ui/rendertext")
    local W, H = Screen:getWidth(), Screen:getHeight()
    local ratios = {}
    -- More sample points so sparse pages still yield >= 3 valid words
    local N = 48
    for i = 1, N do
        local x = math.floor(W * (0.15 + 0.7 * ((i * 37) % 10) / 10))
        local y = math.floor(H * (0.08 + 0.84 * i / (N + 1)))
        local w = doc._document:getTextFromPositions(x, y, x, y, false, false)
        -- Whole words only: no hyphens, no spaces
        if w and w.text and w.text:match("^%a%a%a%a+$") and w.pos0 and w.pos1 then
            local boxes = doc:getScreenBoxesFromPositions(w.pos0, w.pos1, true)
            if boxes and #boxes == 1 and boxes[1].w > 0 then
                local expected = RenderText:sizeUtf8Text(0, W, face_base, w.text, true, false).x
                if expected > 0 then ratios[#ratios + 1] = boxes[1].w / expected end
            end
        end
    end
    if #ratios < 3 then return nil end
    table.sort(ratios)
    local cre_size = ui.document._document:getFontSize()
    local median = ratios[math.ceil(#ratios / 2)]
    if not cre_size or cre_size <= 0 or not face_base.size then return nil end
    return median * face_base.size / cre_size
end

local _css_cache = {}
local _scale_cache = {}   -- [book file] = { scale, source }
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
        return best or any
    end
    return (raw_name:gsub("%s+", "") .. "-Regular")
end

-- Returns the KOReader pt size whose EFFECTIVE x-height (font x-height ratio
-- x book font-size factor) equals `target_mm`. Same model as the menu title.
-- Returns pt, achieved_mm (or nil if the font can't be measured).
ptForXHeight = function(ui, target_mm)
    local ok, pt_res, mm_res = pcall(function()
        local dpi = Device:getDeviceScreenDPI() or Screen:getDPI()
        local px_per_mm = dpi / 25.4

        local ratio, face_name = xHeightRatio(ui.document)
        if not ratio then return nil end

        -- Book font-size factor (same helper the title uses)
        local face = Font:getFace(face_name, 100, 0, true)
        local scale, source = bookScale(ui, face)
        require("logger").dbg("font preset scale=", scale, "source=", source,
            "face=", face_name, "ratio=", ratio)

        -- x_mm = ratio * scale * px / px_per_mm, with px = dpi * pt / 72.
        -- Solve for pt, then round to 0.01 pt (KOReader's resolution).
        local px = target_mm * px_per_mm / (ratio * scale)
        local pt = math.floor(px * 72 / dpi * 100 + 0.5) / 100
        pt = math.max(4, math.min(pt, 255))

        local achieved_mm = ratio * scale * (dpi * pt / 72) / px_per_mm
        return pt, achieved_mm
    end)
    if ok then return pt_res, mm_res end
    -- pt_res holds the error message when pcall fails
    require("logger").warn("ptForXHeight failed:", pt_res)
    return nil
end

-- Returns { value=0.88, unit="rem", share=1.0 }: the most repeated font-size
-- in the EPUB's .css files.
local function bookFontSizeStats(doc)
    local file = doc.file
    if not file then return nil end
    if _css_cache[file] ~= nil then return _css_cache[file] or nil end
    local ok, res = pcall(function()
        local Archiver = require("ffi/archiver")
        local arc = Archiver.Reader:new()
        if not arc:open(file) then return nil end
        local counts, total = {}, 0
        local body_counts, body_total = {}, 0
        for entry in arc:iterate() do
            if entry.mode == "file" and entry.path:lower():match("%.css$") then
                local css = arc:extractToMemory(entry.path)
                if css then
                    css = css:gsub("/%*.-%*/", "")  -- strip comments
                    -- Prefer the body / html / p rules (body text) over counting
                    -- every declaration in the CSS
                    for sel, block in css:gmatch("([^{}]+)%{([^}]*)%}") do
                        local is_body = false
                        for s in sel:gmatch("[^,]+") do
                            local t = s:gsub("^%s+", ""):gsub("%s+$", "")
                            if t == "body" or t == "html" or t == "p" or t == "body p" then
                                is_body = true
                            end
                        end
                        for v, u in block:gmatch("font%-size%s*:%s*([%d%.]+)%s*(%a*%%?)") do
                            local k = v .. "|" .. u
                            counts[k] = (counts[k] or 0) + 1
                            total = total + 1
                            if is_body then
                                body_counts[k] = (body_counts[k] or 0) + 1
                                body_total = body_total + 1
                            end
                        end
                    end
                end
            end
        end
        arc:close()
        if total == 0 then return nil end
        if body_total > 0 then counts, total = body_counts, body_total end
        local best_k, best_n = nil, 0
        for k, n in pairs(counts) do
            -- Tie-break on the key so the result doesn't depend on pairs() order
            if n > best_n or (n == best_n and best_k and k < best_k) then
                best_k, best_n = k, n
            end
        end
        local v, u = best_k:match("^(.-)|(.*)$")
        return { value = tonumber(v), unit = u, share = best_n / total }
    end)
    _css_cache[file] = (ok and res) or false
    return (ok and res) or nil
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
        require("logger").warn("xHeightRatio: cannot load face", raw_name, face_name)
        return nil
    end
    -- Divide by the size the face was really loaded at (it may be DPI-scaled)
    local real_size = face.size or 200
    -- Protected: a 0/nil x-height means the face can't be measured
    local okx, xh = pcall(function() return face.ftsize:getXHeight() end)
    if not okx or not xh or xh <= 0 then
        require("logger").warn("xHeightRatio: no x-height for", face_name)
        return nil
    end
    local xh_px = (xh < 1) and (xh * real_size) or xh
    if xh_px <= 0 or real_size <= 0 then return nil end

    local ratio = xh_px / real_size
    _ratio_cache[face_name] = ratio
    return ratio, face_name
end

-- Book font-size factor (e.g. 0.88 for 0.88rem), computed once per book and
-- cached, so the title and the presets never change between menu reopenings.
-- Prefers the CSS value; falls back to an on-screen measurement.
-- Returns factor, source ("css" | "measured" | "none").
bookScale = function(ui, face_base)
    local doc = ui.document
    local key = doc.file
    local cached = key and _scale_cache[key]
    if cached then return cached[1], cached[2] end

    local scale, source = 1, "none"

    -- With the publisher style sheet disabled ("Book styles" off) crengine
    -- ignores the CSS, so the real factor is 1 (embedded_css: 1 = enabled).
    local conf = doc.configurable
    if conf and conf.embedded_css == 0 then
        if key then _scale_cache[key] = { 1, "nocss" } end
        return 1, "nocss"
    end

    local st = bookFontSizeStats(doc)
    -- Only trust the CSS if one value dominates and the unit is relative
    if st and st.value and st.share >= 0.6
       and (st.unit == "rem" or st.unit == "em" or st.unit == "%") then
        local expected = (st.unit == "%") and st.value / 100 or st.value
        if expected > 0.5 and expected < 1.5 then scale, source = expected, "css" end
    end
    if source == "none" then
        local measured = effectiveScale(ui, face_base)
        if measured and measured > 0.5 and measured < 1.5 then scale, source = measured, "measured" end
    end

    -- Don't cache "none": it may be a failed measurement, so retry next time
    if key and source ~= "none" then _scale_cache[key] = { scale, source } end
    return scale, source
end

-- Public methods (used by the fonts menu in main.lua) --------------------

-- Current EFFECTIVE x-height in mm (same model as the menu title).
-- Returns nil if the font can't be measured.
function PageTextInfo:getXHeightMm()
    local ui = self.ui
    local ok, mm = pcall(function()
        local dpi = Device:getDeviceScreenDPI() or Screen:getDPI()
        local ratio, face_name = xHeightRatio(ui.document)
        if not ratio then return nil end
        local face = Font:getFace(face_name, 100, 0, true)
        local scale = bookScale(ui, face)
        local px = dpi * ui.document.configurable.font_size / 72  -- unrounded, like KOReader
        return ratio * scale * px / (dpi / 25.4)
    end)
    return ok and mm or nil
end

-- True if the book has rem/em/% font-size styles to compensate. Use it to grey
-- out (and show unchecked) the "compensate book rem/em" menu item.
function PageTextInfo:hasRemStyles()
    local ui = self.ui
    local ok, res = pcall(function()
        local __, face_name = xHeightRatio(ui.document)
        if not face_name then return false end
        local scale, source = bookScale(ui, Font:getFace(face_name, 100, 0, true))
        return source == "css" and math.abs(scale - 1) > 0.001
    end)
    return ok and res or false
end

-- Name that Font:getFace accepts for the current face (the one that worked in
-- xHeightRatio). Returns nil if the font can't be loaded.
function PageTextInfo:getFaceName()
    local ok, ratio, face_name = pcall(xHeightRatio, self.ui.document)
    return ok and ratio and face_name or nil
end

-- pt size that gives `target_mm` of effective x-height with the CURRENT face.
function PageTextInfo:ptForXHeight(target_mm)
    return (ptForXHeight(self.ui, target_mm))  -- first return value only
end

-- Set the font size without a notification, keeping configurables in sync.
function PageTextInfo:applyFontSizePt(pt)
    setFontSize(self.ui, pt)
end

-- Title ------------------------------------------------------------------

-- Returns two lines, each a list of segments: { line1, line2 }
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
    local px = display_dpi * pt / 72
    local face_base = Font:getFace(face_name, math.floor(px + 0.5), 0, true)
    if not face_base or not face_base.ftsize then return na end

    local xh_px = ratio * px
    local scale, scale_source = bookScale(ui, face_base)
    if scale_source ~= "none" then xh_px = xh_px * scale end
    if xh_px <= 0 then return na end

    local xh_mm = xh_px * 25.4 / display_dpi
    local angle = math.deg(2 * math.atan(xh_mm / (2 * reading_distance_mm))) * 60
    local angle_class = angle < 12 and "Below critical size" or "Fluent range"

    -- Line 1: angle, x-height, class, rem, pt
    local line1 = {
        { text = string.format("Angle @40cm: %.1f′, %.2f mm ", angle, xh_mm) },
        { text = "[" .. angle_class .. "]", bold = true },
    }
    local st = bookFontSizeStats(doc)
    if st and st.unit == "rem" and st.value then
        table.insert(line1, { text = string.format(" rem %g", st.value), bold = true })
    end
    table.insert(line1, { text = "  |  " })
    table.insert(line1, { text = string.format("%g pt", pt), bold = true })

    -- Line 2: leading, weight, contrast
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
    local CenterContainer = require("ui/widget/container/centercontainer")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local VerticalGroup = require("ui/widget/verticalgroup")

    local ui = self.ui
    if not ui or not ui.document or ui.paging or not ui.font or not ui.typeset then
        return true
    end

    local old_dialog = self.settings_dialog
    local old_region = old_dialog and old_dialog.frame_rect and old_dialog.frame_rect:copy()
    self.settings_dialog = nil

    local screen = Screen:getSize()
    local dialog_w = math.floor(screen.w * 0.9)
    local font_px = Screen:scaleBySize(18)
    local cell_h = math.floor(font_px * 2.4)
    local thin  = Screen:scaleBySize(1)
    local thick = Screen:scaleBySize(3)
    local buttons = {}

    local dialog = InputContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h },
        ges_events = {
            Tap = { GestureRange:new{ ges = "tap",
                range = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h } } },
            Hold = { GestureRange:new{ ges = "hold",
                range = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h } } },
        },
        key_events = Device:hasKeys() and { Close = { { Device.input.group.Back } } } or {},
    }

    local grid = VerticalGroup:new{ align = "center" }
    for __, row_def in ipairs(buildRows(ui)) do
        local n = #row_def
        if n > 0 then
            local cell_w = math.floor(dialog_w / n)
            local row = HorizontalGroup:new{}
            for __, b in ipairs(row_def) do
                local frame = FrameContainer:new{
                    bordersize = thin,
                    color = Blitbuffer.COLOR_BLACK,
                    margin = 0,
                    padding = 0,
                    FrameContainer:new{
                        bordersize = thick - thin,
                        color = b.active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
                        background = Blitbuffer.COLOR_WHITE,
                        margin = 0,
                        padding = 0,
                        CenterContainer:new{
                            dimen = Geom:new{ w = cell_w - 2 * thick, h = cell_h - 2 * thick },
                            TextWidget:new{
                                text = b.text,
                                face = Font:getFace("cfont", 18),
                                max_width = cell_w - 2 * Size.padding.small,
                            },
                        },
                    },
                }
                table.insert(row, frame)
                table.insert(buttons, { frame = frame, callback = b.callback, text = b.text })
            end
            table.insert(grid, row)
        end
    end

    local title_face = Font:getFace("cfont", 14)
    local line_h = math.floor(cell_h * 0.7)
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
    local title_frame = FrameContainer:new{
        bordersize = 0, margin = 0, padding = 0,
        title_rows,
    }

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius = Size.radius.window,
        padding = Size.padding.small,
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
        require("logger").info("settings tap", ges.pos.x, ges.pos.y)

        -- Tap on the title: open the reference popup from typography_popup.lua
        if title_frame.dimen and ges.pos:intersectWith(title_frame.dimen) then
            local plugin_ui = self.plugin.ui
            if plugin_ui and plugin_ui.onShowTypographyReference then
                plugin_ui:onShowTypographyReference()
            else
                require("logger").warn("onShowTypographyReference not available")
            end
            return true
        end

        for __, b in ipairs(buttons) do
            if b.frame.dimen and ges.pos:intersectWith(b.frame.dimen) then
                local ok, err = pcall(b.callback, self.plugin.ui)
                require("logger").dbg("settings menu tap:", b.text, ok and "OK" or err)
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

    -- Long press inside the window: save the current font as the default
    function dialog:onHold(arg, ges)
        if not (title_frame.dimen and ges.pos:intersectWith(title_frame.dimen)) then
            return true
        end
        local plugin = self.plugin
        local ok, face, pt = pcall(saveCurrentFontAsDefault, plugin.ui)
        local text
        if ok and face then
            local mm = plugin:getXHeightMm()
            text = mm
                and string.format("Default font saved:\n%s, %.2f pt (%.2f mm)", face, pt, mm)
                or string.format("Default font saved:\n%s, %.2f pt", face, pt)
        else
            -- face holds the error message when pcall fails
            require("logger").warn("saveCurrentFontAsDefault failed:", face)
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

local logger = require("logger")
-- Re-apply the current font size after the rem compensation setting changes,
-- so the effective size matches the new mode.
function PageTextInfo:reapplyFontCompensation(enabled)
    local ui = self.ui

    -- Ignore a repeated call with the same value (it would apply the factor twice)
    enabled = enabled and true or false
    if self._comp_applied == enabled then return end
    self._comp_applied = enabled

    local cur = ui.font.configurable.font_size
    local scale = remScale(ui)

    -- Turning it on divides by the book factor (see compensate); turning it off
    -- multiplies it back. Starting from the current size, so it also works when
    -- the book was opened with the option already on and after any size change.
    local new_pt = enabled
        and compensate(ui, cur)
        or math.floor(cur * scale * 100 + 0.5) / 100

    logger.dbg("reapply", "enabled", enabled, "cur", cur,
        "scale", scale, "new_pt", new_pt)

    setFontSize(ui, new_pt)
end

end -- return function(PageTextInfo)
