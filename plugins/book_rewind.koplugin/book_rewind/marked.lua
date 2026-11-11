-- Books marked as finished in KOReader that the statistics do not show as finished, for example after the
-- statistics were reset: the book settings keep the status and the day it changed, the statistics do not.
-- They count as finished books, on the shelf and on the timeline, and stay out of everything made from reading
-- sessions (time, pages, hours, profile, wildcards), which those books no longer have.
local Stats = require("book_rewind/stats")
local StablePages = require("book_rewind/stable_pages")

local Marked = {}

-- The same rule as reading to the end: a book marked as finished without being read does not count.
Marked.MIN_PROGRESS = 0.9

-- The day in summary.modified, at noon: "2026-05-10", or "10.05.2026" as older KOReader versions wrote it.
function Marked.date(text)
    if type(text) ~= "string" then
        return nil
    end
    local year, month, day = text:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not year then
        day, month, year = text:match("^(%d%d)%.(%d%d)%.(%d%d%d%d)$")
    end
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    if not year or month < 1 or month > 12 or day < 1 or day > 31 then
        return nil
    end
    local time = os.time{ year = year, month = month, day = day, hour = 12 }
    local check = os.date("*t", time)
    if check.year ~= year or check.month ~= month or check.day ~= day then
        return nil
    end
    return time
end

-- When the book was marked as finished, if it was in this year and the progress confirms the reading.
function Marked.finish_time(entry, year)
    if type(entry) ~= "table" or entry.status ~= "complete" then
        return nil
    end
    if type(entry.percent) ~= "number" or entry.percent < Marked.MIN_PROGRESS then
        return nil
    end
    local time = Marked.date(entry.modified)
    if not time or os.date("*t", time).year ~= year then
        return nil
    end
    return time
end

local function by_md5(books)
    local ids = {}
    for id, book in pairs(books or {}) do
        if book.md5 then
            ids[book.md5] = id
        end
    end
    return ids
end

local function by_id(metrics)
    local infos = {}
    for _, info in ipairs(metrics.books or {}) do
        infos[info.id] = info
    end
    return infos
end

-- The MD5s of marked books with no reading in the year's lists: their earlier sessions must be checked, since a
-- book read to the end in an earlier year and marked later does not belong to this year.
function Marked.to_check(metrics, entries, books, year)
    local ids, infos = by_md5(books), by_id(metrics)
    local md5s = {}
    for _, entry in ipairs(entries or {}) do
        if Marked.finish_time(entry, year) then
            local id = ids[entry.md5]
            if not (id and infos[id]) then
                md5s[#md5s + 1] = entry.md5
            end
        end
    end
    return md5s
end

local function file_title(file)
    return type(file) == "string" and (file:match("([^/]+)%.[^./]+$") or file:match("[^/]+$")) or nil
end

-- Adds metrics.marked_books, sorted by the day they were marked. books: the books of the year, as the store loads
-- them, with md5. finished_before: { [md5] = true } for books read to the end before the year. A book already in
-- the year's lists (read in part before a reset) keeps its id and gets marked_finished; the others get negative ids.
function Marked.add(metrics, entries, books, year, finished_before)
    local ids, infos = by_md5(books), by_id(metrics)
    finished_before = finished_before or {}
    local list, next_id = {}, -1
    for _, entry in ipairs(entries or {}) do
        local time = Marked.finish_time(entry, year)
        if time then
            local date = os.date("*t", time)
            local id = ids[entry.md5]
            local info = id and infos[id]
            local book
            if info then
                if not (info.finished or info.finished_earlier or info.reread) then
                    info.marked_finished = true
                    book = { id = info.id, title = info.title, authors = info.authors, total_pages = info.total_pages, in_books = true }
                end
            elseif not finished_before[entry.md5] then
                local stored = id and books[id]
                local raw = (stored and stored.title) or entry.title or file_title(entry.file)
                local authors = (stored and stored.authors) or entry.authors
                local total = StablePages.total(entry) or (stored and (stored.pages or 0) > 0 and stored.pages) or entry.doc_pages or 0
                book = {
                    id = next_id, title = Stats.clean_title(raw, authors), stored_title = raw, authors = authors,
                    total_pages = math.max(0, math.floor(total)),
                }
                next_id = next_id - 1
            end
            if book then
                book.marked, book.finished = true, true
                book.seconds, book.pages = 0, 0
                book.finish_time, book.finish_month, book.finish_yday = time, date.month, date.yday
                list[#list + 1] = book
            end
        end
    end
    table.sort(list, function(a, b)
        if a.finish_time ~= b.finish_time then
            return a.finish_time < b.finish_time
        end
        return tostring(a.title) < tostring(b.title)
    end)
    metrics.marked_books = list
    return list
end

return Marked
