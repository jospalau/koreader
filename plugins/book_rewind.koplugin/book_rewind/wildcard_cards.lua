-- Turns the picked wildcards into card content. helpers holds the formatting shared with the regular cards.
local WildcardCards = {}

local Build = {}

function Build.comeback(data, metrics, t, h)
    local title = h.title_of(data.book)
    return {
        kicker = t.comeback_kicker,
        big = t.days_big(data.days),
        label = t.comeback_label,
        flag = t.comeback_flag,
        body = t.comeback_body(h.date(data.to), title and h.clip(title, 50), data.after),
        days = metrics.days,
        year = metrics.year,
        from = data.from,
        to = data.to,
    }
end

function Build.back_after_years(data, metrics, t, h)
    local year = metrics.year
    local gap_label
    if data.last_year < year - 1 then
        gap_label = data.last_year + 1 == year - 1 and tostring(year - 1) or t.year_range(data.last_year + 1, year - 1)
    end
    return {
        kicker = t.back_kicker,
        big = t.back_big(data.years),
        label = t.back_label(data.months),
        last_year = data.last_year,
        year = year,
        gap_label = gap_label,
        nothing = t.back_nothing,
        last_seconds = data.last_seconds,
        current_seconds = data.seconds,
        last_time = h.duration(data.last_seconds),
        current_time = h.duration(data.seconds),
    }
end

function Build.waves(data, metrics, t)
    return {
        kicker = t.waves_kicker,
        big = t.waves_big(#data.returns),
        body = t.waves_body(#data.returns),
        days = metrics.days,
        year = metrics.year,
        returns = data.returns,
    }
end

function Build.book_waited(data, _, t, h)
    local book = data.book
    local span = math.max(book.finish_yday - book.first_yday, 1)
    return {
        kicker = t.waited_kicker,
        book_id = book.id,
        big = t.days_big(book.pause.days),
        label = t.waited_label(book.pause.page),
        stop = (book.pause.from - book.first_yday) / span,
        resume = (book.pause.to - book.first_yday) / span,
        start_label = h.month_of(book.first_yday),
        pause_label = t.waited_pause,
        end_label = h.month_of(book.finish_yday),
        foot = t.waited_end,
    }
end

function Build.one_sitting(data, _, t, h)
    local book = data.book
    local started, ended = os.date("*t", book.first_time), os.date("*t", book.finish_time)
    return {
        kicker = t.sitting_kicker,
        book_id = book.id,
        big = t.sitting_big,
        label = t.sitting_label(book.total_pages, h.duration(book.finish_seconds)),
        foot = t.sitting_foot,
        start_hour = started.hour + started.min / 60,
        end_hour = ended.hour + ended.min / 60,
        start_label = t.hour(started.hour),
        end_label = t.hour(ended.hour),
    }
end

function Build.slow_burn(data, _, t, h)
    local book = data.book
    return {
        kicker = t.slow_kicker,
        big = t.days_big(data.days),
        label = t.slow_label,
        title = book.title or t.untitled,
        body = t.slow_body(h.date(book.first_yday), h.date(book.finish_yday)),
    }
end

function Build.reread(data, metrics, t)
    local book = data.book
    return {
        kicker = t.reread_kicker,
        book_id = book.id,
        big = t.reread_big(book.read_count or 2),
        label = t.reread_label,
        from_year = book.first_read_year,
        year = metrics.year,
        later = book.first_read_year and t.reread_later(metrics.year - book.first_read_year) or nil,
    }
end

function Build.series_run(data, _, t)
    return {
        kicker = t.series_kicker,
        big = t.books_big(#data.books),
        label = t.series_label(data.name),
        count = #data.books,
        foot = data.in_a_row and t.series_foot_row(data.days) or t.series_foot(data.days),
    }
end

function Build.juggler(data, metrics, t, h)
    table.sort(data.rows, function(a, b)
        return (a.to - a.from) > (b.to - b.from)
    end)
    local rows = {}
    for i = 1, math.min(5, #data.rows) do
        local row = data.rows[i]
        rows[i] = { title = row.book.title or t.untitled, from = row.from, to = row.to }
    end
    table.sort(rows, function(a, b) return a.from < b.from end)
    return {
        kicker = t.juggler_kicker,
        big = t.books_big(#data.rows),
        label = t.juggler_label(h.month_of(data.peak)),
        rows = rows,
        peak = data.peak,
        peak_label = h.month_of(data.peak),
        foot = data.finished > 0 and t.juggler_foot(data.finished) or nil,
        year = metrics.year,
    }
end

function Build.almost_there(data, _, t)
    local book = data.book
    local left = math.max(1, math.floor(book.total_pages * (1 - book.overall) + 0.5))
    return {
        kicker = t.almost_kicker,
        big = string.format("%d%%", math.floor(book.overall * 100)),
        label = t.almost_label(book.title),
        share = book.overall,
        foot = t.almost_foot(left),
        note = t.almost_note,
    }
end

function Build.extremes(data, _, t, h)
    return {
        kicker = t.extremes_kicker,
        short_title = data.short.title or t.untitled,
        short_pages = h.number(data.short.total_pages),
        short_word = t.pages_label(data.short.total_pages),
        short_label = t.extremes_short,
        long_title = data.long.title or t.untitled,
        long_pages = h.number(data.long.total_pages),
        long_word = t.pages_label(data.long.total_pages),
        long_label = t.extremes_long,
        foot = t.extremes_foot(math.floor(data.ratio)),
    }
end

function Build.most_marked(data, _, t, h)
    local book = data.book
    return {
        kicker = t.marked_kicker,
        big = t.marked_big(book.highlights),
        label = t.marked_label(book.title or t.untitled),
        notes = book.notes > 0 and t.marked_notes(book.notes) or nil,
        seed = book.highlights,
        number = h.number,
    }
end

function Build.bookends(data, _, t, h)
    return {
        kicker = t.ends_kicker,
        opened = t.ends_opened,
        closed = t.ends_closed,
        first_id = data.first.id,
        first_title = data.first.title or t.untitled,
        first_date = h.date(data.first.first_yday),
        last_id = data.last.id,
        last_title = data.last.title or t.untitled,
        last_date = h.date(data.last.last_yday),
        between = data.between,
        foot = data.between > 0 and t.ends_between(data.between) or nil,
    }
end

function Build.ritual(data, _, t)
    return {
        kicker = t.ritual_kicker,
        big = t.ritual_big(t.hour(data.hour)),
        body = t.ritual_body(math.floor(data.share * 100 + 0.5)),
        hour = data.hour,
    }
end

function Build.past_midnight(data, _, t)
    return {
        kicker = t.midnight_kicker,
        big = t.midnight_count(data.count),
        body = t.midnight_body,
        foot = data.latest and t.midnight_latest(t.clock(math.floor(data.latest / 60), data.latest % 60)) or nil,
    }
end

function Build.memorable_day(data, metrics, t, h)
    local date = os.date("*t", os.time{ year = metrics.year, month = 1, day = data.yday, hour = 12 })
    return {
        kicker = t.memorable_kicker,
        book_id = data.book.id,
        date = date,
        big = h.duration(data.seconds),
        label = t.memorable_label,
        body = t.memorable_body(data.pages, h.clip(data.book.title or t.untitled, 50)),
    }
end

function Build.pace_change(data, _, t, h)
    return {
        kicker = t.pace_kicker,
        fast_title = data.fast.book.title,
        fast_value = h.pace(data.fast.pace),
        fast_label = t.pace_fast,
        slow_title = data.slow.book.title,
        slow_value = h.pace(data.slow.pace),
        slow_label = t.pace_slow,
        foot = t.pace_foot(h.clip(data.slow.book.title, 34), data.ratio),
    }
end

function WildcardCards.build(candidate, metrics, strings, helpers)
    local card = Build[candidate.id](candidate.data, metrics, strings, helpers)
    card.id = candidate.id
    return card
end

return WildcardCards
