--[[
Book Info Popup (table layout)
Structured popup replacing onShowTextProperties plain TextViewer.
Shows book metadata, reading stats, session info and page metrics, each
section rendered as a bordered table.
Tap or hold dismisses and applies a random font preset for the book genre.
Swipe or Back just dismisses.

Action: ShowTextProperties
]]--

local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local Dispatcher      = require("dispatcher")
local Event           = require("ui/event")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local Notification    = require("ui/widget/notification")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local Screen          = Device.screen
local datetime        = require("datetime")

-- ── Fonts ─────────────────────────────────────────────────────────────────────

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

-- ── Genre font application ────────────────────────────────────────────────────

local function applyRandomGenreFont(pti)
    if not pti or not pti.getGenreBook or not pti.genres_table then return end
    local genre = pti:getGenreBook()
    genre = genre and (genre:match("^%w+%.(.+)$") or genre) or nil
    if not genre then return end
    local profile = pti.genres_table[genre]
    if not profile or not profile.presets or #profile.presets == 0 then
        UIManager:show(Notification:new{ text = "No genre profile found" })
        return
    end
    local preset = profile.presets[math.random(1, #profile.presets)]
    UIManager:nextTick(function()
        UIManager:broadcastEvent(Event:new("SetFont", preset.font))
        UIManager:broadcastEvent(Event:new("SetFontBaseWeight", preset.weight))
        UIManager:broadcastEvent(Event:new("SetLineSpace", preset.line_spacing_percent))
        UIManager:show(Notification:new{
            text = preset.font .. ", " .. tostring(400 + preset.weight * 100)
                .. ", " .. preset.line_spacing_em .. "em",
        })
    end)
end

-- ── Data gathering ────────────────────────────────────────────────────────────

local function gatherData(ui)
    local d = {}
    if not ui or not ui.document then return d end

    local doc    = ui.document
    local pti    = ui.pagetextinfo
    local footer = ui.view and ui.view.footer

    local props  = doc._document:getDocumentProps()
    d.title      = props.title  or "?"
    d.author     = (props.authors ~= "" and props.authors) or "No metadata"

    -- Genres from OPF
    d.genres = "N/A"
    local file_type = string.lower(string.match(doc.file, ".+%.([^.]+)") or "")
    if file_type == "epub" then
        local opf_text
        for _, path in ipairs({
            "OPS/Miscellaneous/content.opf", "content.opf",
            "OPS/volume.opf", "volume.opf",
            "OEBPS/Miscellaneous/content.opf", "OEBPS/content.opf",
            "epub/content.opf",
        }) do
            opf_text = doc:getDocumentFileContent(path)
            if opf_text then break end
        end
        if opf_text then
            local g = ""
            for w in opf_text:gmatch("<dc:subject>(.-)</dc:subject>") do
                g = g .. ", " .. w
            end
            d.genres = g ~= "" and g:sub(3) or "No metadata"
        end
    end

    -- Main genre
    if pti and pti.getGenreBook then
        local genre = pti:getGenreBook()
        d.main_genre = genre and (genre:match("^%w+%.(.+)$") or genre) or "N/A"
        if pti.genres_table and d.main_genre ~= "N/A" then
            local gp = pti.genres_table[d.main_genre]
            d.genre_fonts = gp and gp.fonts or nil
        end
    else
        d.main_genre = "N/A"
    end

    -- Pages / words / chars
    d.screen_pages = tostring(doc:getPageCount())
    if ui.pagemap and ui.pagemap:wantsPageLabels() then
        d.stable_pages = tostring(ui.pagemap:getLastPageLabel(true))
    end
    local total_chars, total_words = doc:getBookCharactersCount()
    d.total_chars     = tostring(total_chars or 0)
    d.total_words     = tostring(total_words or 0)
    d.total_words_est = tostring(math.ceil((total_chars or 0) / 5.7))

    -- Progress
    local pageno = footer and footer.pageno or 1
    local pages  = footer and footer.pages  or 1
    d.progress   = string.format("%d / %d  (%.0f%%)", pageno, pages,
        pages > 0 and (pageno / pages * 100) or 0)

    -- Chapter
    if ui.toc then
        local left = ui.toc:getChapterPagesLeft(pageno) or doc:getTotalPagesLeft(pageno)
        d.chapter      = ui.toc:getTocTitleByPage(pageno) or ""
        d.chapter_left = tostring(left or 0)
    end

    -- Page line/word/char counts
    if ui.view then
        local ok, nblines, nbwords = pcall(function()
            return ui.view:getCurrentPageLineWordCounts()
        end)
        if ok then
            d.nblines = tostring(nblines or 0)
            d.nbwords = tostring(nbwords or 0)
        end

        local configurable = doc.configurable
        local display_dpi  = Device:getDeviceScreenDPI() or Screen:getDPI()
        local font_size_px = math.floor((display_dpi * (configurable.font_size or 20)) / 72)
        local line_h_px    = math.max(1, math.ceil(
            font_size_px * ((configurable.line_spacing or 100) / 100)))

        local res0 = doc._document:getTextFromPositions(
            0, 0, Screen:getWidth(), line_h_px, false, true)
        if res0 and res0.text then
            d.chars_first_line = tostring(#res0.text)
        end
    end

    -- Frontlight
    local powerd = Device:getPowerDevice()
    if powerd:isFrontlightOn() then
        local warmth = powerd:frontlightWarmth()
        d.frontlight = string.format("L: %d%%", powerd:frontlightIntensity())
        if warmth then d.frontlight = d.frontlight .. string.format("  W: %d%%", warmth) end
    else
        d.frontlight = "Off"
    end

    d.clock = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))

    -- Sessions / wpm history
    -- NOTE: getSessionsInfo is declared in main.lua as a bare global
    -- function `getSessionsInfo(footer)`; it is not attached to the
    -- PageTextInfo table, so call the global directly.
    if pti and _G.getSessionsInfo then
        local ok, sessions, avg_wpm,
              avg7, avg30, avg60, avg90, avg180 =
            pcall(_G.getSessionsInfo, footer)
        if ok then
            d.sessions = tostring(sessions or 0)
            d.avg_wpm  = string.format("%d wpm  %d wph",
                math.floor(avg_wpm or 0), math.floor((avg_wpm or 0) * 60))
            d.avg7   = string.format("%.1fh", avg7   or 0)
            d.avg30  = string.format("%.1fh", avg30  or 0)
            d.avg60  = string.format("%.1fh", avg60  or 0)
            d.avg90  = string.format("%.1fh", avg90  or 0)
            d.avg180 = string.format("%.1fh", avg180 or 0)
        end
    end

    return d
end

-- ── Build sections ────────────────────────────────────────────────────────────

local function buildSections(data, fonts, layout)
    local sections = VerticalGroup:new{ align = "left" }
    local L = layout

    local function kvTable(items)
        return buildTable(fonts, L, KV_COLS, kvRows(items))
    end

    -- BOOK
    local book_items = {
        { "Title",   data.title  or "?", wide = true },
        { "Author",  data.author or "?", wide = true },
        { "Genres",  data.genres or "N/A", wide = true },
        { "Main genre", data.main_genre or "N/A", wide = true },
        { "Progress", data.progress or "?", wide = true },
        { "Chapter", data.chapter or "—", wide = true },
        { "Pages left", (data.chapter_left or "?") .. " in chapter", wide = true },
    }
    if data.genre_fonts then
        table.insert(book_items, { "Suggested", data.genre_fonts, wide = true })
    end
    addSection(sections, fonts, L,
        "BOOK  —  " .. (data.clock or "") .. "  ·  " .. (data.frontlight or "Off"),
        kvTable(book_items))

    -- CONTENT
    addSection(sections, fonts, L, "CONTENT", kvTable{
        { "Screen pages", data.screen_pages or "?" },
        { "Stable pages", data.stable_pages or "—" },
        { "Words",        data.total_words or "?" },
        { "Words (est.)", data.total_words_est or "?" },
        { "Characters",   data.total_chars or "?", wide = true },
        { note = "Estimated words = characters / 5.7" },
    })

    -- THIS PAGE
    addSection(sections, fonts, L, "THIS PAGE", kvTable{
        { "Lines",       data.nblines or "?" },
        { "Words",       data.nbwords or "?" },
        { "First line",  (data.chars_first_line or "?") .. " chars", wide = true },
    })

    -- SPEED & HISTORY
    addSection(sections, fonts, L, "SPEED & HISTORY", kvTable{
        { "Average",  data.avg_wpm or "?" , wide = true },
        { "Sessions", data.sessions or "?", wide = true },
        { "7 days",   data.avg7   or "?" },
        { "30 days",  data.avg30  or "?" },
        { "60 days",  data.avg60  or "?" },
        { "90 days",  data.avg90  or "?" },
        { "180 days", data.avg180 or "?" },
    })

    -- Bottom rule
    table.insert(sections, LineWidget:new{
        dimen      = Geom:new{ w = L.full_width, h = Size.line.thick },
        background = Blitbuffer.COLOR_BLACK,
    })

    return sections
end

-- ── Popup widget ──────────────────────────────────────────────────────────────

local BookInfoPopup = InputContainer:extend{
    modal = true,
    ui    = nil,
}

function BookInfoPopup:init()
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

    self[1]    = VerticalGroup:new{ self.popup_frame }
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

function BookInfoPopup:_closeAndApplyFont()
    local pti = self.ui and self.ui.pagetextinfo
    UIManager:close(self)
    applyRandomGenreFont(pti)
    return true
end

function BookInfoPopup:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.popup_frame.dimen
    end)
    return true
end

function BookInfoPopup:onTapClose()   return self:_closeAndApplyFont() end
function BookInfoPopup:onHoldClose()  return self:_closeAndApplyFont() end
function BookInfoPopup:onSwipeClose() UIManager:close(self); return true end
function BookInfoPopup:onClose()      UIManager:close(self); return true end

function BookInfoPopup:onCloseWidget()
    UIManager:setDirty(nil, "ui")
end

-- ── Registration ──────────────────────────────────────────────────────────────

Dispatcher:registerAction("text_properties", {
    category  = "none",
    event     = "ShowTextProperties",
    title     = "Show text properties",
    general   = true,
    separator = true,
})

local ReaderUI = require("apps/reader/readerui")
local _orig    = ReaderUI.registerKeyEvents

ReaderUI.registerKeyEvents = function(self)
    if _orig then _orig(self) end
    local util = require("util")
    local is_pdf = self.document and util.getFileNameSuffix(self.document.file) == "pdf"
    if is_pdf then return end
    self.onShowTextProperties = function(this)
        UIManager:show(BookInfoPopup:new{ ui = this })
        return true
    end
end
