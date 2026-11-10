local Stats = {}

local SESSION_GAP = 300
local MIN_BOOK_SECONDS = 60
local MIN_AUTHOR_SECONDS = 1800
local FINISHED_FRACTION = 0.9
local DEVOURED_MIN_PAGES = 30
local COVERAGE_STEPS = 1000
local TOP_SESSIONS = 5
local MIN_PATTERN_DAYS = 7
local MIN_STEADY_DAYS = 14
local SEGMENT_GAP_DAYS = 14
local NIGHT_HOURS = { [22] = true, [23] = true, [0] = true, [1] = true, [2] = true, [3] = true, [4] = true }
local MORNING_HOURS = { [5] = true, [6] = true, [7] = true, [8] = true }
local NIGHT_CHANCE, MORNING_CHANCE, WEEKEND_CHANCE = 7 / 24, 4 / 24, 2 / 7

local ACCENTS = {}
for plain, chars in pairs({
    a = "áàâãäÁÀÂÃÄ", c = "çÇ", e = "éèêëÉÈÊË", i = "íìîïÍÌÎÏ", n = "ñÑ", o = "óòôõöÓÒÔÕÖ", u = "úùûüÚÙÛÜ",
}) do
    for char in chars:gmatch("\195[\128-\191]") do
        ACCENTS[char] = plain
    end
end

local TITLE_PLACEHOLDERS = { ["n/a"] = true, ["unknown"] = true, ["desconhecido"] = true, ["desconocido"] = true }
-- What documents carry when nobody filled in the author: the account that made the file, or a generic label.
local AUTHOR_PLACEHOLDERS = {
    ["n/a"] = true, ["unknown"] = true, ["unknown author"] = true, ["author"] = true, ["autor"] = true,
    ["desconhecido"] = true, ["autor desconhecido"] = true, ["desconocido"] = true, ["autor desconocido"] = true,
    ["sem autor"] = true, ["user"] = true, ["usuario"] = true, ["windows user"] = true, ["microsoft office user"] = true,
    ["administrador"] = true, ["administrator"] = true, ["admin"] = true,
    ["varios"] = true, ["varios autores"] = true, ["various"] = true, ["various authors"] = true,
    ["anonymous"] = true, ["personal"] = true, ["digital source"] = true, ["pdfcreator"] = true,
    ["adolix split & merge pdf"] = true,
}
local TITLE_TAGS = {
    ["portuguese edition"] = true, ["brazilian portuguese edition"] = true, ["english edition"] = true, ["spanish edition"] = true,
    ["edicao em portugues"] = true, ["edicao portuguesa"] = true, ["edicion en espanol"] = true, ["edicion espanola"] = true,
    ["em portugues do brasil"] = true, ["em portuguese do brasil"] = true, ["oficial"] = true,
}
local DOMAIN_ENDINGS = { com = true, net = true, org = true, br = true, xyz = true, website = true, site = true, club = true, info = true, love = true, me = true, biz = true }
local SITE_MARKS = { "livros", "ebook", "e%-book", "epub", "%.com", "%.net", "%.org", "%.xyz", "%.website", "%.site" }
local FILE_EXTENSIONS = { pdf = true, doc = true, docx = true, indd = true, qxd = true, qxp = true, pmd = true, rtf = true, txt = true, epub = true, mobi = true, p65 = true, cdr = true }

function Stats.fold(text)
    return (text:gsub("\195[\128-\191]", ACCENTS):lower())
end
local fold = Stats.fold

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function known_title(value)
    return type(value) == "string" and trim(value) ~= "" and not TITLE_PLACEHOLDERS[fold(trim(value))]
end

local function known_author(value)
    if type(value) ~= "string" then
        return false
    end
    local name = fold(trim(value))
    if AUTHOR_PLACEHOLDERS[name] or name:find("https?:") or name:find("www%.") or name:find("%.com") or name:find("%.net") then
        return false
    end
    return select(2, name:gsub("[%a\194-\244]", "")) > 2
end

local function word_count(text)
    return select(2, text:gsub("%S+", ""))
end

-- A comma usually means "Last, First", so it only separates people when every part is a full name.
local function split_person_list(text)
    local parts = {}
    for part in text:gmatch("[^,]+") do
        parts[#parts + 1] = trim(part)
        if word_count(part) < 2 then
            return { text }
        end
    end
    return parts
end

-- Each line is a credited author, and files also pack several people into one line.
-- " e " stays together, because it is part of names like "Cruz e Sousa". "and" and "with" do not have that problem.
function Stats.split_authors(authors)
    local out = {}
    if type(authors) == "string" then
        for line in authors:gmatch("[^\n]+") do
            -- Program names can contain the separators, so the whole line is checked first.
            if not AUTHOR_PLACEHOLDERS[fold(trim(line))] then
                local separated = line:gsub(",?%s+[Aa][Nn][Dd]%s+", ";"):gsub(",?%s+[Ww][Ii][Tt][Hh]%s+", ";")
                for group in separated:gmatch("[^;&]+") do
                    -- Catalogs add the year to the name: "Albert Camus, 1958." or "Croce, Benedetto, 1866-1952".
                    local without_date = trim(group):gsub(",%s*%d%d%d%d%-?%d*%.?$", "")
                    for _, name in ipairs(split_person_list(trim(without_date))) do
                        if known_author(name) then
                            out[#out + 1] = name
                        end
                    end
                end
            end
        end
    end
    return out
end

-- The same person under different spellings: "J.R.R. Tolkien", "Tolkien, J. R. R.", "José"/"Jose".
function Stats.author_key(name)
    local words = {}
    for word in fold(name):gmatch("[%w\128-\255]+") do
        words[#words + 1] = word
    end
    table.sort(words)
    return #words > 0 and table.concat(words, " ") or name
end

local function is_domain(word)
    local lowered = word:lower()
    if lowered:find("^https?://") or lowered:find("^www%.") then
        return true
    end
    local ending = lowered:match("%.(%a+)/?$")
    return ending ~= nil and DOMAIN_ENDINGS[ending] == true and lowered:find("^[%w%.%-]+%.%a+/?$") ~= nil
end

-- A site named at the edges of the title. Only an address or a clear separator counts,
-- because a title can be about a site, like "Como vender na Amazon.com".
local function strip_site_edges(title)
    local cleaned = title
    local first, rest = cleaned:match("^(%S+)%s*[%-|_:]+%s*(.+)$")
    if first and is_domain(first) then
        cleaned = rest
    end
    local head, last = cleaned:match("^(.-)%s*[%-|_]+%s*(%S+)$")
    if head and head ~= "" and is_domain(last) then
        cleaned = head
    end
    local address_head, address = cleaned:match("^(.-)%s+(%S+)$")
    if address_head and address_head ~= "" and (address:lower():find("^https?://") or address:lower():find("^www%.")) then
        cleaned = address_head
    end
    return cleaned
end

local function is_site_mark(text)
    local lowered = text:lower()
    for _, mark in ipairs(SITE_MARKS) do
        if lowered:find(mark) then
            return true
        end
    end
    return false
end

-- "Eric Hobsbawm - A Era das Revoluções" is how a file is named, not the title of the book.
local function strip_author_prefix(title, authors)
    local head, rest = title:match("^(.-)%s+%-%s+(.+)$")
    if not head or not authors then
        return title
    end
    local head_key = Stats.author_key(head)
    for _, name in ipairs(Stats.split_authors(authors)) do
        if Stats.author_key(name) == head_key then
            return rest
        end
    end
    return title
end

-- What the file carries besides the title: the program that made it, its own file name,
-- the mark of the site it came from, a tag about the edition, or the author again.
function Stats.clean_title(title, authors)
    if not known_title(title) then
        return nil
    end
    local cleaned = trim(title)
    local from_file = false
    local wrapped = cleaned:match("^%((.*)%)$")
    if wrapped and wrapped:lower():find("^microsoft %a+ %- ") then
        cleaned = trim(wrapped)
    end
    local lowered = cleaned:lower()
    for _, prefix in ipairs({ "microsoft word %- ", "microsoft powerpoint %- " }) do
        local _, ends = lowered:find("^" .. prefix)
        if ends then
            cleaned = cleaned:sub(ends + 1)
            from_file = true
        end
    end
    local stem, extension = cleaned:match("^(.+)%.(%w+)$")
    if stem and FILE_EXTENSIONS[extension:lower()] then
        cleaned = stem:gsub("[_%-]cs%d+$", "")
        from_file = true
    end
    if cleaned:find("_") and (from_file or not cleaned:find("%s")) then
        cleaned = trim((cleaned:gsub("_+", " ")))
    end
    cleaned = cleaned:gsub("%s*%[([^%]]*)%]", function(inner)
        return is_site_mark(inner) and "" or nil
    end)
    cleaned = cleaned:gsub("%s*%(([^%)]*)%)", function(inner)
        local tag = trim(inner)
        return (TITLE_TAGS[fold(tag)] or is_domain(tag)) and "" or nil
    end)
    cleaned = strip_site_edges(trim(cleaned))
    cleaned = strip_author_prefix(trim(cleaned), authors)
    cleaned = trim(cleaned)
    return cleaned ~= "" and cleaned or trim(title)
end

-- Time zones change on multiples of 15 minutes, so a bucket never crosses a local hour or day.
local function date_parts(cache, timestamp)
    local key = math.floor(timestamp / 900)
    local parts = cache[key]
    if not parts then
        parts = os.date("*t", timestamp)
        cache[key] = parts
    end
    return parts
end

local function ranked(map)
    local list = {}
    for key, value in pairs(map) do
        list[#list + 1] = { key = key, seconds = value }
    end
    table.sort(list, function(a, b)
        if a.seconds ~= b.seconds then
            return a.seconds > b.seconds
        end
        return tostring(a.key) < tostring(b.key)
    end)
    return list
end

local function best_index(values, first, last)
    local best
    for i = first, last do
        if values[i] > 0 and (not best or values[i] > values[best]) then
            best = i
        end
    end
    return best
end

local function filled(first, last)
    local values = {}
    for i = first, last do
        values[i] = 0
    end
    return values
end

-- Marks the part of the book a page covers, so the same passage read at another font size counts once.
-- Returns how many steps are new, and how many of those are not in other either.
local function mark_page(marks, page, total, other)
    if page < 1 or total <= 0 then
        return 0, 0
    end
    local first = math.floor((page - 1) * COVERAGE_STEPS / total) + 1
    local last = math.max(first, math.floor(page * COVERAGE_STEPS / total))
    local added, beyond = 0, 0
    for step = first, math.min(last, COVERAGE_STEPS) do
        if not marks[step] then
            marks[step] = true
            added = added + 1
            if not (other and other[step]) then
                beyond = beyond + 1
            end
        end
    end
    return added, beyond
end

local function reached(steps)
    return steps / COVERAGE_STEPS >= FINISHED_FRACTION
end

-- A page number in the pagination of the book, since the font size changes how many pages it has.
local function reference_page(page, total, page_count)
    if page_count > 0 and total and total > 0 then
        return math.max(1, math.floor(page * page_count / total + 0.5))
    end
    return page
end

-- Turns rows of { book, start, duration, page, total_pages } into the columns Stats.compute reads.
function Stats.columns(rows)
    local columns = { book = {}, start = {}, duration = {}, page = {}, total = {} }
    for i, row in ipairs(rows) do
        columns.book[i], columns.start[i], columns.duration[i] = row[1], row[2], row[3]
        columns.page[i], columns.total[i] = row[4], row[5]
    end
    return columns
end

-- How many times a book was read to the end, from its pages in time order, each as { page, total_pages }.
-- Each pass that reaches the end starts the next one from zero.
function Stats.count_passes(history)
    local marks, steps, passes = {}, 0, 0
    for _, row in ipairs(history) do
        steps = steps + mark_page(marks, row[1], row[2])
        if reached(steps) then
            passes = passes + 1
            marks, steps = {}, 0
        end
    end
    return passes
end

local function days_elapsed(year, now)
    local today = os.date("*t", now)
    if today.year == year then
        return today.yday
    end
    return os.date("*t", os.time{ year = year, month = 12, day = 31, hour = 12 }).yday
end

-- opts.rows holds the reading of the year in columns (see Stats.columns), ordered by start time.
-- opts.earlier_pages has the pages of these books read before the year, each as { book, page, total_pages }.
-- opts.earlier_history(book), when given, returns the earlier pages of a reread book in time order, as Stats.count_passes reads them.
function Stats.compute(opts)
    local year, books = opts.year, opts.books
    local rows = opts.rows
    local row_book, row_start, row_duration, row_page, row_total = rows.book, rows.start, rows.duration, rows.page, rows.total
    local result = {
        year = year,
        total_seconds = 0,
        hours = filled(0, 23),
        weekdays = filled(1, 7),
        months = filled(1, 12),
        previous_seconds = opts.previous_seconds or 0,
    }
    local cache, days, book_seconds, year_marks = {}, {}, {}, {}
    local tracks, first_book_by_day, session_hours = {}, {}, {}
    local midnight = { count = 0 }
    local book_first, book_last = {}, {}
    local last_end, session_seconds, session_start, session_book_seconds
    local longest = { seconds = 0 }
    local session_lengths = {}

    local function close_session()
        if not session_seconds then
            return
        end
        session_lengths[#session_lengths + 1] = session_seconds
        local ended = os.date("*t", last_end)
        if ended.yday ~= date_parts(cache, session_start).yday then
            midnight.count = midnight.count + 1
            local minutes = ended.hour * 60 + ended.min
            if ended.hour < 6 and (not midnight.latest or minutes > midnight.latest) then
                midnight.latest = minutes
            end
        end
        if session_seconds > longest.seconds then
            local book, most = nil, -1
            for id, seconds in pairs(session_book_seconds) do
                if seconds > most then
                    book, most = id, seconds
                end
            end
            longest = { seconds = session_seconds, start = session_start, book = book }
        end
    end

    local earlier_marks, earlier_steps = {}, {}
    for _, row in ipairs(opts.earlier_pages or {}) do
        local id = row[1]
        local marks = earlier_marks[id]
        if not marks then
            marks = {}
            earlier_marks[id] = marks
        end
        earlier_steps[id] = (earlier_steps[id] or 0) + mark_page(marks, row[2], row[3])
    end

    -- How far each book got, to know the moment it reached the end: after that, opening it again
    -- to look something up does not change when it was finished, nor how long it took.
    local progress = {}
    for i = 1, #row_start do
        local book, start, duration, page, total = row_book[i], row_start[i], row_duration[i], row_page[i], row_total[i]
        local parts = date_parts(cache, start)
        if parts.year == year then
            result.total_seconds = result.total_seconds + duration
            result.hours[parts.hour] = result.hours[parts.hour] + duration
            result.weekdays[parts.wday] = result.weekdays[parts.wday] + duration
            result.months[parts.month] = result.months[parts.month] + duration
            days[parts.yday] = (days[parts.yday] or 0) + duration
            book_seconds[book] = (book_seconds[book] or 0) + duration
            if not book_first[book] then
                book_first[book] = start
                year_marks[book] = {}
                local before = earlier_steps[book] or 0
                -- A book already read to the end before the year is finished again only by reading it all again.
                progress[book] = { year_steps = 0, all_steps = before, reread = reached(before), seconds = 0 }
            end
            book_last[book] = start
            first_book_by_day[parts.yday] = first_book_by_day[parts.yday] or book

            local state = progress[book]
            local done_before = state.finish_time ~= nil
            local added, beyond = mark_page(year_marks[book], page, total, earlier_marks[book])
            state.year_steps = state.year_steps + added
            state.all_steps = state.all_steps + beyond
            state.seconds = state.seconds + duration
            if not done_before and reached(state.reread and state.year_steps or state.all_steps) then
                state.finish_time, state.finish_yday, state.finish_seconds = start, parts.yday, state.seconds
            elseif done_before and parts.yday == state.finish_yday then
                -- The last pages after the 90% mark, read on the same day, are part of the time it took.
                state.finish_seconds = state.finish_seconds + duration
            end

            local track = tracks[book]
            if not track then
                track = { segments = { { from = parts.yday, to = parts.yday } } }
                tracks[book] = track
            elseif parts.yday ~= track.last_yday and not done_before then
                local gap = parts.yday - track.last_yday - 1
                if gap > 0 and (not track.pause or gap > track.pause.days) then
                    track.pause = { days = gap, page = track.last_page, total = track.last_total, from = track.last_yday, to = parts.yday }
                end
                if gap > SEGMENT_GAP_DAYS then
                    track.segments[#track.segments + 1] = { from = parts.yday, to = parts.yday }
                else
                    track.segments[#track.segments].to = parts.yday
                end
            end
            if not done_before then
                track.last_yday, track.last_page, track.last_total = parts.yday, page, total
            end

            if not last_end or start - last_end > SESSION_GAP then
                close_session()
                session_seconds, session_start, session_book_seconds = 0, start, {}
                session_hours[parts.yday] = session_hours[parts.yday] or {}
                session_hours[parts.yday][parts.hour] = true
            end
            session_seconds = session_seconds + duration
            session_book_seconds[book] = (session_book_seconds[book] or 0) + duration
            last_end = start + duration
        end
    end
    close_session()
    result.longest_session = longest

    table.sort(session_lengths, function(a, b) return a > b end)
    local top_sum = 0
    for i = 1, math.min(TOP_SESSIONS, #session_lengths) do
        top_sum = top_sum + session_lengths[i]
    end
    result.top_sessions_seconds = top_sum / TOP_SESSIONS

    local yday_list = {}
    local best_day = { seconds = 0 }
    for yday, seconds in pairs(days) do
        yday_list[#yday_list + 1] = yday
        if seconds > best_day.seconds or (seconds == best_day.seconds and yday < (best_day.yday or math.huge)) then
            best_day = { yday = yday, seconds = seconds }
        end
    end
    table.sort(yday_list)
    local streak, best_streak, best_streak_end = 0, 0, nil
    for i, yday in ipairs(yday_list) do
        streak = (i > 1 and yday == yday_list[i - 1] + 1) and streak + 1 or 1
        if streak > best_streak then
            best_streak, best_streak_end = streak, yday
        end
    end
    if best_day.yday then
        -- Pages of the day follow the same rule as the pages of the year.
        local day_seconds, day_marks, day_steps, day_total = {}, {}, {}, {}
        for i = 1, #row_start do
            local parts = date_parts(cache, row_start[i])
            if parts.year == year and parts.yday == best_day.yday then
                local id = row_book[i]
                day_seconds[id] = (day_seconds[id] or 0) + row_duration[i]
                day_marks[id] = day_marks[id] or {}
                day_steps[id] = (day_steps[id] or 0) + mark_page(day_marks[id], row_page[i], row_total[i])
                day_total[id] = math.max(day_total[id] or 0, row_total[i])
            end
        end
        local most = ranked(day_seconds)[1]
        local book = books[most.key] or {}
        local page_count = (book.pages and book.pages > 0) and book.pages or day_total[most.key]
        best_day.book_id = most.key
        best_day.pages = math.floor(day_steps[most.key] / COVERAGE_STEPS * page_count + 0.5)
    end
    result.days = days
    result.day_list = yday_list
    result.first_book_by_day = first_book_by_day
    result.session_hours = session_hours
    result.past_midnight = midnight
    result.year_closed = os.date("*t", opts.now or os.time()).year > year
    result.first_read = row_start[1]
    result.last_read_before = opts.last_read_before
    result.last_year_seconds = opts.last_year_seconds
    result.longest_streak_end = best_streak_end
    result.days_read = #yday_list
    result.longest_streak = best_streak
    result.best_day = best_day
    result.first_yday, result.last_yday = yday_list[1], yday_list[#yday_list]
    result.consistency = math.min(1, #yday_list / days_elapsed(year, opts.now or os.time()))

    result.best_hour = best_index(result.hours, 0, 23)
    result.best_weekday = best_index(result.weekdays, 1, 7)
    result.best_month = best_index(result.months, 1, 12)
    local active_months = 0
    for month = 1, 12 do
        if result.months[month] > 0 then
            active_months = active_months + 1
        end
    end
    result.active_months = active_months

    local night, morning = 0, 0
    for hour = 0, 23 do
        if NIGHT_HOURS[hour] then night = night + result.hours[hour] end
        if MORNING_HOURS[hour] then morning = morning + result.hours[hour] end
    end
    local total = result.total_seconds
    result.night_share = total > 0 and night / total or 0
    result.morning_share = total > 0 and morning / total or 0
    result.weekend_share = total > 0 and (result.weekdays[1] + result.weekdays[7]) / total or 0

    result.books, result.finished_books = {}, {}
    local by_id = {}
    local author_names, author_seconds, author_books, author_long_books = {}, {}, {}, {}
    local merged_into = {}
    local total_pages = 0
    for _, entry in ipairs(ranked(book_seconds)) do
        local id, seconds = entry.key, entry.seconds
        local book = books[id] or {}
        local page_count = (book.pages and book.pages > 0) and book.pages or 0
        local state = progress[id]
        local read = math.floor(state.year_steps / COVERAGE_STEPS * page_count + 0.5)
        total_pages = total_pages + read
        local earlier = earlier_marks[id]
        local done_before = state.reread
        -- Finished in the year it reached the end, or in a later year when read again from start to end.
        local finished = state.finish_time ~= nil
        -- The last pages of a book started in another year count, however quick they were.
        local completed_now = earlier ~= nil and not done_before and finished
        if seconds >= MIN_BOOK_SECONDS or completed_now then
            local first_date, last_date = date_parts(cache, book_first[id]), date_parts(cache, book_last[id])
            local finish_date = finished and date_parts(cache, state.finish_time) or nil
            local pause = tracks[id].pause
            if pause then
                pause.page = reference_page(pause.page, pause.total, page_count)
            end
            local info = {
                id = id,
                title = Stats.clean_title(book.title, book.authors),
                seconds = seconds,
                pages = read,
                total_pages = page_count,
                finished = finished,
                finished_earlier = not finished and done_before,
                reread = finished and done_before,
                overall = state.all_steps / COVERAGE_STEPS,
                read_later = opts.read_later and opts.read_later[id] or false,
                series = known_title(book.series) and (book.series:gsub("%s*#[%d%.]+%s*$", "")) or nil,
                highlights = book.highlights or 0,
                notes = book.notes or 0,
                pause = pause,
                segments = tracks[id].segments,
                first_time = book_first[id],
                authors = book.authors,
                first_yday = first_date.yday,
                last_yday = last_date.yday,
                last_time = book_last[id],
                -- When it reached the end, and the time it took until the end of that day.
                finish_time = state.finish_time,
                finish_yday = finish_date and finish_date.yday,
                finish_month = finish_date and finish_date.month,
                finish_seconds = state.finish_seconds,
                started_before_year = earlier ~= nil,
            }
            if info.reread then
                local reads = opts.earlier_reads and opts.earlier_reads[id]
                if reads then
                    info.first_read_year = os.date("*t", reads.first).year
                end
                local history = opts.earlier_history and opts.earlier_history(id)
                -- Earlier passes, at least one since it was finished before, plus this one.
                info.read_count = math.max(1, history and Stats.count_passes(history) or 0) + 1
            end
            result.books[#result.books + 1] = info
            by_id[id] = info
            if finished then
                result.finished_books[#result.finished_books + 1] = info
            end
            for _, name in ipairs(Stats.split_authors(book.authors)) do
                local key = Stats.author_key(name)
                author_names[key] = author_names[key] or name
                author_seconds[key] = (author_seconds[key] or 0) + seconds
                author_books[key] = (author_books[key] or 0) + 1
                if seconds >= MIN_AUTHOR_SECONDS then
                    author_long_books[key] = (author_long_books[key] or 0) + 1
                end
            end
        end
    end
    result.total_pages = total_pages
    -- The fastest book read from start to end inside this year. Very short files would always win.
    for _, book in ipairs(result.finished_books) do
        if not book.started_before_year and book.total_pages >= DEVOURED_MIN_PAGES then
            local days_taken = book.finish_yday - book.first_yday + 1
            local best = result.devoured
            if not best or days_taken < best.days or (days_taken == best.days and book.total_pages > best.book.total_pages) then
                result.devoured = { book = book, days = days_taken, pages_per_day = math.floor(book.total_pages / days_taken + 0.5) }
            end
        end
    end
    result.pages_per_hour = total > 0 and total_pages * 3600 / total or 0
    result.best_day.book = result.best_day.book_id and by_id[result.best_day.book_id] or nil

    -- "Friedrich Nietzsche" inside "Friedrich Wilhelm Nietzsche" is the same person, when only one longer name fits.
    local function word_set(key)
        local set, count = {}, 0
        for word in key:gmatch("%S+") do
            set[word] = true
            count = count + 1
        end
        return set, count
    end
    local word_sets = {}
    for key in pairs(author_seconds) do
        local set, count = word_set(key)
        word_sets[key] = { set = set, count = count }
    end
    for short in pairs(author_seconds) do
        local short_set, short_count = word_sets[short].set, word_sets[short].count
        local target, matches = nil, 0
        if short_count >= 2 then
            for long in pairs(author_seconds) do
                local long_set, long_count = word_sets[long].set, word_sets[long].count
                if long_count > short_count then
                    local inside = true
                    for word in pairs(short_set) do
                        inside = inside and long_set[word] == true
                    end
                    if inside then
                        target, matches = long, matches + 1
                    end
                end
            end
        end
        if matches == 1 then
            merged_into[short] = target
        end
    end
    for short, long in pairs(merged_into) do
        if author_seconds[short] > author_seconds[long] then
            author_names[long] = author_names[short]
        end
        author_seconds[long] = author_seconds[long] + author_seconds[short]
        author_books[long] = author_books[long] + author_books[short]
        author_long_books[long] = (author_long_books[long] or 0) + (author_long_books[short] or 0)
        author_seconds[short] = nil
    end

    result.authors = {}
    local authors_read, read_seconds, squared = 0, 0, 0
    for _, entry in ipairs(ranked(author_seconds)) do
        result.authors[#result.authors + 1] = {
            name = author_names[entry.key],
            seconds = entry.seconds,
            books = author_books[entry.key],
            long_books = author_long_books[entry.key] or 0,
        }
        if entry.seconds >= MIN_AUTHOR_SECONDS then
            authors_read = authors_read + 1
            read_seconds = read_seconds + entry.seconds
            squared = squared + entry.seconds * entry.seconds
        end
    end
    result.authors_read = authors_read
    -- How many authors the time really went to: 3 equal authors give 3, and one dominant author gives close to 1.
    result.effective_authors = squared > 0 and read_seconds * read_seconds / squared or 0

    result.longest_session_seconds = longest.seconds
    return result
end

-- A trait counts once it reaches its threshold. The score goes from 1 at the threshold to 2 at
-- what is exceptional for it, and stops there, so one huge number cannot outweigh a whole year.
function Stats.strength(value, threshold, exceptional)
    if value < threshold then
        return 0
    end
    return math.min(2, 1 + (value - threshold) / (exceptional - threshold))
end
local strength = Stats.strength

-- How far a share goes beyond chance, from 0 to 1, because time windows have different sizes.
-- A few days of reading say nothing about a habit.
local function habit(share, chance, days_read)
    if days_read < MIN_PATTERN_DAYS then
        return 0
    end
    return strength((share - chance) / (1 - chance), 0.3, 0.8)
end

-- The strongest trait wins, and the next one, if any, is returned as secondary.
-- On a tie, the earlier one in the list wins.
function Stats.archetype(metrics)
    local top_author = metrics.authors[1]
    local percent = function(share) return math.floor(share * 100 + 0.5) end
    local author_share = top_author and top_author.seconds / math.max(metrics.total_seconds, 1) or 0
    local concentration = metrics.effective_authors > 0 and 1 / metrics.effective_authors or 0
    local steady_score = strength(metrics.longest_streak, 30, 180)
    if metrics.days_read >= MIN_STEADY_DAYS then
        steady_score = math.max(steady_score, strength(metrics.consistency, 0.4, 0.9))
    end
    local loyal_score = 0
    if top_author and top_author.long_books >= 2 and author_share >= 0.5 then
        loyal_score = strength(concentration, 0.4, 1)
    end
    local candidates = {
        { score = habit(metrics.night_share, NIGHT_CHANCE, metrics.days_read), id = "night_owl", values = { percent(metrics.night_share) } },
        { score = habit(metrics.morning_share, MORNING_CHANCE, metrics.days_read), id = "early_bird", values = { percent(metrics.morning_share) } },
        { score = steady_score, id = "steady", values = { percent(metrics.consistency), metrics.longest_streak } },
        { score = strength(metrics.top_sessions_seconds, 5400, 14400), id = "marathoner", values = { math.floor(metrics.longest_session_seconds / 60) } },
        {
            score = loyal_score,
            id = "loyal",
            values = { percent(author_share), top_author and top_author.name or "", top_author and top_author.long_books or 0 },
        },
        { score = habit(metrics.weekend_share, WEEKEND_CHANCE, metrics.days_read), id = "weekender", values = { percent(metrics.weekend_share) } },
        { score = strength(metrics.effective_authors, 5, 15), id = "explorer", values = { metrics.authors_read } },
    }
    local best, second
    for _, candidate in ipairs(candidates) do
        if candidate.score > 0 then
            if not best or candidate.score > best.score then
                best, second = candidate, best
            elseif not second or candidate.score > second.score then
                second = candidate
            end
        end
    end
    if not best then
        return { id = "curious", values = { #metrics.books, metrics.days_read } }
    end
    best.secondary = second and second.id or nil
    return best
end

return Stats
