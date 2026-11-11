local bit = require("bit")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderImage = require("ui/renderimage")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Cards = require("book_rewind/cards")
local CardView = require("book_rewind/ui/card_view")
local GeneratedCover = require("book_rewind/ui/generated_cover")
local ShareScreen = require("book_rewind/ui/share_screen")
local BookSettings = require("book_rewind/book_settings")
local Marked = require("book_rewind/marked")
local StablePages = require("book_rewind/stable_pages")
local I18n = require("book_rewind/i18n")
local Stats = require("book_rewind/stats")
local Store = require("book_rewind/store")
local Themes = require("book_rewind/ui/themes")

local Device_screen = Device.screen
local NEW_YEAR_DAYS = 30
local DOUBLE_FLASH_SETTING = "book_rewind_double_flash"
local PLUGIN_DIR = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("/book_rewind/ui/screen%.lua$", "")

local Screen = InputContainer:extend{
    name = "book_rewind_screen",
    covers_fullscreen = true,
    stop_events_propagation = true,
    db_path = nil,
    covers_db = nil,
    language = nil,
    theme = nil,
    now = nil,
    -- The settings of the book open in KOReader, if any, which can be newer than the file on disk, and its path.
    doc_settings = nil,
    doc_file = nil,
    -- For tests: the reading history and how a book's settings are opened (see BookSettings.collect).
    history = nil,
    open_doc_settings = nil,
}

function Screen:init()
    -- The layout only fits portrait; odd rotation modes are landscape.
    local rotation = Device_screen:getRotationMode()
    if bit.band(rotation, 1) == 1 then
        self.restore_rotation = rotation
        Device_screen:setRotationMode(Device_screen.DEVICE_ROTATED_UPRIGHT)
    end
    -- A failure past this point must not leave the screen rotated.
    local ok, err = pcall(self.setup, self)
    if not ok then
        self:free_covers()
        if self.restore_rotation then
            Device_screen:setRotationMode(self.restore_rotation)
            self.restore_rotation = nil
        end
        error(err, 0)
    end
end

function Screen:setup()
    self.dimen = Geom:new{ x = 0, y = 0, w = Device_screen:getWidth(), h = Device_screen:getHeight() }
    self.width, self.height = self.dimen.w, self.dimen.h
    self.language = self.language or I18n.language_from(G_reader_settings and G_reader_settings:readSetting("language"))
    self.strings = I18n[self.language]
    self.theme = self.theme or Themes.device_theme(Device_screen)
    -- KOReader only uses the color waveforms of a color panel for content marked as dithered.
    self.dithered = self.theme == "eink"
    self.double_flash = G_reader_settings:isTrue(DOUBLE_FLASH_SETTING)
    self.db_path = self.db_path or (DataStorage:getSettingsDir() .. "/statistics.sqlite3")
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = self.dimen } },
        Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
    }
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            NextCard = { { Device.input.group.PgFwd } },
            PreviousCard = { { Device.input.group.PgBack } },
        }
    end
    self.close_rect = CardView.close_rect(self.width, self.height)
    local meta_chunk = loadfile(PLUGIN_DIR .. "/_meta.lua")
    if meta_chunk then
        setfenv(meta_chunk, {})
        self.meta = meta_chunk()
    end
    self.covers_db = self.covers_db or (DataStorage:getSettingsDir() .. "/bookinfo_cache.sqlite3")
    self.covers = {}
    self.cover_provider = function(book_id, max_w, max_h, theme) return self:cached_cover(book_id, max_w, max_h, theme) end
    self.years = Store.years(self.db_path, Cards.MIN_SECONDS)
    self.today = os.date("*t", self.now or os.time())
    self.current_year = self.today.year
    self.current_seconds = Store.year_seconds(self.db_path, self.current_year)
    self:open_year(self:first_year())
end

-- The settings KOReader keeps for the books opened in the year (stable page numbers, finished status). Anything
-- that goes wrong leaves the recap as it is with the statistics alone.
function Screen:book_entries(year)
    local ok, entries = pcall(BookSettings.collect, os.time{ year = year, month = 1, day = 1, hour = 0 }, {
        current = self.doc_settings, current_file = self.doc_file, history = self.history, open = self.open_doc_settings,
    })
    if not ok then
        logger.warn("Book Rewind: could not read the book settings", entries)
        return {}
    end
    return entries
end

-- Books marked as finished in KOReader that the statistics do not show as finished (see Marked).
function Screen:add_marked(entries, year)
    local ok, err = pcall(function()
        local finished_before = {}
        local ids = Store.book_ids_by_md5(self.db_path, Marked.to_check(self.metrics, entries, self.book_data, year))
        for md5, book_ids in pairs(ids) do
            for _, book_id in ipairs(book_ids) do
                local history = Store.book_history(self.db_path, book_id, year)
                if history and Stats.count_passes(history) > 0 then
                    finished_before[md5] = true
                end
            end
        end
        for _, book in ipairs(Marked.add(self.metrics, entries, self.book_data, year, finished_before)) do
            if not self.book_data[book.id] then
                self.book_data[book.id] = { title = book.stored_title, authors = book.authors, pages = book.total_pages }
            end
        end
    end)
    if not ok then
        self.metrics.marked_books = nil
        for _, book in ipairs(self.metrics.books or {}) do
            book.marked_finished = nil
        end
        logger.warn("Book Rewind: could not read the books marked as finished", err)
    end
end

-- Early in a year, the one that just ended is the recap worth seeing.
function Screen:first_year()
    if self.years[1] == self.current_year and self.today.yday <= NEW_YEAR_DAYS then
        for _, year in ipairs(self.years) do
            if year == self.current_year - 1 then
                return year
            end
        end
    end
    return self.years[1] or self.current_year
end

function Screen:open_year(year)
    self.year = year
    self:free_covers()
    local data = Store.load_year(self.db_path, year, self.now)
    local entries = data and self:book_entries(year) or {}
    if data then
        StablePages.apply(data.books, StablePages.totals(entries))
    end
    self.metrics = data and Stats.compute{
        year = year,
        rows = data.rows,
        books = data.books,
        earlier_pages = data.earlier_pages,
        earlier_reads = data.earlier_reads,
        read_later = data.read_later,
        last_read_before = data.last_read_before,
        last_year_seconds = data.last_year_seconds,
        previous_seconds = data.previous_seconds,
        earlier_history = function(book_id) return Store.book_history(self.db_path, book_id, year) end,
        now = self.now,
    }
    if not self.metrics or self.metrics.total_seconds < Cards.MIN_SECONDS then
        self:show_empty(year, self.metrics and self.metrics.total_seconds or 0)
        return
    end
    self.book_data = data.books
    self:add_marked(entries, year)
    self:rebuild_cards()
    self.mode = "cards"
    self:show_card(1)
end

function Screen:rebuild_cards()
    -- Only the neighbouring years: older on the left, newer on the right, like turning pages.
    local older, newer
    for _, other in ipairs(self.years) do
        if other < self.year and (not older or other > older) then
            older = other
        elseif other > self.year and (not newer or other < newer) then
            newer = other
        end
    end
    local other_years = {}
    if older then
        other_years[#other_years + 1] = { id = "year", year = older, label = "‹ " .. older, side = "left" }
    end
    if newer then
        other_years[#other_years + 1] = { id = "year", year = newer, label = newer .. " ›", side = "right" }
    end
    -- The newest cover says how close the current year is when it has too little reading to be listed.
    local notice
    if self.year == self.years[1] and self.year < self.current_year then
        notice = self.strings.cover_notice(Cards.minutes_missing(self.current_seconds), self.current_year)
    end
    self.cards = Cards.build(self.metrics, {
        notice = notice,
        strings = self.strings,
        meta = self.meta,
        in_progress = self.year == self.current_year,
        books = self.book_data,
        other_years = #other_years > 0 and other_years or nil,
    })
end

-- Returns a cover scaled to fit the box, with its size, or nil. A broken cover never stops the card.
function Screen:load_cover(book_id, max_w, max_h, theme)
    local book = self.book_data and self.book_data[book_id]
    -- The cache is searched with the title as stored, and the generated cover shows the clean one.
    local display_title = book and Stats.clean_title(book.title, book.authors)
    if not display_title then
        return nil
    end
    local reader = self:cover_reader()
    local ok, cover = pcall(function() return reader and reader:load(book.title, book.authors) end)
    if not ok or not cover then
        return GeneratedCover.draw(display_title, book.authors, max_w, max_h, Themes[theme])
    end
    local scale = math.min(max_w / cover:getWidth(), max_h / cover:getHeight())
    local w, h = math.max(1, math.floor(cover:getWidth() * scale)), math.max(1, math.floor(cover:getHeight() * scale))
    local scaled_ok, scaled = pcall(RenderImage.scaleBlitBuffer, RenderImage, cover, w, h)
    if not scaled_ok or not scaled then
        cover:free()
        return GeneratedCover.draw(display_title, book.authors, max_w, max_h, Themes[theme])
    end
    return scaled, w, h
end

-- Cards are repainted whenever they come back to the screen, so each cover is built only once per year.
function Screen:cached_cover(book_id, max_w, max_h, theme)
    local key = string.format("%s:%s:%dx%d", theme, tostring(book_id), max_w, max_h)
    local entry = self.covers[key]
    if entry == nil then
        local cover, w, h = self:load_cover(book_id, max_w, max_h, theme)
        entry = cover and { cover = cover, w = w, h = h } or false
        self.covers[key] = entry
    end
    if entry then
        return entry.cover, entry.w, entry.h
    end
end

-- The cover cache is opened on the first cover of a year, and closed with the covers.
function Screen:cover_reader()
    if self.covers_reader == nil then
        self.covers_reader = Store.open_covers(self.covers_db) or false
    end
    return self.covers_reader or nil
end

function Screen:free_covers()
    for _, entry in pairs(self.covers or {}) do
        if entry then
            entry.cover:free()
        end
    end
    self.covers = {}
    if self.covers_reader then
        self.covers_reader:close()
    end
    self.covers_reader = nil
end

function Screen:show_empty(year, seconds)
    self.mode = "empty"
    self.cards = nil
    local width = self.width - 2 * Device_screen:scaleBySize(30)
    local group = VerticalGroup:new{
        align = "center",
        TextBoxWidget:new{ text = self.strings.empty_title, face = Font:getFace("noto/NotoSerif-Bold.ttf", 30), width = width, alignment = "center" },
        VerticalSpan:new{ width = Device_screen:scaleBySize(16) },
        TextBoxWidget:new{
            text = self.strings.empty_body(Cards.minutes_missing(seconds), year),
            face = Font:getFace("noto/NotoSerif-Regular.ttf", 19),
            width = width,
            alignment = "center",
        },
        VerticalSpan:new{ width = Device_screen:scaleBySize(24) },
        Button:new{
            text = self.strings.close,
            width = width,
            padding_v = Device_screen:scaleBySize(10),
            radius = Device_screen:scaleBySize(8),
            bordersize = Device_screen:scaleBySize(2),
            callback = function() UIManager:close(self) end,
        },
    }
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        width = self.width,
        height = self.height,
        CenterContainer:new{ dimen = Geom:new{ w = self.width, h = self.height }, group },
    }
    UIManager:setDirty(self, function()
        return "full", self.dimen
    end)
end

function Screen:footer(index)
    return string.format(self.strings.position, index, #self.cards)
end

-- One flash can leave the edges of a high-contrast card, so the panel can go through white first, as KOReader does before a screensaver image.
function Screen:clear_panel()
    if not self.double_flash or not Device:hasEinkScreen() then
        return
    end
    Device_screen.bb:fill(Blitbuffer.COLOR_WHITE)
    Device_screen:refreshFull(0, 0, self.width, self.height)
    if Device:isKobo() and Device:isSunxi() then
        ffiUtil.usleep(150 * 1000)
    end
end

function Screen:show_card(index)
    self.index = index
    self:clear_panel()
    UIManager:setDirty(self, function()
        return "full", self.dimen
    end)
end

function Screen:paintTo(bb, x, y)
    if self.mode ~= "cards" then
        InputContainer.paintTo(self, bb, x, y)
        return
    end
    self.dimen.x, self.dimen.y = x, y
    local card = self.cards[self.index]
    local options = {
        width = self.width,
        height = self.height,
        strings = self.strings,
        footer = self:footer(self.index),
        cover = self.cover_provider,
        plugin_dir = PLUGIN_DIR,
        theme = self.theme,
        flash_option = Device:hasEinkScreen(),
        double_flash = self.double_flash,
    }
    local ok, overflow = pcall(CardView.paint, bb, card, options)
    if ok then
        self.overflow = overflow
        return
    end
    -- One card that cannot be drawn does not take the others with it: it says so, and the navigation goes on.
    logger.warn("Book Rewind: could not draw the card", card.id, overflow)
    self.overflow = false
    local drawn, err = pcall(CardView.paint_error, bb, options)
    if not drawn then
        logger.warn("Book Rewind: could not draw the error card", err)
    end
end

function Screen:go(delta)
    local target = self.index + delta
    if target >= 1 and target <= #self.cards then
        self:show_card(target)
    end
end

function Screen:open_share()
    local function show()
        UIManager:show(ShareScreen:new{
            cards = self.cards,
            year = self.year,
            language = self.language,
            card_strings = self.strings,
            plugin_dir = PLUGIN_DIR,
            cover = self.cover_provider,
            -- Covers at the size of a story take memory, and the next card rarely needs the same ones.
            after_layer = function() self:free_covers() end,
        })
    end
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenConnected(show)
end

local function inside(rect, pos)
    return pos.x >= rect.x and pos.x < rect.x + rect.w and pos.y >= rect.y and pos.y < rect.y + rect.h
end

function Screen:toggle_double_flash(rect)
    self.double_flash = not self.double_flash
    G_reader_settings:saveSetting(DOUBLE_FLASH_SETTING, self.double_flash)
    local region = Geom:new(rect)
    UIManager:setDirty(self, function()
        return "ui", region
    end)
end

function Screen:onTap(_, ges)
    if self.mode ~= "cards" then
        return false
    end
    if inside(self.close_rect, ges.pos) then
        UIManager:close(self)
        return true
    end
    if self.cards[self.index].id == "cover" and Device:hasEinkScreen() then
        local option = CardView.flash_option_rect(self.width, self.height, self.strings)
        if inside(option, ges.pos) then
            self:toggle_double_flash(option)
            return true
        end
    end
    for _, rect in ipairs(CardView.layout_buttons(self.cards[self.index], self.width, self.height)) do
        if inside(rect, ges.pos) then
            if rect.id == "share" then
                self:open_share()
            elseif rect.id == "restart" then
                self:show_card(1)
            elseif rect.id == "year" then
                self:open_year(rect.year)
            end
            return true
        end
    end
    self:go(ges.pos.x < self.width / 3 and -1 or 1)
    return true
end

function Screen:onSwipe(_, ges)
    if self.mode ~= "cards" then
        return false
    end
    if ges.direction == "west" then
        self:go(1)
        return true
    elseif ges.direction == "east" then
        self:go(-1)
        return true
    end
    return false
end

function Screen:onNextCard()
    if self.mode ~= "cards" then
        return false
    end
    self:go(1)
    return true
end

function Screen:onPreviousCard()
    if self.mode ~= "cards" then
        return false
    end
    self:go(-1)
    return true
end

function Screen:onClose()
    UIManager:close(self)
    return true
end

function Screen:onSetRotationMode()
    return true
end

function Screen:onCloseWidget()
    self:free_covers()
    if self.restore_rotation then
        Device_screen:setRotationMode(self.restore_rotation)
    end
    UIManager:setDirty(nil, "full")
end

return Screen
