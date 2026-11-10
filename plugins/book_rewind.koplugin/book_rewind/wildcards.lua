local Stats = require("book_rewind/stats")

-- Rare cards: each year shows the few that stand out the most for that reader.
local Wildcards = {}

Wildcards.MAX = 3

local COMEBACK_DAYS = 30
local WAVE_DAYS = 15
local WAITED_DAYS = 30
local SLOW_BURN_DAYS = 90
local MIN_BOOK_PAGES = 30
local LONG_BOOK_SECONDS = 1800
local ALMOST_MIN, ALMOST_MAX = 0.7, 0.9
local MIN_HIGHLIGHTS = 10
local MIN_RITUAL_DAYS = 20
local MIN_RITUAL_SHARE = 0.65
local MEMORABLE_SECONDS = 10800

local strength = Stats.strength

local function reading_gaps(metrics)
    local gaps = {}
    local days = metrics.day_list
    for i = 2, #days do
        local length = days[i] - days[i - 1] - 1
        if length > 0 then
            gaps[#gaps + 1] = { days = length, from = days[i - 1], to = days[i] }
        end
    end
    return gaps
end

local function best_book(metrics, accepts, better)
    local best
    for _, book in ipairs(metrics.books) do
        if accepts(book) and (not best or better(book, best)) then
            best = book
        end
    end
    return best
end

local Detect = {}

function Detect.back_after_years(metrics)
    local last = metrics.last_read_before
    local first = metrics.first_read
    if not last or not first or not metrics.last_year_seconds or metrics.last_year_seconds < 600 then
        return nil
    end
    if first - last < 365 * 86400 then
        return nil
    end
    local from, to = os.date("*t", last), os.date("*t", first)
    local months = (to.year - from.year) * 12 + to.month - from.month
    if to.day < from.day then
        months = months - 1
    end
    return {
        score = 2,
        group = "return",
        data = {
            years = math.floor(months / 12),
            months = months % 12,
            last_year = from.year,
            last_seconds = metrics.last_year_seconds,
            seconds = metrics.total_seconds,
        },
    }
end

function Detect.comeback(metrics)
    local longest
    for _, gap in ipairs(reading_gaps(metrics)) do
        if not longest or gap.days > longest.days then
            longest = gap
        end
    end
    if not longest or longest.days < COMEBACK_DAYS then
        return nil
    end
    local after = 0
    for _, yday in ipairs(metrics.day_list) do
        if yday > longest.to then
            after = after + 1
        end
    end
    return {
        score = strength(longest.days, COMEBACK_DAYS, 120),
        group = "return",
        data = { days = longest.days, from = longest.from, to = longest.to, after = after, book = metrics.first_book_by_day[longest.to] },
    }
end

function Detect.waves(metrics)
    local returns = {}
    for _, gap in ipairs(reading_gaps(metrics)) do
        if gap.days >= WAVE_DAYS then
            returns[#returns + 1] = gap.to
        end
    end
    if #returns < 3 then
        return nil
    end
    return { score = strength(#returns, 3, 8), group = "return", data = { returns = returns } }
end

function Detect.book_waited(metrics)
    local book = best_book(metrics, function(candidate)
        return candidate.finished and not candidate.started_before_year and candidate.pause and candidate.pause.days >= WAITED_DAYS
    end, function(a, b) return a.pause.days > b.pause.days end)
    if not book then
        return nil
    end
    return { score = strength(book.pause.days, WAITED_DAYS, 180), books = { book.id }, data = { book = book } }
end

function Detect.one_sitting(metrics)
    local book = best_book(metrics, function(candidate)
        return candidate.finished and not candidate.started_before_year and candidate.first_yday == candidate.finish_yday and candidate.total_pages >= MIN_BOOK_PAGES
    end, function(a, b) return a.total_pages > b.total_pages end)
    if not book then
        return nil
    end
    return { score = strength(book.total_pages, MIN_BOOK_PAGES, 300), books = { book.id }, data = { book = book } }
end

function Detect.slow_burn(metrics)
    local function span(book)
        return book.finish_yday - book.first_yday + 1
    end
    local book = best_book(metrics, function(candidate)
        return candidate.finished and not candidate.started_before_year and span(candidate) >= SLOW_BURN_DAYS
    end, function(a, b) return span(a) > span(b) end)
    if not book then
        return nil
    end
    return { score = strength(span(book), SLOW_BURN_DAYS, 240), books = { book.id }, data = { book = book, days = span(book) } }
end

function Detect.reread(metrics)
    local book = best_book(metrics, function(candidate)
        return candidate.reread
    end, function(a, b) return a.total_pages > b.total_pages end)
    if not book then
        return nil
    end
    return { score = 1.7, books = { book.id }, data = { book = book } }
end

-- Words that open many unrelated books, so they say nothing about a series.
local GENERIC_OPENINGS = {
    ["microsoft word"] = true, ["microsoft powerpoint"] = true, ["livro infantil"] = true, ["o livro"] = true, ["o que"] = true,
    ["curso de"] = true, ["manual de"] = true, ["guia pratico"] = true, ["sobre a"] = true, ["sobre o"] = true,
    ["historia da"] = true, ["historia de"] = true, ["historia do"] = true, ["historias de"] = true,
    ["poemas de"] = true, ["contos de"] = true, ["cronicas de"] = true, ["introducao a"] = true, ["introducao ao"] = true,
    ["direito civil"] = true, ["direito penal"] = true, ["direito e"] = true, ["processo civil"] = true, ["processo penal"] = true,
    ["contratos de"] = true, ["responsabilidade civil"] = true, ["o homem"] = true, ["a mulher"] = true,
}
local NOT_A_SERIES = { parte = true, part = true, vol = true, volume = true, livro = true, tomo = true }
local PUBLISHER_WORDS = { "colecao", "classicos", "edicao", "ed%.", "trad%.", "volume unico", "versao", "serie gvlaw", "antologia" }
local CONNECTIVES = {
    a = true, as = true, o = true, os = true, e = true, de = true, da = true, das = true, ["do"] = true, dos = true,
    em = true, no = true, na = true, of = true, the = true, ["and"] = true, y = true, el = true, la = true, que = true,
    edicao = true, vol = true, volume = true, livro = true, serie = true, parte = true,
}

local function bare_word(word)
    return (Stats.fold(word):gsub("^%p+", ""):gsub("%p+$", ""))
end

local VOLUME_MARKERS = { "vol%.?", "volume", "livro", "book", "tomo" }
local ROMAN_NUMBERS = {}
do
    local units = { "", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix" }
    for _, tens in ipairs({ "", "x", "xx", "xxx" }) do
        for _, unit in ipairs(units) do
            if tens .. unit ~= "" then
                ROMAN_NUMBERS[tens .. unit] = true
            end
        end
    end
end

local function is_number(text)
    return text:match("^%d+$") ~= nil or ROMAN_NUMBERS[text] == true
end

-- The last part of "Other Title - Name", without the punctuation left behind.
local function last_part(text)
    local at, name = 1, text
    while true do
        local _, to = text:find("%s+%-%s+", at)
        if not to then
            break
        end
        name = text:sub(to + 1)
        at = to + 1
    end
    return (name:gsub("[%s,;:%-]+$", ""))
end

-- "Name - Vol 3", "Other Title - Name - Vol. III", "Name (Livro 3)", "Name Book 3" and "Name Tomo II".
local function series_from_volume(title)
    local lowered = title:lower()
    for _, marker in ipairs(VOLUME_MARKERS) do
        local before, number = lowered:match("^(.-)%s*%(" .. marker .. "%s*(%w+)%)%s*$")
        if not before then
            before, number = lowered:match("^(.-)%s+%-%s+" .. marker .. "%s*(%w+)%s*$")
        end
        if not before then
            before, number = lowered:match("^(.-)%s+" .. marker .. "%s+(%w+)%s*$")
        end
        if before and before ~= "" and is_number(number) then
            local name = last_part(title:sub(1, #before))
            return #name >= 3 and name or nil
        end
    end
    return nil
end

-- "As Ilusões Armadas II" and "A Torre Negra III - As Terras". One word before the
-- numeral is usually a person, like "Henrique V", so it takes at least two.
local function series_from_roman(title)
    local before, number = title:match("^(.-)%s+([IVX]+)%s*$")
    if not before then
        before, number = title:match("^(.-)%s+([IVX]+)%s*[%-:]%s+.+$")
    end
    if not before or not ROMAN_NUMBERS[number:lower()] then
        return nil
    end
    local name = last_part(before)
    return select(2, name:gsub("%S+", "")) >= 2 and name or nil
end

-- "[Name 2] Title" and "[Name02]Title".
local function series_from_bracket(title)
    local name = title:match("%[([^%]]-)%s*%d+%]")
    if not name or #name < 3 or NOT_A_SERIES[Stats.fold(name)] then
        return nil
    end
    return name
end

-- "Title (Name)" and "Title (Name Livro 4)". Only a name repeated by the same author makes it a series.
local function series_from_parentheses(title)
    local name = title:match("%(([^%)]+)%)%s*$")
    if not name or name:match("^%d") then
        return nil
    end
    local folded = Stats.fold(name)
    for _, word in ipairs(PUBLISHER_WORDS) do
        if folded:find(word) then
            return nil
        end
    end
    name = name:gsub("%s+[Ll]ivro%s+%d+%s*$", ""):gsub("%s+%d+%s*$", "")
    return #name >= 4 and name or nil
end

-- The first two words of a title, when they say something: "O A" does not name a series.
local function title_opening(title)
    local first, second, rest = title:match("^(%S+)%s+(%S+)%s+(.+)$")
    if not rest or first:match("^%d") or (#first < 3 and #second < 3) then
        return nil
    end
    local opening = first .. " " .. second
    return not GENERIC_OPENINGS[Stats.fold(opening)] and opening or nil
end

-- The name a group of titles shares: more than the two words that formed it, and without loose
-- ends, so "Cavalo de Troia 2" and "Cavalo de Troia 3" give "Cavalo de Troia", not "Cavalo de".
local function shared_name(books, fallback)
    local shared
    for _, book in ipairs(books) do
        local words = {}
        for word in book.title:gmatch("%S+") do
            words[#words + 1] = word
        end
        if not shared then
            shared = words
        else
            local count = 0
            while shared[count + 1] and words[count + 1] and bare_word(shared[count + 1]) == bare_word(words[count + 1]) do
                count = count + 1
            end
            for index = #shared, count + 1, -1 do
                shared[index] = nil
            end
        end
    end
    local count = #(shared or {})
    while count > 0 do
        local last = bare_word(shared[count])
        if last ~= "" and not CONNECTIVES[last] and not last:match("^%d+$") then
            break
        end
        shared[count] = nil
        count = count - 1
    end
    if count == 0 then
        return fallback
    end
    return (table.concat(shared, " "):gsub("%s*[%p]+$", ""))
end

-- Most files have no series metadata, so the title is the next clue: an explicit volume or
-- bracket first, then the same author with several titles sharing a parenthesis or an opening.
function Wildcards.series_groups(metrics)
    local groups = {}
    local function add(key, name, book)
        groups[key] = groups[key] or { name = name, books = {} }
        table.insert(groups[key].books, book)
    end
    for _, book in ipairs(metrics.finished_books) do
        local title = book.title
        local name = book.series or (title and (series_from_volume(title) or series_from_bracket(title) or series_from_roman(title)))
        if name and name ~= "" then
            add("named:" .. Stats.author_key(name), name, book)
        elseif title then
            local author = Stats.split_authors(book.authors)[1]
            if author then
                local who = Stats.author_key(author)
                local parenthesis = series_from_parentheses(title)
                if parenthesis then
                    add("parenthesis:" .. who .. "|" .. Stats.author_key(parenthesis), parenthesis, book)
                end
                local opening = title_opening(title)
                if opening then
                    add("opening:" .. who .. "|" .. Stats.author_key(opening), opening, book)
                end
            end
        end
    end
    for key, group in pairs(groups) do
        if key:find("^opening:") then
            group.name = shared_name(group.books, group.name)
        end
    end
    return groups
end

function Detect.series_run(metrics)
    local groups = Wildcards.series_groups(metrics)
    local best
    for _, group in pairs(groups) do
        if #group.books >= 3 and (not best or #group.books > #best.books or (#group.books == #best.books and group.name < best.name)) then
            best = group
        end
    end
    if not best then
        return nil
    end
    table.sort(best.books, function(a, b) return a.first_time < b.first_time end)
    local in_a_row = true
    for i = 2, #best.books do
        if best.books[i].first_time < best.books[i - 1].finish_time then
            in_a_row = false
        end
    end
    local ids, last_finish = {}, 0
    for i, book in ipairs(best.books) do
        ids[i] = book.id
        last_finish = math.max(last_finish, book.finish_yday)
    end
    return {
        score = strength(#best.books, 3, 6),
        books = ids,
        data = {
            name = best.name,
            books = best.books,
            in_a_row = in_a_row,
            days = last_finish - best.books[1].first_yday + 1,
        },
    }
end

function Detect.juggler(metrics)
    local events = {}
    for _, book in ipairs(metrics.books) do
        for _, segment in ipairs(book.segments) do
            events[#events + 1] = { at = segment.from, change = 1 }
            events[#events + 1] = { at = segment.to + 1, change = -1 }
        end
    end
    table.sort(events, function(a, b)
        if a.at ~= b.at then
            return a.at < b.at
        end
        return a.change < b.change
    end)
    local open, most, peak = 0, 0, nil
    for _, event in ipairs(events) do
        open = open + event.change
        if open > most then
            most, peak = open, event.at
        end
    end
    if most < 3 then
        return nil
    end
    local rows, finished = {}, 0
    for _, book in ipairs(metrics.books) do
        for _, segment in ipairs(book.segments) do
            if segment.from <= peak and segment.to >= peak then
                rows[#rows + 1] = { book = book, from = segment.from, to = segment.to }
                if book.finished then
                    finished = finished + 1
                end
                break
            end
        end
    end
    return { score = strength(#rows, 3, 8), data = { rows = rows, peak = peak, finished = finished } }
end

function Detect.almost_there(metrics)
    if not metrics.year_closed then
        return nil
    end
    local book = best_book(metrics, function(candidate)
        return candidate.title and not candidate.finished and not candidate.read_later and candidate.seconds >= LONG_BOOK_SECONDS
            and candidate.overall >= ALMOST_MIN and candidate.overall < ALMOST_MAX and candidate.total_pages > 0
    end, function(a, b) return a.overall > b.overall end)
    if not book then
        return nil
    end
    return { score = strength(book.overall, ALMOST_MIN, ALMOST_MAX), books = { book.id }, data = { book = book } }
end

function Detect.extremes(metrics)
    local short, long
    for _, book in ipairs(metrics.finished_books) do
        if book.total_pages >= MIN_BOOK_PAGES then
            if not short or book.total_pages < short.total_pages then
                short = book
            end
            if not long or book.total_pages > long.total_pages then
                long = book
            end
        end
    end
    if not short or short == long then
        return nil
    end
    local ratio = long.total_pages / short.total_pages
    if ratio < 3 then
        return nil
    end
    return { score = strength(ratio, 3, 15), data = { short = short, long = long, ratio = ratio } }
end

function Detect.most_marked(metrics)
    local book = best_book(metrics, function(candidate)
        return candidate.finished and candidate.highlights >= MIN_HIGHLIGHTS
    end, function(a, b) return a.highlights > b.highlights end)
    if not book then
        return nil
    end
    return { score = strength(book.highlights, MIN_HIGHLIGHTS, 100), books = { book.id }, data = { book = book } }
end

function Detect.bookends(metrics)
    if not metrics.year_closed or #metrics.books < 5 then
        return nil
    end
    local first = best_book(metrics, function() return true end, function(a, b) return a.first_time < b.first_time end)
    local last = best_book(metrics, function() return true end, function(a, b) return a.last_time > b.last_time end)
    if first == last or last.last_yday - first.first_yday < 180 then
        return nil
    end
    return { score = 1.02, data = { first = first, last = last, between = #metrics.books - 2 } }
end

function Detect.ritual(metrics)
    if metrics.days_read < MIN_RITUAL_DAYS then
        return nil
    end
    local best_hour, best_days = nil, 0
    for hour = 0, 23 do
        local next_hour = (hour + 1) % 24
        local days = 0
        for _, hours in pairs(metrics.session_hours) do
            if hours[hour] or hours[next_hour] then
                days = days + 1
            end
        end
        if days > best_days then
            best_hour, best_days = hour, days
        end
    end
    local share = best_days / metrics.days_read
    if not best_hour or share < MIN_RITUAL_SHARE then
        return nil
    end
    -- The window covers two hours, and the card names the busier one.
    local next_hour = (best_hour + 1) % 24
    local at_hour, at_next = 0, 0
    for _, hours in pairs(metrics.session_hours) do
        at_hour = at_hour + (hours[best_hour] and 1 or 0)
        at_next = at_next + (hours[next_hour] and 1 or 0)
    end
    if at_next > at_hour then
        best_hour = next_hour
    end
    return { score = strength(share, MIN_RITUAL_SHARE, 1), data = { hour = best_hour, share = share } }
end

function Detect.past_midnight(metrics)
    local midnight = metrics.past_midnight
    if midnight.count < 5 then
        return nil
    end
    return { score = strength(midnight.count, 5, 30), data = { count = midnight.count, latest = midnight.latest } }
end

function Detect.memorable_day(metrics)
    local day = metrics.best_day
    if not day.yday or day.seconds < MEMORABLE_SECONDS or not day.book then
        return nil
    end
    return { score = strength(day.seconds, MEMORABLE_SECONDS, 28800), books = { day.book.id }, data = { yday = day.yday, seconds = day.seconds, book = day.book, pages = day.pages } }
end

function Detect.pace_change(metrics)
    local fast, slow
    for _, book in ipairs(metrics.books) do
        if book.title and book.pages >= MIN_BOOK_PAGES and book.seconds >= LONG_BOOK_SECONDS then
            local pace = book.seconds / book.pages
            if not fast or pace < fast.pace then
                fast = { book = book, pace = pace }
            end
            if not slow or pace > slow.pace then
                slow = { book = book, pace = pace }
            end
        end
    end
    if not fast or fast.book == slow.book or slow.pace / fast.pace < 2 then
        return nil
    end
    local ratio = slow.pace / fast.pace
    return { score = strength(ratio, 2, 6), data = { fast = fast, slow = slow, ratio = ratio } }
end

Wildcards.ORDER = {
    "back_after_years", "comeback", "waves", "book_waited", "one_sitting", "slow_burn", "reread", "series_run",
    "juggler", "almost_there", "extremes", "most_marked", "bookends", "ritual", "past_midnight", "memorable_day", "pace_change",
}

-- Every wildcard this reader qualifies for, strongest first. On a tie, the earlier one in the order comes first.
function Wildcards.candidates(metrics)
    local list = {}
    for index, id in ipairs(Wildcards.ORDER) do
        local candidate = Detect[id](metrics)
        if candidate then
            candidate.id = id
            candidate.index = index
            list[#list + 1] = candidate
        end
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return a.index < b.index
    end)
    return list
end

-- Similar cards do not appear together, and one book does not star in two of them.
function Wildcards.pick(metrics)
    local picked, groups, books = {}, {}, {}
    for _, candidate in ipairs(Wildcards.candidates(metrics)) do
        local free = not (candidate.group and groups[candidate.group])
        for _, id in ipairs(candidate.books or {}) do
            free = free and not books[id]
        end
        if free then
            picked[#picked + 1] = candidate
            if candidate.group then
                groups[candidate.group] = true
            end
            for _, id in ipairs(candidate.books or {}) do
                books[id] = true
            end
            if #picked == Wildcards.MAX then
                break
            end
        end
    end
    return picked
end

return Wildcards
