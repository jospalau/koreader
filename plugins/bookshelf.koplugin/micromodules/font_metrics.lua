--[[
Start-menu / hero micro-module: font size vs x-height.
Shows the current reading font size on the left, and the rendered
x-height (in mm) with its comfort-range classification on the right.
Mirrors the calculation in apps/reader/modules/topbar.lua
(TopBar:getXHeightRangeLabel), but computed standalone here so it
doesn't depend on the topbar instance.
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

-- Returns size_pt (number), x_height_mm (number), label_key, label_text
-- or nil if there's no open document / face couldn't be loaded.
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

        local label_key, label_text = classifyXHeight(x_height_mm)

        return {
            size_pt     = size_pt,
            x_height_mm = x_height_mm,
            label_key   = label_key,
            label_text  = label_text,
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
    summary = _("Current font size and rendered x-height comfort range. Works offline while reading."),

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

        local size_str   = string.format("%.1fpt", metrics.size_pt)
        local xheight_str = string.format("%.2fmm", metrics.x_height_mm)

        local gap    = sc(24)
        local col_w  = math.floor((mw - gap) / 2)
        local col_w2 = mw - gap - col_w

        local size_sz_fit    = fitFontSize(Fonts, size_str, sc(40), sc(18), col_w,  true)
        local xheight_sz_fit = fitFontSize(Fonts, xheight_str, sc(40), sc(18), col_w2, true)
        local big_sz         = math.min(size_sz_fit, xheight_sz_fit)
        local big_face, big_bold     = Fonts:getFace("cfont", big_sz, {bold=true})
        local label_face, label_bold = Fonts:getFace("cfont", sc(20), {bold=true})

        -- Color del label de la derecha según lo cómodo que sea el x-height
        local xheight_label_color = SM.COLOR_MUTED
        if metrics.label_key == "perfect" and SM.COLOR_SUCCESS then
            xheight_label_color = SM.COLOR_SUCCESS
        elseif metrics.label_key ~= "perfect" and SM.COLOR_WARNING then
            xheight_label_color = SM.COLOR_WARNING
        end

        local size_col = VerticalGroup:new{
            align = "center",
            TextWidget:new{
                text      = size_str,
                face      = big_face,
                bold      = big_bold,
                fgcolor   = BLACK,
                max_width = col_w,
            },
            VerticalSpan:new{ width = sc(2) },
            TextWidget:new{
                text      = _("Font size"),
                face      = label_face,
                bold      = label_bold,
                fgcolor   = SM.COLOR_MUTED,
                max_width = col_w,
            },
        }

        local xheight_col = VerticalGroup:new{
            align = "center",
            TextWidget:new{
                text      = xheight_str,
                face      = big_face,
                bold      = big_bold,
                fgcolor   = BLACK,
                max_width = col_w2,
            },
            VerticalSpan:new{ width = sc(2) },
            TextWidget:new{
                text      = metrics.label_text,
                face      = label_face,
                bold      = label_bold,
                fgcolor   = xheight_label_color,
                max_width = col_w2,
            },
        }

        local max_h = math.max(size_col:getSize().h, xheight_col:getSize().h)

        return HorizontalGroup:new{
            align = "top",
            CenterContainer:new{
                dimen = Geom:new{ w = col_w, h = max_h },
                size_col,
            },
            HorizontalSpan:new{ width = gap },
            CenterContainer:new{
                dimen = Geom:new{ w = col_w2, h = max_h },
                xheight_col,
            },
        }
    end,
}
