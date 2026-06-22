local _ = require("lib/bookshelf_i18n").gettext

local function getCounts()
    if not _G.all_files then return 0, 0, 0, 0 end
    local cy = os.date("%Y")
    local cm = os.date("%m")
    local ly = tostring(tonumber(cy) - 1)
    local lm = string.format("%02d", tonumber(cm) - 1 == 0 and 12 or tonumber(cm) - 1)
    local lmy = tonumber(cm) - 1 == 0 and ly or cy

    local ftm, flm, fty, fly = 0, 0, 0, 0
    for _, f in pairs(_G.all_files) do
        if f.status == "complete" or f.status == "finished" then
            local y, m = f.last_modified_year, f.last_modified_month
            if y and m then
                if y == cy and m == cm then ftm = ftm + 1 end
                if y == lmy and m == lm then flm = flm + 1 end
                if y == cy then fty = fty + 1 end
                if y == ly then fly = fly + 1 end
            end
        end
    end
    return ftm, flm, fty, fly
end

return {
    key   = "finished_stats",
    title = _("Finished stats"),
    summary = _("Books finished this/last month and year."),
    render = function(ctx)
        local width, scale_pct, _preview, avail_h = ctx.width, ctx.scale, ctx.preview, ctx.height
        local Fonts         = require("lib/bookshelf_fonts")
        local TextWidget    = require("ui/widget/textwidget")
        local VerticalGroup = require("ui/widget/verticalgroup")
        local VerticalSpan  = require("ui/widget/verticalspan")
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local HorizontalSpan  = require("ui/widget/horizontalspan")
        local CenterContainer = require("ui/widget/container/centercontainer")
        local Geom          = require("ui/geometry")
        local SM            = require("lib/bookshelf_start_menu_modules")

        local function sc(n) return math.max(1, math.floor(n * (scale_pct or 100) / 100 + 0.5)) end
        local BLACK  = SM.COLOR_PRIMARY
        local mw     = math.max(50, width)

        local ftm, flm, fty, fly = getCounts()

        local ROWS = {
            { label = _("FTM"), value = ftm },
            { label = _("FLM"), value = flm },
            { label = _("FTY"), value = fty },
            { label = _("FLY"), value = fly },
        }

        local head_face        = Fonts:getFace("cfont", sc(12))
        local count_face, count_bold = Fonts:getFace("cfont", sc(18), {bold=true})
        local n      = #ROWS
        local col_w  = math.floor(mw / n)

        local row = HorizontalGroup:new{ align = "top" }
        for _, r in ipairs(ROWS) do
            local col = VerticalGroup:new{
                align = "center",
                TextWidget:new{ text = r.label, face = head_face, fgcolor = SM.COLOR_MUTED, max_width = col_w },
                VerticalSpan:new{ width = sc(2) },
                TextWidget:new{ text = tostring(r.value), face = count_face, bold = count_bold, fgcolor = BLACK, max_width = col_w },
            }
            row[#row + 1] = CenterContainer:new{
                dimen = Geom:new{ w = col_w, h = col:getSize().h }, col }
        end

        return VerticalGroup:new{ align = "left", row }
    end,
}
