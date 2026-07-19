--[[
Start-menu / hero micro-module: font size, x-height, and leading (airy) info.
Three columns: font size (left), x-height with comfort range (center),
and leading factor with its classification (right, e.g. "airy").
Mirrors the calculations in apps/reader/modules/topbar.lua
(TopBar:getXHeightRangeLabel and TopBar:classifyLeading), computed
standalone here so it doesn't depend on the topbar instance.
Works offline. Only meaningful while a document is open.
]]
local _ = require("lib/bookshelf_i18n").gettext

local PERFECT_MIN = 1.7   -- mm, a partir de aquí es cómodo
local PERFECT_MAX = 1.85  -- mm, más allá empieza a verse grande

local function classifyXHeight(xh_mm)
    if xh_mm < PERFECT_MIN then
        return "low", _("Low")
    elseif xh_mm <= PERFECT_MAX then
        return "perfect", _("Perfect")
    else
        return "too_big", _("Too big")
    end
end

-- Idéntico a TopBar:classifyLeading
local function classifyLeading(lf, x_height, ascender, descender)
    if not x_height or x_height == 0 then return "invalid", _("Invalid") end
    local safe_min = (ascender + descender) / x_height
    if lf < safe_min then return "collision", _("Collision")
    elseif lf < safe_min + 0.15 then return "compact", _("Compact")
    elseif lf < safe_min + 0.4 then return "balanced", _("Balanced")
    elseif lf < safe_min + 0.6 then return "airy", _("Airy")
    else return "very_airy", _("Very airy")
    end
end

local function getFontMetrics()
    local ok, ui = pcall(function()
        return require("apps/reader/readerui").instance
    end)
    if not ok or not ui or not ui.document or not ui.document._document then
        return nil
    end

    local ok2, result = pcall(function()
        local Font = require("ui/font")
        local Device = require("device")
        local Screen = Device.screen
        local Math = require("optmath")

        local font_face = ui.document._document:getFontFace()
        local current_face = font_face:gsub("%s+", "") .. "-Regular"
        local display_dpi = Device:getDeviceScreenDPI() or Screen:getDPI()
        local size_px = (display_dpi * ui.document.configurable.font_size) / 72
        local size_pt = (size_px / display_dpi) * 72
        local face_base = Font:getFace(current_face, size_px, 0, false)

        if not face_base then return nil end

        local x_height = Math.round(face_base.ftsize:getXHeight() * size_px)
        if not x_height or x_height == 0 then return nil end
        local x_height_mm = Math.round((x_height * (25.4 / display_dpi) * 100)) / 100
        local xheight_key, xheight_text = classifyXHeight(x_height_mm)

        local line_spacing_factor = ui.document.configurable.line_spacing / 100
        local x_height2, ascender, descender = face_base.ftsize:getAscDesc()
        local leading_factor = math.floor(((1.2 * size_px * line_spacing_factor) / x_height) * 100) / 100
        local leading_key, leading_text = classifyLeading(leading_factor, x_height2, ascender, descender)

        return {
            size_pt        = size_pt,
            x_height_mm    = x_height_mm,
            xheight_key    = xheight_key,
            xheight_text   = xheight_text,
            leading_factor = leading_factor,
            leading_key    = leading_key,
            leading_text   = leading_text,
        }
    end)

    if not ok2 or not result then return nil end
    return result
end

local function fitFontSize(Fonts, text, max_sz, min_sz, max_w, bold)
    local sz = max_sz
    while sz > min_sz do
        local face, b = Fonts:getFace("cfont", sz, bold and {bold=true} or nil)
        local tw = require("ui/widget/textwidget"):new{
            text = text, face = face, bold = b }
        if tw:getSize().w <= max_w then return sz end
        sz = sz - 2
    end
    return min_sz
end

return {
    key     = "xheight_size",
    title   = _("Font size / x-height"),
    summary = _("Current font size, x-height comfort range, and leading. Works offline while reading."),

    render = function(ctx)
        local width, scale_pct = ctx.width, ctx.scale
        local Fonts           = require("lib/bookshelf_fonts")
        local TextWidget      = require("ui/widget/textwidget")
        local VerticalGroup   = require("ui/widget/verticalgroup")
        local VerticalSpan    = require("ui/widget/verticalspan")
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local HorizontalSpan  = require("ui/widget/horizontalspan")
        local CenterContainer = require("ui/widget/container/centercontainer")
        local Geom            = require("ui/geometry")
        local SM              = require("lib/bookshelf_start_menu_modules")
        local mw = math.max(50, width)
        local function sc(n) return math.max(1, math.floor(n * (scale_pct or 100) / 100 + 0.5)) end
        local BLACK = SM.COLOR_PRIMARY

        local metrics = getFontMetrics()

        if metrics == nil then
            return TextWidget:new{
                text      = _("Not reading"),
                face      = Fonts:getFace("cfont", sc(15)),
                fgcolor   = SM.COLOR_MUTED,
                max_width = mw,
            }
        end

        local size_str    = string.format("%.1fpt", metrics.size_pt)
        local xheight_str = string.format("%.2fmm", metrics.x_height_mm)
        local leading_str = string.format("%.2f", metrics.leading_factor)

        local gap    = sc(16)
        local col_w  = math.floor((mw - gap * 2) / 3)
        local col_w3 = mw - gap * 2 - col_w * 2

        local size_sz_fit    = fitFontSize(Fonts, size_str, sc(32), sc(14), col_w, true)
        local xheight_sz_fit = fitFontSize(Fonts, xheight_str, sc(32), sc(14), col_w, true)
        local leading_sz_fit = fitFontSize(Fonts, leading_str, sc(32), sc(14), col_w3, true)
        local big_sz         = math.min(size_sz_fit, xheight_sz_fit, leading_sz_fit)
        local big_face, big_bold     = Fonts:getFace("cfont", big_sz, {bold=true})
        local label_face, label_bold = Fonts:getFace("cfont", sc(16), {bold=true})

        local function labelColor(is_good)
            if is_good and SM.COLOR_SUCCESS then
                return SM.COLOR_SUCCESS
            elseif not is_good and SM.COLOR_WARNING then
                return SM.COLOR_WARNING
            end
            return SM.COLOR_MUTED
        end

        local xheight_label_color = labelColor(metrics.xheight_key == "perfect")
        local leading_label_color = labelColor(
            metrics.leading_key == "balanced" or metrics.leading_key == "airy"
        )

        local function makeCol(value_str, label_text, label_color, w)
            return VerticalGroup:new{
                align = "center",
                TextWidget:new{
                    text      = value_str,
                    face      = big_face,
                    bold      = big_bold,
                    fgcolor   = BLACK,
                    max_width = w,
                },
                VerticalSpan:new{ width = sc(2) },
                TextWidget:new{
                    text      = label_text,
                    face      = label_face,
                    bold      = label_bold,
                    fgcolor   = label_color,
                    max_width = w,
                },
            }
        end

        local size_col    = makeCol(size_str, _("Font size"), SM.COLOR_MUTED, col_w)
        local xheight_col = makeCol(xheight_str, metrics.xheight_text, xheight_label_color, col_w)
        local leading_col = makeCol(leading_str, metrics.leading_text, leading_label_color, col_w3)

        local max_h = math.max(size_col:getSize().h, xheight_col:getSize().h, leading_col:getSize().h)

        return HorizontalGroup:new{
            align = "top",
            CenterContainer:new{
                dimen = Geom:new{ w = col_w, h = max_h },
                size_col,
            },
            HorizontalSpan:new{ width = gap },
            CenterContainer:new{
                dimen = Geom:new{ w = col_w, h = max_h },
                xheight_col,
            },
            HorizontalSpan:new{ width = gap },
            CenterContainer:new{
                dimen = Geom:new{ w = col_w3, h = max_h },
                leading_col,
            },
        }
    end,
}
