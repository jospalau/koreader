-- Draws the wildcard cards, in the same 600x800 design space and print language as the regular ones.
return function(Paint, tools)
    local BLACK, WHITE, GRAY, LIGHT = tools.BLACK, tools.WHITE, tools.GRAY, tools.LIGHT
    local SERIF, BOLD, ITALIC, SANS = tools.SERIF, tools.BOLD, tools.ITALIC, tools.SANS
    local spine, pile, clip, upper = tools.spine, tools.pile, tools.clip, tools.upper
    local BASE_W = 600

    -- A small fixed sequence, so the drawings look the same every time the card opens.
    local function sequence(seed)
        local state = seed
        return function(low, high)
            state = (state * 1103515245 + 12345) % 2147483648
            return low + math.floor(state / 65536) % (high - low + 1)
        end
    end

    local function stars(c, seed, count, top, bottom, avoid)
        local next_value = sequence(seed)
        for _ = 1, count do
            local x, y = next_value(16, 584), next_value(top, bottom)
            local free = true
            for _, band in ipairs(avoid or {}) do
                free = free and not (y >= band[1] and y <= band[2])
            end
            if free then
                c:disc(x, y, next_value(0, 3) == 0 and 2 or 1, WHITE)
            end
        end
    end

    local function cover_or_block(c, card_id, provider, x, y, w, h, frame_color)
        if not c:cover(provider, card_id, x, y, w, h, 2, frame_color) then
            c:rect(x, y, x + w, y + h, BLACK, frame_color or BLACK, 2)
            c:rect(x + w * 0.15, y + h * 0.2, x + w * 0.85, y + h * 0.22, WHITE)
            c:rect(x + w * 0.15, y + h * 0.26, x + w * 0.85, y + h * 0.27, WHITE)
        end
    end

    local function days_in_year(year)
        return os.date("*t", os.time{ year = year, month = 12, day = 31, hour = 12 }).yday
    end

    local function month_axis(c, t, x0, x1, y)
        for month = 1, 12 do
            c:text(x0 + (month - 0.5) * (x1 - x0) / 12, y, t.month_letters[month], SERIF, 15)
        end
    end

    function Paint.comeback(c, card, t)
        c:text(300, 100, card.kicker, ITALIC, 24)
        c:fit(300, 196, card.big, BOLD, { 104, 84, 64 }, 540)
        c:text(300, 274, card.label, SERIF, 25)
        local x0, x1, axis = 36, 564, 470
        local total = days_in_year(card.year)
        local function x_of(yday)
            return x0 + (x1 - x0) * (yday - 1) / total
        end
        local left, right = x_of(card.from + 1), x_of(card.to)
        c:hatch(left, axis - 106, right, axis + 4, 8)
        c:rect(left, axis - 106, right, axis + 4, nil, BLACK, 2)
        local peak = 1
        for _, seconds in pairs(card.days) do
            peak = math.max(peak, seconds)
        end
        for yday, seconds in pairs(card.days) do
            local height = math.max(14, 96 * seconds / peak)
            c:rect(x_of(yday), axis - height, x_of(yday) + 1.4, axis, BLACK)
        end
        c:rect(x0 - 6, axis, x1 + 6, axis + 4, BLACK)
        month_axis(c, t, x0, x1, axis + 26)
        c:line({ { right, axis - 106 }, { right, axis - 140 } }, BLACK, 3)
        if right > 440 then
            c:poly({ { right, axis - 140 }, { right - 40, axis - 128 }, { right, axis - 116 } }, BLACK)
            c:text(right - 48, axis - 126, card.flag, BOLD, 16, BLACK, "r")
        else
            c:poly({ { right, axis - 140 }, { right + 40, axis - 128 }, { right, axis - 116 } }, BLACK)
            c:text(right + 48, axis - 126, card.flag, BOLD, 16, BLACK, "l")
        end
        c:wrap(300, 536, card.body, SERIF, 22, 470, BLACK, 180)
    end

    function Paint.back_after_years(c, card)
        stars(c, 11, 70, 56, 560, { { 80, 290 }, { 560, 760 } })
        c:text(300, 100, card.kicker, ITALIC, 25, WHITE)
        c:fit(300, 190, card.big, BOLD, { 110, 90, 70 }, 540, WHITE)
        c:fit(300, 268, card.label, SERIF, { 25, 21, 18 }, 540, WHITE)
        local base = 640
        local largest = math.max(card.last_seconds, card.current_seconds, 1)
        local function count(seconds)
            return math.max(1, math.floor(12 * seconds / largest + 0.5))
        end
        local tones = { "white", "dots", "white", "hatch" }
        pile(c, 115, count(card.last_seconds), base, tones)
        pile(c, 485, count(card.current_seconds), base, tones)
        if card.gap_label then
            c:rect(232, base - 3, 368, base - 1, LIGHT)
            c:fit(300, base - 62, card.gap_label, ITALIC, { 19, 16, 14 }, 130, LIGHT)
            c:fit(300, base - 34, card.nothing, ITALIC, { 15, 13 }, 130, LIGHT)
        end
        c:rect(20, base, 580, base + 4, WHITE)
        c:text(115, base + 24, tostring(card.last_year), BOLD, 18, WHITE)
        c:text(115, base + 48, card.last_time, ITALIC, 15, WHITE)
        c:text(485, base + 24, tostring(card.year), BOLD, 18, WHITE)
        c:text(485, base + 48, card.current_time, ITALIC, 15, WHITE)
    end

    function Paint.waves(c, card, t)
        c:text(300, 96, card.kicker, ITALIC, 25)
        c:fit(300, 186, card.big, BOLD, { 92, 76, 60 }, 540)
        c:wrap(300, 244, card.body, SERIF, 21, 480, BLACK, 90)
        local base, top = 690, 440
        local total = days_in_year(card.year)
        local weeks, peak = {}, 1
        for week = 0, 53 do
            local seconds = 0
            for yday = week * 7 + 1, week * 7 + 7 do
                seconds = seconds + (card.days[yday] or 0)
            end
            weeks[week] = seconds
        end
        local smooth = {}
        for week = 0, 53 do
            smooth[week] = ((weeks[week - 1] or 0) + 2 * weeks[week] + (weeks[week + 1] or 0)) / 4
            peak = math.max(peak, smooth[week])
        end
        local function surface(x)
            local at = x * total / BASE_W / 7
            local index = math.min(52, math.floor(at))
            local value = smooth[index] + (smooth[index + 1] - smooth[index]) * (at - index)
            return base - 12 - (base - top - 12) * value / peak
        end
        c:dots(0, top - 20, BASE_W, base - 3, 7, 2.1, function(x, y) return y > surface(x) + 3 end)
        local outline = {}
        for x = 0, BASE_W, 6 do
            outline[#outline + 1] = { x, surface(x) }
        end
        c:line(outline, BLACK, 3.2)
        c:rect(0, base, BASE_W, base + 4, BLACK)
        for index, yday in ipairs(card.returns) do
            local x = BASE_W * (yday - 1) / total
            local y = surface(x)
            local top_y = math.max(330, y - 58)
            c:line({ { x, y }, { x, top_y } }, BLACK, 2.4)
            c:disc(x, top_y, 14, WHITE)
            c:ring(x, top_y, 14, BLACK, 2.4)
            c:text(x, top_y, tostring(index), BOLD, 15)
        end
        month_axis(c, t, 0, BASE_W, base + 24)
    end

    function Paint.book_waited(c, card, _, provider)
        c:fit(300, 74, card.kicker, ITALIC, { 25, 21, 18 }, 480)
        cover_or_block(c, card.book_id, provider, 192, 104, 216, 316)
        c:poly({ { 372, 92 }, { 396, 92 }, { 396, 136 }, { 384, 124 }, { 372, 136 } }, BLACK)
        c:fit(300, 482, card.big, BOLD, { 72, 60, 48 }, 540)
        c:fit(300, 540, card.label, SERIF, { 23, 20, 17 }, 540)
        local x0, x1, y = 60, 540, 618
        -- Both reading stretches stay visible, even for a book read on only two days.
        local stop = x0 + (x1 - x0) * math.max(card.stop, 0.14)
        local resume = x0 + (x1 - x0) * math.min(card.resume, 0.86)
        c:rect(x0, y - 11, stop, y + 11, BLACK)
        c:hatch(stop, y - 11, resume, y + 11, 7)
        c:rect(stop, y - 11, resume, y + 11, nil, BLACK, 2)
        c:rect(resume, y - 11, x1, y + 11, BLACK)
        c:text(x0, y + 32, card.start_label, ITALIC, 15, BLACK, "l")
        c:text((stop + resume) / 2, y + 32, card.pause_label, ITALIC, 15)
        c:text(x1, y + 32, card.end_label, ITALIC, 15, BLACK, "r")
        c:fit(300, 694, card.foot, BOLD, { 24, 20, 17 }, 540)
    end

    function Paint.one_sitting(c, card, _, provider)
        stars(c, 5, 34, 56, 490, { { 66, 102 }, { 214, 470 } })
        c:fit(300, 84, card.kicker, ITALIC, { 25, 21, 18 }, 460, WHITE)
        local cx, cy, r = 300, 400, 240
        local function angle(hour)
            return math.rad(180 + hour * 7.5)
        end
        for degrees = 180, 357, 6 do
            local a, b = math.rad(degrees), math.rad(degrees + 3)
            c:line({ { cx + r * math.cos(a), cy + r * math.sin(a) }, { cx + r * math.cos(b), cy + r * math.sin(b) } }, LIGHT, 2.4)
        end
        local from, to = angle(card.start_hour), angle(math.max(card.end_hour, card.start_hour + 0.5))
        local arc = {}
        for i = 0, 16 do
            local a = from + (to - from) * i / 16
            arc[i + 1] = { cx + r * math.cos(a), cy + r * math.sin(a) }
        end
        c:line(arc, WHITE, 9)
        c:disc(arc[#arc][1], arc[#arc][2], 18, WHITE)
        c:text(arc[1][1] - 30, arc[1][2] - 14, card.start_label, BOLD, 16, WHITE)
        c:text(arc[#arc][1] + 36, arc[#arc][2] - 14, card.end_label, BOLD, 16, WHITE)
        cover_or_block(c, card.book_id, provider, 212, 214, 176, 256, WHITE)
        c:rect(20, 500, 580, 503, WHITE)
        c:fit(300, 566, card.big, BOLD, { 62, 50, 40 }, 540, WHITE)
        c:fit(300, 630, card.label, SERIF, { 25, 21, 18 }, 540, WHITE)
        c:fit(300, 676, card.foot, ITALIC, { 20, 17, 15 }, 540, WHITE)
    end

    function Paint.slow_burn(c, card)
        stars(c, 21, 60, 56, 750, { { 60, 250 }, { 360, 620 }, { 640, 700 } })
        c:text(300, 80, card.kicker, ITALIC, 27, WHITE)
        c:fit(300, 162, card.big, BOLD, { 86, 70, 56 }, 540, WHITE)
        c:text(300, 228, card.label, SERIF, 24, WHITE)
        local cx, top, base = 180, 370, 670
        c:poly({ { cx, top - 94 }, { cx + 40, top - 40 }, { cx + 25, top - 8 }, { cx, top }, { cx - 25, top - 8 }, { cx - 40, top - 40 } }, WHITE)
        c:poly({ { cx, top - 54 }, { cx + 15, top - 26 }, { cx, top - 8 }, { cx - 15, top - 26 } }, BLACK)
        c:rect(cx - 2, top - 6, cx + 2, top + 12, WHITE)
        c:rect(cx - 44, top + 10, cx + 44, base, WHITE)
        c:hatch(cx - 44, top + 10, cx - 12, base, 7)
        c:poly({ { cx + 16, top + 8 }, { cx + 44, top + 8 }, { cx + 44, top + 78 }, { cx + 30, top + 92 }, { cx + 16, top + 66 } }, LIGHT)
        c:rect(cx - 76, base, cx + 76, base + 18, WHITE)
        local height = c:wrap(400, 370, clip(card.title, 44), BOLD, 28, 280, WHITE, 150)
        c:wrap(400, 386 + height, card.body, SERIF, 21, 280, WHITE, 130)
    end

    function Paint.reread(c, card, _, provider)
        c:text(300, 74, card.kicker, ITALIC, 25)
        local cx, cy, r = 300, 290, 180
        local points = {}
        for degrees = 205, 508, 4 do
            local a = math.rad(degrees)
            points[#points + 1] = { cx + r * math.cos(a), cy + r * math.sin(a) }
        end
        c:line(points, BLACK, 20)
        for _, point in ipairs(points) do
            c:disc(point[1], point[2], 10, BLACK)
        end
        local a = math.rad(205)
        local px, py = cx + r * math.cos(a), cy + r * math.sin(a)
        local tx, ty = math.sin(a), -math.cos(a)
        local nx, ny = math.cos(a), math.sin(a)
        c:poly({ { px + tx * 46, py + ty * 46 }, { px + nx * 36, py + ny * 36 }, { px - nx * 36, py - ny * 36 } }, BLACK)
        cover_or_block(c, card.book_id, provider, 206, 150, 188, 276)
        c:fit(300, 528, card.big, BOLD, { 70, 58, 46 }, 540)
        c:text(300, 590, card.label, SERIF, 25)
        if card.from_year then
            local x0, x1, y = 120, 480, 660
            c:rect(x0, y - 2, x1, y + 2, BLACK)
            c:disc(x0, y, 11, BLACK)
            c:disc(x1, y, 11, BLACK)
            c:text(x0, y + 30, tostring(card.from_year), BOLD, 17)
            c:text(x1, y + 30, tostring(card.year), BOLD, 17)
            c:text(300, y + 30, card.later, ITALIC, 16)
        end
    end

    function Paint.series_run(c, card)
        c:fit(300, 96, card.kicker, ITALIC, { 25, 21, 18 }, 480)
        c:fit(300, 186, card.big, BOLD, { 96, 80, 62 }, 540)
        c:fit(300, 262, clip(card.label, 40), SERIF, { 25, 21, 18 }, 540)
        local base = 610
        local shown = math.min(6, card.count)
        local width = math.min(92, 500 / shown - 8)
        local x = (BASE_W - shown * (width + 8) + 8) / 2
        local tones = { "black", "dots", "black", "hatch" }
        for i = 1, shown do
            local height = 252 + (i * 13) % 38
            spine(c, x, base, width, height, tones[(i - 1) % #tones + 1])
            local cy = base - height / 2
            c:disc(x + width / 2, cy, 21, WHITE)
            c:ring(x + width / 2, cy, 21, BLACK, 2)
            c:text(x + width / 2, cy, tostring(i), BOLD, 24)
            x = x + width + 8
        end
        c:rect(30, base, 570, base + 7, BLACK)
        c:fit(300, base + 56, card.foot, BOLD, { 23, 20, 17 }, 540)
    end

    local function tilted_book(c, cx, cy, w, h, degrees, tone)
        local a = math.rad(degrees)
        local ux, uy = math.cos(a), math.sin(a)
        local vx, vy = -uy, ux
        local function p(px, py)
            return { cx + px * ux + py * vx, cy + px * uy + py * vy }
        end
        local corners = { p(-w / 2, -h / 2), p(w / 2, -h / 2), p(w / 2, h / 2), p(-w / 2, h / 2) }
        c:poly(corners, tone == "black" and BLACK or WHITE)
        if tone == "black" then
            c:line({ p(-w / 2 + 6, -h / 2 + 20), p(w / 2 - 6, -h / 2 + 20) }, WHITE, 3.5)
            c:line({ p(-w / 2 + 6, -h / 2 + 29), p(w / 2 - 6, -h / 2 + 29) }, WHITE, 2.2)
        elseif tone == "dots" then
            c:dots(cx - h, cy - h, cx + h, cy + h, 7, 1.8, function(x, y)
                local dx, dy = x - cx, y - cy
                return math.abs(dx * ux + dy * uy) < w / 2 - 3 and math.abs(dx * vx + dy * vy) < h / 2 - 3
            end)
        else
            local y = -h / 2 + 8
            while y < h / 2 - 4 do
                c:line({ p(-w / 2 + 4, y), p(w / 2 - 4, y + 6) }, BLACK, 1.5)
                y = y + 8
            end
        end
        corners[#corners + 1] = corners[1]
        c:line(corners, BLACK, 2.5)
    end

    function Paint.juggler(c, card)
        c:text(300, 84, card.kicker, ITALIC, 26)
        c:fit(300, 166, card.big, BOLD, { 88, 72, 58 }, 540)
        c:fit(300, 236, card.label, SERIF, { 23, 20, 17 }, 540)
        local cx, cy, r = 300, 470, 170
        for degrees = 190, 346, 10 do
            local a, b = math.rad(degrees), math.rad(degrees + 5)
            c:line({ { cx + r * math.cos(a), cy + r * 0.72 * math.sin(a) }, { cx + r * math.cos(b), cy + r * 0.72 * math.sin(b) } }, BLACK, 2)
        end
        local placed = { { 150, 422, -46, "black" }, { 220, 366, -22, "hatch" }, { 300, 344, 0, "black" }, { 380, 366, 22, "dots" }, { 450, 422, 46, "black" } }
        for _, book in ipairs(placed) do
            tilted_book(c, book[1], book[2], 46, 66, book[3], book[4])
        end
        local first, last = math.huge, 0
        for _, row in ipairs(card.rows) do
            first, last = math.min(first, row.from), math.max(last, row.to)
        end
        local x0, x1 = 230, 548
        local span = math.max(last - first, 1)
        local function x_of(yday)
            return x0 + (x1 - x0) * (yday - first) / span
        end
        local y = 484
        local peak = x_of(card.peak)
        local band_left, band_right = math.max(x0, peak - 35), math.min(x1, peak + 35)
        c:dots(band_left, 472, band_right, y + #card.rows * 30 - 12, 7, 1.6)
        for _, row in ipairs(card.rows) do
            c:fit(52, y + 6, row.title, ITALIC, { 18, 15, 13 }, 170, BLACK, "l")
            c:rect(x_of(row.from), y - 3, math.max(x_of(row.to), x_of(row.from) + 6), y + 15, BLACK)
            y = y + 30
        end
        c:text((band_left + band_right) / 2, y + 8, card.peak_label, BOLD, 16)
        if card.foot then
            c:fit(300, 690, card.foot, BOLD, { 23, 20, 17 }, 540)
        end
    end

    function Paint.almost_there(c, card)
        c:text(300, 80, card.kicker, ITALIC, 27)
        c:fit(300, 172, card.big, BOLD, { 118, 96 }, 540)
        c:fit(300, 256, clip(card.label, 40), BOLD, { 30, 25, 20 }, 540)
        local x0, x1, base, height = 90, 510, 560, 180
        local stop = x0 + (x1 - x0) * card.share
        local function surface(x)
            return base - height * (x - x0) / (x1 - x0)
        end
        c:dots(x0, base - height - 10, stop, base - 3, 7, 2.1, function(x, y) return y > surface(x) + 3 end)
        c:line({ { x0, base }, { stop, surface(stop) } }, BLACK, 3.4)
        for i = 0, 3 do
            local a = stop + (x1 - stop) * i / 4
            local b = stop + (x1 - stop) * (i + 0.55) / 4
            c:line({ { a, surface(a) }, { b, surface(b) } }, BLACK, 3.4)
        end
        c:line({ { stop, surface(stop) }, { stop, base } }, BLACK, 2)
        c:rect(x0 - 40, base, x1 + 40, base + 4, BLACK)
        c:disc(stop, surface(stop), 9, BLACK)
        c:line({ { x1, surface(x1) }, { x1, surface(x1) - 56 } }, BLACK, 3)
        c:poly({ { x1, surface(x1) - 56 }, { x1 + 38, surface(x1) - 44 }, { x1, surface(x1) - 32 } }, BLACK)
        c:fit(300, 612, card.foot, BOLD, { 26, 22, 18 }, 540)
        c:fit(300, 656, card.note, ITALIC, { 19, 17, 15 }, 540)
    end

    function Paint.extremes(c, card)
        c:fit(300, 84, card.kicker, ITALIC, { 26, 22, 18 }, 480)
        local base = 500
        spine(c, 118, base, 24, 200, "black")
        local x = 318
        c:rect(x, base - 340, x + 200, base, BLACK)
        c:rect(x + 14, base - 310, x + 186, base - 304, WHITE)
        c:rect(x + 14, base - 292, x + 186, base - 288, WHITE)
        c:rect(x + 14, base - 62, x + 186, base - 58, WHITE)
        c:rect(x + 14, base - 46, x + 186, base - 40, WHITE)
        c:fit(x + 100, base - 180, card.long_pages, BOLD, { 60, 48, 38 }, 180, WHITE)
        c:text(x + 100, base - 132, card.long_word, ITALIC, 22, WHITE)
        c:text(130, base - 268, card.short_pages, BOLD, 52)
        c:text(130, base - 226, card.short_word, ITALIC, 18)
        c:rect(40, base, 560, base + 7, BLACK)
        c:wrap(130, base + 34, clip(card.short_title, 30), BOLD, 20, 210, BLACK, 60)
        c:text(130, base + 112, card.short_label, ITALIC, 17)
        c:wrap(418, base + 34, clip(card.long_title, 30), BOLD, 20, 250, BLACK, 60)
        c:text(418, base + 112, card.long_label, ITALIC, 17)
        c:fit(300, 690, card.foot, SERIF, { 21, 18, 15 }, 540)
    end

    function Paint.most_marked(c, card)
        c:fit(300, 74, card.kicker, ITALIC, { 25, 21, 18 }, 480)
        c:rect(116, 106, 484, 500, WHITE, BLACK, 2.5)
        c:rect(124, 500, 492, 508, BLACK)
        local next_value = sequence(card.seed + 14)
        for i = 0, 17 do
            local y = 132 + i * 20
            local length = next_value(250, 320)
            if next_value(0, 3) == 0 then
                c:rect(134, y - 9, 142 + length, y + 9, BLACK)
                c:rect(142, y - 2, 134 + length, y + 2, WHITE)
            else
                c:rect(138, y - 2, 138 + length, y + 2, GRAY)
            end
        end
        c:fit(300, 568, card.big, BOLD, { 60, 50, 40 }, 540)
        c:fit(300, 628, clip(card.label, 44), BOLD, { 24, 20, 17 }, 540)
        if card.notes then
            c:fit(300, 668, card.notes, ITALIC, { 20, 17, 15 }, 540)
        end
    end

    function Paint.bookends(c, card, _, provider)
        c:fit(300, 78, card.kicker, ITALIC, { 25, 21, 18 }, 480)
        c:text(150, 134, card.opened, BOLD, 22)
        c:text(450, 134, card.closed, BOLD, 22)
        cover_or_block(c, card.first_id, provider, 48, 160, 204, 300)
        cover_or_block(c, card.last_id, provider, 348, 160, 204, 300)
        c:fit(150, 490, card.first_date, ITALIC, { 19, 16, 14 }, 260)
        c:fit(450, 490, card.last_date, ITALIC, { 19, 16, 14 }, 260)
        local y, x0, x1 = 590, 54, 546
        c:rect(x0, y - 2, x1, y + 2, BLACK)
        c:disc(x0, y, 12, BLACK)
        c:disc(x1, y, 12, BLACK)
        local next_value = sequence(card.between + 3)
        local x = 96
        while x < 500 do
            local w, h = next_value(9, 16), next_value(32, 52)
            c:rect(x, y - h, x + w, y - 3, next_value(0, 2) == 0 and WHITE or BLACK, BLACK, 1.5)
            x = x + w + 3
        end
        if card.foot then
            c:fit(300, 650, card.foot, BOLD, { 23, 20, 17 }, 540)
        end
    end

    function Paint.ritual(c, card)
        c:text(300, 84, card.kicker, ITALIC, 26)
        c:fit(300, 170, card.big, BOLD, { 92, 76, 60 }, 540)
        c:wrap(300, 226, card.body, SERIF, 22, 470, BLACK, 90)
        local cx, cy, r = 300, 520, 176
        c:disc(cx, cy, r, WHITE)
        c:ring(cx, cy, r, BLACK, 7)
        local hour = card.hour % 12
        local from = hour * 30
        c:dots(cx - r, cy - r, cx + r, cy + r, 7, 2, function(x, y)
            local dx, dy = x - cx, y - cy
            if dx * dx + dy * dy > (r - 10) * (r - 10) then
                return false
            end
            local degrees = (math.deg(math.atan2(dy, dx)) + 90) % 360
            return degrees >= from and degrees <= from + 60
        end)
        for mark = 0, 11 do
            local a = math.rad(mark * 30 - 90)
            local inner = r - (mark % 3 == 0 and 24 or 15)
            c:line({ { cx + inner * math.cos(a), cy + inner * math.sin(a) }, { cx + (r - 6) * math.cos(a), cy + (r - 6) * math.sin(a) } }, BLACK, mark % 3 == 0 and 4 or 2)
        end
        local hand = math.rad(from - 90)
        c:line({ { cx, cy }, { cx + 96 * math.cos(hand), cy + 96 * math.sin(hand) } }, BLACK, 9)
        c:line({ { cx, cy }, { cx, cy - 140 } }, BLACK, 5)
        c:disc(cx, cy, 12, BLACK)
    end

    function Paint.past_midnight(c, card)
        stars(c, 31, 80, 56, 510, { { 88, 132 }, { 230, 480 } })
        c:disc(462, 138, 66, WHITE)
        c:disc(434, 124, 58, BLACK)
        c:fit(60, 110, card.kicker, ITALIC, { 26, 22, 18 }, 330, WHITE, "l")
        c:text(300, 292, "00:00", BOLD, 118, WHITE)
        c:fit(300, 386, card.big, BOLD, { 46, 38 }, 540, WHITE)
        c:wrap(300, 420, card.body, SERIF, 22, 470, WHITE, 70)
        local base = 640
        c:line({ { 0, base }, { 120, base - 54 }, { 230, base - 22 }, { 340, base - 62 }, { 470, base - 18 }, { 600, base - 48 } }, WHITE, 3)
        c:poly({ { 300, base - 118 }, { 300, base - 10 }, { 226, base - 24 }, { 226, base - 132 } }, WHITE)
        c:poly({ { 300, base - 118 }, { 300, base - 10 }, { 374, base - 24 }, { 374, base - 132 } }, WHITE)
        c:line({ { 300, base - 118 }, { 300, base - 10 } }, BLACK, 3)
        for _, offset in ipairs({ 34, 52, 70, 88 }) do
            c:line({ { 240, base - 132 + offset }, { 288, base - 122 + offset } }, BLACK, 2)
            c:line({ { 312, base - 122 + offset }, { 360, base - 132 + offset } }, BLACK, 2)
        end
        if card.foot then
            c:fit(300, 684, card.foot, ITALIC, { 21, 18, 15 }, 540, WHITE)
        end
    end

    function Paint.memorable_day(c, card, t, provider)
        c:fit(40, 70, card.kicker, ITALIC, { 27, 23, 19 }, 440, BLACK, "l")
        local x0, y0, x1, y1 = 56, 108, 304, 400
        c:rect(x0 + 8, y0 + 8, x1 + 8, y1 + 8, BLACK)
        c:rect(x0, y0, x1, y1, WHITE, BLACK, 3)
        c:rect(x0, y0, x1, y0 + 58, BLACK)
        c:fit((x0 + x1) / 2, y0 + 29, upper(t.months[card.date.month]), SANS, { 28, 24, 20 }, 230, WHITE)
        c:text((x0 + x1) / 2, y0 + 150, tostring(card.date.day), BOLD, 120)
        c:fit((x0 + x1) / 2, y0 + 256, t.weekdays[card.date.wday], ITALIC, { 23, 19, 16 }, 230)
        cover_or_block(c, card.book_id, provider, 340, 118, 204, 298)
        c:fit(300, 488, card.big, BOLD, { 78, 64, 50 }, 540)
        c:fit(300, 556, card.label, SERIF, { 24, 20, 17 }, 540)
        c:wrap(300, 596, card.body, SERIF, 21, 470, BLACK, 120)
    end

    function Paint.pace_change(c, card)
        c:fit(300, 84, card.kicker, ITALIC, { 25, 21, 18 }, 480)
        local function lane(y, title, value, label, fast)
            c:fit(56, y - 92, title, BOLD, { 24, 20, 17 }, 300, BLACK, "l")
            c:fit(56, y - 58, label, ITALIC, { 18, 16, 14 }, 280, BLACK, "l")
            c:fit(544, y - 72, value, BOLD, { 44, 36, 28 }, 210, BLACK, "r")
            local tip = fast and 500 or 190
            if fast then
                c:rect(60, y - 21, 380, y - 18, BLACK)
                c:rect(110, y - 3, 380, y, BLACK)
                c:rect(80, y + 15, 380, y + 18, BLACK)
            else
                for x = 60, tip - 18, 18 do
                    c:rect(x, y - 2, x + 7, y + 2, BLACK)
                end
            end
            c:rect(tip, y - 28, tip + 42, y + 28, BLACK)
            c:rect(tip + 8, y - 28, tip + 11, y + 28, WHITE)
            c:rect(60, y + 40, 544, y + 43, BLACK)
        end
        lane(290, card.fast_title, card.fast_value, card.fast_label, true)
        lane(560, card.slow_title, card.slow_value, card.slow_label, false)
        c:wrap(300, 628, card.foot, SERIF, 19, 520, BLACK, 90)
    end
end
