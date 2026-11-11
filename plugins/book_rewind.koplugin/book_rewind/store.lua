local SQ3 = require("lua-ljsqlite3/init")
local ffi = require("ffi")
local logger = require("logger")

local Store = {}

local function open(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    file:close()
    local ok, conn = pcall(SQ3.open, path, "ro")
    return ok and conn or nil
end

-- The connection is always closed, and a database that cannot be read counts as having no data.
local function with_connection(path, work)
    local conn = open(path)
    if not conn then
        return nil
    end
    local ok, result = pcall(work, conn)
    conn:close()
    if not ok then
        logger.warn("Book Rewind: could not read", path, result)
        return nil
    end
    return result
end

local function year_bounds(year)
    return os.time{ year = year, month = 1, day = 1, hour = 0 }, os.time{ year = year + 1, month = 1, day = 1, hour = 0 }
end

local function number(value)
    return tonumber(value) or 0
end

local function numbers(column)
    for i = 1, #column do
        column[i] = number(column[i])
    end
    return column
end

local function single_value(conn, query)
    local result = conn:exec(query)
    return result and tonumber(result[1][1]) or nil
end

local function seconds_in_year(conn, year)
    local first, after = year_bounds(year)
    return single_value(conn, string.format("SELECT SUM(duration) FROM page_stat_data WHERE start_time >= %d AND start_time < %d", first, after)) or 0
end

function Store.year_seconds(path, year)
    return with_connection(path, function(conn) return seconds_in_year(conn, year) end) or 0
end

-- The years with at least min_seconds of reading, newest first. Walks the start_time index,
-- so the cost follows the number of years and not the number of pages read.
function Store.years(path, min_seconds)
    return with_connection(path, function(conn)
        local years = {}
        local time = single_value(conn, "SELECT MIN(start_time) FROM page_stat_data")
        while time do
            local year = os.date("*t", time).year
            local _, after = year_bounds(year)
            if seconds_in_year(conn, year) >= (min_seconds or 0) then
                table.insert(years, 1, year)
            end
            time = single_value(conn, string.format("SELECT MIN(start_time) FROM page_stat_data WHERE start_time >= %d", after))
        end
        return years
    end) or {}
end

-- A year in progress is compared with the same part of the previous one, not with all of it.
local function previous_period_end(year, first, now)
    local today = os.date("*t", now)
    if today.year ~= year then
        return first
    end
    today.year = year - 1
    today.isdst = nil
    return math.min(first, os.time(today))
end

function Store.load_year(path, year, now)
    return with_connection(path, function(conn)
        local first, after = year_bounds(year)
        -- The columns come back as they are, converted in place: a busy year has tens of thousands of rows.
        local rows = { book = {}, start = {}, duration = {}, page = {}, total = {} }
        local result = conn:exec(string.format(
            "SELECT id_book, start_time, duration, page, total_pages FROM page_stat_data WHERE start_time >= %d AND start_time < %d ORDER BY start_time",
            first, after))
        if result then
            rows = {
                book = numbers(result[1]), start = numbers(result[2]), duration = numbers(result[3]),
                page = numbers(result[4]), total = numbers(result[5]),
            }
        end

        -- Only the books read in the year matter here.
        local year_books = string.format("SELECT id_book FROM page_stat_data WHERE start_time >= %d AND start_time < %d", first, after)
        local in_year = "id_book IN (" .. year_books .. ")"
        local books = {}
        result = conn:exec("SELECT id, title, authors, pages, series, highlights, notes, md5 FROM book WHERE id IN (" .. year_books .. ")")
        if result then
            for i = 1, #result[1] do
                books[number(result[1][i])] = {
                    title = result[2][i], authors = result[3][i], pages = number(result[4][i]),
                    series = result[5][i], highlights = number(result[6][i]), notes = number(result[7][i]),
                    md5 = type(result[8][i]) == "string" and result[8][i] ~= "" and result[8][i] or nil,
                }
            end
        end

        local earlier_pages = {}
        result = conn:exec(string.format(
            "SELECT DISTINCT id_book, page, total_pages FROM page_stat_data WHERE start_time < %d AND total_pages > 0 AND %s",
            first, in_year))
        if result then
            for i = 1, #result[1] do
                earlier_pages[i] = { number(result[1][i]), number(result[2][i]), number(result[3][i]) }
            end
        end

        local earlier_reads = {}
        result = conn:exec(string.format("SELECT id_book, MIN(start_time) FROM page_stat_data WHERE start_time < %d AND %s GROUP BY id_book", first, in_year))
        if result then
            for i = 1, #result[1] do
                earlier_reads[number(result[1][i])] = { first = number(result[2][i]) }
            end
        end

        local read_later = {}
        result = conn:exec(string.format("SELECT DISTINCT id_book FROM page_stat_data WHERE start_time >= %d AND %s", after, in_year))
        if result then
            for i = 1, #result[1] do
                read_later[number(result[1][i])] = true
            end
        end

        local last_read_before = single_value(conn, string.format("SELECT MAX(start_time) FROM page_stat_data WHERE start_time < %d", first))
        local last_year_seconds = last_read_before and seconds_in_year(conn, os.date("*t", last_read_before).year) or nil

        local previous_first = year_bounds(year - 1)
        local previous_seconds = single_value(conn, string.format(
            "SELECT SUM(duration) FROM page_stat_data WHERE start_time >= %d AND start_time < %d",
            previous_first, previous_period_end(year, first, now or os.time())))
        return {
            rows = rows, books = books, earlier_pages = earlier_pages, earlier_reads = earlier_reads, read_later = read_later,
            last_read_before = last_read_before, last_year_seconds = last_year_seconds,
            previous_seconds = previous_seconds or 0, year = year,
        }
    end)
end

-- The ids of the books with these partial MD5s, as { [md5] = { id, ... } }. Only hexadecimal MD5s are asked for.
function Store.book_ids_by_md5(path, md5s)
    local quoted = {}
    for _, md5 in ipairs(md5s or {}) do
        if type(md5) == "string" and md5:match("^%x+$") then
            quoted[#quoted + 1] = "'" .. md5 .. "'"
        end
    end
    if #quoted == 0 then
        return {}
    end
    return with_connection(path, function(conn)
        local ids = {}
        local result = conn:exec("SELECT md5, id FROM book WHERE md5 IN (" .. table.concat(quoted, ",") .. ")")
        if result then
            for i = 1, #result[1] do
                local md5 = result[1][i]
                ids[md5] = ids[md5] or {}
                table.insert(ids[md5], number(result[2][i]))
            end
        end
        return ids
    end) or {}
end

-- The pages of one book read before the year, in time order, to count how many times it was read to the end.
function Store.book_history(path, book_id, year)
    return with_connection(path, function(conn)
        local first = year_bounds(year)
        local history = {}
        local result = conn:exec(string.format(
            "SELECT page, total_pages FROM page_stat_data WHERE id_book = %d AND start_time < %d AND total_pages > 0 ORDER BY start_time",
            book_id, first))
        if result then
            for i = 1, #result[1] do
                history[i] = { number(result[1][i]), number(result[2][i]) }
            end
        end
        return history
    end)
end

local MAX_COVER_SIDE = 10000

-- A cover whose size does not match its pixels would make the screen read outside of it.
local function plausible_cover(Blitbuffer, w, h, kind, stride)
    if not (w and h and kind and stride) or w <= 0 or h <= 0 or w > MAX_COVER_SIDE or h > MAX_COVER_SIDE then
        return false
    end
    local row_bytes = ({
        [Blitbuffer.TYPE_BB4] = math.ceil(w / 2), [Blitbuffer.TYPE_BB8] = w, [Blitbuffer.TYPE_BB8A] = w * 2,
        [Blitbuffer.TYPE_BBRGB16] = w * 2, [Blitbuffer.TYPE_BBRGB24] = w * 3, [Blitbuffer.TYPE_BBRGB32] = w * 4,
    })[kind]
    return row_bytes ~= nil and stride >= row_bytes
end

local Covers = {}
Covers.__index = Covers

-- Covers live in the cache of the Cover browser plugin, found there by title and author.
-- The cache has no index on titles, so they are read once, and each cover is then read by its rowid.
-- The connection stays open until close(), so a year with many covers opens the database once.
function Store.open_covers(path)
    local conn = open(path)
    if not conn then
        return nil
    end
    local ok, by_title = pcall(function()
        local index = {}
        local result = conn:exec("SELECT rowid, title, authors FROM bookinfo WHERE has_cover = 'Y' AND cover_bb_data IS NOT NULL")
        if result then
            for i = 1, #result[1] do
                local title = result[2][i]
                if type(title) == "string" then
                    index[title] = index[title] or {}
                    table.insert(index[title], { rowid = number(result[1][i]), authors = result[3][i] or "" })
                end
            end
        end
        return index
    end)
    if not ok then
        logger.warn("Book Rewind: could not read", path, by_title)
        conn:close()
        return nil
    end
    return setmetatable({ conn = conn, by_title = by_title }, Covers)
end

-- The book with the same title and author. Without one, the title alone is enough only when a single
-- book in the cache has it: generic titles such as "Poemas" would bring the cover of another book.
function Covers:find(title, authors)
    local list = type(title) == "string" and self.by_title[title]
    if not list then
        return nil
    end
    local wanted = type(authors) == "string" and authors or ""
    for _, entry in ipairs(list) do
        if entry.authors == wanted then
            return entry.rowid
        end
    end
    for i = 2, #list do
        if list[i].authors ~= list[1].authors then
            return nil
        end
    end
    return list[1].rowid
end

local function read_cover(statement, rowid)
    local Blitbuffer = require("ffi/blitbuffer")
    local zstd = require("ffi/zstd")
    local row = statement:bind(rowid):step()
    if not row then
        return nil
    end
    local w, h, kind, stride, blob = tonumber(row[1]), tonumber(row[2]), tonumber(row[3]), tonumber(row[4]), row[5]
    if type(blob) ~= "table" or not plausible_cover(Blitbuffer, w, h, kind, stride) then
        return nil
    end
    local data, size = zstd.zstd_uncompress_ctx(blob[1], blob[2])
    if size ~= stride * h then
        ffi.C.free(data)
        return nil
    end
    local cover = Blitbuffer.new(w, h, kind, data, stride)
    cover:setAllocated(1)
    return cover
end

-- Returns the cover as a new Blitbuffer, owned by the caller, or nil.
function Covers:load(title, authors)
    local rowid = self:find(title, authors)
    if not rowid then
        return nil
    end
    self.statement = self.statement or self.conn:prepare(
        "SELECT cover_w, cover_h, cover_bb_type, cover_bb_stride, cover_bb_data FROM bookinfo WHERE rowid = ?")
    local ok, cover = pcall(read_cover, self.statement, rowid)
    pcall(function() self.statement:clearbind():reset() end)
    if not ok then
        logger.warn("Book Rewind: could not read a cover", cover)
        return nil
    end
    return cover
end

function Covers:close()
    if self.statement then
        pcall(self.statement.close, self.statement)
        self.statement = nil
    end
    pcall(self.conn.close, self.conn)
end

return Store
