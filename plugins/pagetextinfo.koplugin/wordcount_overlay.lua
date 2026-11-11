-- Word counter overlay: per-line word counts on the left, running total on
-- the right, plus session info panels. Replaces the body of paintTo.
--
--   function MyWidget:paintTo(bb, x, y)
--       ...
--       if self.is_enabled then
--           WordCount.paint(self, bb, x, y)
--       end
--   end

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Screen = require("device").screen
local TextWidget = require("ui/widget/textwidget")

local FACE_NAME = "myfont4"
local MIN_WPM_MINUTES = 0.1 -- below this the words-per-minute figure is noise

-- ─── counting words ──────────────────────────────────────────────────────────

-- Typographic characters, as UTF-8 byte strings. Opening quotes disappear
-- (so "“Hola" counts as one word), the closing apostrophe becomes a plain
-- one, and dashes, ellipsis and Spanish/French marks become spaces.
local REPLACE = {
    ["\226\128\152"] = "",   -- ‘
    ["\226\128\156"] = "",   -- “
    ["\226\128\157"] = "",   -- ”
    ["\226\128\153"] = "'",  -- ’
    ["\226\128\148"] = " ",  -- —
    ["\226\128\147"] = " ",  -- –
    ["\226\128\166"] = " ",  -- …
    ["\194\171"] = " ",      -- «
    ["\194\187"] = " ",      -- »
    ["\194\191"] = " ",      -- ¿
    ["\194\161"] = " ",      -- ¡
}

local function countWords(text)
    if not text or text == "" then return 0 end
    text = text:gsub("\226\128[\147\148\152\153\156\157\166]", REPLACE)
    text = text:gsub("\194[\161\171\187\191]", REPLACE)
    -- anything that is not a letter, a digit, an apostrophe or part of a
    -- multibyte character (bytes 128-255, accents included) separates words
    text = text:gsub("[^%w\128-\255']", " ")
    local n = 0
    for token in text:gmatch("%S+") do
        if token:find("[^']") then n = n + 1 end -- a lone apostrophe is no word
    end
    return n
end

-- ─── the lines on the page ───────────────────────────────────────────────────

local function getLineBoxes(self)
    local doc = self.ui.document
    local res = doc:getTextFromPositions({ x = 0, y = 0 },
        { x = Screen:getWidth(), y = Screen:getHeight() }, true) -- do not highlight
    if not (res and res.pos0 and res.pos1) then return nil end
    return doc:getScreenBoxesFromPositions(res.pos0, res.pos1, true)
end

-- What identifies this page's layout: where it starts, the font settings and
-- the shape of its lines. Same signature = same counts, no need to ask the
-- engine for every line again on each repaint.
local function signature(self, boxes)
    local doc = self.ui.document
    local ok, xp = pcall(doc.getXPointer, doc)
    if not ok or not xp then return nil end
    local cfg = doc.configurable or {}
    local parts = { xp, cfg.font_size or "", cfg.line_spacing or "", Screen:getWidth() }
    for _, box in ipairs(boxes) do
        if box.h ~= 0 then parts[#parts + 1] = math.floor(box.x) .. ":" .. math.floor(box.y) .. ":" .. math.floor(box.w) end
    end
    return table.concat(parts, "|")
end

-- The words of each line, by box index (boxes with no height have none).
local function getLineCounts(self, boxes)
    local sig = signature(self, boxes)
    local cache = self._wc_cache
    if sig and cache and cache.sig == sig then return cache.counts end

    local engine = self.ui.document._document
    local width = Screen:getWidth()
    local counts = {}
    for i, box in ipairs(boxes) do
        if box.h ~= 0 then
            local res = engine:getTextFromPositions(box.x, box.y, width, box.y, false, false)
            counts[i] = countWords(res and res.text)
        end
    end
    self._wc_cache = sig and { sig = sig, counts = counts } or nil
    return counts
end

-- ─── drawing ─────────────────────────────────────────────────────────────────

-- Text at x, or ending at right_edge when that is given. The widget is
-- freed after painting: making them without freeing leaks on every repaint.
local function drawText(bb, text, face, x, y, right_edge)
    local widget = TextWidget:new{ text = tostring(text), face = face, fgcolor = Blitbuffer.COLOR_BLACK }
    local px = right_edge and (right_edge - widget:getSize().w) or x
    widget:paintTo(bb, px, y)
    widget:free()
end

local function paintLineCounts(self, bb, x, y)
    local boxes = getLineBoxes(self)
    if not boxes then return end

    local face = Font:getFace(FACE_NAME, self.ui.document.configurable.font_size)
    local right_edge = x + Screen:getWidth()
    local counts = getLineCounts(self, boxes)

    local total = 0 -- running total for this page
    for i, box in ipairs(boxes) do
        if box.h ~= 0 then
            local words = counts[i] or 0
            total = total + words
            -- Hyphenated words split across lines are counted on both; fine.
            drawText(bb, words, face, x, box.y)
            drawText(bb, total, face, nil, box.y, right_edge)
        end
        self.view:drawHighlightRect(bb, x, y, box, "underscore", nil, false)
    end
end

-- ─── the info banner ─────────────────────────────────────────────────────────
-- A small two-line banner at the top right. It builds itself the first time
-- it is painted (so vertical_frame, vg1 and vg2 are no longer needed).

local FrameContainer = require("ui/widget/container/framecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local Size = require("ui/size")

local PANEL_FONT = 11                  -- points; Font:getFace scales it
local PANEL_PADDING = Size.padding.small
local PANEL_MARGIN = Screen:scaleBySize(6) -- distance from the screen's edge
local SEP = "  \194\183  "              -- "  ·  "
local SHOW_CFL = true                  -- characters on the first line

local function ensurePanel(self)
    if self._wc_panel then return self._wc_panel end
    local face = Font:getFace(FACE_NAME, PANEL_FONT)
    local group = VerticalGroup:new{ align = "right" }
    local lines = {}
    for i = 1, 2 do
        lines[i] = TextWidget:new{ text = " ", face = face, fgcolor = Blitbuffer.COLOR_BLACK }
        group[i] = lines[i]
    end
    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.thin,
        radius = Size.radius.default,
        margin = 0,
        padding = PANEL_PADDING,
        group,
    }
    self._wc_panel = { frame = frame, group = group, lines = lines, last = {} }
    return self._wc_panel
end

-- Sets the text of line i, only when it changed (setText relays the line out).
local function setLine(panel, i, text)
    if panel.last[i] == text then return end
    panel.last[i] = text
    panel.lines[i]:setText(text)
    panel.group:resetLayout()
end

local function updateInfoPanels(self)
    local panel = ensurePanel(self)

    -- line 1: the page
    local nblines, nbwords = self.ui.view:getCurrentPageLineWordCounts()
    local parts = { "Lines " .. tostring(nblines or 0), "Words " .. tostring(nbwords or 0) }
    if SHOW_CFL then
        local first = self.ui.document._document:getTextFromPositions(0, 0, Screen:getWidth(), 1, false, true)
        parts[#parts + 1] = "CFL " .. ((first and first.text) and #first.text or 0)
    end
    setLine(panel, 1, table.concat(parts, SEP))

    -- line 2: the session
    local stats = self.ui.statistics
    if stats and stats.start_current_period then
        local minutes = (os.time() - stats.start_current_period) / 60
        local words = stats._total_words or 0
        local wpm = (words > 0 and minutes >= MIN_WPM_MINUTES) and math.floor(words / minutes) or 0
        setLine(panel, 2, string.format("%s w%s%s p%s%s wpm", words, SEP, stats._total_pages or 0, SEP, wpm))
    else
        setLine(panel, 2, "Statistics off")
    end
    return panel
end

-- Single entry point: everything the overlay does in one paintTo.
local function paint(self, bb, x, y)
    paintLineCounts(self, bb, x, y)
    local panel = updateInfoPanels(self)
    local size = panel.frame:getSize()
    panel.frame:paintTo(bb, x + Screen:getWidth() - size.w - PANEL_MARGIN, y + PANEL_MARGIN)
end

return {
    paint = paint,
    countWords = countWords,
    paintLineCounts = paintLineCounts,
    updateInfoPanels = updateInfoPanels,
}
