--[[
Typography Info Popup (table layout)
Replaces the plain InfoMessage from onGetTextPage with a structured popup.
Every section is rendered as a bordered table:

  - TEXT        start of the text the CSS is sampled from (truncated)
  - FONT        face, size, didot, px, mm, weight
  - X-HEIGHT    px, mm, visual angle
  - DISPLAY     device, ppi, resolution, frontlight
  - CSS         3-column table: property | <p tag> | <body tag>
  - TWEAKS      one row per applied tweak
  - READING     avg wpm, wph, sessions, recent averages
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
local util            = require("util")
local Screen          = Device.screen

-- Max characters of page text shown in the TEXT section (0 = hide)
local SNIPPET_CHARS = 150

-- ── Fonts ────────────────────────────────────────────────────────────────────

local function buildFonts()
    return {
        section = Font:getFace("NotoSans-Bold.ttf",    20) or Font:getFace("tfont", 20),
        head    = Font:getFace("NotoSans-Bold.ttf",    16) or Font:getFace("tfont", 16),
        value   = Font:getFace("NotoSans-Bold.ttf",    18) or Font:getFace("tfont", 18),
        label   = Font:getFace("NotoSans-Regular.ttf", 16) or Font:getFace("x_smallinfofont", 16),
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

    return padded(layout.padding_h, FrameContainer:new{
        bordersize = border,
        color      = Blitbuffer.COLOR_GRAY,
        padding    = 0,
        margin     = 0,
        radius     = 0,
        vg,
    })
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
    table.insert(sections, sectionHeader(fonts, title, layout.full_width))
    table.insert(sections, tbl)
    table.insert(sections, VerticalSpan:new{ height = Size.padding.large })
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
        -- If xh < 1 it is a ratio, otherwise it is already in px
        local xh_px = (xh < 1) and Math.round(xh * px) or Math.round(xh)
        local xh_mm = Math.round(xh_px * 25.4 / display_dpi * 100) / 100
        data.x_height_px     = xh_px .. "px"
        data.x_height_mm     = xh_mm .. "mm"
        data.x_height_arcmin = string.format("%.1f′ @40cm", arcminutes_from_mm(xh_mm, 400))
    else
        data.x_height_px, data.x_height_mm, data.x_height_arcmin = "N/A", "N/A", "N/A"
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
        { "Face",   (data.font_face or "?") .. "  (" .. (data.readability or "N/A") .. ")", wide = true },
        { "Size",   string.format("%.1f pt", data.font_size_pt or 0) },
        { "Didot",  data.font_size_didot or "?" },
        { "Pixels", tostring(data.font_size_px or "?") .. " px" },
        { "Metric", tostring(data.font_size_mm or "?") .. " mm" },
        { "Weight", tostring(data.font_weight or "?") },
    })

    -- X-HEIGHT
    addSection(sections, fonts, L, "X-HEIGHT", kvTable{
        { "Pixels", data.x_height_px or "?" },
        { "Metric", data.x_height_mm or "?" },
        { "Angle",  data.x_height_arcmin or "?", wide = true },
        { note = "~20′ ideal · 17–19′ comfortable · <15′ demanding · >25′ oversized" },
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

    return sections
end

-- ── Popup widget ──────────────────────────────────────────────────────────────

local TextInfoPopup = InputContainer:extend{
    modal = true,
    ui    = nil,
}

function TextInfoPopup:init()
    local fonts    = buildFonts()
    local screen_w = Screen:getWidth()
    local layout   = buildLayout(screen_w, Size.padding.large)
    local data     = gatherData(self.ui)
    local sections = buildSections(data, fonts, layout)

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

function TextInfoPopup:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.popup_frame.dimen
    end)
    return true
end

function TextInfoPopup:onTapClose()   UIManager:close(self); return true end
function TextInfoPopup:onSwipeClose() UIManager:close(self); return true end
function TextInfoPopup:onHoldClose()  UIManager:close(self); return true end
function TextInfoPopup:onClose()      UIManager:close(self); return true end

function TextInfoPopup:onCloseWidget()
    UIManager:setDirty(nil, "ui")
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
