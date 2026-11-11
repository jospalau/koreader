local Stats = require("book_rewind/stats")
local WildcardCards = require("book_rewind/wildcard_cards")
local Wildcards = require("book_rewind/wildcards")

local Cards = {}

Cards.MIN_SECONDS = 600

function Cards.minutes_missing(seconds)
    return math.max(1, math.ceil((Cards.MIN_SECONDS - seconds) / 60))
end

function Cards.number(value, separator)
    local digits = tostring(math.floor(value))
    local grouped = digits:reverse():gsub("(%d%d%d)", "%1" .. (separator == "%" and "%%" or separator)):reverse()
    if grouped:sub(1, 1) == separator then
        grouped = grouped:sub(2)
    end
    return grouped
end

-- Long titles would push everything else off the card. Counts characters, not bytes.
function Cards.clip(text, limit)
    local out, count = {}, 0
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
        if count > limit then
            return table.concat(out):gsub("%s+$", "") .. "…"
        end
        out[count] = char
    end
    return text
end

function Cards.pace(seconds)
    local rounded = math.floor(seconds + 0.5)
    if rounded < 60 then
        return string.format("%d s", rounded)
    end
    return string.format("%d min %d s", math.floor(rounded / 60), rounded % 60)
end

local function decimal(value, separator)
    return (string.format("%.1f", value):gsub("%.", separator))
end

function Cards.duration(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if hours == 0 then
        return string.format("%d min", minutes)
    elseif minutes == 0 then
        return string.format("%d h", hours)
    end
    return string.format("%d h %d min", hours, minutes)
end

local function date_from_yday(year, yday, t)
    local date = os.date("*t", os.time{ year = year, month = 1, day = yday, hour = 12 })
    return t.date(date.day, t.months[date.month])
end

local function period_of_hour(hour, t)
    if hour < 5 then return t.periods.dawn end
    if hour < 12 then return t.periods.morning end
    if hour < 18 then return t.periods.afternoon end
    return t.periods.night
end

local function bars(values, first, last, labels, highlight)
    local list = {}
    for i = first, last do
        list[#list + 1] = { value = values[i], label = labels(i), highlight = i == highlight }
    end
    return list
end

function Cards.profile_text(profile, t)
    local entry = t.profiles[profile.id]
    if type(entry[2]) == "function" then
        return entry[1], entry[2](unpack(profile.values))
    end
    return entry[1], string.format(entry[2], unpack(profile.values))
end

-- The books of the year with the ones marked as finished in KOReader and missing from the statistics: the shelf
-- (opened books) and the finished books. A marked book already in the year's lists counts once on the shelf.
function Cards.book_lists(metrics)
    local shelf, finished = {}, {}
    for _, book in ipairs(metrics.books or {}) do
        shelf[#shelf + 1] = book
    end
    for _, book in ipairs(metrics.finished_books or {}) do
        finished[#finished + 1] = book
    end
    for _, book in ipairs(metrics.marked_books or {}) do
        if not book.in_books then
            shelf[#shelf + 1] = book
        end
        finished[#finished + 1] = book
    end
    return shelf, finished
end

-- Cards without enough data are left out, so a short reading history still makes a coherent story.
function Cards.build(metrics, opts)
    local t = opts.strings
    local year = metrics.year
    local list = {}
    local function add(card)
        list[#list + 1] = card
    end
    local function number(value)
        return Cards.number(value, t.thousands)
    end
    local hours = metrics.total_seconds / 3600
    local wildcards = Wildcards.pick(metrics)
    local chosen = {}
    for _, candidate in ipairs(wildcards) do
        chosen[candidate.id] = candidate
    end
    local wildcard_helpers = {
        date = function(yday) return date_from_yday(year, yday, t) end,
        month_of = function(yday) return t.months[os.date("*t", os.time{ year = year, month = 1, day = yday, hour = 12 }).month] end,
        duration = Cards.duration,
        pace = Cards.pace,
        number = number,
        clip = Cards.clip,
        title_of = function(id)
            local book = id and opts.books[id]
            return book and Stats.clean_title(book.title, book.authors) or nil
        end,
    }

    add{
        id = "cover",
        art = "cover",
        kicker = opts.in_progress and t.cover_kicker_progress or t.cover_kicker,
        big = tostring(year),
        label = t.cover_label,
        body = opts.in_progress and t.cover_progress or nil,
        notice = opts.notice,
        buttons = opts.other_years,
    }
    add{
        id = "time",
        art = "time",
        kicker = t.time_kicker,
        big = Cards.duration(metrics.total_seconds),
        label = t.time_label(metrics.days_read),
        body = hours >= 24 and string.format(t.time_body, decimal(hours / 24, t.decimal)) or nil,
    }
    if metrics.total_pages > 0 then
        local books_equivalent = metrics.total_pages / 300
        add{
            id = "pages",
            art = "pages",
            kicker = t.pages_kicker,
            big = number(metrics.total_pages),
            label = t.pages_label(metrics.total_pages),
            body = books_equivalent >= 1 and string.format(t.pages_body, decimal(books_equivalent, t.decimal)) or nil,
        }
    end
    local shelf, finished_books = Cards.book_lists(metrics)
    if #shelf > 0 then
        local ranks = {}
        for i = 1, math.min(3, #metrics.books) do
            local book = metrics.books[i]
            ranks[i] = { title = book.title or t.untitled, meta = Cards.duration(book.seconds), book_id = book.id }
        end
        add{
            id = "books",
            books = shelf,
            kicker = t.books_kicker,
            big = tostring(#shelf),
            label = t.books_label(#shelf),
            body = #finished_books > 0 and string.format(t.books_body, #finished_books) or nil,
            ranks = ranks,
        }
    end
    if #finished_books >= 2 then
        local by_month = {}
        for month = 1, 12 do
            by_month[month] = {}
        end
        local finished = {}
        for i, book in ipairs(finished_books) do
            finished[i] = book
        end
        table.sort(finished, function(a, b) return a.finish_time < b.finish_time end)
        for _, book in ipairs(finished) do
            table.insert(by_month[book.finish_month], book)
        end
        add{
            id = "timeline",
            kicker = t.timeline_kicker,
            label = t.timeline_label(#finished),
            months_books = by_month,
        }
    end
    local devoured_in_one_sitting = chosen.one_sitting and metrics.devoured and chosen.one_sitting.data.book.id == metrics.devoured.book.id
    if metrics.devoured and not devoured_in_one_sitting then
        local devoured = metrics.devoured
        add{
            id = "devoured",
            kicker = t.devoured_kicker,
            title = devoured.book.title or t.untitled,
            book_id = devoured.book.id,
            total_pages = devoured.book.total_pages,
            big = t.devoured_label(devoured.days),
            body = string.format(t.devoured_body, devoured.pages_per_day),
        }
    end
    if #metrics.authors > 0 then
        local author = metrics.authors[1]
        local ranks = {}
        for i = 2, math.min(4, #metrics.authors) do
            ranks[#ranks + 1] = { title = metrics.authors[i].name, meta = Cards.duration(metrics.authors[i].seconds) }
        end
        add{
            id = "author",
            art = "author",
            kicker = t.author_kicker,
            big_text = author.name,
            label = t.author_label(Cards.duration(author.seconds), author.books),
            ranks = #ranks > 0 and ranks or nil,
        }
    end
    if metrics.longest_streak >= 2 then
        add{
            id = "streak",
            metrics = metrics,
            year = year,
            kicker = t.streak_kicker,
            big = tostring(metrics.longest_streak),
            label = t.streak_label,
        }
    end
    if metrics.days_read >= 2 and not chosen.memorable_day then
        add{
            id = "best_day",
            art = "best_day",
            kicker = t.best_day_kicker,
            big_text = date_from_yday(year, metrics.best_day.yday, t),
            date = os.date("*t", os.time{ year = year, month = 1, day = metrics.best_day.yday, hour = 12 }),
            label = string.format(t.reading_time, Cards.duration(metrics.best_day.seconds)),
        }
    end
    if metrics.longest_session.start and metrics.longest_session.seconds >= 900 then
        local session = metrics.longest_session
        local book = opts.books[session.book]
        add{
            id = "session",
            art = "session",
            kicker = t.session_kicker,
            big = Cards.duration(session.seconds),
            label = t.session_label,
            body = book and Stats.clean_title(book.title, book.authors) or nil,
        }
    end
    if metrics.best_hour then
        add{
            id = "hours",
            best_hour = metrics.best_hour,
            hour_values = metrics.hours,
            kicker = t.hours_kicker,
            big_text = period_of_hour(metrics.best_hour, t),
            label = string.format(t.hours_label, t.hour(metrics.best_hour)),
            bars = bars(metrics.hours, 0, 23, function(hour)
                return hour % 6 == 0 and tostring(hour) or ""
            end, metrics.best_hour),
        }
    end
    if metrics.days_read >= 7 then
        add{
            id = "weekdays",
            best = metrics.best_weekday,
            kicker = t.weekdays_kicker,
            big_text = t.weekdays[metrics.best_weekday],
            bars = bars(metrics.weekdays, 1, 7, function(day) return t.weekday_letters[day] end, metrics.best_weekday),
        }
    end
    if metrics.active_months >= 2 then
        add{
            id = "months",
            best = metrics.best_month,
            kicker = t.months_kicker,
            big_text = t.months[metrics.best_month],
            label = string.format(t.reading_time, Cards.duration(metrics.months[metrics.best_month])),
            bars = bars(metrics.months, 1, 12, function(month) return t.month_letters[month] end, metrics.best_month),
        }
    end
    if metrics.total_pages >= 20 then
        add{
            id = "speed",
            art = "speed",
            speed = metrics.pages_per_hour,
            body = metrics.total_pages > 0 and string.format(t.speed_body, math.floor(metrics.total_seconds / metrics.total_pages + 0.5)) or nil,
            kicker = t.speed_kicker,
            big = tostring(math.floor(metrics.pages_per_hour + 0.5)),
            label = t.speed_label,
        }
    end
    for _, candidate in ipairs(wildcards) do
        add(WildcardCards.build(candidate, metrics, t, wildcard_helpers))
    end
    if metrics.previous_seconds >= Cards.MIN_SECONDS then
        local change = math.floor((metrics.total_seconds - metrics.previous_seconds) * 100 / metrics.previous_seconds + 0.5)
        add{
            id = "previous",
            year = year,
            current_seconds = metrics.total_seconds,
            previous_seconds = metrics.previous_seconds,
            kicker = string.format(opts.in_progress and t.previous_kicker_progress or t.previous_kicker, year - 1),
            big = string.format("%s%s%%", change >= 0 and "+" or "-", number(math.abs(change))),
            label = t.previous_label,
            body = string.format(t.previous_body, Cards.duration(metrics.total_seconds), year, Cards.duration(metrics.previous_seconds), year - 1),
        }
    end
    local profile = Stats.archetype(metrics)
    local profile_name, profile_reason = Cards.profile_text(profile, t)
    add{
        id = "archetype",
        art = "profile_" .. profile.id,
        kicker = t.profile_kicker,
        big_text = profile_name,
        secondary = profile.secondary and string.format(t.profile_secondary, t.profiles[profile.secondary][1]) or nil,
        body = profile_reason,
    }
    local summary = {
        { title = t.summary_time, meta = Cards.duration(metrics.total_seconds) },
        { title = t.summary_pages, meta = number(metrics.total_pages) },
        { title = t.summary_books, meta = t.summary_books_value(#shelf, #finished_books) },
        { title = t.summary_streak, meta = t.summary_streak_value(metrics.longest_streak) },
        { title = t.summary_profile, meta = profile_name },
    }
    if metrics.authors[1] then
        table.insert(summary, 4, { title = t.summary_author, meta = metrics.authors[1].name })
    end
    if metrics.best_month then
        table.insert(summary, #summary, { title = t.summary_month, meta = t.months[metrics.best_month] })
    end
    add{
        id = "summary",
        art = "summary",
        year = year,
        kicker = string.format(t.summary_kicker, year),
        ranks = summary,
        buttons = {
            { id = "share", label = t.share },
            { id = "restart", label = t.restart },
        },
    }
    if opts.meta then
        add{ id = "about", meta = opts.meta, not_shared = true }
    end
    return list
end

return Cards
