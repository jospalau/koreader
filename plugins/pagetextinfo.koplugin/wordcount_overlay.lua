-- Word counter overlay: per-line word counts on the left, running total on
-- the right, and a small two-line banner with page and session figures.
--
--   local WordCount = require("wordcount_overlay")
--   ...
--   function MyWidget:paintTo(bb, x, y)
--       ...
--       if self.is_enabled then
--           local ok, err = pcall(WordCount.paint, self, bb, x, y)
--           if not ok then require("logger").warn("wordcount overlay:", err) end
--       end
--   end

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Screen = require("device").screen
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")

-- ─── settings ────────────────────────────────────────────────────────────────

local FACE_NAME = "myfont4"
local PANEL_FONT = 11                      -- points; Font:getFace scales it
local PANEL_PADDING = Size.padding.small
local PANEL_MARGIN = Screen:scaleBySize(6) -- distance from the screen's edge
local SEP = "  \194\183  "                  -- "  ·  "
local SHOW_CFL = true                      -- characters on the first line
local SHOW_CML = true                      -- characters on the page's longest line
local SHOW_RATING = true                   -- next to CML: how good that line length is for reading
-- Rating of the page's longest line, in characters. The longest line sits a few characters above the average, so the
-- comfortable range of print typography (45 to 75 characters, ideal 66) is read a little higher. Each entry holds up to
-- (and including) its limit; the first one that fits gives the label.
local RATING = {
    { 37, "Short" },
    { 49, "Comfortable" },
    { 75, "Excellent" },
    { 80, "Comfortable" },
    { 90, "Still readable" },
    { math.huge, "Too long" },
}
local SHOW_LEGIBILITY = true               -- 3rd line: legibility of the typesetting, 0-100 and its word (legibility.lua)
local SHOW_LEGIBILITY_DETAILS = true       -- and below it one line per parameter: measured value, points it costs, weight
local MIN_WPM_MINUTES = 0.1                -- only for the fallback wpm (stock statistics plugin)

local HYPHEN_FIX = true   -- a word split by a hyphen at the end of a line counts once
local WORDS_FROM = "engine" -- banner's "Words": "engine" (KOReader's count) or "own" (this module's)
local DEBUG = true        -- log, once per page, own vs engine word counts and hyphenated lines
                          -- (set to false once the figures look right)

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

-- The words of one line's text. Returns the count, the first and the last
-- word, and whether the line ends in a hyphenation ("informa-").
local function scanLine(text)
    if not text or text == "" then return 0 end
    local hyphenated = text:find("[%w\128-\255]%-%s*$") ~= nil
    text = text:gsub("\226\128[\147\148\152\153\156\157\166]", REPLACE)
    text = text:gsub("\194[\161\171\187\191]", REPLACE)
    -- numbers: 3.14 and 1,000 are one word
    text = text:gsub("(%d)[.,](%d)", "%1%2")
    -- compounds: "bien-estar" is one word (the hyphen is kept as \1 so the
    -- punctuation pass below leaves it alone; it stays inside the word)
    text = text:gsub("([%w\128-\255])%-([%w\128-\255])", "%1\1%2")
    -- anything that is not a letter, a digit, an apostrophe, a compound's
    -- hyphen or part of a multibyte character (accents included) separates words
    text = text:gsub("[^%w\128-\255'\1]", " ")
    local n, first, last = 0, nil, nil
    for token in text:gmatch("%S+") do
        if token:find("[^']") then -- a lone apostrophe is no word
            n = n + 1
            first = first or token
            last = token
        end
    end
    return n, first, last, hyphenated
end

local function countWords(text)
    return (scanLine(text))
end

-- Characters, not bytes: every byte that is not a UTF-8 continuation byte.
-- Leading/trailing spaces and the paragraph's final newline are not counted.
local function countChars(text)
    if not text then return 0 end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return select(2, text:gsub("[^\128-\191]", ""))
end

-- The label for a line of this many characters (nil for an empty page).
local function rateLine(chars)
    if not chars or chars <= 0 then return nil end
    for _, level in ipairs(RATING) do
        if chars <= level[1] then return level[2] end
    end
end

-- ─── the lines on the page ───────────────────────────────────────────────────

local function getLineBoxes(self)
    local doc = self.ui.document
    local res = doc:getTextFromPositions({ x = 0, y = 0 },
        { x = Screen:getWidth(), y = Screen:getHeight() }, true) -- do not highlight
    if not (res and res.pos0 and res.pos1) then return nil end
    return doc:getScreenBoxesFromPositions(res.pos0, res.pos1, true)
end

-- The engine can return several boxes for one visual line (italics, links,
-- font changes). Asking each one for the text up to the right edge would
-- count the same words again, so the boxes are grouped by line: one entry
-- per y, at the leftmost x.
local function groupLines(boxes)
    local lines, by_y = {}, {}
    for _, box in ipairs(boxes) do
        if box.h ~= 0 then
            local key = math.floor(box.y)
            local line = by_y[key]
            if line then
                line.x = math.min(line.x, box.x)
            else
                line = { x = box.x, y = box.y }
                by_y[key] = line
                lines[#lines + 1] = line
            end
        end
    end
    return lines
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

-- The page's lines and their word counts ({ lines, counts, total }), from
-- the cache when the layout is the same. The second value says whether it
-- was just worked out.
local function getLineCounts(self, boxes)
    local sig = signature(self, boxes)
    local cache = self._wc_cache
    if sig and cache and cache.sig == sig then return cache, false end

    local lines = groupLines(boxes)
    local engine = self.ui.document._document
    local width = Screen:getWidth()
    local counts, total, prev, max_chars = {}, 0, nil, 0
    for i, line in ipairs(lines) do
        local res = engine:getTextFromPositions(line.x, line.y, width, line.y, false, false)
        local n, first, last, hyphenated = scanLine(res and res.text)
        max_chars = math.max(max_chars, countChars(res and res.text))
        if HYPHEN_FIX and prev and n > 0 then
            if prev.last and first == prev.last and #first >= 4 then
                n = n - 1 -- the engine returned the whole word on both lines
            elseif prev.hyphenated then
                n = n - 1 -- it returned the two pieces: "informa-" + "ción"
            end
        end
        if DEBUG and hyphenated then
            logger.info("wordcount: line ends in a hyphen:", res and res.text)
        end
        counts[i] = n
        total = total + n
        prev = { last = last, hyphenated = hyphenated }
    end
    cache = { sig = sig, lines = lines, counts = counts, total = total, max_chars = max_chars }
    self._wc_cache = sig and cache or nil
    return cache, true
end

-- ─── drawing the line counts ─────────────────────────────────────────────────

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
    local data, fresh = getLineCounts(self, boxes)
    self._wc_total = data.total
    self._wc_max_chars = data.max_chars

    if DEBUG and fresh then
        local _, engine_words = self.ui.view:getCurrentPageLineWordCounts()
        logger.info(string.format("wordcount: page words own=%d engine=%s lines=%d",
            data.total, tostring(engine_words), #data.lines))
    end

    local running = 0 -- running total for this page
    for i, line in ipairs(data.lines) do
        local words = data.counts[i] or 0
        running = running + words
        drawText(bb, words, face, x, line.y)
        drawText(bb, running, face, nil, line.y, right_edge)
    end
    for _, box in ipairs(boxes) do
        self.view:drawHighlightRect(bb, x, y, box, "underscore", nil, false)
    end
end

-- ─── the info banner ─────────────────────────────────────────────────────────
-- A small banner at the top right (two lines, three with the legibility). It builds itself the first time
-- it is painted.

local function ensurePanel(self)
    if self._wc_panel then return self._wc_panel end
    local face = Font:getFace(FACE_NAME, PANEL_FONT)
    local group = VerticalGroup:new{ align = "right" }
    local lines = {}
    for i = 1, SHOW_LEGIBILITY and 3 or 2 do
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
    self._wc_panel = { frame = frame, group = group, lines = lines, last = {}, face = face,
                       base = #lines }
    return self._wc_panel
end

-- Lines after the fixed ones (the legibility details): as many as texts, made or removed as needed
local function setExtraLines(panel, texts)
    local want = panel.base + #texts
    local changed = false
    while #panel.lines < want do
        local w = TextWidget:new{ text = " ", face = panel.face, fgcolor = Blitbuffer.COLOR_BLACK }
        panel.lines[#panel.lines + 1] = w
        panel.group[#panel.group + 1] = w
        changed = true
    end
    while #panel.lines > want do
        local i = #panel.lines
        panel.lines[i]:free()
        panel.lines[i] = nil
        panel.group[i] = nil
        panel.last[i] = nil
        changed = true
    end
    if changed then panel.group:resetLayout() end
    for i, text in ipairs(texts) do
        local n = panel.base + i
        if panel.last[n] ~= text then
            panel.last[n] = text
            panel.lines[n]:setText(text)
            changed = true
        end
    end
    if changed then panel.group:resetLayout() end
end

-- Sets the text of line i, only when it changed (setText relays the line out).
local function setLine(panel, i, text)
    if panel.last[i] == text then return end
    panel.last[i] = text
    panel.lines[i]:setText(text)
    panel.group:resetLayout()
end

-- Words per minute of the session. With the patched statistics plugin this
-- is words over the time actually spent reading (_total_read_time, seconds),
-- the same figure the plugin keeps; with the stock one it falls back to the
-- time since the session began.
local function sessionWpm(stats)
    local words = stats._total_words or 0
    if words <= 0 then return 0 end
    if stats._total_read_time then
        local minutes = stats._total_read_time / 60
        return minutes > 0 and math.floor(words / minutes) or 0
    end
    local minutes = (os.time() - stats.start_current_period) / 60
    return minutes >= MIN_WPM_MINUTES and math.floor(words / minutes) or 0
end

local function legibilityText(self)
    if not self.measureLegibility then return "\226\128\147" end
    local ok, err = pcall(self.measureLegibility, self)
    if not ok then logger.warn("wordcount legibility:", err) end
    local tracker, doc = self.legibility, self.ui.document
    local r = tracker and tracker.result
    if not r then return "\226\128\147" end
    local okh, hash = pcall(doc.getDocumentRenderingHash, doc, true)
    if not okh or hash ~= tracker.hash then return "\226\128\147" end -- figure of other settings
    return tracker:label()
end

local function updateInfoPanels(self)
    local panel = ensurePanel(self)

    -- line 1: the page
    local nblines, nbwords = self.ui.view:getCurrentPageLineWordCounts()
    local words_page = (WORDS_FROM == "own" and self._wc_total) or nbwords
    local parts = { "Lines " .. tostring(nblines or 0), "Words " .. tostring(words_page or 0) }
    if SHOW_CFL then
        local first = self.ui.document._document:getTextFromPositions(0, 0, Screen:getWidth(), 1, false, true)
        parts[#parts + 1] = "CFL " .. countChars(first and first.text)
    end
    if SHOW_CML then
        -- worked out by paintLineCounts with the line counts (cached per layout)
        local cml = self._wc_max_chars or 0
        local rating = SHOW_RATING and rateLine(cml)
        parts[#parts + 1] = "CML " .. tostring(cml) .. (rating and (" " .. rating) or "")
    end
    setLine(panel, 1, table.concat(parts, SEP))

    -- line 2: the session
    local stats = self.ui.statistics
    if stats and stats.start_current_period then
        setLine(panel, 2, string.format("%s w%s%s p%s%s wpm",
            stats._total_words or 0, SEP, stats._total_pages or 0, SEP, sessionWpm(stats)))
    else
        setLine(panel, 2, "Statistics off")
    end

    -- line 3: legibility of the typesetting (pagetextinfo measures the page already drawn, once per page; the
    -- last pages with the same settings are pooled). "–" while there is no figure for the current settings
    if SHOW_LEGIBILITY and panel.lines[3] then
        local leg = legibilityText(self)
        setLine(panel, 3, "Legibility " .. leg)
        -- below: every parameter with its value, the points it costs alone and its weight (legibility.lua)
        local details = {}
        if SHOW_LEGIBILITY_DETAILS and self.legibility and leg ~= "\226\128\147" then
            local ok, d = pcall(self.legibility.detailLines, self.legibility)
            if ok and d then details = d end
        end
        setExtraLines(panel, details)
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

-- The banner's figures as plain texts, without painting anything (used by the big legibility message of
-- pagetextinfo). self needs .ui and .view. Returns { page = "Lines 38 · Words 312", chars = "CFL 61 · CML 68
-- Excellent", session = "1234 w · 12 p · 250 wpm" } (session nil with statistics off)
local function pageInfo(self)
    local out = {}
    local nblines, nbwords = self.ui.view:getCurrentPageLineWordCounts()
    local cml
    local boxes = getLineBoxes(self)
    if boxes then
        local data = getLineCounts(self, boxes)
        cml = data.max_chars
        if WORDS_FROM == "own" then nbwords = data.total end
    end
    out.page = "Lines " .. tostring(nblines or 0) .. SEP .. "Words " .. tostring(nbwords or 0)
    local parts = {}
    if SHOW_CFL then
        local first = self.ui.document._document:getTextFromPositions(0, 0, Screen:getWidth(), 1, false, true)
        parts[#parts + 1] = "CFL " .. countChars(first and first.text)
    end
    if SHOW_CML and cml then
        local rating = SHOW_RATING and rateLine(cml)
        parts[#parts + 1] = "CML " .. tostring(cml) .. (rating and (" " .. rating) or "")
    end
    if #parts > 0 then out.chars = table.concat(parts, SEP) end
    local stats = self.ui.statistics
    if stats and stats.start_current_period then
        out.session = string.format("%s w%s%s p%s%s wpm",
            stats._total_words or 0, SEP, stats._total_pages or 0, SEP, sessionWpm(stats))
    end
    return out
end

return {
    pageInfo = pageInfo,
    paint = paint,
    countWords = countWords,
    paintLineCounts = paintLineCounts,
    updateInfoPanels = updateInfoPanels,
}
