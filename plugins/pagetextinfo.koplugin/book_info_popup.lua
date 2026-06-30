--[[
Book Info Popup
Structured sectioned popup replacing onShowTextProperties plain TextViewer.
Shows book metadata, reading stats, session info and page metrics.
Tap or any gesture dismisses and applies a random font preset for the book genre.

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
local Math            = require("optmath")
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
        value   = Font:getFace("NotoSans-Bold.ttf",    26) or Font:getFace("tfont", 26),
        label   = Font:getFace("NotoSans-Regular.ttf", 16) or Font:getFace("x_smallinfofont", 16),
        mono    = Font:getFace("myfont3",              14) or Font:getFace("cfont", 14),
    }
end

-- ── Layout helpers ────────────────────────────────────────────────────────────

local function buildLayout(screen_w, padding_h, column_gap)
    local sep_w = 2 * column_gap + Size.line.medium
    local col_w = math.floor((screen_w - 2 * padding_h - sep_w) / 2)
    return {
        full_width      = screen_w,
        padding_h       = padding_h,
        column_gap      = column_gap,
        separator_width = sep_w,
        col_width       = col_w,
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
        dimen      = Geom:new{
            w = layout.full_width - 2 * layout.padding_h,
            h = thick and Size.line.thick or Size.line.thin,
        },
        background = Blitbuffer.COLOR_GRAY,
    })
end

local function sectionHeader(fonts, text, width, left_pad)
    left_pad = left_pad or Size.padding.large
    local tw = TextWidget:new{ text = text, face = fonts.section }
    return FrameContainer:new{
        background     = Blitbuffer.COLOR_WHITE,
        bordersize     = 0,
        padding_top    = Size.padding.small,
        padding_bottom = Size.padding.small,
        padding_left   = left_pad,
        padding_right  = 0,
        LeftContainer:new{
            dimen = Geom:new{ w = width - left_pad, h = tw:getSize().h },
            tw,
        },
    }
end

local function valueLine(fonts, col_width, value_str, label_str)
    if not value_str or value_str == "" then
        return TextBoxWidget:new{
            text      = label_str or "",
            face      = fonts.label,
            width     = col_width,
            alignment = "left",
        }
    end
    local vw    = TextWidget:new{ text = value_str, face = fonts.value }
    local vw_w  = vw:getSize().w
    local lbl_w = col_width - vw_w - Size.padding.large
    if lbl_w <= 0 then
        return VerticalGroup:new{
            align = "left",
            vw,
            TextBoxWidget:new{
                text      = label_str or "",
                face      = fonts.label,
                width     = col_width,
                alignment = "left",
            },
        }
    end
    return HorizontalGroup:new{
        align = "center",
        vw,
        HorizontalSpan:new{ width = Size.padding.large },
        TextBoxWidget:new{
            text      = label_str or "",
            face      = fonts.label,
            width     = lbl_w,
            alignment = "left",
        },
    }
end

local function monoLine(fonts, layout, text)
    return padded(layout.padding_h, TextBoxWidget:new{
        text      = text,
        face      = fonts.mono,
        width     = layout.full_width - 2 * layout.padding_h,
        alignment = "left",
    })
end

local function twoColRow(fonts, layout, lv, ll, rv, rl)
    local lw = valueLine(fonts, layout.col_width, lv, ll)
    local rw = valueLine(fonts, layout.col_width, rv, rl)
    local h  = math.max(lw:getSize().h, rw:getSize().h)
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

local function sp() return VerticalSpan:new{ height = Size.padding.default } end

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
        -- Suggested fonts for genre
        if pti.genres_table and d.main_genre ~= "N/A" then
            local gp = pti.genres_table[d.main_genre]
            d.genre_fonts = gp and gp.fonts or nil
        end
    else
        d.main_genre = "N/A"
    end

    -- Pages / words / chars
    d.screen_pages    = tostring(doc:getPageCount())
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

    -- Stats via pagetextinfo helpers
    if pti then
        local user_fmt = "letters"

        -- Sessions / wpm history
        -- NOTE: getSessionsInfo is declared in main.lua as a bare global
        -- function `getSessionsInfo(footer)` — it was never attached to the
        -- PageTextInfo table, so `pti.getSessionsInfo` is nil and `pti:...`
        -- would also pass the wrong first argument. Call the global directly.
        if _G.getSessionsInfo then
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
    end

    return d
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
    local function mono(text)
        return monoLine(fonts, L, text)
    end

    -- ── BOOK ─────────────────────────────────────────────────────────────────
    addSection(sections,
        sectionHeader(fonts, "BOOK  —  " .. (data.clock or "") ..
            "  ·  " .. (data.frontlight or "Off"), L.full_width),
        {
            row1(data.title  or "?", "title"),
            sp(),
            row1(data.author or "?", "author"),
            sp(),
            mono("Genres: " .. (data.genres or "N/A")),
            sp(),
            row2(data.main_genre or "N/A", "main genre",
                 data.progress   or "?",   "progress"),
            sp(),
            row2(data.chapter_left or "?", "pages left in chapter", "", ""),
            sp(),
            mono("Chapter: " .. (data.chapter or "—")),
            data.genre_fonts and sp() or VerticalSpan:new{ height = 0 },
            data.genre_fonts and mono("Suggested fonts: " .. data.genre_fonts) or VerticalSpan:new{ height = 0 },
        }, L)

    -- ── CONTENT ──────────────────────────────────────────────────────────────
    table.insert(sections, hline(L, true))
    addSection(sections,
        sectionHeader(fonts, "CONTENT", L.full_width),
        {
            row2(data.screen_pages    or "?", "screen pages",
                 data.stable_pages    or "—", "stable pages"),
            sp(),
            row2(data.total_words     or "?", "words",
                 data.total_words_est or "?", "words (chars/5.7)"),
            sp(),
            row1(data.total_chars     or "?", "characters"),
        }, L)

    -- ── THIS PAGE ────────────────────────────────────────────────────────────
    table.insert(sections, hline(L, true))
    addSection(sections,
        sectionHeader(fonts, "THIS PAGE", L.full_width),
        {
            row2(data.nblines          or "?", "lines",
                 data.nbwords          or "?", "words"),
            sp(),
            row1(data.chars_first_line or "?", "chars in first line"),
        }, L)

    -- ── SPEED & HISTORY ───────────────────────────────────────────────────────
    table.insert(sections, hline(L, true))
    addSection(sections,
        sectionHeader(fonts, "SPEED & HISTORY", L.full_width),
        {
            row1(data.avg_wpm  or "?", "average  (" .. (data.sessions or "?") .. " sessions)"),
            sp(),
            row2(data.avg7   or "?", "last 7 d",
                 data.avg30  or "?", "last 30 d"),
            sp(),
            row2(data.avg60  or "?", "last 60 d",
                 data.avg90  or "?", "last 90 d"),
            sp(),
            row1(data.avg180 or "?", "last 180 d"),
        }, L)

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

    self[1]    = VerticalGroup:new{ self.popup_frame }
    self.dimen = Geom:new{ w = screen_w, h = Screen:getHeight() }

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
function BookInfoPopup:onSwipeClose() return UIManager:close(self) end
function BookInfoPopup:onHoldClose()  return self:_closeAndApplyFont() end
function BookInfoPopup:onClose()      return UIManager:close(self) end

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
    self.onShowTextProperties = function(this)
        UIManager:show(BookInfoPopup:new{ ui = this })
        return true
    end
end

