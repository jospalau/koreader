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
local JSON = require("json")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

-- The plugin instance (set whenever the plugin paints / updates), so code that has no
-- `self` (the dictionary hook, the panel) can refresh the page after the vocabulary changes.
local active_plugin

return function(PageTextInfo)

-- Grammar labels that dictionaries put in front of / between translations.
-- An explicit set is used instead of a length-based pattern so that real short
-- Spanish words ("dar", "ir", "sol", "luz", "pan"...) are never discarded.
local GRAMMAR_LABELS = {
    n = true, v = true, vt = true, vi = true, vr = true, vtr = true, vpr = true,
    adj = true, adv = true, prep = true, conj = true, pron = true, interj = true,
    art = true, loc = true, m = true, f = true,
    nm = true, nf = true, nmf = true, npl = true, nmpl = true, nfpl = true,
}

-- Persistent cache of translations (only non-empty ones are stored on disk).
local function translationsFile()
    return DataStorage:getSettingsDir() .. "/vocabulary_translations.json"
end

-- Merges the translations saved on disk into self.translations (once per session).
local function loadPersistedTranslations(self)
    if self._translations_loaded then return end
    self._translations_loaded = true
    self.translations = self.translations or {}
    local f = io.open(translationsFile(), "r")
    if not f then return end
    local content = f:read("*a")
    f:close()
    local ok, decoded = pcall(JSON.decode, content)
    if ok and type(decoded) == "table" then
        for k, v in pairs(decoded) do
            if type(k) == "string" and type(v) == "string" and v ~= ""
                and self.translations[k] == nil then
                self.translations[k] = v
            end
        end
    end
end

-- Writes the translations to disk, only if something new was added.
local function savePersistedTranslations(self)
    if not self._translations_dirty then return end
    self._translations_dirty = false
    local out = {}
    for k, v in pairs(self.translations or {}) do
        if type(v) == "string" and v ~= "" then out[k] = v end
    end
    local ok, encoded = pcall(JSON.encode, out)
    if not ok or not encoded then return end
    local f = io.open(translationsFile(), "w")
    if f then
        f:write(encoded)
        f:close()
    end
end

-- Cheap "has the DB changed?" stamp. The -wal file is included because with
-- SQLite WAL mode the main file's mtime may not change on writes.
local function dbStamp(path)
    local m = lfs.attributes(path, "modification") or 0
    local w = lfs.attributes(path .. "-wal", "modification") or 0
    return m .. ":" .. w
end

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
        tailAfterFirstHyphen(hyphenatedWord),       -- level 1
        nestedTail(hyphenatedWord, 2),              -- level 2
        nestedTail(hyphenatedWord, 3),              -- level 3
        nestedTail(hyphenatedWord, 4),              -- level 4
        nestedTail(hyphenatedWord, 5),              -- level 5
        (hyphenatedWord:gsub("%-", "")),            -- without hyphens
    }

    for _, suggestion in ipairs(attempts) do
        local found = doc:findText(suggestion, 1, false, true, -1, false, 1)
        if found then return found end
    end

    return nil
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

-- Extracts the shortest, cleanest translation from a dictionary definition.
-- Tries each line in order, preferring short lines that look like translations
-- (Spanish accents, semicolons, commas) and discarding headers and long prose.
local function extractDefinition(def)
    if not def or def == "" then return "" end

    -- FIX: turn block-level HTML tags into line breaks BEFORE stripping tags,
    -- otherwise multi-line HTML definitions collapse into a single line.
    for _, pat in ipairs({ "<[bB][rR]%s*/?>", "</[pP]>", "</[lL][iI]>", "</[dD][iI][vV]>" }) do
        def = def:gsub(pat, "\n")
    end

    -- FIX: decode numeric entities (&#233; / &#xE9;) so accents are not lost.
    local function entityToUtf8(cp)
        if not cp or not util.unicodeCodepointToUtf8 then return "" end
        local ok, ch = pcall(util.unicodeCodepointToUtf8, cp)
        return ok and ch or ""
    end
    def = def:gsub("&#[xX](%x+);", function(h) return entityToUtf8(tonumber(h, 16)) end)
    def = def:gsub("&#(%d+);", function(d) return entityToUtf8(tonumber(d)) end)

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
        -- FIX: only KNOWN labels are stripped (it used to remove any word followed by
        -- a dot), and the duplicated %) in the character class is gone.
        local s = line:gsub("^%d+[%.%)]%s*", "")
        local label = s:match("^(%a+)[%.%)]%s*")
        if label and GRAMMAR_LABELS[label:lower()] then
            s = s:gsub("^%a+[%.%)]%s*", "")
        end
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
        -- FIX: explicit label set; the old pattern ^%a%a?%a?%.?$ also dropped real
        -- words of 1-3 letters ("dar", "ir", "sol", "luz"...).
        local label = p and p:lower():gsub("%.$", "")
        -- Parts of 1-3 letters (plus an optional dot) are dropped on purpose, as the
        -- original code did: it filters out the many abbreviated labels ("pl", "fam.",
        -- "abr"...) that GRAMMAR_LABELS does not list, at the price of also dropping
        -- very short real words. GRAMMAR_LABELS stays as an extra filter.
        if p and #p > 1 and not GRAMMAR_LABELS[label] and not p:match("^%a%a?%a?%.?$") then
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
local DICTIONARIES = { "Babylon English-Spanish", "WordReference_EN_ES" }

-- Orders sdcv results by the position of their dictionary in DICTIONARIES (the first one
-- is the preferred); the other dictionaries go last. sdcv returns the results in its own
-- order, so the order of DICTIONARIES alone does not decide which dictionary is used.
local function sortByPreferredDictionary(results)
    local rank = {}
    for i, name in ipairs(DICTIONARIES) do rank[name] = i end
    local indexed = {}
    for i, r in ipairs(results) do indexed[i] = { r = r, i = i } end
    table.sort(indexed, function(a, b)
        local ra, rb = rank[a.r.dict] or math.huge, rank[b.r.dict] or math.huge
        if ra ~= rb then return ra < rb end
        return a.i < b.i   -- table.sort is not stable: keep the sdcv order inside a rank
    end)
    local sorted = {}
    for i, e in ipairs(indexed) do sorted[i] = e.r end
    return sorted
end

-- Runs sdcv synchronously with a plain io.popen and returns the decoded entries
-- (the same list startSdcv returns, minus its dummy "no result" entry).
-- ReaderDictionary:startSdcv() is not used here because it goes through
-- Trapper:dismissablePopen(), which logs "unwrapped dismissablePopen()" and falls
-- back to a blocking io.popen() anyway when called outside Trapper:wrap().
-- This runs while painting, so it cannot be wrapped (or deferred): going straight
-- to io.popen gives the same blocking behaviour, without the warning.
local function sdcvLookup(dictionary, word, dict_names, fuzzy_search)
    local dict_dirs = { dictionary.data_dir }
    local dict_ext = dictionary.data_dir .. "_ext"
    if lfs.attributes(dict_ext, "mode") == "directory" then
        table.insert(dict_dirs, dict_ext)
    end

    local entries = {}
    for _, dict_dir in ipairs(dict_dirs) do
        local args = {
            "./sdcv", "--utf8-input", "--utf8-output", "--json-output",
            "--non-interactive", "--data-dir", dict_dir,
        }
        if not fuzzy_search then
            table.insert(args, "--exact-search")
        end
        if dict_names then
            for _, name in pairs(dict_names) do
                table.insert(args, "-u")
                table.insert(args, name)
            end
        end
        table.insert(args, "--")   -- a word starting with "-" is not an option
        table.insert(args, word)

        local cmd = util.shell_escape(args) .. "; echo"   -- the echo guarantees some output
        local pipe = io.popen(cmd, "r")
        if pipe then
            local out = pipe:read("*a")
            pipe:close()
            local line = out and out:match("[^\n]+")
            if line then
                local ok, decoded = pcall(JSON.decode, line)
                if ok and type(decoded) == "table" then
                    for _, entry in ipairs(decoded) do
                        table.insert(entries, entry)
                    end
                end
            end
        end
    end
    return entries
end

-- With fuzzy search sdcv may return approximate matches ("have" -> "haven").
-- If any entry matches the word exactly, keep only those; otherwise keep all
-- (same behaviour as before for words that only have fuzzy matches).
local function preferExactEntries(results, key)
    local exact = {}
    for _, r in ipairs(results) do
        if type(r.word) == "string" and r.word:lower() == key then
            table.insert(exact, r)
        end
    end
    return #exact > 0 and exact or results
end

-- FIX: local (it used to leak into the global namespace).
local function getTranslation(self, word)
    -- Translations saved in previous sessions (loaded once).
    loadPersistedTranslations(self)
    self.translations = self.translations or {}

    -- Normalise to lowercase so "Have" and "have" share the same cache entry.
    local key = word:lower()
    if self.translations[key] then
        return self.translations[key]
    end

    local dictionary = self.ui.dictionary
    local results = sdcvLookup(dictionary, key, DICTIONARIES, true)

    -- If the preferred dictionaries have no entry for this word, fall back to
    -- whatever dictionaries are installed.
    if #results == 0 then
        results = sdcvLookup(dictionary, key, nil, true)
    end
    results = sortByPreferredDictionary(preferExactEntries(results, key))

    local translation = ""

    for _, result in ipairs(results) do
        if result.definition then
            local candidate = extractDefinition(result.definition)
            if candidate and candidate ~= "" then
                translation = formatTranslation(candidate)
                break
            end
        end
    end

    self.translations[key] = translation
    -- Empty results stay in memory only, so they are retried in a later session
    -- (e.g. after installing a dictionary).
    if translation ~= "" then self._translations_dirty = true end
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
            -- FIX: integer y and explicit colour (it used to pass a fractional y and nil)
            bb:paintRect(box.x, math.floor(y_baseline), box.w, Size.line.thick, Blitbuffer.COLOR_BLACK)
        end
    end
end

-- (paintTranslationLabel is currently unused: the chips drawn by paintGloss replaced it)
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

-- (wordVariants is no longer used by updateWordsVocabulary, which now indexes the
-- lowercase form only; it is kept in case it is needed again)
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

-- Splits an xpointer into its node path and its character offset
-- ("/body/DocFragment[3]/body/p[5]/text().12" -> "/body/DocFragment[3]/body/p[5]/text()", 12).
local function xpointerParts(xp)
    local path, offset = tostring(xp):match("^(.*)%.(%d+)$")
    return path, tonumber(offset)
end

-- True when the xpointer `xp` lies inside one of the search results in `words`.
-- Used so that the tail search of the first word never marks twice a word that the
-- normal search already found.
local function insideAnyMatch(words, xp)
    local path, offset = xpointerParts(xp)
    if not path then return false end
    for _, w in ipairs(words or {}) do
        local p1, o1 = xpointerParts(w.start)
        local p2, o2 = xpointerParts(w["end"])
        if p1 == path and p2 == path and o1 and o2 and offset >= o1 and offset <= o2 then
            return true
        end
    end
    return false
end

-- True when the search result `hit` lies on the first line of the page (or above it).
-- The tail of a word split from the previous page is always there, so a tail search hit
-- further down is a different word that just contains the fragment ("ing" in "going").
-- If the position cannot be known the hit is kept, as it was before this check.
local function isOnFirstLine(self, hit)
    local ok1, pos = pcall(self.document.getPosFromXPointer, self.document, hit.start)
    local ok2, boxes = pcall(self.document.getScreenBoxesFromPositions, self.document,
        hit.start, hit["end"], true)
    if not (ok1 and ok2 and pos and boxes and boxes[1] and boxes[1].h) then return true end
    local line_h = boxes[1].h
    local on_first_line = pos - self.document:getCurrentPos() < line_h * 0.75
    dbg_vocab("tail hit at pos=%s top=%s line_h=%s -> first line: %s",
        tostring(pos), tostring(self.document:getCurrentPos()), tostring(line_h), tostring(on_first_line))
    return on_first_line
end

-- True when the first word of the page lies completely on this page, i.e. the first
-- normal search result starts where the page text starts (or on its first line).
-- When it does not, the first word is the tail of a word split from the previous
-- page and the tail search is needed, even if the word is repeated further down.
local function firstWordIsWhole(self, words, res)
    if not (words and words[1] and res and res.pos0) then return false end
    if words[1].start == res.pos0 then return true end
    local ok1, y_word = pcall(self.document.getPosFromXPointer, self.document, words[1].start)
    local ok2, y_top  = pcall(self.document.getPosFromXPointer, self.document, res.pos0)
    return ok1 and ok2 and y_word <= y_top
end

function PageTextInfo:updateWordsVocabulary()
    active_plugin = self
    if not ffiUtil.realpath(DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3") then return end
    local db_location = DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3"
    self.words = {}

    -- FIX: the DB is only re-read when it changed (it used to be opened and fully
    -- read on every page update). Errors are contained with pcall and the
    -- connection is always closed.
    local stamp = dbStamp(db_location)
    if not self.all_words or self._vocab_stamp ~= stamp then
        local all_words = {}
        local ok_open, conn = pcall(function()
            return require("lua-ljsqlite3/init").open(db_location)
        end)
        if ok_open and conn then
            local ok_read = pcall(function()
                local stmt = conn:prepare("SELECT DISTINCT LOWER(word) FROM vocabulary")
                while true do
                    local row = {}
                    if not stmt:step(row) then break end
                    local word = row[1]
                    if word and not word:find("%s+") then
                        -- Index the lowercase form only: page words are lowercased before
                        -- the lookup, so any capitalisation ("Have" at the start of a
                        -- sentence, "HAVE", "McDonald"...) matches the entry "have".
                        -- The typographic apostrophe is normalised to a plain one.
                        local key = word:gsub("’", "'")
                        all_words[key] = word  -- value = canonical DB form
                    end
                end
                if stmt.close then stmt:close() end
            end)
            conn:close()
            if ok_read then
                self.all_words = all_words
                self._vocab_stamp = stamp
            end
        end
    end

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
        -- Lowercase and normalise the typographic apostrophe, as the keys of all_words are.
        word_page = word_page:lower():gsub("’", "'")
        local canonical = self.all_words[word_page]

        if canonical and not seen_canonical[canonical] then
            seen_canonical[canonical] = true

            local words      = nil
            local hyphenated = false

            -- case_insensitive = true: finds "have", "Have" and "HAVE" in one call.
            -- FIX: this normal search now also runs for the FIRST word of the page;
            -- before, that word got a single result and every other occurrence of it
            -- on the page was missed (seen_canonical blocked any further search).
            words = self.document:findText(canonical, 1, false, true, -1, false, 30)

            -- The DB stores a plain apostrophe, but the book may use the typographic one.
            if not (words and #words > 0) and canonical:find("'", 1, true) then
                words = self.document:findText((canonical:gsub("'", "’")), 1, false, true, -1, false, 30)
            end

            if i == 1 then
                dbg_vocab("first word %q: pos0=%s first_hit=%s", canonical, tostring(res.pos0),
                    tostring(words and words[1] and words[1].start))
            end

            -- FIX: the tail search only runs when the first word is NOT whole on this page
            -- (it is the tail of a word split from the previous page). Running it for a
            -- whole word hit the same word twice, or a stray fragment ("ing") elsewhere.
            -- It also runs when the word is repeated further down the page: the normal
            -- search finds those copies but not the fragment cut at the top of the page.
            if i == 1 and not firstWordIsWhole(self, words, res) then
                -- First word on the page may be hyphenated; handle separately and
                -- append those hits (each one flagged individually) to the list.
                local cre = require("libs/libkoreader-cre")
                local hyphenation = cre.getHyphenationForWord(canonical)
                if hyphenation:find("-") then
                    local hyph_words = findBestHyphenatedMatch(self.document, hyphenation)
                    if hyph_words then
                        words = words or {}
                        for _, hw in ipairs(hyph_words) do
                            -- skip a hit inside a word the normal search already found,
                            -- and a hit that is not on the first line of the page
                            if not insideAnyMatch(words, hw.start) and isOnFirstLine(self, hw) then
                                hw.hyphenated = true
                                table.insert(words, hw)
                            end
                        end
                    end
                end
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

-- Underline style (adjust here)
-- (VOCAB_UNDERLINE_COLOR and VOCAB_UNDERLINE_THICK are currently unused)
local VOCAB_UNDERLINE_COLOR = Blitbuffer.COLOR_DARK_GRAY -- needs: local Blitbuffer = require("ffi/blitbuffer") (already required at the top)
local VOCAB_UNDERLINE_THICK = Size.line.medium
-- (VOCAB_MIN_TRANSLATION_SIZE is declared again below with the other style constants)
-- local VOCAB_MIN_TRANSLATION_SIZE = 7

-- Keeps only the last word of the text returned by the engine, normalising the typographic apostrophe.
local function lastWord(text)
    text = (text:gsub("’", "'"):gsub("%s+$", ""))
    return text:match("[A-Za-zÁÉÍÓÚÜÑáéíóúüñ']+$") or text
end



-- ─────────────────────────────────────────────────────────────────────────────
-- Notes
-- Marks, with a small icon, the words that have a note in the annotations of the book.
-- This code lives here, after the vocabulary helpers (firstWordIsWhole, isOnFirstLine,
-- insideAnyMatch, lastWord), because it reuses them.

-- Normalises a word so that it can be compared: lowercase, plain apostrophe and without
-- the invisible characters (non-breaking space, zero-width space) that e-book text may have.
local function normalizeNoteWord(text)
    text = tostring(text or ""):gsub("\xC2\xA0", ""):gsub("\xE2\x80\x8B", "")
    return (text:lower():gsub("’", "'"))
end

-- Shallow copy of a search result, so each annotation can carry its own note.
local function copyHit(hit)
    local copy = {}
    for k, v in pairs(hit) do copy[k] = v end
    return copy
end

-- Finds the occurrences of the annotated word `text` (up to 60, from the current page on).
-- `is_first_word`: the word is the first one of the page, so it may be the tail of a word
-- split from the previous page. Same strategy as updateWordsVocabulary: a normal search,
-- plus a search of the tail only when the first word is not whole on this page.
local function findNoteHits(self, text, res, is_first_word)
    local hits = self.document:findText(text, 1, false, true, -1, false, 60)

    -- The annotation may use the typographic apostrophe and the book the plain one, or vice versa.
    if not (hits and #hits > 0) then
        local alt
        if text:find("'", 1, true) then
            alt = text:gsub("'", "’")
        elseif text:find("’", 1, true) then
            alt = text:gsub("’", "'")
        end
        if alt then
            hits = self.document:findText(alt, 1, false, true, -1, false, 60)
        end
    end

    if is_first_word and not firstWordIsWhole(self, hits, res) then
        local cre = require("libs/libkoreader-cre")
        local hyphenation = cre.getHyphenationForWord(text)
        if hyphenation:find("-") then
            local tail_hits = findBestHyphenatedMatch(self.document, hyphenation)
            if tail_hits then
                hits = hits or {}
                for _, hit in ipairs(tail_hits) do
                    -- skip a hit inside a word the normal search already found,
                    -- and a hit that is not on the first line of the page
                    if not insideAnyMatch(hits, hit.start) and isOnFirstLine(self, hit) then
                        hit.hyphenated = true
                        table.insert(hits, hit)
                    end
                end
            end
        end
    end
    return hits
end

-- Builds self.pages_notes (page -> list of occurrences, each one with its `note`) and
-- self.notes (the annotations that were found on the page).
function PageTextInfo:updateNotes()
    self.pages_notes = {}
    self.notes = {}
    local annotations = self.ui.annotation.annotations
    local res = self.document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(), false)
    if res and res.text and annotations then
        local t = util.splitToWords2(res.text)
        -- Words of the page (normalised): annotations of other words are skipped
        local words_page = {}
        for i = 1, #t do
            words_page[normalizeNoteWord(t[i])] = true
        end
        local first_key = t[1] and normalizeNoteWord(t[1])
        -- Search results by word: annotations of the same word share one search
        local hits_cache = {}

        for _, item in ipairs(annotations) do
            -- Only notes on a single word are marked. This is checked first, so highlights
            -- without a note (most of the annotations) never trigger a search.
            if item.note and item.text and not item.text:find("%s") then
                local key = normalizeNoteWord(item.text)
                if key ~= "" and words_page[key] then
                    local hits = hits_cache[key]
                    if hits == nil then
                        hits = findNoteHits(self, item.text, res, key == first_key) or false
                        hits_cache[key] = hits
                    end
                    if hits then
                        table.insert(self.notes, item)
                        for _, hit in ipairs(hits) do
                            -- own copy per annotation: the hits are shared between them
                            local word = copyHit(hit)
                            word.note = item.note
                            word.text = item.text
                            local page = self.document:getPageFromXPointer(word.start)
                            if not self.pages_notes[page] then
                                self.pages_notes[page] = {}
                            end
                            table.insert(self.pages_notes[page], word)
                            -- a word split over two pages belongs to both of them
                            local page2 = self.document:getPageFromXPointer(word["end"])
                            if page2 ~= page then
                                if not self.pages_notes[page2] then
                                    self.pages_notes[page2] = {}
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

-- Paints the note icon on the words of the current page that have a note.
-- The geometry is cached (it is only recomputed when the page, position, font or layout
-- change), so a repaint of the same page only paints.
-- Signature of the notes that are marked (the words of the annotations with a note). When it
-- changes (a note was added or deleted) the marks are rebuilt, so a deleted note loses its mark.
local function notesSignature(self)
    local parts = {}
    for _, item in ipairs(self.ui.annotation and self.ui.annotation.annotations or {}) do
        if item.note and item.text and not item.text:find("%s") then
            parts[#parts + 1] = normalizeNoteWord(item.text)
        end
    end
    return #parts .. ":" .. table.concat(parts, "|")
end

function PageTextInfo:drawXPointerSavedHighlightNotes(bb, x, y)
    -- A note was added or deleted since the marks were built: build them again
    if self.pages_notes then
        local sig = notesSignature(self)
        if self._notes_signature ~= nil and self._notes_signature ~= sig then
            self._notes_draw_cache = nil
            self:updateNotes()
        end
        self._notes_signature = sig
    end

    local page_notes = self.pages_notes and self.pages_notes[self.ui.view.state.page]
    if not page_notes then
        self._notes_draw_cache = nil   -- no notes on this page: a tap must not use the previous one
        return
    end

    self:registerNoteDoubleTap()
    -- The single taps on the notes go through the tap zone of the vocabulary (see onTapVocabularyWord)
    self:registerWordTap()

    local cur_view_top = self.document:getCurrentPos()
    local key = table.concat({
        self.ui.view.state.page, cur_view_top, self.ui.document:getFontFace(),
        self.ui.document.configurable.font_size,
        self.document:getPageCount(),
        Screen:getWidth(), Screen:getHeight(),
        tostring(self.ui.document.configurable.line_spacing),
    }, ":")

    -- (not the same cache as the vocabulary: that one is self._draw_cache)
    local cache = self._notes_draw_cache
    if not cache or cache.key ~= key or cache.pages_notes ~= self.pages_notes then
        local entries = {}
        local seen = {}
        for _, item in ipairs(page_notes) do
            -- the same word can come from several annotations: it is only marked once
            local id = tostring(item.start) .. "|" .. tostring(item["end"])
            if not seen[id] then
                seen[id] = true
                -- Cheap check first: skip words above the viewport.
                -- getScreenBoxesFromPositions() is expensive.
                local end_pos = self.document:getPosFromXPointer(item["end"])
                if end_pos >= cur_view_top then
                    local boxes = self.document:getScreenBoxesFromPositions(item.start, item["end"], true) -- get_segments=true
                    if boxes and boxes[1] then
                        -- Sample from the center of the first box so we don't land on a neighbor word
                        local mid_x = boxes[1].x + math.floor(boxes[1].w / 2)
                        local mid_y = boxes[1].y + math.floor(boxes[1].h / 2)
                        local word = self.ui.document._document:getTextFromPositions(
                            mid_x, mid_y, mid_x, mid_y, false, false)
                        if word and word.text
                            and normalizeNoteWord(lastWord(word.text)) == normalizeNoteWord(item.text) then
                            -- Text matches: recompute precise boxes for the word
                            local precise
                            if item.hyphenated then
                                precise = self.document:getScreenBoxesFromPositions(word.pos0, word.pos1, true)
                            else
                                precise = self.document:getScreenBoxesFromPositions(item.start, word.pos1, true)
                            end
                            if precise then
                                entries[#entries + 1] = { boxes = precise, text = item.text }
                            end
                        end
                    end
                end
            end
        end
        cache = { key = key, entries = entries, pages_notes = self.pages_notes,
                  page = self.ui.view.state.page }
        self._notes_draw_cache = cache
    end

    -- The icon widget is built once and painted at every box
    local mark = self._note_mark
    if not mark then
        mark = FrameContainer:new{
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
        self._note_mark = mark
    end

    for _, entry in ipairs(cache.entries) do
        for _, box in ipairs(entry.boxes) do
            if box.h ~= 0 then
                -- self.ui.view:drawHighlightRect(bb, x, y, box, "underscore", nil, false)
                mark:paintTo(bb, box.x, box.y)
            end
        end
    end
end

-- The note (entry of the cache) under a tap, or nil. It works when the notes are marked,
-- i.e. in the vocabulary mode ("Highlight all words vocabulary builder and notes") or in
-- the one that highlights all the notes ("highlight_all_notes_and_allow_to_edit_them_on_tap").
local function noteAt(self, ges)
    local cache = self._notes_draw_cache
    if not (cache and ges and ges.pos) then return nil end
    -- the cache belongs to the page that was painted last
    if cache.page ~= self.ui.view.state.page then return nil end
    if not (self.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes")
        or self.settings:isTrue("highlight_all_notes_and_allow_to_edit_them_on_tap")) then
        return nil
    end
    local pad = Screen:scaleBySize(4)   -- a little margin: the words are small
    for _, entry in ipairs(cache.entries) do
        -- the boxes of the word (several when it is split over two lines)
        for _, box in ipairs(entry.boxes) do
            if box.h ~= 0
                and ges.pos.x >= box.x - pad and ges.pos.x <= box.x + box.w + pad
                and ges.pos.y >= box.y - pad and ges.pos.y <= box.y + box.h + pad then
                return entry
            end
        end
    end
    return nil
end

-- Single tap on a note: PageTextInfo:showNote() of main.lua shows it
local function showNoteOf(self, entry)
    local logger = require("logger")
    logger.dbg("[PTI] tap on the note of", entry.text)
    if not self.showNote then
        logger.warn("[PTI] PageTextInfo:showNote() does not exist")
        return
    end
    local ok, err = pcall(self.showNote, self, entry.text)
    if not ok then logger.warn("[PTI] showNote failed:", err) end
end

-- Double tap on a note: the standard note editor of the reader
local function editNoteOf(self, entry)
    local logger = require("logger")
    logger.dbg("[PTI] double tap on the note of", entry.text)
    local annotations = self.ui.annotation and self.ui.annotation.annotations
    for i, item in ipairs(annotations or {}) do
        if item.note and item.text and item.text:upper() == entry.text:upper() then
            local ok, err = pcall(self.ui.highlight.editNote, self.ui.highlight, i)
            if not ok then logger.warn("[PTI] editNote failed:", err) end
            return
        end
    end
    logger.warn("[PTI] no annotation with a note for", entry.text)
end

-- The single tap waits a short time to know whether it is the first of a double tap
local NOTE_DOUBLE_TAP_SECONDS = 0.4

local function cancelPendingNoteTap(self)
    if self._pending_note_tap then
        require("ui/uimanager"):unschedule(self._pending_note_tap)
        self._pending_note_tap = nil
    end
end

-- Double tap on a note when KOReader sends it as a double tap gesture
function PageTextInfo:onDoubleTapNote(ges)
    local entry = noteAt(self, ges)
    if not entry then return false end
    cancelPendingNoteTap(self)
    self._last_note_tap = nil
    editNoteOf(self, entry)
    return true
end

-- Taps on a note, called from onTapVocabularyWord. The tap is always taken here, so the
-- standard behaviour of the reader (which opens the editor) does not run. A first tap
-- schedules showNote; a second one on the same note before it runs cancels it and edits
-- the note. This works with KOReader's double tap on or off.
function PageTextInfo:onTapNote(ges)
    local entry = noteAt(self, ges)
    if not entry then
        self._last_note_tap = nil
        return false
    end
    local last = self._last_note_tap
    if last and last.text == entry.text and self._pending_note_tap then
        cancelPendingNoteTap(self)
        self._last_note_tap = nil
        editNoteOf(self, entry)
        return true
    end
    cancelPendingNoteTap(self)
    self._last_note_tap = { text = entry.text }
    self._pending_note_tap = function()
        self._pending_note_tap = nil
        self._last_note_tap = nil
        showNoteOf(self, entry)
    end
    require("ui/uimanager"):scheduleIn(NOTE_DOUBLE_TAP_SECONDS, self._pending_note_tap)
    return true
end

-- Registers the double tap zone once per reader. It is done on the first paint of a page
-- with notes, when self.ui is surely ready.
function PageTextInfo:registerNoteDoubleTap()
    if self._note_double_tap_registered then return end
    local function register(overrides)
        self.ui:registerTouchZones({
            {
                id = "pagetextinfo_note_double_tap",
                ges = "double_tap",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                overrides = overrides,
                handler = function(ges) return self:onDoubleTapNote(ges) end,
            },
        })
    end
    -- Before the double tap zones of the gestures of KOReader. If one of those ids is not
    -- known the registration may fail: then it is tried again without them.
    local ok = pcall(register, {
        "double_tap_left_side", "double_tap_right_side",
        "double_tap_top_left_corner", "double_tap_top_right_corner",
        "double_tap_left_bottom_corner", "double_tap_right_bottom_corner",
    })
    if not ok then
        ok = pcall(register, nil)
    end
    -- Only a registration that worked is final; otherwise it is tried again on the next paint
    self._note_double_tap_registered = ok
end

-- ─────────────────────────────────────────────────────────────────────────────

local RenderText = require("ui/rendertext")
-- (Blitbuffer is already required at the top of the file)
-- local Blitbuffer = require("ffi/blitbuffer")

-- Style constants
local VOCAB_MIN_TRANSLATION_SIZE = 7   -- minimum font size for the gloss
local GLOSS_MAX_CHARS = 14             -- max visible characters before truncating with "…"
local GLOSS_SCALE = 0.70   -- gloss size relative to the book text (lower = smaller)
local GLOSS_INVERTED  = false          -- true = black background, white text
local GLOSS_PAD_X     = Screen:scaleBySize(3)  -- horizontal padding inside the chip
local GLOSS_PAD_Y     = Screen:scaleBySize(1)  -- vertical padding inside the chip

-- (lastWord is already defined above; this second definition was identical)
-- Keep only the last word of the text returned by the engine.
-- Also normalizes the typographic apostrophe to a plain one.
-- local function lastWord(text)
--     text = (text:gsub("’", "'"):gsub("%s+$", ""))
--     return text:match("[A-Za-zÁÉÍÓÚÜÑáéíóúüñ']+$") or text
-- end

-- (getGlossFace is defined below, after the helpers that find the font of the book)

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
local VOCAB_UNDERLINE_DOTTED = true  -- true = dotted underline, false = solid line

local function paintDotted(bb, x, y, w, thick)
    -- Solid underline (same look as the fallback underline for hyphenated words)
    if not VOCAB_UNDERLINE_DOTTED then
        bb:paintRect(x, y, w, thick, Blitbuffer.COLOR_BLACK)
        return
    end
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
-- `layout` is an optional table used to memoize the text measurements, so the
-- text is not measured again on every paint of the same page.
-- `faux_bold`: draw the text with simulated bold (the face is not a real bold).
local function paintGloss(bb, box, gloss, face, layout, faux_bold)
    layout = layout or {}
    -- Measure the text and the font height/ascender
    if not layout.text_w then
        local size = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, gloss, true, faux_bold)
        layout.text_w = size.x
        local h, a = face.ftsize:getHeightAndAscender()
        layout.height, layout.ascender = math.ceil(h), math.ceil(a)
    end
    local text_w = layout.text_w
    local height, ascender = layout.height, layout.ascender

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
        face, gloss, true, faux_bold, fg)
end

-- ─────────────────────────────────────────────────────────────────────────────

-- Tap on a gloss chip: a centered window with the full dictionary translation.

-- Fixes the layout of a definition that is already plain text (the tags are gone, so
-- spaces and line breaks that they provided are missing): dictionaries like the OED
-- glue the pronunciation, the numbered senses and the dated quotations together.
local function prettifyDefinition(def)
    -- "tippling.1858 in" -> "tippling. 1858 in"
    def = def:gsub("([%a%)%]])%.(%d%d%d%d)(%D)", "%1. %2%3")
    -- "fig.c 1375" / "smiling.a 1500" -> a space before the c / a of a dated quotation
    def = def:gsub("([%a%)%]]%.)([ca] %d%d%d%d)", "%1 %2")
    -- numbered senses start a new paragraph: "...]1. The action" / "reasonable.2. U.S."
    def = def:gsub("([%.%]%)])%s*(%d%d?)%.%s+(%u)", "%1\n\n%2. %3")
    -- "smiling.attrib." / "x.Comb." glued to the end of the previous sense
    def = def:gsub("([%a%)%]])%.(attrib%.)", "%1.\n%2")
    def = def:gsub("([%a%)%]])%.(Comb%.)", "%1.\n%2")
    -- each dated quotation on its own line: "...Peace iv. Wks. IX. 92 ... 1846 M{supc}Culloch"
    def = def:gsub("([%.%]%)!%?])[ \t]+(%d%d%d%d)[ \t]+(%u)", "%1\n%2 %3")
    def = def:gsub("([%.%]%)!%?])[ \t]+([ca] %d%d%d%d)[ \t]+(%u)", "%1\n%2 %3")
    -- lettered sub-senses: ". b. Of or pertaining" (first: the two rules below put
    -- back together what this one splits after "A." / "1.")
    def = def:gsub("([%.%]%)])[ \t]+(%l)%.[ \t]+(%u)", "%1\n%2. %3")
    -- main divisions: "A. adj." / "B. sb." / "B. n."
    def = def:gsub("([%.%]%)])[ \t]+([A-D])%.[ \t\n]+(%l+%.)", "%1\n\n%2. %3")
    -- numbered senses followed by a letter: "1. a. Of, belonging"
    def = def:gsub("([%.%]%)])[ \t]+(%d%d?)%.[ \t\n]+(%l)%.[ \t]", "%1\n\n%2. %3. ")
    -- tidy the blank lines
    def = def:gsub("[ \t]+\n", "\n"):gsub("\n\n\n+", "\n\n")
    return (def:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Returns the whole definition as plain text: HTML removed, one entry per line.
local function fullDefinitionText(def)
    if not def or def == "" then return "" end

    -- Block-level HTML tags become line breaks BEFORE stripping the tags
    for _, pat in ipairs({ "<[bB][rR]%s*/?>", "</[pP]>", "</[lL][iI]>", "</[dD][iI][vV]>" }) do
        def = def:gsub(pat, "\n")
    end

    -- Numeric entities (&#233; / &#xE9;) so accents are not lost
    local function entityToUtf8(cp)
        if not cp or not util.unicodeCodepointToUtf8 then return "" end
        local ok, ch = pcall(util.unicodeCodepointToUtf8, cp)
        return ok and ch or ""
    end
    def = def:gsub("&#[xX](%x+);", function(h) return entityToUtf8(tonumber(h, 16)) end)
    def = def:gsub("&#(%d+);", function(d) return entityToUtf8(tonumber(d)) end)

    -- Strip the tags. Each tag leaves a marker (\1), so that text which only the tags
    -- were separating ("fig.</i>c 1375", "reasonable.</b><b>2.</b>") can be spaced below.
    def = def:gsub("%b<>", "\1")
    local named = {
        aacute = "á", eacute = "é", iacute = "í", oacute = "ó", uacute = "ú", uuml = "ü", ntilde = "ñ",
        Aacute = "Á", Eacute = "É", Iacute = "Í", Oacute = "Ó", Uacute = "Ú", Uuml = "Ü", Ntilde = "Ñ",
        iquest = "¿", iexcl = "¡", laquo = "«", raquo = "»",
    }
    def = def:gsub("&(%a+);", function(name) return named[name] end)   -- unknown names are kept
    def = def:gsub("&nbsp;", " "):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&amp;", "&")
    def = def:gsub("&%a+;", "")                                         -- the rest of the named entities

    -- Spacing / line breaks lost with the tags (dictionaries like the OED glue the
    -- pronunciation, the numbered senses and the quotations together)
    def = def:gsub("\1+", "\1")
    -- a tag between a closing punctuation mark and the next word was a separation
    def = def:gsub("([%.%]%)%?!;:])\1([%w%(%[\128-\255])", "%1 %2")
    def = def:gsub("\1", "")
    def = prettifyDefinition(def)

    def = def:gsub("\r", ""):gsub("[ \t]+\n", "\n"):gsub("\n\n\n+", "\n\n")
    return (def:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The panel that shows the full translation: a rounded card with the word, the name of
-- the dictionary and the scrollable text. When several dictionaries have the word, a
-- swipe left / right goes to the next / previous one, in a loop ("n / total" on the
-- right of the title). It opens at the bottom of the screen when the tapped word is in
-- the upper half, and at the top when it is in the lower half, so it does not cover the
-- word, and it can be moved (hold and drag). A tap outside the card (or the Back key)
-- closes it.
-- The class is built on first use, so nothing is required until a word is tapped.
-- Is the translation panel the dictionary? Setting "translation_panel_dictionary", off
-- until it is turned on.
local SETTING_PANEL_DICTIONARY = "translation_panel_dictionary"

local function panelDictionaryEnabled()
    return G_reader_settings:isTrue(SETTING_PANEL_DICTIONARY)
end

-- True only while a tap on an underlined word starts its lookup: that lookup always goes
-- to the panel (even with the setting off) and must not open "Vocabulary exists".
local silence_vocab_once = false

-- The word that the last lookup added to the vocabulary (nil if it was already there)
local word_added_by_lookup = nil

-- Vocabulary (vocabulary_builder.sqlite3) helpers for the panel.
-- Words are stored as looked up ("smiling"); the comparison ignores the case.
local function vocabKey(word)
    return (tostring(word or ""):lower():gsub("’", "'"))
end

local function vocabDbPath()
    local path = DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3"
    return ffiUtil.realpath(path) and path or nil
end

-- True when `word` is in the vocabulary.
local function wordInVocabulary(word)
    local key = vocabKey(word)
    local path = vocabDbPath()
    if key == "" or not path then return false end
    local found = false
    pcall(function()
        local conn = require("lua-ljsqlite3/init").open(path)
        local ok = pcall(function()
            local stmt = conn:prepare("SELECT 1 FROM vocabulary WHERE LOWER(word) = ? LIMIT 1")
            stmt:bind(key)
            found = stmt:step({}) ~= nil
            if stmt.close then stmt:close() end
        end)
        conn:close()
        if not ok then found = false end
    end)
    return found
end

-- Deletes `word` from the vocabulary. Returns true if the query ran without errors.
local function removeFromVocabulary(word)
    local key = vocabKey(word)
    local path = vocabDbPath()
    if key == "" or not path then return false end
    local done = false
    pcall(function()
        local conn = require("lua-ljsqlite3/init").open(path)
        done = pcall(function()
            local stmt = conn:prepare("DELETE FROM vocabulary WHERE LOWER(word) = ?")
            stmt:bind(key)
            stmt:step()
            if stmt.close then stmt:close() end
        end)
        conn:close()
    end)
    return done
end

-- Repaints the page so the underline / gloss of a removed word disappears.
local function refreshVocabularyHighlights()
    local plugin = active_plugin
    if not plugin then return end
    pcall(function()
        plugin.all_words = nil        -- read the DB again (the mtime may not have changed yet)
        plugin._vocab_stamp = nil
        plugin._draw_cache = nil
        plugin:updateWordsVocabulary()
        require("ui/uimanager"):setDirty("all", "ui")
    end)
end

-- The font of the open document (the panel text uses it) ---------------------

-- Name of the font family of the book that is open, or nil
local function documentFontName()
    local plugin = active_plugin
    local ok, name = pcall(function() return plugin.ui.document._document:getFontFace() end)
    return ok and type(name) == "string" and name ~= "" and name or nil
end

-- Real file of the regular style of a family, found through KOReader's font list
local _family_path_cache = {}
local function fontPathForFamily(name)
    if _family_path_cache[name] ~= nil then return _family_path_cache[name] or nil end
    local function norm(s) return (s:gsub("%s+", ""):lower()) end
    local want = norm(name)
    local FontList = require("fontlist")
    pcall(function() FontList:getFontList() end)   -- makes sure fontinfo is filled
    local best, any
    for path, info in pairs(FontList.fontinfo or {}) do
        for _, f in ipairs(info) do
            if f.name and norm(f.name) == want then
                -- tie-break on path so the result doesn't depend on pairs() order
                if not f.bold and not f.italic then
                    if not best or path < best then best = path end
                elseif not any or path < any then
                    any = path
                end
            end
        end
    end
    _family_path_cache[name] = best or any or false
    return best or any
end

-- Font files of a family by style: { regular =, bold =, italic =, bolditalic = } (paths)
local function familyFontFiles(name)
    local function norm(s) return (s:gsub("%s+", ""):lower()) end
    local want = norm(name)
    local FontList = require("fontlist")
    pcall(function() FontList:getFontList() end)
    local files = {}
    for path, info in pairs(FontList.fontinfo or {}) do
        for _, f in ipairs(info) do
            if f.name and norm(f.name) == want then
                local style = (f.bold and f.italic) and "bolditalic"
                    or f.bold and "bold" or f.italic and "italic" or "regular"
                if not files[style] or path < files[style] then files[style] = path end
            end
        end
    end
    return files
end

-- Face of the document font at `size`, or nil if it can't be loaded
local function documentFace(size)
    local name = documentFontName()
    local path = name and fontPathForFamily(name)
    if not path then return nil end
    local ok, face = pcall(Font.getFace, Font, path, size)
    return ok and face or nil
end

-- Face of the gloss: the font of the book, so the chip matches the text around it.
-- Returns the face and `faux_bold`: true when the face is not a real bold, so the
-- text must be drawn with the `bold` flag of renderUtf8Text (simulated bold).
-- Order: the real bold file of the family, then its regular file with simulated bold,
-- then the generic UI font ("cfont", it always exists) with simulated bold.
-- A face that cannot be loaded never reaches the painting code.
local function getGlossFace(self, font_name, size)
    local ckey = tostring(font_name) .. ":" .. tostring(size)
    if self._gloss_face_key == ckey and self._gloss_face then
        return self._gloss_face, self._gloss_faux_bold
    end

    local face, faux_bold
    if type(font_name) == "string" and font_name ~= "" then
        -- real bold of the family, if its file exists
        local bold_path = familyFontFiles(font_name).bold
        if bold_path then
            local ok, f = pcall(Font.getFace, Font, bold_path, size)
            if ok and f and f.ftsize then face, faux_bold = f, false end
        end
        -- regular file of the family, with simulated bold
        if not face then
            local regular_path = fontPathForFamily(font_name)
            if regular_path then
                local ok, f = pcall(Font.getFace, Font, regular_path, size)
                if ok and f and f.ftsize then face, faux_bold = f, true end
            end
        end
    end
    if not face then
        dbg_vocab("getGlossFace: font %s not usable, using cfont", tostring(font_name))
        face, faux_bold = Font:getFace("cfont", size), true
    end

    self._gloss_face_key = ckey
    self._gloss_face = face
    self._gloss_faux_bold = faux_bold
    return face, faux_bold
end

local TranslationPanel
local function getTranslationPanelClass()
    if TranslationPanel then return TranslationPanel end

    local CenterContainer = require("ui/widget/container/centercontainer")
    local MovableContainer = require("ui/widget/container/movablecontainer")
    local GestureRange = require("ui/gesturerange")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local LineWidget = require("ui/widget/linewidget")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local ScrollTextWidget = require("ui/widget/scrolltextwidget")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local Device = require("device")
    local ok_html, ScrollHtmlWidget = pcall(require, "ui/widget/scrollhtmlwidget")

    -- Same base CSS as KOReader's dictionary window (Noto Sans has the IPA symbols);
    -- `extra` is the dictionary's own css, if it has one
    -- Returns the css and the folder of the document font files (the folder must be the
    -- resource directory of the html, MuPDF loads @font-face files relative to it).
    -- `has_res_dir`: the dictionary has its own resource directory (images...); then the
    -- font files can't be reached and only Noto Sans is used.
    local function htmlDictionaryCss(extra, has_res_dir)
        local justify = G_reader_settings:nilOrTrue("dict_justify") and "text-align: justify;" or ""
        -- The document font first (if MuPDF knows it), Noto Sans (it has the IPA symbols) after
        -- MuPDF only knows its own fonts, so the document font is loaded with @font-face
        local family, font_face_css, font_dir = "'Noto Sans'", "", nil
        local doc_font = documentFontName()
        if doc_font and not has_res_dir then
            pcall(function()
                local files = familyFontFiles(doc_font)
                local dir = files.regular and files.regular:match("^(.*)/[^/]+$")
                if not dir then return end
                local styles = {
                    regular = "font-weight: normal; font-style: normal;",
                    bold = "font-weight: bold; font-style: normal;",
                    italic = "font-weight: normal; font-style: italic;",
                    bolditalic = "font-weight: bold; font-style: italic;",
                }
                local have = {}
                for style, props in pairs(styles) do
                    local path = files[style]
                    -- only the files of the same folder can be reached
                    if path and path:match("^(.*)/[^/]+$") == dir then
                        -- The file name goes as it is (MuPDF does not decode %20), in double quotes
                        local file = path:match("[^/]+$")
                        if not file:find('"', 1, true) then
                            font_face_css = font_face_css .. string.format(
                                "@font-face { font-family: 'DocumentFont'; %s src: url(\"%s\"); }\n", props, file)
                            have[style] = true
                        end
                    end
                end
                if font_face_css ~= "" then
                    family = "'DocumentFont', 'Noto Sans'"
                    font_dir = dir
                    -- MuPDF never fakes bold or italic: a family without those files shows
                    -- <b> and <i> as plain text. For every missing style the tags go back to
                    -- Noto Sans, which has them, so the dictionary keeps its formatting.
                    if not have.bold then
                        font_face_css = font_face_css ..
                            "b, strong, th, h1, h2, h3, h4, h5, h6 { font-family: 'Noto Sans'; }\n"
                    end
                    if not have.italic then
                        font_face_css = font_face_css ..
                            "i, em, cite, dfn, var { font-family: 'Noto Sans'; }\n"
                    end
                    if not have.bolditalic then
                        font_face_css = font_face_css ..
                            "b i, i b, b em, em b, strong i, i strong, strong em, em strong { font-family: 'Noto Sans'; }\n"
                    end
                end
            end)
        end
        local css = font_face_css .. [[
            @page { margin: 0; font-family: ]] .. family .. [[; }
            body { margin: 0; line-height: 1.3; ]] .. justify .. [[ }
            blockquote, dd { margin: 0 1em; }
            ol, ul, menu { margin: 0; padding: 0 1.7em; }
        ]]
        return (extra and (css .. extra) or css), font_dir
    end

    -- The text scrolls vertically, but the horizontal swipes must reach the panel
    -- (they change the dictionary), so the text lets them through.
    local PassthroughScrollText = ScrollTextWidget:extend{}
    if ScrollTextWidget.onScrollText then
        function PassthroughScrollText:onScrollText(arg, ges)
            if ges.direction == "east" or ges.direction == "west" then
                return false
            end
            return ScrollTextWidget.onScrollText(self, arg, ges)
        end
    end

    TranslationPanel = InputContainer:extend{
        modal = true,
        name = "vocabulary_translation_panel",
        word = "",       -- the word, shown as the title
        entries = nil,   -- list of { dict = <dictionary name>, text = <full translation> }
        index = 1,       -- the entry that is shown
        anchor_y = 0,    -- y of the tapped word; decides if the panel goes up or down
        on_close = nil,  -- optional function called once when the panel is closed
        in_vocab = nil,  -- is the word in the vocabulary? (nil: it is looked up)
    }

    function TranslationPanel:init()
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local margin = Screen:scaleBySize(10)
        local pad = Screen:scaleBySize(14)
        local border = Screen:scaleBySize(2)
        local inner_w = sw - 2 * margin - 2 * pad - 2 * border
        local muted = Blitbuffer.Color8(110)
        local entry = self.entries[self.index]
        local several = #self.entries > 1

        -- Title row: the word on the left, "n / total" on the right (several dictionaries)
        local counter_w = several and Screen:scaleBySize(56) or 0
        local title = TextWidget:new{
            text = entry.word or self.word,   -- entry.word: headword of that dictionary
            -- The UI title font ("tfont") at the same size as KOReader's own window: the
            -- font selected for the interface, not the one of the book
            face = Font:getFace("tfont", math.max(22, G_reader_settings:readSetting("dict_font_size") or 20)),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
            max_width = inner_w - counter_w,
        }
        local content = VerticalGroup:new{ align = "left" }
        if several then
            local title_h = title:getSize().h
            table.insert(content, HorizontalGroup:new{
                align = "center",
                left_container:new{
                    dimen = Geom:new{ w = inner_w - counter_w, h = title_h },
                    title,
                },
                RightContainer:new{
                    dimen = Geom:new{ w = counter_w, h = title_h },
                    TextWidget:new{
                        text = string.format("%d / %d", self.index, #self.entries),
                        face = Font:getFace("cfont", 14),
                        fgcolor = muted,
                    },
                },
            })
        else
            table.insert(content, title)
        end
        if entry.dict and entry.dict ~= "" then
            table.insert(content, TextWidget:new{
                text = entry.dict,
                face = Font:getFace("cfont", 14),
                fgcolor = muted,
                max_width = inner_w,
            })
        end
        table.insert(content, VerticalSpan:new{ width = Screen:scaleBySize(8) })
        table.insert(content, LineWidget:new{
            background = Blitbuffer.Color8(225),
            dimen = Geom:new{ w = inner_w, h = Size.line.thin },
        })
        table.insert(content, VerticalSpan:new{ width = Screen:scaleBySize(8) })

        local max_h = math.floor(sh * 0.45)
        local body_widget
        -- HTML dictionaries (sametypesequence=h) are drawn like KOReader's own window does
        -- (bold, italics, paragraphs, lists...), instead of as plain text
        if entry.html and ok_html and ScrollHtmlWidget then
            local css_text, font_dir = htmlDictionaryCss(entry.css, entry.res_dir ~= nil)
            local function newHtmlWidget(height)
                return ScrollHtmlWidget:new{
                    html_body = entry.html,
                    html_resource_directory = entry.res_dir or font_dir,
                    css = css_text,
                    default_font_size = Screen:scaleBySize(G_reader_settings:readSetting("dict_font_size") or 20),
                    width = inner_w,
                    height = height,
                    dialog = self,
                }
            end
            local ok_w, widget = pcall(newHtmlWidget, max_h)
            if ok_w then
                -- A short definition fits on one page: use only the height it needs
                -- (getSinglePageHeight() is nil when the text needs several pages)
                local ok_h, used = pcall(function() return widget:getSinglePageHeight() end)
                if ok_h and used and used > 0 and used < max_h then
                    local ok_t, tight = pcall(newHtmlWidget, math.min(max_h, used + Screen:scaleBySize(6)))
                    if ok_t then
                        pcall(function() if widget.free then widget:free() end end)
                        widget = tight
                    end
                end
                body_widget = widget
            end
        end
        if not body_widget then
            -- The text box is as tall as its text, up to 45% of the screen (then it scrolls)
            -- Same font and size as KOReader's dictionary window. Not justified: in a
            -- narrow card the justification opens huge gaps between the words
            local justified = false
            local body_size = G_reader_settings:readSetting("dict_font_size") or 20
            local body_face = documentFace(body_size) or Font:getFace("cfont", body_size)
            local probe = TextBoxWidget:new{
                text = entry.text, face = body_face, width = inner_w,
                justified = justified, auto_para_direction = true,
            }
            local text_h = probe:getSize().h
            probe:free()
            body_widget = PassthroughScrollText:new{
                text = entry.text,
                face = body_face,
                width = inner_w,
                height = math.min(text_h, max_h),
                dialog = self,
                justified = justified,
                auto_para_direction = true,
            }
        end
        table.insert(content, body_widget)

        -- "Remove from vocabulary" button, only when the word is in the vocabulary
        self.remove_btn = nil
        if self.in_vocab == nil then self.in_vocab = wordInVocabulary(self.word) end
        if self.in_vocab then
            local bs = Size.border.thin
            local btn_h = Screen:scaleBySize(36)
            self.remove_label = TextWidget:new{
                text = "Remove from vocabulary",
                face = Font:getFace("cfont", 16),
                fgcolor = Blitbuffer.COLOR_BLACK,
                max_width = inner_w - 2 * Screen:scaleBySize(10),
            }
            self.remove_btn = FrameContainer:new{
                bordersize = bs,
                color = Blitbuffer.COLOR_DARK_GRAY,
                background = Blitbuffer.COLOR_WHITE,
                radius = Size.radius.button,
                margin = 0,
                padding = 0,
                CenterContainer:new{
                    dimen = Geom:new{ w = inner_w - 2 * bs, h = btn_h - 2 * bs },
                    self.remove_label,
                },
            }
            table.insert(content, VerticalSpan:new{ width = Screen:scaleBySize(10) })
            table.insert(content, self.remove_btn)
        end

        self.frame = FrameContainer:new{
            radius = Screen:scaleBySize(16),
            bordersize = border,
            padding = pad,
            background = Blitbuffer.COLOR_WHITE,
            content,
        }

        -- The card can be moved (hold and drag). It is centered on the screen by default,
        -- so it is first moved to the top or to the bottom, with a margin.
        self.movable = MovableContainer:new{ self.frame }
        if self.movable.setMovedOffset then
            local free = math.floor((sh - self.frame:getSize().h) / 2)
            local at_bottom = self.anchor_y < sh / 2
            self.movable:setMovedOffset({ x = 0, y = at_bottom and (free - margin) or (margin - free) })
        end
        self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
        self[1] = CenterContainer:new{ dimen = self.dimen, self.movable }

        if Device:hasKeys() then
            self.key_events.Close = { { Device.input.group.Back } }
        end
        if Device:isTouchDevice() then
            self.ges_events.TapClose = {
                GestureRange:new{ ges = "tap", range = self.dimen },
            }
            self.ges_events.Swipe = {
                GestureRange:new{ ges = "swipe", range = self.dimen },
            }
        end
    end

    -- The children (the movable container, the scrolling text) get the gestures before the
    -- panel and may keep them, so the two gestures that the panel needs are caught here,
    -- before they go down: a horizontal swipe (change dictionary) and a tap outside the card.
    function TranslationPanel:handleEvent(event)
        if event.handler == "onGesture" and event.args then
            local ges = event.args[1]
            if ges and ges.ges == "swipe"
                and (ges.direction == "west" or ges.direction == "east") then
                return self:onSwipe(nil, ges)
            elseif ges and ges.ges == "tap" and ges.pos
                and self.frame.dimen and ges.pos:notIntersectWith(self.frame.dimen) then
                return self:onClose()
            elseif ges and ges.ges == "tap" and ges.pos and self.remove_btn
                and self.remove_btn.dimen and ges.pos:intersectWith(self.remove_btn.dimen) then
                return self:onRemoveWord()
            end
        end
        return InputContainer.handleEvent(self, event)
    end

    -- A tap outside the card closes it; taps inside go to the scrolling text
    function TranslationPanel:onTapClose(arg, ges)
        if self.frame.dimen and ges.pos:notIntersectWith(self.frame.dimen) then
            self:onClose()
            return true
        end
        return false
    end

    -- Swipe left / right: next / previous dictionary, in a loop. The new panel is shown
    -- first and then this one is closed.
    function TranslationPanel:onSwipe(arg, ges)
        local BD = require("ui/bidi")
        local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
        if #self.entries > 1 and (direction == "west" or direction == "east") then
            local step = (direction == "west") and 1 or -1
            local index = (self.index - 1 + step) % #self.entries + 1
            UIManager:show(TranslationPanel:new{
                word = self.word,
                entries = self.entries,
                index = index,
                anchor_y = self.anchor_y,
                on_close = self.on_close,
                in_vocab = self.in_vocab,
            })
            -- The new panel owns on_close now: closing this one must not call it
            self.on_close = nil
            UIManager:close(self)
        end
        return true   -- the panel is modal: no swipe goes through to the page
    end

    -- Remove the word from the vocabulary and close the panel. Closing it repaints the
    -- page (onCloseWidget), so the underline and the gloss of the word disappear.
    function TranslationPanel:onRemoveWord()
        if removeFromVocabulary(self.word) then
            self.vocab_changed = true
            UIManager:close(self)
        else
            -- keep the panel open and say what happened
            self.remove_label:setText("Could not remove the word")
            UIManager:setDirty(self, function()
                return "ui", self.frame.dimen
            end)
        end
        return true
    end

    function TranslationPanel:onShow()
        UIManager:setDirty(self, function()
            return "ui", self.frame.dimen
        end)
        return true
    end

    function TranslationPanel:onCloseWidget()
        local dimen = self.frame.dimen
        if dimen then
            UIManager:setDirty(nil, function()
                return "ui", dimen
            end)
        end
        if self.vocab_changed then
            -- A word was removed: repaint the page once the panel is gone
            UIManager:nextTick(refreshVocabularyHighlights)
        end
        if self.on_close then
            local callback = self.on_close
            self.on_close = nil
            callback()
        end
    end

    function TranslationPanel:onClose()
        UIManager:close(self)
        return true
    end

    return TranslationPanel
end

-- Returns the full translations of `key` as a list of { dict = <name>, text = <text> }:
-- first the preferred dictionaries (WordReference, Babylon), then every other installed
-- dictionary that has exactly that word. Repeated entries are dropped.
local function collectTranslations(self, key)
    local dictionary = self.ui.dictionary
    local list, seen = {}, {}

    local function add(results, strict)
        if not strict then results = preferExactEntries(results, key) end
        for _, result in ipairs(results) do
            -- strict: with fuzzy search sdcv also returns similar words ("house" -> "housed")
            local exact = type(result.word) == "string" and result.word:lower() == key
            if result.definition and (exact or not strict) then
                local body = fullDefinitionText(result.definition)
                local id = tostring(result.dict) .. "\0" .. body
                if body ~= "" and not seen[id] then
                    seen[id] = true
                    list[#list + 1] = { dict = result.dict, text = body }
                end
            end
        end
    end

    add(sdcvLookup(dictionary, key, DICTIONARIES, true), false)
    add(sdcvLookup(dictionary, key, nil, true), true)
    return list
end

-- Phrasal verbs ------------------------------------------------------------
-- When a tapped word is followed by a particle ("gave up", "look out for"), the panel
-- also shows the phrasal verb, as its first page.

-- Particles that make a phrasal verb with the word before them
local PARTICLES = {
    ["up"] = true, ["down"] = true, ["in"] = true, ["out"] = true, ["on"] = true,
    ["off"] = true, ["over"] = true, ["away"] = true, ["back"] = true, ["about"] = true,
    ["around"] = true, ["round"] = true, ["along"] = true, ["through"] = true, ["by"] = true,
    ["for"] = true, ["with"] = true, ["of"] = true, ["to"] = true, ["at"] = true,
    ["into"] = true, ["onto"] = true, ["after"] = true, ["across"] = true, ["ahead"] = true,
    ["apart"] = true, ["aside"] = true, ["forward"] = true, ["together"] = true,
    ["behind"] = true, ["from"] = true, ["against"] = true, ["past"] = true, ["under"] = true,
}
local MAX_PARTICLES = 2   -- "come up with"

-- The particles that follow the word of `entry` (a draw cache entry), in order, up to
-- MAX_PARTICLES. It stops at the first word that is not a particle.
local function followingParticles(self, entry)
    local found = {}
    local doc = self.ui and self.ui.document
    if not (doc and entry and entry.pos1) then
        dbg_vocab("followingParticles: %q has no end xpointer", tostring(entry and entry.text))
        return found
    end

    local function wordOf(text)
        local w = tostring(text or ""):lower():gsub("’", "'"):match("[a-z']+")
        return w
    end

    -- By xpointer: it works across lines and pages
    local ok = pcall(function()
        local xp = entry.pos1
        while #found < MAX_PARTICLES do
            local start = doc:getNextVisibleWordStart(xp)
            local stop = start and doc:getNextVisibleWordEnd(start)
            if not stop then break end
            local w = wordOf(doc:getTextFromXPointers(start, stop))
            dbg_vocab("followingParticles: %q is followed by %q (particle: %s)",
                tostring(entry.text), tostring(w), tostring(w and PARTICLES[w] or false))
            if not (w and PARTICLES[w]) then break end
            found[#found + 1] = w
            xp = stop
        end
    end)
    if not ok then dbg_vocab("followingParticles: xpointer API failed") end
    return found
end

-- Entries of the dictionaries that have exactly `key` as a headword (no fuzzy matches:
-- "give up" must not fall back to "give"). A list of { dict, text, word }.
local function collectExactTranslations(ui, key)
    local dictionary = ui and ui.dictionary
    local list, seen = {}, {}
    if not dictionary then return list end

    local function add(results)
        for _, result in ipairs(results) do
            if result.definition and type(result.word) == "string" and result.word:lower() == key then
                local body = fullDefinitionText(result.definition)
                local id = tostring(result.dict) .. "\0" .. body
                if body ~= "" and not seen[id] then
                    seen[id] = true
                    list[#list + 1] = { dict = result.dict, text = body, word = key }
                end
            end
        end
    end

    add(sortByPreferredDictionary(sdcvLookup(dictionary, key, DICTIONARIES, false)))
    add(sdcvLookup(dictionary, key, nil, false))
    return list
end

-- The phrasal verb of `word` and the particles that follow it, as panel entries, or nil
-- when the dictionaries do not have it. The verb is tried as tapped ("gave") and as
-- the headwords that the lookup gave ("give"), the longest phrase first.
local MAX_VERB_FORMS = 3
local function phrasalVerbEntries(ui, word, results, following)
    if not (following and #following > 0) then
        dbg_vocab("phrasalVerbEntries: %q has no particle after it", tostring(word))
        return nil
    end

    local verbs, seen = {}, {}
    local function addVerb(v)
        v = vocabKey(v)
        if v ~= "" and not v:find("%s") and not seen[v] and #verbs < MAX_VERB_FORMS then
            seen[v] = true
            verbs[#verbs + 1] = v
        end
    end
    addVerb(word)
    for _, result in ipairs(results or {}) do
        if type(result.word) == "string" then addVerb(result.word) end
    end

    for n = #following, 1, -1 do
        local particles = table.concat(following, " ", 1, n)
        for _, verb in ipairs(verbs) do
            local list = collectExactTranslations(ui, verb .. " " .. particles)
            dbg_vocab("phrasalVerbEntries: %q -> %d entries", verb .. " " .. particles, #list)
            if #list > 0 then return list end
        end
    end
    return nil
end

-- Shows the full translation of `word`.
-- `anchor_y` is the y of the tapped word (the panel goes to the opposite half).
-- `following` is the optional list of particles that follow the word in the book.
function PageTextInfo:showFullTranslation(word, anchor_y, following)
    active_plugin = self
    local UIManager = require("ui/uimanager")

    -- Panel as dictionary: do a normal KOReader lookup. It goes through the dictionary
    -- hook below, so the panel gets the same results as the standard window (HTML
    -- dictionaries drawn as HTML, the dictionary order and presets of KOReader...).
    -- `boxes` only tells the panel where the word is (it opens on the other half).
    -- Always, also with the setting off: tapping an underlined word has always opened the
    -- panel, and this way it gets the HTML formatting (`force_panel` makes the hook use it).
    if self.ui and self.ui.dictionary then
        silence_vocab_once = true   -- the word is in the vocabulary: no "Vocabulary exists"
        local ok, err = pcall(function()
            self.ui.dictionary:onLookupWord(word, true,
                { { x = 0, y = anchor_y or 0, w = 0, h = 0 }, force_panel = true, following = following })
        end)
        silence_vocab_once = false   -- the event is sent at the start of the lookup
        if not ok then require("logger").warn("[PTI] lookup failed:", err) end
        return
    end

    local entries = collectTranslations(self, word:lower())

    if #entries == 0 then
        UIManager:show(require("ui/widget/infomessage"):new{ text = word .. ": no translation found" })
        return
    end

    UIManager:show(getTranslationPanelClass():new{
        word = word,
        entries = entries,
        index = 1,
        anchor_y = anchor_y or 0,
    })
end

-- ─────────────────────────────────────────────────────────────────────────────

-- Default dictionary window.
-- KOReader opens every dictionary lookup (tap on a word, selection > Dictionary,
-- the dictionary search box...) through ReaderDictionary:showDict(), which builds
-- the standard DictQuickLookup window. It is replaced here by the translation panel:
-- one entry per dictionary result (swipe left / right to change dictionary).
-- Everything before showDict is untouched, so the lookup itself, the lookup history
-- and the "WordLookedUp" event (vocabulary builder) work as always.
-- Not replaced: Wikipedia (it needs the standard window) and lookups without results
-- (KOReader's own "no results" dialog).
-- It is controlled by the setting "translation_panel_dictionary" (see
-- panelDictionaryEnabled above). Menu entry: PageTextInfo:getDictionaryPanelMenuItem(),
-- or the one in main.lua.

-- Menu entry (same style as the other checkable entries) that turns the setting on / off
function PageTextInfo:getDictionaryPanelMenuItem()
    local _ = require("gettext")
    return {
        text = _("Translation panel as dictionary"),
        checked_func = panelDictionaryEnabled,
        help_text = _([[Show dictionary lookups in the translation panel (one page per dictionary, swipe left / right to change) instead of KOReader's standard dictionary window.]]),
        callback = function()
            G_reader_settings:saveSetting(SETTING_PANEL_DICTIONARY, not panelDictionaryEnabled())
            G_reader_settings:flush()
            return true
        end,
    }
end

local function installDefaultDictionaryPanel()
    local ok, ReaderDictionary = pcall(require, "apps/reader/modules/readerdictionary")
    if not (ok and ReaderDictionary and ReaderDictionary.showDict) then
        require("logger").warn("[PTI] readerdictionary not found: the panel is not the default dictionary")
        return
    end
    -- The module can be loaded again: wrap showDict only once
    if ReaderDictionary._pti_panel_installed then return end
    ReaderDictionary._pti_panel_installed = true

    local original_showDict = ReaderDictionary.showDict
    local original_stardictLookup = ReaderDictionary.stardictLookup

    -- The vocabulary builder shows its "Vocabulary exists" window when a looked up word is
    -- already in the vocabulary (event "WordLookedUp", sent at the start of the lookup).
    -- While the panel is the dictionary that window is not wanted: this answers the event
    -- first and lets it through only for new words (they are added as always) or when the
    -- panel is off.
    local function findVocabularyBuilder(ui)
        if not ui then return nil end
        -- the plugin is registered under its folder name ("vocabbuilder"), not under the
        -- name it has inside its main.lua
        local vb = ui.vocabbuilder or ui.vocabulary_builder
        if vb then return vb end
        for _, module in ipairs(ui) do
            if type(module) == "table" and module.onWordLookedUp
                and tostring(module.name):lower():find("vocab", 1, true) then
                return module
            end
        end
        return nil
    end

    local function silenceVocabularyExists(ui)
        local vb = findVocabularyBuilder(ui)
        if not (vb and vb.onWordLookedUp) or vb._pti_silenced then return end
        vb._pti_silenced = true
        local original = vb.onWordLookedUp
        vb.onWordLookedUp = function(this, word, title, is_manual)
            local exists = wordInVocabulary(word)
            word_added_by_lookup = (not exists and not is_manual) and vocabKey(word) or nil
            if not is_manual and (panelDictionaryEnabled() or silence_vocab_once) and exists then
                return true
            end
            return original(this, word, title, is_manual)
        end
    end

    if original_stardictLookup then
        function ReaderDictionary:stardictLookup(...)
            silenceVocabularyExists(self.ui)
            return original_stardictLookup(self, ...)
        end
    end

    function ReaderDictionary:showDict(word, results, boxes, link, dict_close_callback)
        local forced = boxes and boxes.force_panel   -- tap on an underlined word
        if not (panelDictionaryEnabled() or forced) or self.is_wiki or not (results and results[1]) then
            return original_showDict(self, word, results, boxes, link, dict_close_callback)
        end

        local entries = {}
        for _, result in ipairs(results) do
            local def = result.definition
            if type(def) == "string" and def ~= "" then
                if result.is_html then
                    -- Drawn as HTML by the panel; the plain text is only the fallback
                    entries[#entries + 1] = {
                        dict = result.dict, word = result.word,
                        html = def, css = result.css, res_dir = result.dictionary_resource_directory,
                        text = fullDefinitionText(def),
                    }
                else
                    -- KOReader already turned it into plain text (without the tags)
                    local body = prettifyDefinition(def)
                    if body ~= "" then
                        entries[#entries + 1] = { dict = result.dict, word = result.word, text = body }
                    end
                end
            end
        end
        if #entries == 0 then
            return original_showDict(self, word, results, boxes, link, dict_close_callback)
        end

        -- The word is followed by a particle ("gave up"): the phrasal verb is the first page.
        -- A tap on an underlined word brings the particles in `boxes`; any other lookup (the
        -- word is not underlined yet) has none, so they are read after the looked up word.
        local following = boxes and boxes.following
        if not following and not tostring(word):find("%s") then
            -- End of the word: from the selection, or, for lookups that do not come from
            -- one (the double tap), from the word that is under its box on the screen
            local selected = self.highlight and self.highlight.selected_text
            local pos1 = selected and selected.pos1
            if not pos1 then
                local box = boxes and ((#boxes > 0 and boxes[#boxes]) or (boxes.w and boxes))
                if box and box.w and box.w > 0 then
                    local mid_x = box.x + math.floor(box.w / 2)
                    local mid_y = box.y + math.floor(box.h / 2)
                    local ok_t, found = pcall(function()
                        return self.ui.document._document:getTextFromPositions(
                            mid_x, mid_y, mid_x, mid_y, false, false)
                    end)
                    -- only if it is the same word that was looked up
                    if ok_t and found and found.text and found.pos1
                        and vocabKey(lastWord(found.text)) == vocabKey(word) then
                        pos1 = found.pos1
                    end
                end
            end
            dbg_vocab("showDict: lookup of %q, selection=%s, boxes=%s, end of the word=%s",
                tostring(word), tostring(selected ~= nil), tostring(boxes ~= nil), tostring(pos1))
            if pos1 then
                following = followingParticles({ ui = self.ui }, { pos1 = pos1, text = word })
            end
        end
        local phrasal = phrasalVerbEntries(self.ui, word, results, following)
        if phrasal then
            for i = #phrasal, 1, -1 do
                phrasal[i].word = phrasal[i].word .. " (phrasal verb detected)"
                table.insert(entries, 1, phrasal[i])
            end
            -- It is a phrasal verb: the single word that this lookup has just added is not kept
            if word_added_by_lookup == vocabKey(word) then
                removeFromVocabulary(word)
                word_added_by_lookup = nil
            end
        end

        local UIManager = require("ui/uimanager")
        self:dismissLookupInfo()   -- close the "Searching..." message

        -- `boxes` is the list of boxes of the looked up word (or a single box)
        local box = boxes and (boxes[1] or boxes)
        local anchor_y = box and tonumber(box.y) or 0

        local highlight = self.highlight
        UIManager:show(getTranslationPanelClass():new{
            word = word,
            entries = entries,
            index = 1,
            anchor_y = anchor_y,
            -- Same as DictQuickLookup:onClose: clear the selection a moment later,
            -- then run KOReader's own close callback
            on_close = function()
                if highlight then
                    local clear_id = highlight:getClearId()
                    local delay = G_defaults and G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S") or 0.5
                    UIManager:scheduleIn(delay, function() highlight:clear(clear_id) end)
                end
                if dict_close_callback then dict_close_callback() end
                -- The vocabulary builder may have added the word when it was looked up:
                -- repaint the page so it is underlined (and glossed) right away
                UIManager:nextTick(refreshVocabularyHighlights)
            end,
        })
    end
end

installDefaultDictionaryPanel()

-- Tap handler: opens the full translation if the tap lands on an underlined word.
-- Returns false otherwise, so the tap goes on to the rest of the reader (turning page...).
function PageTextInfo:onTapVocabularyWord(ges)
    -- The taps on a note (a double tap shows the note). It goes first because it must also
    -- work on pages without vocabulary words, and because the word of a note may be in the
    -- vocabulary too.
    if self:onTapNote(ges) then return true end
    if not (self._draw_cache and ges and ges.pos) then return false end
    -- Only in the highlight mode ("Highlight all words vocabulary builder and notes")
    if not self.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") then return false end
    local pad = Screen:scaleBySize(4)   -- a little margin: the words are small
    for _, entry in ipairs(self._draw_cache.entries) do
        if entry.text then
            -- the boxes of the word (several when it is split over two lines)
            for _, box in ipairs(entry.boxes or entry.fallback or {}) do
                if box.h ~= 0
                    and ges.pos.x >= box.x - pad and ges.pos.x <= box.x + box.w + pad
                    and ges.pos.y >= box.y - pad and ges.pos.y <= box.y + box.h + pad then
                    self:showFullTranslation(entry.text, box.y, followingParticles(self, entry))
                    return true
                end
            end
        end
    end
    return false
end

-- showNote (moved here from main.lua, so remove it from there)
-- If no argument, the call is coming from a new entry Notes added in the readerhighlight.lua source
-- to show possible notes associate to a word
function PageTextInfo:showNote(text_note)
    local UIManager = require("ui/uimanager")
    local TextViewer = require("ui/widget/textviewer")
    local _ = require("gettext")
    if text_note then
        -- local text = ""
        -- local annotations = self.ui.annotation.annotations
        -- for i, item in ipairs(annotations) do
        --     if item.note and item.text:upper() == text_note:upper() then
        --         text = text .. '<p style="display:block;font-size:1.25em;">' .. item.note .. "</p>"
        --     end
        -- end
        -- local FootnoteWidget = require("ui/widget/footnotewidget")
        -- local popup
        -- popup = FootnoteWidget:new{
        --     html = text,
        --     doc_font_name = self.ui.font.font_face,
        --     doc_font_size = Screen:scaleBySize(self.document.configurable.font_size),
        --     doc_margins = self.document:getPageMargins(),
        --     follow_callback = function() -- follow the link on swipe west
        --         UIManager:close(popup)
        --     end,
        --     dialog = self.dialog,
        -- }
        -- UIManager:show(popup)
        -- return true

        local annotations = self.ui.annotation.annotations
        for i, item in ipairs(annotations) do
            if item.note and item.text:upper() == text_note:upper() then
                local bookmark_note = item.note
                local index = i
                local textviewer
                textviewer = TextViewer:new{
                    title = _("Note"),
                    show_menu = false,
                    text = bookmark_note,
                    width = math.floor(math.min(self.ui.highlight.screen_w, self.ui.highlight.screen_h) * 0.8),
                    height = math.floor(math.max(self.ui.highlight.screen_w, self.ui.highlight.screen_h) * 0.4),
                    anchor = function()
                        return self.ui.highlight:_getDialogAnchor(textviewer, index)
                    end,
                    buttons_table = {
                        {
                            {
                                text = _("Delete note"),
                                callback = function()
                                    UIManager:close(textviewer)
                                    -- Deleting the highlight also deletes its note
                                    self.ui.highlight:deleteHighlight(index)
                                    if self.settings:isTrue("highlight_all_notes_and_allow_to_edit_them_on_tap") or self.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") then
                                        self:updateNotes()
                                        UIManager:setDirty("all", "full")
                                    end
                                end,
                            },
                            {
                                text = _("Edit note"),
                                callback = function()
                                    UIManager:close(textviewer)
                                    self.ui.highlight:editNote(index)
                                end,
                            },
                        },
                        {
                            {
                                text = _("Delete highlight"),
                                callback = function()
                                    UIManager:close(textviewer)
                                    self.ui.highlight:deleteHighlight(index)
                                end,
                            },
                            {
                                text = _("Highlight menu"),
                                callback = function()
                                    UIManager:close(textviewer)
                                    self.ui.highlight:showHighlightDialog(index)
                                end,
                            },
                        },
                    },
                }
                UIManager:show(textviewer)
                return true
            end
        end
    end

    local text = nil
    local annotations = self.ui.annotation.annotations
    for i, item in ipairs(annotations) do
        if item.text == self.ui.highlight.selected_text.text then
            text = item.note
        end
    end
    if self.ui.highlight.highlight_dialog then
        UIManager:close(self.ui.highlight.highlight_dialog)
    end
    local FootnoteWidget = require("ui/widget/footnotewidget")
    local popup = nil
    if text then
        text = '<p style="display:block;font-size:1.25em;">' .. text .. "</p>"
        --if true then
            --UIManager:show( require("ui/widget/textviewer"):new{text = text})
        --end
        popup = FootnoteWidget:new{
            html = text,
            doc_font_name = self.ui.font.font_face,
            doc_font_size = Screen:scaleBySize(self.document.configurable.font_size),
            doc_margins = self.document:getPageMargins(),
            follow_callback = function() -- follow the link on swipe west
                UIManager:close(popup)
            end,
            dialog = self.dialog,
        }
    else
        popup = FootnoteWidget:new{
            html = "No notes",
            doc_font_name = self.ui.font.font_face,
            doc_font_size = Screen:scaleBySize(self.document.configurable.font_size),
            doc_margins = self.document:getPageMargins(),
            follow_callback = function() -- follow the link on swipe west
                UIManager:close(popup)
            end,
            dialog = self.dialog,
        }
        -- local UIManager = require("ui/uimanager")
        -- local Notification = require("ui/widget/notification")
        -- UIManager:show(Notification:new{
        --     text = _("No note"),
        -- })
    end
    UIManager:show(popup)
    self.ui.highlight:clear()
    return false
end

-- Registers the tap zone once per reader. It is done on the first paint, when self.ui
-- is surely ready, and it goes before the zones that would take the tap otherwise.
function PageTextInfo:registerWordTap()
    if self._word_tap_registered then return end
    self._word_tap_registered = true
    pcall(function()
        self.ui:registerTouchZones({
            {
                id = "pagetextinfo_vocabulary_word_tap",
                ges = "tap",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                overrides = { "tap_link", "readerhighlight_tap", "tap_forward", "tap_backward" },
                handler = function(ges) return self:onTapVocabularyWord(ges) end,
            },
            {
                -- A two finger swipe to the east shows a popup (FootnoteWidget) with the notes of
                -- all the words of the page that have one
                id = "pagetextinfo_two_finger_swipe_east",
                ges = "two_finger_swipe",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                -- Before the zone of the gestures plugin for the same gesture, if there is one
                overrides = { "two_finger_swipe_east" },
                handler = function(ges)
                    local BD = require("ui/bidi")
                    -- only the east direction (mirrored UI layouts flip it)
                    if BD.flipDirectionIfMirroredUILayout(ges.direction) ~= "east" then
                        return false
                    end
                    -- the words with a note on this page, in page order, each one once
                    local cache = self._notes_draw_cache
                    if not (cache and cache.page == self.ui.view.state.page) then return false end
                    local html, seen = "", {}
                    for _, entry in ipairs(cache.entries) do
                        local id = entry.text:upper()
                        if not seen[id] then
                            seen[id] = true
                            local notes = ""
                            for _, item in ipairs(self.ui.annotation.annotations or {}) do
                                if item.note and item.text and item.text:upper() == id then
                                    notes = notes .. '<p style="display:block;font-size:1.15em;margin:0 0 0.4em 0;">'
                                        .. item.note .. "</p>"
                                end
                            end
                            if notes ~= "" then
                                html = html .. '<p style="display:block;font-size:1.25em;font-weight:bold;'
                                    .. 'margin:0.6em 0 0.2em 0;">' .. entry.text .. "</p>" .. notes
                            end
                        end
                    end
                    if html == "" then return false end
                    local UIManager = require("ui/uimanager")
                    local popup
                    popup = require("ui/widget/footnotewidget"):new{
                        html = html,
                        doc_font_name = self.ui.font.font_face,
                        doc_font_size = Screen:scaleBySize(self.document.configurable.font_size),
                        doc_margins = self.document:getPageMargins(),
                        follow_callback = function() -- follow the link on swipe west
                            UIManager:close(popup)
                        end,
                        dialog = self.dialog,
                    }
                    UIManager:show(popup)
                    return true
                end,
            },
        })
    end)
end

function PageTextInfo:drawXPointerVocabulary(bb, x, y)
    active_plugin = self
    local page_words = self.words[self.ui.view.state.page]
    if not page_words then return end

    self:registerWordTap()

    local cur_view_top = self.document:getCurrentPos()
    local current_font = self.ui.document:getFontFace():gsub(" ", "")
    local font_size    = self.ui.document.configurable.font_size
    local show_defs    = self.settings:isTrue("show_definitions")

    -- Gloss font: the font of the book, larger and bold so it stands out
    -- pt -> px of the book text, then -> getFace units
    local book_px = font_size * Screen:getDPI() / 72
    local translation_size = math.max(
        book_px * GLOSS_SCALE / Screen:scaleBySize(1),
        VOCAB_MIN_TRANSLATION_SIZE)
    local translation_face, translation_faux_bold
    if show_defs then
        translation_face, translation_faux_bold =
            getGlossFace(self, self.ui.document:getFontFace(), translation_size)
    end

    self._tr_cache = self._tr_cache or {}

    -- Geometry cache: only recomputed when page, position, font or layout change
    -- FIX: screen size (rotation) and line spacing are part of the key too.
    local key = table.concat({
        self.ui.view.state.page, cur_view_top, current_font, font_size,
        self.document:getPageCount(),
        Screen:getWidth(), Screen:getHeight(),
        tostring(self.ui.document.configurable.line_spacing),
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
                                -- pos1: end of the word, to read the words that follow it
                                entries[#entries + 1] = { boxes = precise, text = got, pos1 = word.pos1 }
                            end
                        elseif item.hyphenated then
                            -- No match but hyphenated: still underline with the rough boxes
                            entries[#entries + 1] = { fallback = boxes, text = item.text }
                        end
                    elseif item.hyphenated then
                        entries[#entries + 1] = { fallback = boxes, text = item.text }
                    end
                end
            end
        end
        self._draw_cache = { key = key, entries = entries, words = self.words }
    end

    -- Painting (cheap: only uses already computed data).
    -- Two passes: first all the underlines, then all the glosses, so a gloss is never covered
    -- by the underline of another word (the entries are grouped by word, not in page order).
    for _, entry in ipairs(self._draw_cache.entries) do
        if entry.fallback then
            paintBaselines(bb, entry.fallback, current_font)
        else
            for _, box in ipairs(entry.boxes) do
                if box.h ~= 0 then
                    -- Dotted underline slightly below the baseline
                    -- FIX: integer y (getBaseline returns a fractional value)
                    local y_line = math.floor(getBaseline(box, current_font) + Screen:scaleBySize(1))
                    paintDotted(bb, box.x, y_line, box.w, Size.line.thick)
                end
            end
        end
    end

    if show_defs then
        for _, entry in ipairs(self._draw_cache.entries) do
            if not entry.fallback then
                -- Gloss: only on the first box of the word
                local first_box
                for _, box in ipairs(entry.boxes) do
                    if box.h ~= 0 then first_box = box; break end
                end
                if first_box then
                    -- The gloss is memoized in the entry (entries are rebuilt whenever
                    -- the page / font / layout change).
                    local gloss = entry.gloss
                    if gloss == nil then
                        local lkey = entry.text:lower()
                        gloss = self._tr_cache[lkey]
                        if not gloss then
                            local tr = getTranslation(self, entry.text)
                            if tr then
                                gloss = shortGloss(tr)
                                self._tr_cache[lkey] = gloss   -- cache only valid results
                            end
                        end
                        entry.gloss = gloss or false
                    end
                    -- FIX: an empty gloss ("" is truthy in Lua) used to paint an empty chip.
                    if gloss and gloss ~= "" then
                        entry.layout = entry.layout or {}
                        paintGloss(bb, first_box, gloss, translation_face, entry.layout, translation_faux_bold)
                    end
                end
            end
        end
    end

    -- Persist any translation looked up during this paint (no-op if nothing new).
    savePersistedTranslations(self)
end
end
