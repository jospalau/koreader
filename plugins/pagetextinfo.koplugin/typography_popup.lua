--[[
Typography Info Popup
Replaces the plain InfoMessage from onGetTextPage with a structured
sectioned popup: font metrics, x-height, display info, CSS properties,
applied tweaks, and reading speed history.

Sections:
  - FONT        face, size, weight, readability
  - DISPLAY     device, resolution, DPI, frontlight
  - CSS         tag, line-height, indent, margin, alignment (two columns: p vs body)
  - TWEAKS      count + list of applied tweaks
  - WPM         avg wpm, sessions, recent averages
]]--

local Blitbuffer   = require("ffi/blitbuffer")
local Device       = require("device")
local Dispatcher   = require("dispatcher")
local Font         = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom         = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local Math         = require("optmath")
local Size         = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget   = require("ui/widget/textwidget")
local UIManager    = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan  = require("ui/widget/verticalspan")
local Screen       = Device.screen

-- ── Fonts ────────────────────────────────────────────────────────────────────

local function buildFonts()
    return {
        section = Font:getFace("NotoSans-Bold.ttf",    20) or Font:getFace("tfont", 20),
        value   = Font:getFace("NotoSans-Bold.ttf",    26) or Font:getFace("tfont", 26),
        label   = Font:getFace("NotoSans-Regular.ttf", 16) or Font:getFace("x_smallinfofont", 16),
        mono    = Font:getFace("myfont3",              14) or Font:getFace("cfont", 14),
    }
end

-- ── Layout helpers ────────────────────────────────────────────────────────────

local function buildLayout(screen_w, padding_h, column_gap)
    local sep_w   = 2 * column_gap + Size.line.medium
    local col_w   = math.floor((screen_w - 2 * padding_h - sep_w) / 2)
    return {
        full_width     = screen_w,
        padding_h      = padding_h,
        column_gap     = column_gap,
        separator_width = sep_w,
        col_width      = col_w,
    }
end

local function padded(padding_h, widget)
    return HorizontalGroup:new{
        HorizontalSpan:new{ width = padding_h },
        widget,
    }
end

local function fixedCol(widget, width, height)
    height = height or widget:getSize().h
    return LeftContainer:new{
        dimen  = Geom:new{ w = width, h = height },
        widget,
    }
end

local function buildSep(column_gap, height)
    local vp = Size.padding.default
    return HorizontalGroup:new{
        HorizontalSpan:new{ width = column_gap },
        VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ height = vp },
            LineWidget:new{
                dimen      = Geom:new{ w = Size.line.medium, h = height - 2 * vp },
                background = Blitbuffer.COLOR_GRAY,
            },
            VerticalSpan:new{ height = vp },
        },
        HorizontalSpan:new{ width = column_gap },
    }
end

local function hline(layout, thick)
    return padded(layout.padding_h, LineWidget:new{
        dimen      = Geom:new{ w = layout.full_width - 2 * layout.padding_h,
                               h = thick and Size.line.thick or Size.line.thin },
        background = Blitbuffer.COLOR_GRAY,
    })
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

-- A value+label pair in a single column.
local function valueLine(fonts, col_width, value_str, label_str)
    if not value_str or value_str == "" then
        return TextBoxWidget:new{
            text      = label_str or "",
            face      = fonts.label,
            width     = col_width,
            alignment = "left",
        }
    end
    local vw        = TextWidget:new{ text = value_str, face = fonts.value }
    local vw_width  = vw:getSize().w
    local lbl_width = col_width - vw_width - Size.padding.large
    if lbl_width <= 0 then
        return VerticalGroup:new{
            align = "left",
            vw,
            TextBoxWidget:new{ text = label_str or "", face = fonts.label,
                               width = col_width, alignment = "left" },
        }
    end
    return HorizontalGroup:new{
        align = "center",
        vw,
        HorizontalSpan:new{ width = Size.padding.large },
        TextBoxWidget:new{ text = label_str or "", face = fonts.label,
                           width = lbl_width, alignment = "left" },
    }
end

-- Full-width mono text line (for tweaks list, etc.)
local function monoLine(fonts, layout, text)
    return padded(layout.padding_h, TextBoxWidget:new{
        text      = text,
        face      = fonts.mono,
        width     = layout.full_width - 2 * layout.padding_h,
        alignment = "left",
    })
end

local function twoColRow(fonts, layout, left_val, left_lbl, right_val, right_lbl)
    local lw = valueLine(fonts, layout.col_width, left_val,  left_lbl)
    local rw = valueLine(fonts, layout.col_width, right_val, right_lbl)
    local lh = lw:getSize().h
    local rh = rw:getSize().h
    local h  = math.max(lh, rh)
    return HorizontalGroup:new{
        align = "center",
        fixedCol(lw, layout.col_width, h),
        buildSep(layout.column_gap, h),
        fixedCol(rw, layout.col_width, h),
    }
end

local function addSection(sections, header, rows, layout)
    table.insert(sections, header)
    table.insert(sections, VerticalSpan:new{ height = Size.padding.default })
    table.insert(sections, hline(layout, false))
    for _, row in ipairs(rows) do
        table.insert(sections, row)
    end
    table.insert(sections, VerticalSpan:new{ height = Size.padding.large })
end

-- ── Data gathering ────────────────────────────────────────────────────────────

local function arcminutes_from_mm(size_mm, distance_mm)
    local angle_rad  = 2 * math.atan(size_mm / (2 * distance_mm))
    local angle_arcmin = math.deg(angle_rad) * 60
    return angle_arcmin
end

local function gatherData(ui)
    local data = {}
    if not ui or not ui.document then return data end

    local doc        = ui.document
    local configurable = doc.configurable
    local display_dpi  = Device:getDeviceScreenDPI() or Screen:getDPI()

    -- Font
    data.font_face = doc._document:getFontFace()
    data.font_face_clean = data.font_face:gsub("%s+", "") .. "-Regular"
    data.font_size_pt  = configurable.font_size
    data.font_size_mm  = configurable.font_size * 0.35
    data.font_size_px  = math.floor((display_dpi * configurable.font_size) / 72)
    data.font_weight   = 400 + configurable.font_base_weight * 100
    data.display_dpi   = display_dpi

    -- x-height
    local face_base = Font:getFace(data.font_face_clean, data.font_size_px, 0, false)
    if face_base then
        local xh_px = Math.round(face_base.ftsize:getXHeight() * data.font_size_px)
        data.x_height_px  = xh_px .. "px"
        local xh_mm = Math.round((xh_px * (25.4 / display_dpi)) * 100) / 100
        data.x_height_mm  = xh_mm .. "mm"
        data.x_height_arcmin = string.format("%.1f′ @40cm",
            arcminutes_from_mm(xh_mm, 400))
    else
        data.x_height_px     = "N/A"
        data.x_height_mm     = "N/A"
        data.x_height_arcmin = "N/A"
    end

    -- Readability table (from pagetextinfo if available)
    if ui.pagetextinfo and ui.pagetextinfo.readability_table then
        data.readability = ui.pagetextinfo.readability_table[data.font_face_clean] or "N/A"
    else
        data.readability = "N/A"
    end

    -- Didot size
    data.font_size_didot = string.format("%.2fp", configurable.font_size * 0.94)

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

    -- CSS properties from page
    local res = doc._document:getTextFromPositions(
        0, 0, Screen:getWidth(), Screen:getHeight(), false, false)
    if res and res.pos1 ~= ".0" then
        local name, name2, height, unitheight, height2, unitheight2,
              indent, unitindent, indent2, unitindent2,
              margin, unitmargin, margin2, unitmargin2,
              alignment, alignment2, fontsize, unitfontsize, fontsize2, unitfontsize2

        name, name2, height, unitheight, height2, unitheight2,
        indent, unitindent, indent2, unitindent2,
        margin, unitmargin, margin2, unitmargin2,
        alignment, alignment2, fontsize, unitfontsize, fontsize2, unitfontsize2
            = doc:getHeight(res.pos1)

        if name == "" and res.pos0 ~= ".0" then
            name, name2, height, unitheight, height2, unitheight2,
            indent, unitindent, indent2, unitindent2,
            margin, unitmargin, margin2, unitmargin2,
            alignment, alignment2, fontsize, unitfontsize, fontsize2, unitfontsize2
                = doc:getHeight(res.pos0)
        end

        if unitheight == "Font" then
            height  = height  * configurable.line_spacing / 100
            height2 = height2 * configurable.line_spacing / 100
        end

        local tweaks = ui.tweaks or ""
        local function tweaked(pattern, unit, unit2)
            if tweaks:find(pattern) then
                return unit .. "*", unit2 .. "*"
            end
            return unit, unit2
        end

        unitheight,  unitheight2  = tweaked("Spacing between lines %(1.2em%%)", unitheight,  unitheight2)
        unitindent,  unitindent2  = tweaked("Indentation on first paragraph line", unitindent, unitindent2)
        unitmargin,  unitmargin2  = tweaked("Ignore publisher page margins", unitmargin, unitmargin2)
        if tweaks:find("Left align most text") or tweaks:find("Justify most text") then
            alignment = alignment .. "*"; alignment2 = alignment2 .. "*"
        end
        unitfontsize, unitfontsize2 = tweaked("Ignore publisher font sizes", unitfontsize, unitfontsize2)

        if name ~= "" then
            data.css_tag        = { p = name,  body = name2 }
            data.css_lineheight = {
                p    = Math.round(height  * 100) / 100 .. unitheight,
                body = Math.round(height2 * 100) / 100 .. unitheight2,
            }
            data.css_indent = {
                p    = Math.round(indent  * 100) / 100 .. unitindent,
                body = Math.round(indent2 * 100) / 100 .. unitindent2,
            }
            data.css_margin = {
                p    = Math.round(margin  * 100) / 100 .. unitmargin,
                body = Math.round(margin2 * 100) / 100 .. unitmargin2,
            }
            data.css_align = { p = alignment, body = alignment2 }
        end
    end

    -- Tweaks
    data.tweaks_count = ui.tweaks_no or 0
    data.tweaks_text  = ui.tweaks   or ""

    -- WPM from pagetextinfo if available
    if ui.pagetextinfo and ui.view and ui.view.footer then
        local ok, sessions, avg_wpm,
              avg7, avg30, avg60, avg90, avg180 = pcall(function()
            -- getSessionsInfo is defined in pagetextinfo main.lua
            return ui.pagetextinfo.getSessionsInfo
                and ui.pagetextinfo:getSessionsInfo(ui.view.footer)
                or nil
        end)
        if ok and sessions then
            data.avg_wpm   = math.floor(avg_wpm)
            data.avg_wph   = math.floor(avg_wpm * 60)
            data.sessions  = sessions
            data.avg7      = avg7  and math.floor(avg7)  or nil
            data.avg30     = avg30 and math.floor(avg30) or nil
            data.avg60     = avg60 and math.floor(avg60) or nil
            data.avg90     = avg90 and math.floor(avg90) or nil
            data.avg180    = avg180 and math.floor(avg180) or nil
        end
    end

    return data
end

-- ── Build sections ────────────────────────────────────────────────────────────

local function buildSections(data, fonts, layout)
    local sections = VerticalGroup:new{ align = "left" }
    local L = layout

    local function row2(lv, ll, rv, rl)
        return padded(L.padding_h, twoColRow(fonts, L, lv, ll, rv, rl))
    end
    local function row1(v, l)
        return padded(L.padding_h, valueLine(fonts, L.full_width - 2*L.padding_h, v, l))
    end
    local function sp() return VerticalSpan:new{ height = Size.padding.default } end

    -- ── FONT ─────────────────────────────────────────────────────────────────
    addSection(sections,
        sectionHeader(fonts, "FONT", L.full_width),
        {
            row1(data.font_face or "?", "face  (" .. (data.readability or "N/A") .. ")"),
            sp(),
            row2(
                string.format("%.1fpt", data.font_size_pt or 0), "size",
                (data.font_size_didot or "?"), "didot"
            ),
            sp(),
            row2(
                tostring(data.font_size_px or "?") .. "px", "pixels",
                string.format("%.2fmm", data.font_size_mm or 0), "mm"
            ),
            sp(),
            row1(tostring(data.font_weight or "?"), "weight"),
        }, L)

    -- ── X-HEIGHT ─────────────────────────────────────────────────────────────
    table.insert(sections, hline(L, true))
    addSection(sections,
        sectionHeader(fonts, "X-HEIGHT", L.full_width),
        {
            row2(data.x_height_px or "?", "pixels",
                 data.x_height_mm or "?", "mm"),
            sp(),
            row1(data.x_height_arcmin or "?", "visual angle at 40 cm"),
            sp(),
            padded(L.padding_h, TextBoxWidget:new{
                text = "• ~20′ ideal · 17–19′ comfortable · <15′ demanding · >25′ oversized",
                face = fonts.mono,
                width = L.full_width - 2*L.padding_h,
                alignment = "left",
            }),
        }, L)

    -- ── DISPLAY ──────────────────────────────────────────────────────────────
    table.insert(sections, hline(L, true))
    addSection(sections,
        sectionHeader(fonts, "DISPLAY", L.full_width),
        {
            row2(data.device_model or "?", "model",
                 tostring(data.display_dpi or "?") .. " ppi", "resolution"),
            sp(),
            row2(data.screen_res or "?", "pixels",
                 data.frontlight or "Off", "frontlight"),
        }, L)

    -- ── CSS ───────────────────────────────────────────────────────────────────
    if data.css_tag then
        table.insert(sections, hline(L, true))
        -- Two-column header: p | body
        local hdr_left_w = L.padding_h + L.col_width + math.floor(L.separator_width / 2)
        local hdr_right_w = L.full_width - hdr_left_w
        local hdr = HorizontalGroup:new{
            align = "center",
            sectionHeader(fonts, "CSS  —  " .. (data.css_tag.p or "p"), hdr_left_w),
            sectionHeader(fonts, data.css_tag.body or "body", hdr_right_w, math.ceil(L.separator_width / 2)),
        }
        addSection(sections, hdr, {
            row2(data.css_lineheight.p,  "line-height",
                 data.css_lineheight.body, ""),
            sp(),
            row2(data.css_indent.p,      "text-indent",
                 data.css_indent.body,    ""),
            sp(),
            row2(data.css_margin.p,      "margin",
                 data.css_margin.body,    ""),
            sp(),
            row2(data.css_align.p,       "text-align",
                 data.css_align.body,     ""),
        }, L)
    end

    -- ── TWEAKS ────────────────────────────────────────────────────────────────
    table.insert(sections, hline(L, true))
    addSection(sections,
        sectionHeader(fonts, "TWEAKS  (" .. tostring(data.tweaks_count) .. " applied)", L.full_width),
        {
            monoLine(fonts, L, data.tweaks_text ~= "" and data.tweaks_text or "None"),
        }, L)

    -- ── WPM ──────────────────────────────────────────────────────────────────
    if data.avg_wpm then
        table.insert(sections, hline(L, true))
        addSection(sections,
            sectionHeader(fonts, "READING SPEED", L.full_width),
            {
                row2(tostring(data.avg_wpm) .. " wpm", "average",
                     tostring(data.avg_wph) .. " wph", ""),
                sp(),
                row2(tostring(data.sessions or 0), "sessions",
                     "", ""),
                sp(),
                row2(data.avg7  and (data.avg7  .. " wpm") or "–", "last 7 d",
                     data.avg30 and (data.avg30 .. " wpm") or "–", "last 30 d"),
                sp(),
                row2(data.avg60  and (data.avg60  .. " wpm") or "–", "last 60 d",
                     data.avg90  and (data.avg90  .. " wpm") or "–", "last 90 d"),
                sp(),
                row2(data.avg180 and (data.avg180 .. " wpm") or "–", "last 180 d",
                     "", ""),
            }, L)
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
    local layout   = buildLayout(screen_w, Size.padding.large, Screen:scaleBySize(20))
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
        self.ges_events.TapClose = {
            GestureRange:new{ ges = "tap", range = self.dimen }
        }
    end

   if Device:isTouchDevice() then
        local range = GestureRange:new{ ges = "tap",   range = self.dimen }
        self.ges_events.TapClose   = { range }
        self.ges_events.SwipeClose = {
            GestureRange:new{ ges = "swipe", range = self.dimen }
        }
        self.ges_events.HoldClose  = {
            GestureRange:new{ ges = "hold",  range = self.dimen }
        }
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

function TextInfoPopup:onTapClose()
    UIManager:close(self)
    return true
end

function TextInfoPopup:onClose()
    UIManager:close(self)
    return true
end

function TextInfoPopup:onTapClose()   return UIManager:close(self) end
function TextInfoPopup:onSwipeClose() return UIManager:close(self) end
function TextInfoPopup:onHoldClose()  return UIManager:close(self) end
function TextInfoPopup:onClose()      return UIManager:close(self) end

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
    self.onGetTextPage = function(this)
        UIManager:show(TextInfoPopup:new{ ui = this })
        return true
    end
end

