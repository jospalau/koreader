--[[
Start-menu / hero micro-module: book info.
Shows title, series, word count and publication year of the current book.
Data comes from the active ReaderUI topbar instance. Works offline.
]]
local _ = require("lib/bookshelf_i18n").gettext

local function getInfo()
    local ok, ui = pcall(function()
        return require("apps/reader/readerui").instance
    end)
    if not ok or not ui then return nil end
    local topbar = ui.view and ui.view.topbar
    if not topbar then return nil end
    return {
        title       = topbar.title or "",
        series      = topbar.series or "",
        total_words = tonumber(topbar.total_words) or 0,
        pub_date    = topbar.pub_date or "",
    }
end

local function fmtWords(n)
    if n <= 0 then return nil end
    if n >= 1000 then
        return string.format("%dk", math.floor(n / 1000))
    end
    return tostring(n)
end

return {
    key     = "book_info",
    title   = _("Book info"),
    summary = _("Title, series, word count and publication year. Works offline."),

    render = function(ctx)
        local width, scale_pct = ctx.width, ctx.scale
        local Fonts         = require("lib/bookshelf_fonts")
        local TextWidget    = require("ui/widget/textwidget")
        local VerticalGroup = require("ui/widget/verticalgroup")
        local VerticalSpan  = require("ui/widget/verticalspan")
        local SM            = require("lib/bookshelf_start_menu_modules")
        local mw = math.max(50, width)
        local function sc(n) return math.max(1, math.floor(n * (scale_pct or 100) / 100 + 0.5)) end

        local info = getInfo()

        if not info or info.title == "" then
            return TextWidget:new{
                text      = _("Not reading"),
                face      = Fonts:getFace("cfont", sc(28)),
                fgcolor   = SM.COLOR_MUTED,
                max_width = mw,
            }
        end

        local title_face, title_bold = Fonts:getFace("cfont", sc(28), {bold=true})
        local meta_face              = Fonts:getFace("cfont", sc(20))

        local title = info.title:gsub("%[/?b%]", ""):gsub("\xEF\xBF\xBC", "")
        title = title:match("^%s*(.-)%s*$")

        local series = info.series:gsub("^%s*⋅%s*", ""):gsub("%[/?b%]", ""):gsub("\xEF\xBF\xBC", "")
        series = series:match("^%s*(.-)%s*$")

        local words_str  = fmtWords(info.total_words)
        local meta_parts = {}
        if words_str     then table.insert(meta_parts, words_str .. "w") end
        if info.pub_date ~= "" then table.insert(meta_parts, info.pub_date) end
        local meta_str = table.concat(meta_parts, "  ·  ")

        local vg = VerticalGroup:new{ align = "left" }

        vg[#vg+1] = TextWidget:new{
            text      = title,
            face      = title_face,
            bold      = title_bold,
            fgcolor   = SM.COLOR_PRIMARY,
            max_width = mw,
        }

        if series ~= "" then
            vg[#vg+1] = VerticalSpan:new{ width = sc(4) }
            vg[#vg+1] = TextWidget:new{
                text      = series,
                face      = meta_face,
                fgcolor   = SM.COLOR_MUTED,
                max_width = mw,
            }
        end

        if meta_str ~= "" then
            vg[#vg+1] = VerticalSpan:new{ width = sc(4) }
            vg[#vg+1] = TextWidget:new{
                text      = meta_str,
                face      = meta_face,
                fgcolor   = SM.COLOR_MUTED,
                max_width = mw,
            }
        end

        return vg
    end,
}

