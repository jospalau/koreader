-- Module loaded from the plugin's main.lua, at the top level (while the plugin loads):
--
--     require("highlight_translate_vocabulary_words")(PageTextInfo)
--
-- Note: no ".lua" in the name, or require looks for highlight_translate_vocabulary_words/lua.lua.
-- The file must be in the plugin folder, next to main.lua.

local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local ffiUtil = require("ffi/util")
local left_container = require("ui/widget/container/leftcontainer")
local Screen = require("device").screen
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local util = require("util")

return function(PageTextInfo)

local function tailAfterFirstHyphen(str)
    local pos = str:find("-")
    return pos and str:sub(pos + 1) or str
end

local function nestedTail(str, depth)
    local segment = tailAfterFirstHyphen(str)
    for _ = 2, depth do
        segment = tailAfterFirstHyphen(segment)
    end
    return segment
end

local function findBestHyphenatedMatch(doc, hyphenatedWord)
    local attempts = {
        tailAfterFirstHyphen(hyphenatedWord),       -- nivel 1
        nestedTail(hyphenatedWord, 2),              -- nivel 2
        nestedTail(hyphenatedWord, 3),              -- nivel 3
        nestedTail(hyphenatedWord, 4),              -- nivel 4
        nestedTail(hyphenatedWord, 5),              -- nivel 5
        (hyphenatedWord:gsub("%-", "")),            -- sin guiones
    }

    for _, suggestion in ipairs(attempts) do
        local found = doc:findText(suggestion, 1, false, true, -1, false, 1)
        if found then return found end
    end

    return nil
end

function PageTextInfo:updateNotes()
    -- self.search:fullTextSearch("Citra")
    self.pages_notes = {}
    self.notes = {}
    local annotations = self.ui.annotation.annotations
    local res = self.document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(), false)
    if res and res.text then
        local t = util.splitToWords2(res.text) -- contar palabras
        local words_page = {}
        for i=1, #t do
            words_page[t[i]] = "";
        end
        if words_page and annotations then
            for i, item in ipairs(annotations) do
                local words = nil
                local hyphenated = false
                if words_page[item.text] then
                    if t[1] == item.text then -- If first word is hyphenated
                        local cre = require("libs/libkoreader-cre")
                        local hyphenation = cre.getHyphenationForWord(item.text)

                        if hyphenation:find("-") then
                            hyphenated = true
                            words = findBestHyphenatedMatch(self.document, hyphenation)
                        else
                            words = self.document:findText(item.text, 1, false, true, -1, false, 1)
                        end
                    else
                        words = self.document:findText(item.text, 1, false, true, -1, false, 60)
                    end
                    -- words = self.document:findText(item.text, 1, false, true, -1, false, 30)
                    if words then
                        if item.note and not item.text:find("%s+") then
                            table.insert(self.notes, item)
                            for i, word in ipairs(words) do
                                word.note = item.note
                                word.text = item.text
                                if hyphenated then
                                    word.hyphenated = true
                                else

                                end
                                local page = self.document:getPageFromXPointer(word.start)
                                if not self.pages_notes[page] then
                                    self.pages_notes[page]={}
                                end
                                table.insert(self.pages_notes[page], word)
                                local page2 = self.document:getPageFromXPointer(word["end"])
                                if not self.pages_notes[page2] then
                                    self.pages_notes[page2]={}
                                end
                                table.insert(self.pages_notes[page2], word)
                            end
                        end
                    end
                end
            end
        end
    end
    self.ui.document:clearSelection()
end

local function removeDupes(tab)
    local seen = {}
    local result = {}
    for _, val in ipairs(tab) do
        if not seen[val] then
            seen[val] = true
            table.insert(result, val)
        end
    end
    return result
end

function PageTextInfo:drawXPointerSavedHighlightNotes(bb, x, y)
    -- Getting screen boxes is done for each tap on screen (changing pages,
    -- showing menu...). We might want to cache these boxes per page (and
    -- clear that cache when page layout change or highlights are added
    -- or removed).
    -- Even in page mode, it's safer to use pos and ui.dimen.h
    -- than pages' xpointers pos, even if ui.dimen.h is a bit
    -- larger than pages' heights
    local cur_view_top = self.document:getCurrentPos()
    local cur_view_bottom
    if self.view_mode == "page" and self.document:getVisiblePageCount() > 1 then
        cur_view_bottom = cur_view_top + 2 * self.ui.dimen.h
    else
        cur_view_bottom = cur_view_top + self.ui.dimen.h
    end
    local colorful
--    if true then
--        local dump = require("dump")
--        UIManager:show( require("ui/widget/textviewer"):new{text = dump(self.ui.notes)})
--    end
--
    if self.pages_notes[self.ui.view.state.page] then
        for _, item in ipairs(self.pages_notes[self.ui.view.state.page]) do
            -- document:getScreenBoxesFromPositions() is expensive, so we
            -- first check if this item is on current page
            local start_pos = self.document:getPosFromXPointer(item.start)
            --if start_pos > cur_view_bottom then return colorful end -- this and all next highlights are after the current page
            local end_pos = self.document:getPosFromXPointer(item["end"])
            if end_pos >= cur_view_top then
                local boxes = self.document:getScreenBoxesFromPositions(item.start, item["end"], true) -- get_segments=true
                if boxes then
                    local word = self.ui.document._document:getTextFromPositions(boxes[1].x, boxes[1].y, boxes[1].x, boxes[1].y, false, false)
                    word.text = word.text:match("[A-Za-zÁÉÍÓÚÜÑáéíóúüñ']+$") or word.text
                    if (item.hyphenated and word.text:upper() == item.text:upper()) or word.text:upper() == item.text:upper() then
                        if item.hyphenated and word.text:upper() == item.text:upper() then
                            boxes = self.document:getScreenBoxesFromPositions(word.pos0, word.pos1, true)
                        else
                            boxes = self.document:getScreenBoxesFromPositions(item.start, word.pos1, true)
                        end
                        if boxes then
                            for _, box in ipairs(boxes) do
                                if box.h ~= 0 then
                                    local mark = FrameContainer:new{
                                        left_container:new{
                                            dimen = Geom:new(),
                                            TextWidget:new{
                                                text =  "\u{EB4D}",
                                                face = Font:getFace("symbols", 12),
                                                fgcolor = Blitbuffer.COLOR_BLACK,
                                            },
                                        },
                                        -- background = Blitbuffer.COLOR_WHITE,
                                        bordersize = 0,
                                        padding = 0,
                                        padding_bottom = self.bottom_padding,
                                    }
                                    -- self.ui.view:drawHighlightRect(bb, x, y, box, "underscore", nil, false)
                                    mark:paintTo(bb, box.x, box.y)
                                end
                            end
                        end
                        if item.hyphenated then
                            if boxes then
                                for _, box in ipairs(boxes) do
                                    if box.h ~= 0 then
                                        local mark = FrameContainer:new{
                                            left_container:new{
                                                dimen = Geom:new(),
                                                TextWidget:new{
                                                    text =  "\u{EB4D}",
                                                    face = Font:getFace("symbols", 12),
                                                    fgcolor = Blitbuffer.COLOR_BLACK,
                                                },
                                            },
                                            -- background = Blitbuffer.COLOR_WHITE,
                                            bordersize = 0,
                                            padding = 0,
                                            padding_bottom = self.bottom_padding,
                                        }
                                        -- self.ui.view:drawHighlightRect(bb, x, y, box, "underscore", nil, false)
                                        mark:paintTo(bb, box.x, box.y)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return colorful
end

-- Extracts the shortest, cleanest translation from a dictionary definition.
-- Tries each line in order, preferring short lines that look like translations
-- (Spanish accents, semicolons, commas) and discarding headers and long prose.
local function extractDefinition(def)
    if not def or def == "" then return "" end

    -- Strip HTML tags and normalize whitespace
    def = def:gsub("%b<>", ""):gsub("[\r\n]+", "\n"):gsub("&nbsp;", " "):gsub("&[a-z]+;", "")

    local lines = {}
    for line in def:gmatch("[^\n]+") do
        local clean = line:match("^%s*(.-)%s*$")
        if clean and clean ~= "" then
            table.insert(lines, clean)
        end
    end

    local function score(line)
        -- Strip leading numbering and part-of-speech labels: "1. ", "adj. ", "v. "
        local s = line:gsub("^%d+[%.%)%)]%s*", ""):gsub("^%a+[%.%)%)]%s*", "")
        -- Too short or too long to be a useful inline gloss
        if #s < 2 or #s > 60 then return nil end
        -- Must contain at least one letter
        if not s:match("%a") then return nil end
        return s
    end

    -- First pass: prefer lines with Spanish diacritics, semicolons or commas
    -- (strong signals that this is a translation, not an English-only definition)
    for _, line in ipairs(lines) do
        local s = score(line)
        if s and (s:match("[áéíóúüñÁÉÍÓÚÜÑ]") or s:match("[,;]")) then
            return s
        end
    end

    -- Second pass: accept any short line that looks like a word or phrase
    for _, line in ipairs(lines) do
        local s = score(line)
        if s then return s end
    end

    return lines[#lines] or def
end

-- Truncates a translation to fit comfortably as an inline gloss.
-- Cuts at the first separator (, ; () and trims to max_len characters.
local function formatTranslation(text, max_len)
    if not text or text == "" then return "" end
    max_len = max_len or 50

    -- Split on , or ; and take first 3 alternatives
    local parts = {}
    for part in text:gmatch("[^,;]+") do
        local p = part:match("^%s*(.-)%s*$")
        -- Skip parts that look like grammar labels: "vtr", "adj", etc.
        if p and #p > 1 and not p:match("^%a%a?%a?%.?$") then
            table.insert(parts, p)
            if #parts >= 3 then break end
        end
    end

    local result = table.concat(parts, " / ")
    if #result > max_len then
        result = result:sub(1, max_len - 1) .. "…"
    end
    return result ~= "" and result or text
end

-- Queries the dictionary for a word and returns a short inline gloss.
-- Tries each result in order until one yields a non-empty translation,
-- so that if WordReference fails Babylon is used as fallback.
local DICTIONARIES = { "WordReference_EN_ES", "Babylon English-Spanish" }

function getTranslation(self, word)
    -- Normalise to lowercase so "Have" and "have" share the same cache entry.
    local key = word:lower()
    if self.translations[key] then
        return self.translations[key]
    end

    local results = self.ui.dictionary:startSdcv(key, DICTIONARIES, true, true)

    -- If the preferred dictionaries have no entry for this word, fall back to
    -- whatever dictionaries are installed.
    if not results or #results == 0 then
        results = self.ui.dictionary:startSdcv(key, nil, true, true)
    end

    local translation = ""

    if results then
        for _, result in ipairs(results) do
            if result.definition then
                local candidate = extractDefinition(result.definition)
                if candidate and candidate ~= "" then
                    translation = formatTranslation(candidate)
                    break
                end
            end
        end
    end

    self.translations[key] = translation
    return translation
end

-- ─────────────────────────────────────────────────────────────────────────────

local DEBUG_VOCAB = false  -- flip to false to silence
local dbg = require("dbg")
local function dbg_vocab(fmt, ...)
    if DEBUG_VOCAB then
        dbg(string.format("[vocab-paint] " .. fmt, ...))
    end
end


-- Returns the ascender ratio for the given font name.
-- The ascender defines where the baseline sits within the line box.
local function getFontAscenderRatio(font_name)
    if font_name:find(".*UglyQua.*") or font_name:find(".*Literata.*")
        or font_name:find(".*BitterPro.*") or font_name:find(".*ChartereBook.*") then
        return 0.90
    elseif font_name:find(".*Chare.*") then
        return 0.72
    elseif font_name:find(".*Vollkorn.*") or font_name:find(".*Garamond.*")
        or font_name:find(".*APHont.*") or font_name:find(".*Thesis.*") then
        return 0.68
    end
    return 0.80
end

-- Computes the y coordinate of the baseline for a given bounding box and font.
local function getBaseline(box, font_name)
    local ratio    = getFontAscenderRatio(font_name)
    local ascender = box.h * ratio
    local baseline = box.y + ascender
    dbg_vocab("getBaseline: font=%s ratio=%.2f box={x=%s,y=%s,w=%s,h=%s} → baseline=%.1f",
        font_name, ratio, box.x, box.y, box.w, box.h, baseline)
    return baseline
end

-- Paints an underline at the baseline of each non-empty box.
local function paintBaselines(bb, boxes, font_name)
    dbg_vocab("paintBaselines: %d boxes, font=%s", #boxes, font_name)
    for i, box in ipairs(boxes) do
        dbg_vocab("  box[%d]: x=%s y=%s w=%s h=%s", i, box.x, box.y, box.w, box.h)
        if box.h == 0 then
            dbg_vocab("  box[%d]: SKIPPED — h is zero", i)
        else
            local y_baseline = getBaseline(box, font_name)
            dbg_vocab("  box[%d]: painting underline at y=%.1f", i, y_baseline)
            bb:paintRect(box.x, y_baseline, box.w, Size.line.thick, nil)
        end
    end
end

-- Paints a floating translation label above a bounding box.
-- Horizontally positions the label depending on where the box falls on screen:
--   left quarter  → align label to the left edge of the word
--   right quarter → align label to the right edge of the word
--   centre        → centre label over the word
-- Paints a floating translation label above a bounding box.
-- The label has a light-gray background and slightly dimmed text so it reads
-- as an annotation rather than body text.
-- Horizontal alignment:
--   left quarter  → align to the left edge of the word
--   right quarter → align to the right edge of the word
--   centre        → centre over the word
local function paintTranslationLabel(bb, box, translation, font_face, font_size, bottom_padding)
    if not translation or translation == "" then
        dbg_vocab("paintTranslationLabel: SKIPPED — translation is nil or empty")
        return
    end
    dbg_vocab("paintTranslationLabel: text=%q font_size=%s box={x=%s,y=%s,w=%s,h=%s}",
        translation, font_size, box.x, box.y, box.w, box.h)

    local label = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            TextWidget:new{
                text    = translation,
                face    = font_face,
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            },
        },
        background     = Blitbuffer.COLOR_LIGHT_GRAY,
        bordersize     = 0,
        padding        = 1,
        padding_bottom = bottom_padding,
    }

    local label_w  = label[1][1]:getSize().w
    local screen_w = Screen:getWidth()
    local label_x

    if box.x < screen_w / 4 then
        label_x = box.x
        dbg_vocab("  label alignment: LEFT edge (box.x=%s < screen_w/4=%s)", box.x, screen_w/4)
    elseif box.x > screen_w - screen_w / 4 then
        label_x = box.x + box.w - label_w
        dbg_vocab("  label alignment: RIGHT edge (box.x=%s > %s)", box.x, screen_w - screen_w/4)
    else
        label_x = box.x + box.w / 2 - label_w / 2
        dbg_vocab("  label alignment: CENTRE")
    end

    local label_y = box.y + font_size / 2
    dbg_vocab("  label_w=%s label_x=%s label_y=%s screen_w=%s", label_w, label_x, label_y, screen_w)
    label:paintTo(bb, label_x, label_y)
end

-- ─────────────────────────────────────────────────────────────────────────────

-- Returns the capitalisation variants to search for a given vocabulary word.
-- "have" → { "have", "Have", "HAVE" }
-- Duplicates are removed (e.g. "I" would not produce "i" and "I" twice).
local function wordVariants(word)
    local lower      = word:lower()
    local capitalized = lower:gsub("^%l", string.upper)
    local upper      = word:upper()
    local seen, variants = {}, {}
    for _, v in ipairs({ lower, capitalized, upper }) do
        if not seen[v] then
            seen[v] = true
            table.insert(variants, v)
        end
    end
    dbg_vocab("wordVariants(%q) → %s", word, table.concat(variants, ", "))
    return variants
end

-- ─────────────────────────────────────────────────────────────────────────────

function PageTextInfo:updateWordsVocabulary()
    if not ffiUtil.realpath(DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3") then return end
    local db_location = DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3"
    local conn = require("lua-ljsqlite3/init").open(db_location)
    local stmt = conn:prepare("SELECT DISTINCT LOWER(word) FROM vocabulary")
    self.words    = {}
    self.all_words = {}
    while true do
        local row = {}
        if not stmt:step(row) then break end
        local word = row[1]
        if not word:find("%s+") then
            -- Index every capitalisation variant so that "Have" at the start
            -- of a sentence still matches the vocabulary entry "have".
            for _, variant in ipairs(wordVariants(word)) do
                self.all_words[variant] = word  -- value = canonical DB form
            end
        end
    end
    conn:close()

    if not self.all_words then return end

    local res = self.document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(), false)
    if not (res and res.text) then return end

    local words_page = removeDupes(util.splitToWords2(res.text))
    if not words_page then return end

    -- Track which canonical words have already been searched on this page.
    -- Without this, "have", "Have" and "HAVE" would each trigger a separate
    -- findText() call and produce duplicate entries in self.words.
    local seen_canonical = {}

    for i = 1, #words_page do
        local word_page = words_page[i]
        -- E-book text may contain Unicode whitespace (e.g. non-breaking space U+00A0,
        -- zero-width space U+200B) that the DB never stores. Strip them so the
        -- lookup against all_words succeeds.
        word_page = word_page:gsub("\xC2\xA0", ""):gsub("\xE2\x80\x8B", "")
        local canonical = self.all_words[word_page]

        if canonical and not seen_canonical[canonical] then
            seen_canonical[canonical] = true

            local words      = nil
            local hyphenated = false

            if i == 1 then
                -- First word on the page may be hyphenated; handle separately.
                local cre = require("libs/libkoreader-cre")
                local hyphenation = cre.getHyphenationForWord(canonical)
                if hyphenation:find("-") then
                    hyphenated = true
                    words = findBestHyphenatedMatch(self.document, hyphenation)
                else
                    words = self.document:findText(canonical, 1, false, true, -1, false, 1)
                end
            else
                -- case_insensitive = true: finds "have", "Have" and "HAVE" in one call.
                words = self.document:findText(canonical, 1, false, true, -1, false, 30)
            end

            if words then
                for j = 1, #words do
                    local wordi = words[j]
                    -- Store the canonical form; drawXPointerVocabulary compares
                    -- with :upper() so capitalisation differences are handled there.
                    wordi.text = canonical
                    if hyphenated then
                        wordi.hyphenated = true
                    end
                    local page = self.document:getPageFromXPointer(wordi.start)
                    if not self.words[page] then self.words[page] = {} end
                    table.insert(self.words[page], wordi)
                    local page2 = self.document:getPageFromXPointer(wordi["end"])
                    if page2 ~= page then
                        if not self.words[page2] then self.words[page2] = {} end
                        table.insert(self.words[page2], wordi)
                    end
                end
            end
        end
    end

    self.ui.document:clearSelection()
end

-- ─────────────────────────────────────────────────────────────────────────────

-- Estilo del subrayado (ajusta aquí)
local VOCAB_UNDERLINE_COLOR = Blitbuffer.COLOR_DARK_GRAY -- necesitas: local Blitbuffer = require("ffi/blitbuffer")
local VOCAB_UNDERLINE_THICK = Size.line.medium
local VOCAB_MIN_TRANSLATION_SIZE = 7

-- Deja solo la última palabra del texto devuelto por el motor, normalizando el apóstrofo tipográfico.
local function lastWord(text)
    text = (text:gsub("’", "'"):gsub("%s+$", ""))
    return text:match("[A-Za-zÁÉÍÓÚÜÑáéíóúüñ']+$") or text
end



local RenderText = require("ui/rendertext")
local Blitbuffer = require("ffi/blitbuffer")

-- Style constants
local VOCAB_MIN_TRANSLATION_SIZE = 7   -- minimum font size for the gloss
local GLOSS_MAX_CHARS = 14             -- max visible characters before truncating with "…"
local GLOSS_SCALE = 0.70   -- gloss size relative to the book text (lower = smaller)
local GLOSS_INVERTED  = false          -- true = black background, white text
local GLOSS_PAD_X     = Screen:scaleBySize(3)  -- horizontal padding inside the chip
local GLOSS_PAD_Y     = Screen:scaleBySize(1)  -- vertical padding inside the chip

-- Keep only the last word of the text returned by the engine.
-- Also normalizes the typographic apostrophe to a plain one.
local function lastWord(text)
    text = (text:gsub("’", "'"):gsub("%s+$", ""))
    return text:match("[A-Za-zÁÉÍÓÚÜÑáéíóúüñ']+$") or text
end

-- Always use the generic UI font: it always exists, so no missing-font crash.
-- Bold is simulated through the `bold` flag of renderUtf8Text.
local function getGlossFace(self, size)
    local ckey = tostring(size)
    if self._gloss_face_key == ckey and self._gloss_face then
        return self._gloss_face
    end
    local face = Font:getFace("cfont", size)
    self._gloss_face_key = ckey
    self._gloss_face = face
    return face
end

-- Keep only the first meaning of a translation and truncate it with "…".
-- Uses utf8.len so accented characters are never cut in half.
local function shortGloss(text)
    text = text:gsub("%s+", " ")                -- collapse whitespace
    text = text:match("^[^;,/\n]+") or text     -- first meaning only
    text = text:gsub("^%s+", ""):gsub("%s+$", "")  -- trim
    if utf8 and utf8.len(text) and utf8.len(text) > GLOSS_MAX_CHARS then
        local cut = utf8.offset(text, GLOSS_MAX_CHARS + 1)
        if cut then text = text:sub(1, cut - 1) .. "…" end
    elseif #text > GLOSS_MAX_CHARS then
        text = text:sub(1, GLOSS_MAX_CHARS) .. "…"
    end
    return text
end

-- Dotted underline: black, thick, longer dashes so it is visible on e-ink.
local function paintDotted(bb, x, y, w, thick)
    local dash = Screen:scaleBySize(5)
    local gap  = Screen:scaleBySize(2)
    local x1 = x + w
    while x < x1 do
        bb:paintRect(x, y, math.min(dash, x1 - x), thick, Blitbuffer.COLOR_BLACK)
        x = x + dash + gap
    end
end

-- Paint a gloss as a "chip" (background + optional border) above the word.
-- It is always centered on the word (clamped to the screen).
-- Overlaps with neighbouring glosses are tolerated.
local function paintGloss(bb, box, gloss, face)
    -- Measure the text and the font height/ascender
    local size = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, gloss, true, true)
    local text_w = size.x
    local height, ascender = face.ftsize:getHeightAndAscender()
    height, ascender = math.ceil(height), math.ceil(ascender)

    local chip_w = text_w + 2 * GLOSS_PAD_X
    local chip_h = height + 2 * GLOSS_PAD_Y
    local margin = Screen:scaleBySize(2)

    -- Center the chip directly above the word
    local x = box.x + math.floor((box.w - chip_w) / 2)
    x = math.max(margin, math.min(x, Screen:getWidth() - chip_w - margin))

    -- Place the chip just above the word; skip if it would go off the top
    local y = box.y - chip_h + Screen:scaleBySize(3)
    if y < 0 then return end

    local bg = GLOSS_INVERTED and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
    local fg = GLOSS_INVERTED and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK

    -- Background and border (border only in the non-inverted style)
    bb:paintRect(x, y, chip_w, chip_h, bg)
    if not GLOSS_INVERTED then
        bb:paintBorder(x, y, chip_w, chip_h, Size.border.thin, Blitbuffer.COLOR_BLACK, Size.radius.default)
    end

    -- Text, vertically aligned using the font ascender
    RenderText:renderUtf8Text(bb, x + GLOSS_PAD_X, y + GLOSS_PAD_Y + ascender,
        face, gloss, true, true, fg)
end

function PageTextInfo:drawXPointerVocabulary(bb, x, y)
    local page_words = self.words[self.ui.view.state.page]
    if not page_words then return end

    local cur_view_top = self.document:getCurrentPos()
    local current_font = self.ui.document:getFontFace():gsub(" ", "")
    local font_size    = self.ui.document.configurable.font_size
    local show_defs    = self.settings:isTrue("show_definitions")

    -- Gloss font: larger and bold so it stands out
    -- pt -> px of the book text, then -> getFace units
    local book_px = font_size * Screen:getDPI() / 72
    local translation_size = math.max(
        book_px * GLOSS_SCALE / Screen:scaleBySize(1),
        VOCAB_MIN_TRANSLATION_SIZE)
    local translation_face = show_defs
        and getGlossFace(self, translation_size)
        or nil

    self._tr_cache = self._tr_cache or {}

    -- Geometry cache: only recomputed when page, position, font or layout change
    local key = table.concat({
        self.ui.view.state.page, cur_view_top, current_font, font_size,
        self.document:getPageCount(),
    }, ":")
    if not self._draw_cache
        or self._draw_cache.key ~= key
        or self._draw_cache.words ~= self.words then
        local entries = {}
        for _, item in ipairs(page_words) do
            -- Cheap check: skip words above the viewport
            local end_pos = self.document:getPosFromXPointer(item["end"])
            if end_pos >= cur_view_top then
                local boxes = self.document:getScreenBoxesFromPositions(item.start, item["end"], true)
                if boxes and boxes[1] then
                    -- Sample from the center of the first box so we don't land on a neighbor word
                    local mid_x = boxes[1].x + math.floor(boxes[1].w / 2)
                    local mid_y = boxes[1].y + math.floor(boxes[1].h / 2)
                    local word = self.ui.document._document:getTextFromPositions(
                        mid_x, mid_y, mid_x, mid_y, false, false)

                    if word and word.text then
                        local got  = lastWord(word.text)
                        local want = item.text:gsub("’", "'")
                        if got:upper() == want:upper() then
                            -- Text matches: recompute precise boxes for the word
                            local precise
                            if item.hyphenated then
                                precise = self.document:getScreenBoxesFromPositions(word.pos0, word.pos1, true)
                            else
                                precise = self.document:getScreenBoxesFromPositions(item.start, word.pos1, true)
                            end
                            if precise then
                                entries[#entries + 1] = { boxes = precise, text = got }
                            end
                        elseif item.hyphenated then
                            -- No match but hyphenated: still underline with the rough boxes
                            entries[#entries + 1] = { fallback = boxes }
                        end
                    elseif item.hyphenated then
                        entries[#entries + 1] = { fallback = boxes }
                    end
                end
            end
        end
        self._draw_cache = { key = key, entries = entries, words = self.words }
    end

    -- Painting (cheap: only uses already computed data)
    for _, entry in ipairs(self._draw_cache.entries) do
        if entry.fallback then
            paintBaselines(bb, entry.fallback, current_font)
        else
            local labeled = false
            for _, box in ipairs(entry.boxes) do
                if box.h ~= 0 then
                    -- Gloss: only on the first box of the word
                    if show_defs and not labeled then
                        labeled = true
                        local lkey = entry.text:lower()
                        local gloss = self._tr_cache[lkey]
                        if not gloss then
                            local tr = getTranslation(self, entry.text)
                            if tr then
                                gloss = shortGloss(tr)
                                self._tr_cache[lkey] = gloss   -- cache only valid results
                            end
                        end
                        if gloss then
                            paintGloss(bb, box, gloss, translation_face)
                        end
                    end

                    -- Dotted underline slightly below the baseline
                    local y_line = getBaseline(box, current_font) + Screen:scaleBySize(1)
                    paintDotted(bb, box.x, y_line, box.w, Size.line.thick)
                end
            end
        end
    end
end
end
