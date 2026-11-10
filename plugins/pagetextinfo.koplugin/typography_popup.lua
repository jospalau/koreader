--[[
Typography Info Popup (table layout)
Replaces the plain InfoMessage from onGetTextPage with a structured popup.
Every section is rendered as a bordered table:

  - TEXT        start of the text the CSS is sampled from (truncated)
  - FONT        face, size, didot, px, mm, weight
  - X-HEIGHT    px, mm, visual angle, multiple of CPS, leading,
                delta vs personal preference, font size that would hit it
                (tap this section to open the REFERENCE popup)
  - DISPLAY     device, ppi, resolution, frontlight
  - CSS         3-column table: property | <p tag> | <body tag>
  - TWEAKS      one row per applied tweak
  - READING     avg wpm, wph, sessions, recent averages

REFERENCE popup (opened by tapping X-HEIGHT):
  - ANGLE → SIZE  x-height in mm and font size in pt for each reference angle
  - REFERENCE     sources, CPS definition, bands, print books, preference
]]

local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local Dispatcher      = require("dispatcher")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local Math            = require("optmath")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local logger          = require("logger")
local util            = require("util")
local Screen          = Device.screen

-- Max characters of page text shown in the TEXT section (0 = hide)
local SNIPPET_CHARS = 150

-- Reading distance used for every angular computation. 40 cm is the
-- conventional "standard" distance of the vision-science literature, which
-- makes the numbers comparable with published ones. Real e-reader distances
-- vary (one study cited by Legge & Bigelow found ~50 cm for e-paper), so
-- change it here if you read from elsewhere.
local READING_DISTANCE_MM = 400

-- Critical print size (CPS) in arcminutes of x-height. Evidence-based (see
-- below); used both as the first band edge and as the unit for "× CPS".
local CPS_ARCMIN = 12

-- x-height angles of real printed books and newspapers, in arcminutes
-- (Legge & Bigelow 2011: 0.20-0.28 deg = 12-17′, mean ~14′).
local PRINT_MIN_ARCMIN  = 12
local PRINT_MEAN_ARCMIN = 14
local PRINT_MAX_ARCMIN  = 17

-- Preferred x-height, in arcminutes: the midpoint between the mean and the
-- maximum of printed books (15.5′ ≈ 1.80mm at 40cm), i.e. the upper half of
-- the print range, a bit larger than the average book to compensate for the
-- lower contrast of e-ink. Derived from external data instead of a free
-- number, but it is still a personal choice of reference, NOT a scientific
-- norm: it is shown separately from the evidence-based bands below. If you
-- find your own comfortable value, replace it (stored as an angle).
local PREFERRED_ARCMIN = (PRINT_MEAN_ARCMIN + PRINT_MAX_ARCMIN) / 2

-- Reader's age, used to estimate how much the critical print size grows.
local AGE = 50

-- Age dependence of the CPS (Calabrèse et al. 2016, IOVS 57(8):3836-3843;
-- 645 normally sighted people aged 8-81, MNREAD at 40 cm, CPS = smallest size
-- giving 90% of max speed). Their piecewise-linear fit, in logMAR:
--   constant 0.08 up to 23 y, rising to 0.21 at 68 y, then to 0.34 at 81 y.
-- Values between breakpoints are linearly interpolated (as in their model).
-- Only the RATIO to a young adult (0.08) is used, applied to CPS_ARCMIN: it
-- assumes the logMAR scaling carries over to x-height, which is an
-- approximation. The age effect is weak and individual variation is large.
local function cpsLogMAR(age)
    if age <= 23 then return 0.08 end
    if age <= 68 then return 0.08 + (0.21 - 0.08) * (age - 23) / (68 - 23) end
    if age <= 81 then return 0.21 + (0.34 - 0.21) * (age - 68) / (81 - 68) end
    return 0.34
end

local CPS_AGE_FACTOR = 10 ^ (cpsLogMAR(AGE) - 0.08)
local CPS_AGE_ARCMIN = CPS_ARCMIN * CPS_AGE_FACTOR   -- ≈14.4′ at 50 years

-- Angle for display: one decimal, trailing ".0" dropped (12, 14.4, 15.5)
local function fmtArc(v)
    local s = string.format("%.1f", v)
    return (s:gsub("%.0$", ""))
end

-- Angles listed in the ANGLE → SIZE table. Edit freely: for each one the popup
-- shows the x-height in mm and the font size (pt) that gives it with the
-- CURRENT font. Everything is recomputed from READING_DISTANCE_MM, so changing
-- the distance above updates the whole table. Rows are shown in this order.
local REFERENCE_ANGLES = {
    { CPS_ARCMIN,       "CPS" },
    { CPS_AGE_ARCMIN,   string.format("CPS ref. age %d (population reference, not individual)", AGE) },
    { PREFERRED_ARCMIN, "Preferred" },
    { PRINT_MAX_ARCMIN, "Print book (max)" },
    { 25,               "Larger" },
}

-- WHY THESE BANDS (evidence-based, edit here only):
-- Source: Legge & Bigelow (2011), "Does print size matter for reading? A
-- review of findings from vision science and typography", J. Vision 11(5):8.
--  * Critical print size (CPS) for normal vision is ~0.2 deg of x-height
--    (12′; individual range ~0.15-0.3 deg). Below it, reading speed drops
--    sharply.
--  * Above the CPS there is a very wide plateau of maximum reading speed,
--    from 0.2 to ~2 deg (12′-120′). Speed only declines gradually beyond it.
--  * Real printed books and newspapers cluster at 0.20-0.28 deg (12-17′,
--    mean ~14′), i.e. just above the CPS.
-- So there is no single "ideal" angle: only "below the CPS" and "fluent
-- range" (everything from the CPS up), where the choice is personal comfort
-- (contrast, lighting, e-ink panel, vision, taste). Printed books (12-17′)
-- are NOT a separate band: they are already inside the fluent range, so they
-- are only mentioned in the reference note. The previous labels (Demanding /
-- Ideal / Oversized) had no empirical basis, which is why they were replaced.
-- The upper edge of the plateau (~120′ ≈ 14 mm of x-height at 40 cm) can never
-- be reached on an e-reader, so the last band is open-ended. Anything finer
-- than this is personal (delta vs preference), never inside ANGLE_BANDS.
-- The classification and the reference note are both generated from this table.
local ANGLE_BANDS = {
    { upto = CPS_ARCMIN, label = "Below critical size" },
    { upto = math.huge,  label = "Fluent range" },
}

local function classifyAngle(angle)
    for _, b in ipairs(ANGLE_BANDS) do
        if angle < b.upto then return b.label end
    end
end

local function mmFromArcmin(arcmin, distance_mm)
    return 2 * distance_mm * math.tan(math.rad(arcmin / 60) / 2)
end

local function angleNote()
    local parts, prev = {}, nil
    for _, b in ipairs(ANGLE_BANDS) do
        local txt
        if not prev then
            txt = string.format("<%d′ (<%.2fmm) %s",
                b.upto, mmFromArcmin(b.upto, READING_DISTANCE_MM), b.label)
        elseif b.upto == math.huge then
            txt = string.format("≥%d′ (≥%.2fmm) %s",
                prev, mmFromArcmin(prev, READING_DISTANCE_MM), b.label)
        else
            txt = string.format("%d–%d′ (%.2f–%.2fmm) %s", prev, b.upto,
                mmFromArcmin(prev, READING_DISTANCE_MM),
                mmFromArcmin(b.upto, READING_DISTANCE_MM), b.label)
        end
        table.insert(parts, txt)
        prev = b.upto
    end
    local lines = {
        string.format("x-height at %dcm (Legge & Bigelow 2011)", READING_DISTANCE_MM / 10),
        string.format("Critical print size %d′ (CPS, %.2fmm): below it reading slows down",
            CPS_ARCMIN, mmFromArcmin(CPS_ARCMIN, READING_DISTANCE_MM)),
    }
    for _, part in ipairs(parts) do table.insert(lines, part) end   -- one band per line
    table.insert(lines, string.format("Printed books: %d–%d′ (mean ~%d′)",
        PRINT_MIN_ARCMIN, PRINT_MAX_ARCMIN, PRINT_MEAN_ARCMIN))
    table.insert(lines, string.format("CPS at age %d: %s′ (%.2fmm), ×%.2f vs young adults (Calabrèse et al. 2016)",
        AGE, fmtArc(CPS_AGE_ARCMIN), mmFromArcmin(CPS_AGE_ARCMIN, READING_DISTANCE_MM), CPS_AGE_FACTOR))
    table.insert(lines, string.format("Preferred (midpoint of print mean and max, %d–%d′): %g′ (%.2fmm)",
        PRINT_MEAN_ARCMIN, PRINT_MAX_ARCMIN,
        PREFERRED_ARCMIN, mmFromArcmin(PREFERRED_ARCMIN, READING_DISTANCE_MM)))
    table.insert(lines, string.format("Preferred vs CPS at age %d: %+.0f%%",
        AGE, (PREFERRED_ARCMIN / CPS_AGE_ARCMIN - 1) * 100))
    return table.concat(lines, "\n")
end

-- ── Fonts ────────────────────────────────────────────────────────────────────

local function buildFonts()
    return {
        section = Font:getFace("NotoSans-Bold.ttf",    16) or Font:getFace("tfont", 16),
        head    = Font:getFace("NotoSans-Bold.ttf",    16) or Font:getFace("tfont", 16),
        value   = Font:getFace("NotoSans-Bold.ttf",    14) or Font:getFace("tfont", 14),
        label   = Font:getFace("NotoSans-Regular.ttf", 12) or Font:getFace("x_smallinfofont", 12),
        mono    = Font:getFace("myfont3",              14) or Font:getFace("cfont", 14),
    }
end

-- ── Layout helpers ────────────────────────────────────────────────────────────

local PT_TO_MM    = 25.4 / 72   -- 0.3528
local PT_TO_DIDOT = 0.938       -- 1 pt PostScript ≈ 0.938 Didot

local function ptToPx(pt, dpi)
    return math.floor(dpi * pt / 72 + 0.5)
end

local function buildLayout(screen_w, padding_h)
    return { full_width = screen_w, padding_h = padding_h }
end

local function padded(padding_h, widget)
    return HorizontalGroup:new{
        HorizontalSpan:new{ width = padding_h },
        widget,
    }
end

local function sectionHeader(fonts, text, width)
    local tw = TextWidget:new{ text = text, face = fonts.section }
    return FrameContainer:new{
        background     = Blitbuffer.COLOR_WHITE,
        bordersize     = 0,
        padding_top    = Size.padding.small,
        padding_bottom = Size.padding.small,
        padding_left   = Size.padding.large,
        padding_right  = 0,
        LeftContainer:new{
            dimen = Geom:new{ w = width - Size.padding.large, h = tw:getSize().h },
            tw,
        },
    }
end

-- ── Table builder ─────────────────────────────────────────────────────────────
-- A row is { header = bool, cells = { {text=, kind=, align=, span=}, ... } }
--   kind:  "label" | "value" | "head" | "mono"   (maps to a font)
--   align: "left" | "center" | "right"
--   span:  number of columns the cell covers (default 1)

local function spanWidth(cols, start, span, sep_w)
    local w = 0
    for i = start, start + span - 1 do w = w + (cols[i] or 0) end
    return w + (span - 1) * sep_w
end

local function buildRow(fonts, cols, row, sep_w)
    local pad = Size.padding.small
    local built, max_h, ci = {}, 0, 1

    for _, cell in ipairs(row.cells) do
        local span = cell.span or 1
        local w    = spanWidth(cols, ci, span, sep_w)
        local text = tostring(cell.text or "")
        if text == "" then text = " " end
        local tb = TextBoxWidget:new{
            text      = text,
            face      = fonts[cell.kind or "label"],
            width     = w - 2 * pad,
            alignment = cell.align or "left",
        }
        max_h = math.max(max_h, tb:getSize().h)
        table.insert(built, { widget = tb, w = w })
        ci = ci + span
    end

    local row_h = max_h + 2 * pad
    local group = HorizontalGroup:new{ align = "center" }
    for i, b in ipairs(built) do
        if i > 1 then
            table.insert(group, LineWidget:new{
                dimen      = Geom:new{ w = sep_w, h = row_h },
                background = Blitbuffer.COLOR_GRAY,
            })
        end
        table.insert(group, LeftContainer:new{
            dimen = Geom:new{ w = b.w, h = row_h },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = pad },
                b.widget,
            },
        })
    end

    if row.header then
        return FrameContainer:new{
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            bordersize = 0, padding = 0, margin = 0,
            group,
        }
    end
    return group
end

local function buildTable(fonts, layout, col_fracs, rows)
    local border  = Size.border.thin
    local table_w = layout.full_width - 2 * layout.padding_h
    local inner_w = table_w - 2 * border
    local sep_w   = Size.line.thin
    local n       = #col_fracs
    local avail   = inner_w - (n - 1) * sep_w

    local cols, used = {}, 0
    for i, f in ipairs(col_fracs) do
        if i < n then
            cols[i] = math.floor(avail * f)
            used = used + cols[i]
        else
            cols[i] = avail - used   -- last column takes the remainder
        end
    end

    local vg = VerticalGroup:new{ align = "left" }
    for i, row in ipairs(rows) do
        if i > 1 then
            table.insert(vg, LineWidget:new{
                dimen      = Geom:new{ w = inner_w, h = Size.line.thin },
                background = Blitbuffer.COLOR_GRAY,
            })
        end
        table.insert(vg, buildRow(fonts, cols, row, sep_w))
    end

    local frame = FrameContainer:new{
        bordersize = border,
        color      = Blitbuffer.COLOR_GRAY,
        padding    = 0,
        margin     = 0,
        radius     = 0,
        vg,
    }
    local group = padded(layout.padding_h, frame)
    group.table_frame = frame   -- its dimen is filled on paint: used for taps
    return group
end

-- Key/value table: two label|value pairs per row (4 columns).
-- Items: { "Label", "Value" }            → half-width pair
--        { "Label", "Value", wide=true } → label + value spanning the row
--        { note = "text" }               → full-width mono note row
local KV_COLS = { 0.20, 0.30, 0.20, 0.30 }

local function kvRows(items)
    local rows, pending = {}, nil

    local function flush()
        if pending then
            table.insert(rows, { cells = {
                { text = pending[1], kind = "label" },
                { text = pending[2], kind = "value" },
                { text = "",         kind = "label" },
                { text = "",         kind = "value" },
            } })
            pending = nil
        end
    end

    for _, it in ipairs(items) do
        if it.note then
            flush()
            table.insert(rows, { cells = { { text = it.note, kind = "mono", span = 4 } } })
        elseif it.wide then
            flush()
            table.insert(rows, { cells = {
                { text = it[1], kind = "label" },
                { text = it[2], kind = "value", span = 3 },
            } })
        elseif pending then
            table.insert(rows, { cells = {
                { text = pending[1], kind = "label" },
                { text = pending[2], kind = "value" },
                { text = it[1],      kind = "label" },
                { text = it[2],      kind = "value" },
            } })
            pending = nil
        else
            pending = it
        end
    end
    flush()
    return rows
end

local function addSection(sections, fonts, layout, title, tbl)
    local header = sectionHeader(fonts, title, layout.full_width)
    table.insert(sections, header)
    table.insert(sections, tbl)
    table.insert(sections, VerticalSpan:new{ height = Size.padding.large })
    return header, tbl
end

local function classifyLeading(lf, x_height, ascender, descender)
    if not x_height or x_height == 0 then
        return "invalid", "Invalid"
    end

    local safe_min = (ascender + descender) / x_height

    if lf < safe_min then
        return "collision", "Collision"
    elseif lf < safe_min + 0.15 then
        return "compact", "Compact"
    elseif lf < safe_min + 0.4 then
        return "balanced", "Balanced"
    elseif lf < safe_min + 0.6 then
        return "airy", "Airy"
    else
        return "very_airy", "Very airy"
    end
end

-- ── Data gathering ────────────────────────────────────────────────────────────

local function arcminutes_from_mm(size_mm, distance_mm)
    local angle_rad    = 2 * math.atan(size_mm / (2 * distance_mm))
    return math.deg(angle_rad) * 60
end

-- true  = the C++ getHeight already multiplies EVERY line-height branch
--         (including "Font") by KOReader's line spacing factor (my rewrite).
-- false = original C++, which only scaled "em"/"unesp": then "Font" must be
--         scaled here.
local CPP_SCALES_LINE_HEIGHT = true

-- Tweak detection by menu text (breaks if KOReader is translated or the menu
-- text changes). Kept in one table so it is easy to swap for ids later.
local TWEAK_PATTERNS = {
    line_height = "Spacing between lines %(1.2em%%)",
    indent      = "Indentation on first paragraph line",
    margin      = "Ignore publisher page margins",
    font_size   = "Ignore publisher font sizes",
    align       = { "Left align most text", "Justify most text" },
}

local function hasTweak(tweaks, pattern)
    if type(pattern) == "table" then
        for _, p in ipairs(pattern) do
            if tweaks:find(p) then return true end
        end
        return false
    end
    return tweaks:find(pattern) ~= nil
end

-- Indices of the 20 values returned by doc:getHeight(xpointer)
local IDX = {
    tag = 1, body_tag = 2,
    line_height = 3, body_line_height = 5,   -- value at i, unit at i+1
    indent = 7,      body_indent = 9,
    margin = 11,     body_margin = 13,
    align = 15,      body_align = 16,
    font_size = 17,  body_font_size = 19,
}

-- Plain text → collapsed whitespace, NBSP as normal spaces, truncated to
-- `max_chars` characters (UTF-8 safe).
local function makeSnippet(text, max_chars)
    if not text or text == "" then return "" end
    text = text:gsub("\194\160", " ")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    local chars = util.splitToChars(text)
    if #chars <= max_chars then return text end
    return table.concat(chars, "", 1, max_chars) .. "…"
end

-- xpointer of a position -> xpointer of its enclosing <p> element (or nil)
local function paragraphStart(pos)
    local last_end, init = nil, 1
    while true do
        local s, e = pos:find("/p%f[%W]%[?%d*%]?", init)
        if not s then break end
        last_end, init = e, e + 1
    end
    return last_end and pos:sub(1, last_end) or nil
end

-- Text from the start of the paragraph containing `pos` to the bottom of the
-- page. Falls back to the text from line `y`, then to `fallback`.
local function textFromLine(doc, y, fallback, pos)
    local ok, res = pcall(function()
        return doc._document:getTextFromPositions(0, y, Screen:getWidth(),
                                                  Screen:getHeight(), false, false)
    end)
    if not ok then
        logger.warn("TextInfoPopup getTextFromPositions error:", res)
        return fallback
    end

    local p0 = pos and paragraphStart(pos)
    if p0 and res and res.pos1 then
        local ok2, txt = pcall(function()
            return doc._document:getTextFromXPointers(p0, res.pos1)
        end)
        if ok2 and type(txt) == "string" and txt ~= "" then return txt end
        if not ok2 then
            logger.warn("TextInfoPopup getTextFromXPointers error:", txt)
        end
    end

    if res and res.text and res.text ~= "" then return res.text end
    return fallback
end

-- Looks for a representative paragraph in the middle of the page instead of
-- using the last position (which may be a title or a footnote).
-- Returns the table of 20 values (preferring a <p>) and the text that starts
-- at the sampled line.
local function sampleCSS(doc)
    local W, H = Screen:getWidth(), Screen:getHeight()
    local fallback, fallback_text
    for _, frac in ipairs({ 0.5, 0.4, 0.6, 0.3, 0.7 }) do
        local y = math.floor(H * frac)
        local res = doc._document:getTextFromPositions(0, y, W, y + 10, false, false)
        if res then
            for _, pos in ipairs({ res.pos0, res.pos1 }) do
                if pos and pos ~= ".0" then
                    local ok, r = pcall(function() return { doc:getHeight(pos) } end)
                    if ok and r and r[IDX.tag] and r[IDX.tag] ~= "" then
                        if r[IDX.tag] == "p" then
                            return r, textFromLine(doc, y, res.text, pos)
                        end
                        if not fallback then
                            fallback = r
                            fallback_text = textFromLine(doc, y, res.text, pos)
                        end
                    end
                end
            end
        end
    end
    return fallback, fallback_text
end

-- Formats (value, unit) for display. Absent values come as -2 with an empty
-- or "unesp" unit; a real "-2em" hanging indent is kept.
local function fmtLength(value, unit, tweaked)
    if type(value) ~= "number" then
        return (value == nil or value == "") and "—" or tostring(value)
    end
    unit = unit or ""
    if value == -2 and (unit == "" or unit == "unesp") then return "—" end
    return (Math.round(value * 100) / 100) .. unit .. (tweaked and "*" or "")
end

local function gatherData(ui)
    local data = {}
    if not ui or not ui.document then return data end

    local doc          = ui.document
    local configurable = doc.configurable
    local display_dpi  = Device:getDeviceScreenDPI() or Screen:getDPI()

    -- Font
    data.font_face = doc._document:getFontFace() or "?"
    data.font_face_clean = data.font_face:gsub("%s+", "") .. "-Regular"
    local pt = configurable.font_size
    local px = ptToPx(pt, display_dpi)

    data.font_size_pt    = pt
    data.font_size_mm    = string.format("%.2f", pt * PT_TO_MM)
    data.font_size_px    = px
    data.font_size_didot = string.format("%.2fp", pt * PT_TO_DIDOT)
    data.font_weight     = 400 + configurable.font_base_weight * 100
    data.display_dpi     = display_dpi

    -- x-height
    local face_base = Font:getFace(data.font_face_clean, px, 0, true)
    if face_base then
        local xh = face_base.ftsize:getXHeight()
        -- If xh < 1 it is a ratio, otherwise it is already in px.
        -- Kept fractional: no intermediate rounding.
        local xh_px = (xh < 1) and (xh * px) or xh
        -- leading factor (line spacing relative to x-height)
        if xh_px > 0 then
            local line_spacing_factor = (configurable.line_spacing or 100) / 100
            local ok, xh2, ascender, descender = pcall(function()
                return face_base.ftsize:getAscDesc()
            end)

            if ok and xh2 and ascender and descender then
                data.leading_factor = (1.2 * px * line_spacing_factor) / xh_px
                data.leading_key, data.leading_text =
                    classifyLeading(data.leading_factor, xh2, ascender, descender)
            else
                logger.warn("TextInfoPopup getAscDesc error:", xh2)
            end
        end

        local xh_mm = xh_px * 25.4 / display_dpi            -- unrounded
        local angle = arcminutes_from_mm(xh_mm, READING_DISTANCE_MM)

        -- x-height scales linearly with font size: mm of x-height per pt of
        -- font for the current face (used by the ANGLE → SIZE table)
        if pt and pt > 0 then data.xh_mm_per_pt = xh_mm / pt end

        data.x_height_px     = string.format("%.1fpx", xh_px)
        data.x_height_mm     = string.format("%.2fmm", xh_mm)
        -- Evidence-based part: angle + band (Legge & Bigelow)
        data.x_height_arcmin = string.format("%.1f′  [%s]", angle, classifyAngle(angle))
        -- Continuous multiple of the critical print size (data, not a verdict)
        local cps_ratio = angle / CPS_ARCMIN
        local cps_pct   = (cps_ratio - 1) * 100
        data.x_height_cps    = string.format("%.2f× (%.0f%% %s than CPS)",
            cps_ratio, math.abs(cps_pct), cps_pct >= 0 and "bigger" or "smaller")
        -- Personal part: relative difference against the preference
        -- (not a scientific norm)
        local pct = (angle / PREFERRED_ARCMIN - 1) * 100
        data.x_height_vs_pref = string.format("%+.0f%% vs %g′ preferred", pct, PREFERRED_ARCMIN)
        -- x-height scales linearly with font size, so the size that would
        -- give exactly PREFERRED_ARCMIN is a simple ratio.
        if angle > 0 then
            local target_pt = pt * PREFERRED_ARCMIN / angle
            data.x_height_target = string.format("%.1f pt (%+.1f)", target_pt, target_pt - pt)
        else
            data.x_height_target = "N/A"
        end
    else
        data.x_height_px, data.x_height_mm, data.x_height_arcmin = "N/A", "N/A", "N/A"
        data.x_height_cps    = "N/A"
        data.x_height_vs_pref = "N/A"
        data.x_height_target = "N/A"
    end

    -- Readability table (from pagetextinfo if available)
    if ui.pagetextinfo and ui.pagetextinfo.readability_table then
        data.readability = ui.pagetextinfo.readability_table[data.font_face_clean] or "N/A"
    else
        data.readability = "N/A"
    end

    -- Device
    data.device_model = Device.model
    if Device:isAndroid() then
        local android = require("android")
        data.device_model = android.prop.model
    end
    data.screen_res = Screen:getWidth() .. "×" .. Screen:getHeight()

    -- Frontlight
    local powerd = Device:getPowerDevice()
    if powerd:isFrontlightOn() then
        local warmth = powerd:frontlightWarmth()
        data.frontlight = string.format("L: %d%%", powerd:frontlightIntensity())
        if warmth then
            data.frontlight = data.frontlight .. string.format("  W: %d%%", warmth)
        end
    else
        data.frontlight = "Off"
    end

    -- CSS properties of a representative paragraph (+ the text it starts with)
    local r, sample_text = sampleCSS(doc)
    if SNIPPET_CHARS > 0 then
        data.snippet = makeSnippet(sample_text, SNIPPET_CHARS)
    end
    if r then
        local tweaks = ui.tweaks or ""
        local tw = {
            line_height = hasTweak(tweaks, TWEAK_PATTERNS.line_height),
            indent      = hasTweak(tweaks, TWEAK_PATTERNS.indent),
            margin      = hasTweak(tweaks, TWEAK_PATTERNS.margin),
            font_size   = hasTweak(tweaks, TWEAK_PATTERNS.font_size),
            align       = hasTweak(tweaks, TWEAK_PATTERNS.align),
        }

        local function lengths(i_p, i_b, tweaked)
            return fmtLength(r[i_p],     r[i_p + 1], tweaked),
                   fmtLength(r[i_b],     r[i_b + 1], tweaked)
        end

        -- line-height: only scale "Font" here if the C++ does not do it
        local function lineHeight(i)
            local v, u = r[i], r[i + 1]
            if not CPP_SCALES_LINE_HEIGHT and u == "Font" and type(v) == "number" then
                v = v * configurable.line_spacing / 100
            end
            return fmtLength(v, u, tw.line_height)
        end

        local function align(a)
            if a == nil or a == "" then return "—" end
            return a .. (tw.align and "*" or "")
        end

        data.css_tag = { p = r[IDX.tag], body = r[IDX.body_tag] }
        data.css_lineheight = { p = lineHeight(IDX.line_height), body = lineHeight(IDX.body_line_height) }
        local ip, ib
        ip, ib = lengths(IDX.indent, IDX.body_indent, tw.indent)
        data.css_indent = { p = ip, body = ib }
        ip, ib = lengths(IDX.margin, IDX.body_margin, tw.margin)
        data.css_margin = { p = ip, body = ib }
        ip, ib = lengths(IDX.font_size, IDX.body_font_size, tw.font_size)
        data.css_fontsize = { p = ip, body = ib }
        data.css_align = { p = align(r[IDX.align]), body = align(r[IDX.body_align]) }
    end

    -- Tweaks
    data.tweaks_count = ui.tweaks_no or 0
    data.tweaks_text  = ui.tweaks   or ""

    -- WPM from pagetextinfo if available
    if ui.pagetextinfo and ui.view and ui.view.footer then
        local ok, sessions, avg_wpm,
              avg7, avg30, avg60, avg90, avg180 = pcall(function()
            return ui.pagetextinfo.getSessionsInfo
                and ui.pagetextinfo:getSessionsInfo(ui.view.footer)
                or nil
        end)
        if ok and sessions then
            data.avg_wpm   = math.floor(avg_wpm)
            data.avg_wph   = math.floor(avg_wpm * 60)
            data.sessions  = sessions
            data.avg7      = avg7   and math.floor(avg7)   or nil
            data.avg30     = avg30  and math.floor(avg30)  or nil
            data.avg60     = avg60  and math.floor(avg60)  or nil
            data.avg90     = avg90  and math.floor(avg90)  or nil
            data.avg180    = avg180 and math.floor(avg180) or nil
        end
    end

    return data
end

-- ── Build sections ────────────────────────────────────────────────────────────

local function buildSections(data, fonts, layout)
    local sections = VerticalGroup:new{ align = "left" }
    local L = layout

    local function kvTable(items)
        return buildTable(fonts, L, KV_COLS, kvRows(items))
    end
    local function wpm(v) return v and (v .. " wpm") or "–" end

    -- TEXT: start of the text the CSS was sampled from
    if SNIPPET_CHARS > 0 then
        local snippet = data.snippet
        if not snippet or snippet == "" then snippet = "(no text)" end
        addSection(sections, fonts, L, "TEXT  (sampled paragraph)",
            buildTable(fonts, L, { 1 },
                { { cells = { { text = snippet, kind = "mono" } } } }))
    end

    -- FONT
    addSection(sections, fonts, L, "FONT", kvTable{
        { "Face",   (data.font_face or "?") .. " (" .. (data.readability or "N/A") .. ")", wide = true },
        { "Size",   string.format("%.1f pt", data.font_size_pt or 0) },
        { "Didot",  data.font_size_didot or "?" },
        { "Pixels", tostring(data.font_size_px or "?") .. " px" },
        { "Metric", tostring(data.font_size_mm or "?") .. " mm" },
        { "Weight", tostring(data.font_weight or "?") },
    })

    -- X-HEIGHT
    --   Angle / vs CPS : evidence-based (Legge & Bigelow)
    --   vs Pref / For pref : personal preference, not a norm
    --   Tap on this section opens the REFERENCE popup (angle → size table
    --   and the reference note), kept out of the main popup to save space.
    local xh_header, xh_tbl = addSection(sections, fonts, L, "X-HEIGHT  (tap for reference)", kvTable{
        { "Pixels",  data.x_height_px or "?" },
        { "Metric",  data.x_height_mm or "?" },
        { string.format("Angle @%dcm", READING_DISTANCE_MM / 10),
          data.x_height_arcmin or "?", wide = true },
        { "vs CPS",  data.x_height_cps or "?" },
        { "Leading", data.leading_text and
            string.format("%.2f× [%s]", data.leading_factor, data.leading_text) or "N/A" },
        { "vs Pref", data.x_height_vs_pref or "?", wide = true },
        { "For pref", data.x_height_target or "?", wide = true },
    })

    -- DISPLAY
    addSection(sections, fonts, L, "DISPLAY", kvTable{
        { "Model",      data.device_model or "?" },
        { "Density",    tostring(data.display_dpi or "?") .. " ppi" },
        { "Resolution", data.screen_res or "?" },
        { "Frontlight", data.frontlight or "Off" },
    })

    -- CSS: property | p | body
    if data.css_tag then
        local function r(label, t)
            return { cells = {
                { text = label, kind = "label" },
                { text = t.p,   kind = "value" },
                { text = t.body, kind = "value" },
            } }
        end
        local rows = {
            { header = true, cells = {
                { text = "Property",                kind = "head" },
                { text = "<" .. (data.css_tag.p    or "p")    .. ">", kind = "head" },
                { text = "<" .. (data.css_tag.body or "body") .. ">", kind = "head" },
            } },
            r("line-height", data.css_lineheight),
            r("text-indent", data.css_indent),
            r("margin",      data.css_margin),
            r("text-align",  data.css_align),
        }
        addSection(sections, fonts, L, "CSS",
            buildTable(fonts, L, { 0.28, 0.36, 0.36 }, rows))
    end

    -- TWEAKS: one row per line
    do
        local rows = {}
        local text = data.tweaks_text or ""
        if text == "" then
            table.insert(rows, { cells = { { text = "None", kind = "mono" } } })
        else
            for line in text:gmatch("[^\n]+") do
                table.insert(rows, { cells = { { text = line, kind = "mono" } } })
            end
        end
        addSection(sections, fonts, L,
            "TWEAKS  (" .. tostring(data.tweaks_count) .. " applied)",
            buildTable(fonts, L, { 1 }, rows))
    end

    -- READING SPEED
    if data.avg_wpm then
        addSection(sections, fonts, L, "READING SPEED", kvTable{
            { "Average",  data.avg_wpm .. " wpm" },
            { "Per hour", data.avg_wph .. " wph" },
            { "Sessions", tostring(data.sessions or 0) },
            { "7 days",   wpm(data.avg7) },
            { "30 days",  wpm(data.avg30) },
            { "60 days",  wpm(data.avg60) },
            { "90 days",  wpm(data.avg90) },
            { "180 days", wpm(data.avg180) },
        })
    end

    -- Bottom rule
    table.insert(sections, LineWidget:new{
        dimen      = Geom:new{ w = L.full_width, h = Size.line.thick },
        background = Blitbuffer.COLOR_BLACK,
    })

    -- second value: widgets whose tap opens the reference popup
    return sections, { xh_header, xh_tbl.table_frame }
end

-- Reference popup content: ANGLE → SIZE table + reference note.
local function buildReferenceSections(data, fonts, layout)
    local sections = VerticalGroup:new{ align = "left" }
    local L = layout

    -- ANGLE → SIZE: generic table, depends only on READING_DISTANCE_MM and
    -- (for the pt column) on the current font's x-height proportion
    do
        local rows = {
            { header = true, cells = {
                { text = "Angle",  kind = "head" },
                { text = "Name",   kind = "head" },
                { text = "x-height", kind = "head" },
                { text = "Font",   kind = "head" },
            } },
        }
        local refs = {}
        for _, ra in ipairs(REFERENCE_ANGLES) do table.insert(refs, ra) end
        table.sort(refs, function(a, b) return a[1] < b[1] end)   -- by angle
        for _, ra in ipairs(refs) do
            local mm = mmFromArcmin(ra[1], READING_DISTANCE_MM)
            local font_txt = data.xh_mm_per_pt
                and string.format("%.1f pt", mm / data.xh_mm_per_pt) or "N/A"
            table.insert(rows, { cells = {
                { text = fmtArc(ra[1]) .. "′", kind = "value" },
                { text = ra[2],                        kind = "label" },
                { text = string.format("%.2f mm", mm), kind = "value" },
                { text = font_txt,                     kind = "value" },
            } })
        end
        -- Note: why going above the preferred range has no measurable benefit.
        -- (Reasoned from the flat plateau in Legge & Bigelow 2011; personal
        -- guidance, not a measured result.)
        table.insert(rows, { cells = { { kind = "mono", span = 4,
            text = "Above ~22–25′ you lose text per page without any measurable gain in reading speed, since the plateau is flat. If comfort is the goal there is room to go larger, but pages turn more often." } } })
        addSection(sections, fonts, L,
            string.format("ANGLE → SIZE  (@%dcm)", READING_DISTANCE_MM / 10),
            buildTable(fonts, L, { 0.16, 0.38, 0.23, 0.23 }, rows))
    end

    -- Reference note: sources, CPS definition, bands, print books, preference
    addSection(sections, fonts, L, "REFERENCE",
        buildTable(fonts, L, { 1 },
            { { cells = { { text = angleNote(), kind = "mono" } } } }))

    -- Bottom rule
    table.insert(sections, LineWidget:new{
        dimen      = Geom:new{ w = L.full_width, h = Size.line.thick },
        background = Blitbuffer.COLOR_BLACK,
    })

    return sections
end

-- ── Popup widget ──────────────────────────────────────────────────────────────

-- Base popup: full-width, closes on tap / swipe / hold / Back. Subclasses
-- implement :buildContent(fonts, layout) returning the sections widget.
local BasePopup = InputContainer:extend{
    modal = true,
}

function BasePopup:init()
    local fonts    = buildFonts()
    local screen_w = Screen:getWidth()
    local layout   = buildLayout(screen_w, Size.padding.large)
    local sections = self:buildContent(fonts, layout)

    self.popup_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        radius     = 0,
        padding    = 0,
        width      = screen_w,
        sections,
    }

    self[1] = VerticalGroup:new{ self.popup_frame }
    self.dimen = Geom:new{ w = screen_w, h = Screen:getHeight() }

    if Device:isTouchDevice() then
        self.ges_events.TapClose   = { GestureRange:new{ ges = "tap",   range = self.dimen } }
        self.ges_events.SwipeClose = { GestureRange:new{ ges = "swipe", range = self.dimen } }
        self.ges_events.HoldClose  = { GestureRange:new{ ges = "hold",  range = self.dimen } }
    end

    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
end

function BasePopup:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.popup_frame.dimen
    end)
    return true
end

function BasePopup:onTapClose()   UIManager:close(self); return true end
function BasePopup:onSwipeClose() UIManager:close(self); return true end
function BasePopup:onHoldClose()  UIManager:close(self); return true end
function BasePopup:onClose()      UIManager:close(self); return true end

function BasePopup:onCloseWidget()
    UIManager:setDirty(nil, "ui")
end

-- Secondary popup: angle → size table and reference note.
local ReferencePopup = BasePopup:extend{
    data = nil,
}

function ReferencePopup:buildContent(fonts, layout)
    return buildReferenceSections(self.data or {}, fonts, layout)
end

-- Main popup.
local TextInfoPopup = BasePopup:extend{
    ui = nil,
}

function TextInfoPopup:buildContent(fonts, layout)
    self.data = gatherData(self.ui)
    local sections, targets = buildSections(self.data, fonts, layout)
    self.ref_targets = targets
    return sections
end

-- A tap on the X-HEIGHT section opens the reference popup; a tap anywhere
-- else closes this one.
function TextInfoPopup:onTapClose(arg, ges)
    if ges and ges.pos then
        for _, w in ipairs(self.ref_targets or {}) do
            if w.dimen and ges.pos:intersectWith(w.dimen) then
                UIManager:show(ReferencePopup:new{ data = self.data })
                return true
            end
        end
    end
    UIManager:close(self)
    return true
end

-- ── Registration ──────────────────────────────────────────────────────────────

Dispatcher:registerAction("get_text_page", {
    category  = "none",
    event     = "GetTextPage",
    title     = "Get text page",
    general   = true,
    separator = true,
})

local ReaderUI = require("apps/reader/readerui")
local _orig    = ReaderUI.registerKeyEvents

ReaderUI.registerKeyEvents = function(self)
    if _orig then _orig(self) end
    local is_pdf = self.document and util.getFileNameSuffix(self.document.file) == "pdf"
    if is_pdf then return end
    self.onGetTextPage = function(this)
        UIManager:show(TextInfoPopup:new{ ui = this })
        return true
    end
end
