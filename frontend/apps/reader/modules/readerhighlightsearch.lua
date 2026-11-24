--[[--
Full-text search of the selected word (not part of upstream KOReader).

On a short long-press over a word (with pagetextinfo active), every occurrence of that
word BEFORE the current reading position is searched (to avoid spoilers) and shown in a
list with context. Tapping a row shows the extended context and allows jumping to it.

This module is not a widget and is not registered in ReaderUI: ReaderHighlight uses it
as a plain table of functions, passing its own instance (`hl`).
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = Device.screen
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextViewer = require("ui/widget/textviewer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local util = require("util")

local ReaderHighlightSearch = {}

local MAX_HITS      = 1000
local PREVIEW_WORDS = 150    -- context words kept for the full preview
local LIST_WORDS    = 15     -- context words per side in the list rows; keep small so every row
                             -- fits the fixed row height and the bold match is never clipped
local LIST_ROWS      = 6      -- rows per page in the results list
local LIST_FONT_DELTA = 3      -- points to subtract from Menu's default row font size (2-4 is sensible)
local SEARCH_FLAGS  = 0x10FF -- CRE default flags + MATCH_WHOLE_WORDS
-- Font size is chosen so that the x-height of the book font is this many millimetres
-- (same measurement as PageTextInfo:getCurrentXHeightMm in main.lua). nil = keep KOReader's own sizes.
local LIST_XHEIGHT_MM    = 1.8   -- results list (the first screen)
local PREVIEW_XHEIGHT_MM = 1.5   -- extended context of one occurrence (after tapping a row)
-- Occurrences inside the table of contents or an index are left out of the results. A hit counts as one when
-- the chapter title it falls under (from the book's own table of contents) starts with one of these words.
-- Limit: a contents page that is not itself listed in the table of contents is not detected.
local SKIP_INDEX_SECTIONS = true
local INDEX_TITLES = {
    "index", "indice", "índice", "Índice", "contents", "table of contents", "contenido", "tabla de contenido",
    "sumario", "sommaire", "table des mati", "inhalt", "inhaltsverzeichnis", "indholds", "register",
}
-- Only these fields cross back from the subprocess ("page" is computed there).
local FIELDS = { "prev_text", "matched_word_prefix", "matched_text",
                 "matched_word_suffix", "next_text", "start", "end" }

-- Keep the first or last `max_words` words of a string.
local function trimWords(s, max_words, keep_last)
    if not s or s == "" then return s end
    local words = {}
    for w in s:gmatch("%S+") do words[#words + 1] = w end
    if #words <= max_words then return s end
    local first = keep_last and (#words - max_words + 1) or 1
    local last  = keep_last and #words or max_words
    return table.concat(words, " ", first, last)
end

-- Build the rich text: context before, bold match, context after.
local function buildContext(r, text)
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local parts = { TextBoxWidget.PTF_HEADER }
    if r.prev_text and r.prev_text ~= "" then
        table.insert(parts, r.prev_text)
        if not r.prev_text:find("%s$") then table.insert(parts, " ") end
    end
    table.insert(parts, TextBoxWidget.PTF_BOLD_START)
    table.insert(parts, r.matched_word_prefix or "")
    table.insert(parts, r.matched_text or text)
    table.insert(parts, r.matched_word_suffix or "")
    table.insert(parts, TextBoxWidget.PTF_BOLD_END)
    if r.next_text and r.next_text ~= "" then
        if not r.next_text:find("^[%s%p]") then table.insert(parts, " ") end
        table.insert(parts, r.next_text)
    end
    return table.concat(parts)
end

-- Returns the font file (and face index) used by the book, or nil to keep the UI font.
-- The face name -> file lookup lives in the cre library, not in the document object.
local function getBookFontFile(ui)
    local document = ui.document
    local face_name = ui.font and ui.font.font_face
    if not face_name and type(document.getFontFace) == "function" then
        local okn, n = pcall(document.getFontFace, document)
        if okn then face_name = n end
    end
    if not face_name then
        logger.info("highlight search: book font name not found")
        return nil
    end
    local okc, cre = pcall(require, "libs/libkoreader-cre")
    if not okc or type(cre) ~= "table" or type(cre.getFontFaceFilenameAndFaceIndex) ~= "function" then
        logger.info("highlight search: cre.getFontFaceFilenameAndFaceIndex not available")
        return nil
    end
    local ok, filename, faceindex = pcall(cre.getFontFaceFilenameAndFaceIndex, face_name)
    if not ok or type(filename) ~= "string" or filename == "" then
        logger.info("highlight search: no font file for", face_name)
        return nil
    end
    logger.info("highlight search: using book font", face_name, filename, faceindex)
    return filename, faceindex
end

-- Font size (in the unscaled units Font:getFace and Menu/TextViewer use) at which the x-height of
-- `font_file` is `target_mm`. The x-height is linear in the size, so one measurement at a probe
-- size is enough (the ratio is cached per file). Returns nil if it cannot be measured.
local xheight_ratio = {}   -- font file -> x-height / px size
local function sizeForXHeight(font_file, target_mm)
    if not font_file or not target_mm then return nil end
    local Device = require("device")
    local Font = require("ui/font")
    local dpi = Device:getDeviceScreenDPI() or Screen:getDPI()
    if not dpi or dpi <= 0 then return nil end
    local ratio = xheight_ratio[font_file]
    if not ratio then
        local probe = 40
        local ok, face = pcall(Font.getFace, Font, font_file, probe)
        if not ok or not face or not face.ftsize then return nil end
        local okx, xh = pcall(face.ftsize.getXHeight, face.ftsize)
        if not okx or type(xh) ~= "number" or xh <= 0 then return nil end
        local px = Screen:scaleBySize(probe)
        -- getXHeight returns either a ratio of the size (< 1) or pixels
        local xh_px = (xh < 1) and (xh * px) or xh
        ratio = xh_px / px
        xheight_ratio[font_file] = ratio
    end
    -- pixels needed for the target, then back to unscaled units (Screen:scaleBySize is linear)
    local want_px = target_mm * dpi / 25.4
    local size = want_px / ratio * 100 / Screen:scaleBySize(100)
    size = math.floor(size * 10 + 0.5) / 10
    if size < 8 or size > 60 then return nil end   -- implausible: keep the default
    return size
end

-- TextViewer has no font parameter: its face is built in init() from Font.fontmap
-- ("x_smallinfofont"). Remap that entry while the viewer is being built, then restore it.
local function newTextViewerWithFont(font_file, args, font_size)
    local Font = require("ui/font")
    local key = "x_smallinfofont"
    local old = Font.fontmap[key]
    if font_file and old then Font.fontmap[key] = font_file end
    local ok, res = pcall(function()
        local viewer = TextViewer:new(args)
        if font_size then
            -- TextViewer reads its size from the saved settings, not from the arguments: set it and lay out again
            -- (init(true), not reinit(), which would also save the size as the user's own setting)
            viewer.text_font_size = font_size
            viewer:init(true)
        end
        return viewer
    end)
    Font.fontmap[key] = old
    if not ok then error(res, 0) end
    return res
end

-- Menu does not pass a font to its rows: every MenuItem builds its face from
-- Font.fontmap["smallinfofont"] each time the page is (re)drawn. Subclass Menu so that
-- entry points to the book font while updateItems() runs.
local function newBookMenuClass(Menu, font_file)
    local BookMenu = Menu:extend{}
    function BookMenu:updateItems(...)
        local Font = require("ui/font")
        local key = "smallinfofont"
        local old = Font.fontmap[key]
        if font_file and old then Font.fontmap[key] = font_file end
        local ok, res = pcall(Menu.updateItems, self, ...)
        Font.fontmap[key] = old
        if not ok then error(res, 0) end
        return res
    end
    return BookMenu
end

---------------------------------------------------------------------------
-- "Searching" widget: magnifier badge, the word, animated dots, cancel hint
---------------------------------------------------------------------------

local TICK_SECONDS = 0.4   -- animation step of the dots

-- Row of dots; one is black, its neighbours fade out. Drawn by hand (no child widgets).
local DotsWidget = Widget:extend{
    count = 5,
    active = 1,
}

function DotsWidget:init()
    self.dot = Screen:scaleBySize(12)
    self.gap = Screen:scaleBySize(12)
    self.dimen = Geom:new{
        w = self.count * self.dot + (self.count - 1) * self.gap,
        h = self.dot,
    }
end

function DotsWidget:step()
    self.active = self.active % self.count + 1
end

function DotsWidget:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    for i = 1, self.count do
        local dist = math.abs(i - self.active)
        local color = dist == 0 and Blitbuffer.COLOR_BLACK
            or dist == 1 and Blitbuffer.COLOR_DARK_GRAY
            or Blitbuffer.COLOR_LIGHT_GRAY
        bb:paintRoundedRect(x + (i - 1) * (self.dot + self.gap), y, self.dot, self.dot,
                            color, math.floor(self.dot / 2))
    end
end

-- Tap anywhere (or any key) dismisses it. It sets/calls `dismiss_callback` like InfoMessage does,
-- so Trapper:dismissableRunInSubprocess can use it as its trap widget.
local SearchingWidget = InputContainer:extend{
    word = "",
    dismiss_callback = nil,
}

function SearchingWidget:init()
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local inner_w = math.floor(math.min(screen_w, screen_h) * 0.55)

    -- Magnifier inside a round badge.
    local icon_size = Screen:scaleBySize(56)
    local badge_pad = Screen:scaleBySize(14)
    local badge_border = Size.border.thick
    local badge_size = icon_size + 2 * badge_pad + 2 * badge_border
    local badge = FrameContainer:new{
        radius = math.floor(badge_size / 2),
        bordersize = badge_border,
        padding = badge_pad,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        IconWidget:new{ icon = "appbar.search", width = icon_size, height = icon_size },
    }

    local title = TextWidget:new{
        text = "Searching…",
        face = Font:getFace("tfont", 22),
    }
    local word = TextBoxWidget:new{
        text = "“" .. self.word .. "”",
        face = Font:getFace("tfont", 28),
        width = inner_w,
        alignment = "center",
    }
    self.dots = DotsWidget:new{}
    local hint = TextWidget:new{
        text = "Tap to cancel",
        face = Font:getFace("cfont", 16),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    }
    local function gap(n) return VerticalSpan:new{ width = Screen:scaleBySize(n) } end

    self.frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius = Size.radius.window,
        padding = Screen:scaleBySize(24),
        margin = 0,
        VerticalGroup:new{
            align = "center",
            badge, gap(14), title, gap(8), word, gap(18), self.dots, gap(18), hint,
        },
    }
    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = screen_w, h = screen_h },
        self.frame,
    }

    self.ges_events = {
        TapClose = { GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = 0, y = 0, w = screen_w, h = screen_h },
        } },
    }
    if Device:hasKeys() then
        self.key_events = { AnyKeyPressed = { { Device.input.group.Any } } }
    end
end

function SearchingWidget:dismiss()
    UIManager:close(self)
    if self.dismiss_callback then self.dismiss_callback() end
    return true
end
function SearchingWidget:onTapClose() return self:dismiss() end
function SearchingWidget:onAnyKeyPressed() return self:dismiss() end

function SearchingWidget:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
    self._tick = function()
        if self._closed then return end
        self.dots:step()
        UIManager:setDirty(self, function() return "fast", self.dots.dimen end)
        UIManager:scheduleIn(TICK_SECONDS, self._tick)
    end
    UIManager:scheduleIn(TICK_SECONDS, self._tick)
    return true
end

function SearchingWidget:onCloseWidget()
    self._closed = true
    if self._tick then UIManager:unschedule(self._tick) end
    UIManager:setDirty(nil, function() return "ui", self.frame.dimen end)
end

---------------------------------------------------------------------------
-- Short long-press trigger (used from ReaderHighlight:onHold/onHoldRelease)
---------------------------------------------------------------------------

-- Call when a long-press starts.
function ReaderHighlightSearch:onHoldStart(hl)
    hl.t1 = os.time()
end

-- Short wait before processing hold_release.
function ReaderHighlightSearch:waitHoldRelease()
    ffiUtil.usleep(350000)
end

-- true if the long-press just released was short (< 2 s) and pagetextinfo is present.
function ReaderHighlightSearch:isQuickHold(hl)
    hl.t2 = os.time()
    return (hl.ui.pagetextinfo and hl.t1 and hl.t2 and hl.t2 - hl.t1 < 2) and true or false
end

-- Action to run when isQuickHold() is true.
function ReaderHighlightSearch:onQuickHoldRelease(hl)
    if hl.selected_text then
        UIManager:broadcastEvent(Event:new("ClearLocationStack"))
        self:search(hl)
    end
end

---------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------

function ReaderHighlightSearch:search(hl)
    logger.dbg("search highlight")
    -- Close the highlight dialog if it is still shown.
    if hl.highlight_dialog then
        UIManager:close(hl.highlight_dialog)
        hl.highlight_dialog = nil
    end
    hl:highlightFromHoldPos()
    if not hl.selected_text then return end

    local text = util.stripPunctuation(util.cleanupSelectedText(hl.selected_text.text))
    -- Save the position BEFORE clear(), which resets it.
    local selected_position = hl.selected_text.pos0 or hl.selected_text_start_xpointer
    hl:clear()
    if text == "" then return end

    local ui = hl.ui
    local document = ui.document

    -- true if the xpointer falls in a chapter whose title looks like a table of contents / an index
    local function inIndexSection(xp)
        if not SKIP_INDEX_SECTIONS or not xp or not ui.toc or not ui.toc.getTocTitleByPage then return false end
        local okp, page = pcall(document.getPageFromXPointer, document, xp)
        if not okp or type(page) ~= "number" then return false end
        local okt, title = pcall(ui.toc.getTocTitleByPage, ui.toc, page)
        if not okt or type(title) ~= "string" or title == "" then return false end
        local lower = title:lower()
        for _, pat in ipairs(INDEX_TITLES) do
            local p = pat:gsub("%p", "%%%0")
            if title:find("^%s*" .. p) or lower:find("^%s*" .. p) then return true end
        end
        return false
    end
    ui.search.start_page = ui.paging and hl.view.state.page or document:getXPointer()

    -- PDF/DjVu (or no findAllText): keep the original behaviour.
    if ui.paging or type(document.findAllText) ~= "function" then
        ui.search:fullTextSearch(text)
        return
    end

    local Menu    = require("ui/widget/menu")
    local Trapper = require("ui/trapper")

    local showResults, showPreview

    -- Full-context view of a single occurrence.
    showPreview = function(result, n, data)
        local viewer
        local book_font = getBookFontFile(ui)
        local title = string.format("%s — %d/%d", text, n, #data)
        if result.page then
            title = title .. string.format(" · p. %s", tostring(result.page))
        end
        viewer = newTextViewerWithFont(book_font, {
            title = title,
            text = buildContext(result, text),
            text_type = "lookup",
            height = math.floor(Screen:getHeight() * 0.82),
            buttons_table = {{
                {
                    text = "Go to",
                    callback = function()
                        UIManager:close(viewer)
                        if result.start then
                            -- Remember where we were so the user can come back.
                            ui.link:addCurrentLocationToStack()
                            -- Second argument marks the target line, as in the normal search.
                            ui.rolling:onGotoXPointer(result.start, result.start)

                            -- Temporarily highlight the match.
                            if result["end"] then
                                local ok, boxes = pcall(document.getScreenBoxesFromPositions,
                                                        document, result.start, result["end"], true)
                                if ok and boxes and #boxes > 0 then
                                    hl.view.highlight.temp[document:getCurrentPage()] = boxes
                                    UIManager:setDirty(hl.dialog, "ui")
                                end
                            end
                        end
                    end,
                },
            }},
            -- Back to the list when the preview is closed.
            close_callback = function()
                UIManager:nextTick(function() showResults(data) end)
            end,
        }, sizeForXHeight(book_font, PREVIEW_XHEIGHT_MM))
        UIManager:show(viewer)
    end

    -- List of occurrences, one compact passage per row.
    showResults = function(data)
        local book_font = getBookFontFile(ui)
        local items = {}
        for i, r in ipairs(data) do
            -- Shorter excerpts in the list; the preview keeps the full context.
            local short = {
                prev_text = trimWords(r.prev_text, LIST_WORDS, true),
                matched_word_prefix = r.matched_word_prefix,
                matched_text = r.matched_text,
                matched_word_suffix = r.matched_word_suffix,
                next_text = trimWords(r.next_text, LIST_WORDS, false),
            }
            table.insert(items, {
                text = buildContext(short, text),
                -- Page number shown on the right of each row.
                mandatory = r.page and tostring(r.page) or nil,
                result = r,
                n = i,
            })
        end
        local count = #data .. (#data >= MAX_HITS and "+" or "")
        -- Default row font size for this many rows per page, minus a few points.
        local base_size = type(Menu.getItemFontSize) == "function"
            and Menu.getItemFontSize(LIST_ROWS) or 20
        local menu = newBookMenuClass(Menu, book_font):new{
            title = text,
            subtitle = string.format("%s occurrences before this point · tap a passage to read more", count),
            item_table = items,
            -- Fixed number of rows per page => uniform row height. Do NOT set items_max_lines:
            -- it switches Menu to variable-height rows and variable-size pages.
            items_per_page = LIST_ROWS,
            items_font_size = sizeForXHeight(book_font, LIST_XHEIGHT_MM) or math.max(10, base_size - LIST_FONT_DELTA),
            multilines_forced = true,
            covers_fullscreen = true,
            is_borderless = true,
            is_popout = false,
            title_bar_fm_style = true,
            onMenuChoice = function(this_menu, item)
                if not item or not item.result then return end
                -- Close the list before opening another interactive window.
                UIManager:close(this_menu)
                UIManager:nextTick(function() showPreview(item.result, item.n, data) end)
            end,
        }
        UIManager:show(menu)
    end

    local searching = SearchingWidget:new{ word = text }
    UIManager:show(searching)
    UIManager:forceRePaint()

    -- Run the document-wide search outside the UI thread.
    Trapper:wrap(function()
        local completed, payload = Trapper:dismissableRunInSubprocess(function()
            local ok, res = pcall(function()
                -- Without a way to compare positions we cannot rule out spoilers:
                -- show nothing rather than risk it.
                if not selected_position or type(document.compareXPointers) ~= "function" then
                    return { error = "Cannot determine reading position" }
                end

                -- Search the whole document (last argument false): with untilCurrentPage
                -- the engine may stop before the current page and miss its hits.
                -- Spoilers are prevented by the position filter below instead.
                local results = document:findAllText(
                    text, true, PREVIEW_WORDS, MAX_HITS, false, SEARCH_FLAGS, false) or {}

                -- Keep only hits that end before the selected word, including those
                -- on the current page (results come in document order).
                local out = {}
                for _, r in ipairs(results) do
                    local okc, cmp = pcall(document.compareXPointers, document,
                                           r["end"], selected_position)
                    -- compareXPointers(a, b): 1 if b follows a, 0 if equal, -1 if a follows b
                    if not okc or cmp == nil or cmp < 0 then break end
                    if inIndexSection(r.start) then goto next_hit end
                    local c = {}
                    for _, f in ipairs(FIELDS) do c[f] = r[f] end
                    -- Stable page label if the book has the page map enabled;
                    -- otherwise the engine's page number.
                    if r.start then
                        local label
                        local pagemap = ui.pagemap
                        if pagemap and pagemap.wantsPageLabels and pagemap:wantsPageLabels() then
                            local okl, l = pcall(pagemap.getXPointerPageLabel, pagemap, r.start, true)
                            if okl then label = l end
                        end
                        if not label then
                            local okp, page = pcall(document.getPageFromXPointer, document, r.start)
                            if okp then label = page end
                        end
                        c.page = label
                    end
                    out[#out + 1] = c
                    ::next_hit::
                end
                return out
            end)
            if ok then return res end
            return { error = tostring(res) }
        end, searching)

        -- Search was dismissed by the user.
        if not completed then return end
        UIManager:close(searching)
        -- The book may have been closed while searching.
        if not hl.ui or not hl.ui.document then return end

        if type(payload) ~= "table" or payload.error then
            UIManager:show(InfoMessage:new{
                text = "Search failed" .. (payload and payload.error and ("\n" .. payload.error) or ""),
            })
            return
        end
        if #payload == 0 then
            UIManager:show(InfoMessage:new{ text = "No earlier occurrences found for: " .. text })
            return
        end
        hl.ui.document:clearSelection()
        showResults(payload)
    end)
end

return ReaderHighlightSearch
