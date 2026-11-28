--[[--
Legibility grade of the current typesetting, measured on the pages as they are drawn.

The same analysis as optimal_typesetting.py / OptimalTypesetting.lua (testCREngine), on the
bitmap crengine already keeps of the page on screen (CreDocument.buffer), so nothing is
rendered again. The last pages read with the same settings are pooled, and the grade is
recomputed when the settings change (rendering hash).

What is measured on the pixels: x-height, characters per line, how much the spaces of the
justified lines are stretched (Knuth's badness), very loose lines, hyphens at line ends and
ladders of 3 or more, rivers, line pitch against the x-height and pages ending with a gap.
Parameters added: x-height in mm (the one of the top bar when given), side margins and word
expansion.

Each problem is a penalty; the total P gives score = 100 * exp(-P / SCALE) and a letter A-E.
]]

local ffi = require("ffi")

local floor, abs, max, min, exp = math.floor, math.abs, math.max, math.min, math.exp

local Legibility = {
    MAX_PAGES = 12,       -- pages pooled for the grade
    MIN_FULL_LINES = 10,  -- justified lines needed before showing a grade
    -- x-height band, the same one as TopBar:getXHeightRangeLabel(), in mm at VIEW_DISTANCE. It is applied as an angle:
    -- on every device the x-height is taken as seen from VIEW_DISTANCE (change it and the band moves with it)
    XH_MIN = 1.70,
    XH_MAX = 1.85,
    VIEW_DISTANCE = 400,  -- mm, the same for every device
    BAND_DISTANCE = 400,  -- mm, distance at which XH_MIN / XH_MAX are given
    REASON_MIN = 1.0,
    XH_FONT_TRUST = 1.3,  -- the x-height of the fonts menu is used if within x1.3 of the measured one
    -- "balanced" line spacing of the top bar: safe_min + 0.15 ... safe_min + 0.40 (no penalty inside)
    LEADING_BALANCED = { 0.15, 0.40 },     -- a problem is named in brackets when its penalty is at least this
    SCALE = 12,           -- P -> score: 100 * exp(-P / SCALE)
    GRADES = { { 85, "A" }, { 70, "B" }, { 55, "C" }, { 40, "D" }, { 0, "E" } },
    -- Words for the score (the first one whose minimum is reached)
    CATEGORIES = { { 90, "Excellent" }, { 75, "Good" }, { 55, "Fair" }, { 40, "Poor" }, { 0, "Bad" } },
    -- Weights of each penalty (1 = as in optimal_typesetting.py)
    W = { size = 1, measure = 1, stretch = 1, loose = 1, hyph = 1, ladder = 1,
          rivers = 1, leading = 1, margin = 1, expand = 1, pagefill = 1 },
}

local function clamp(x, a, b) return x < a and a or (x > b and b or x) end

local function percentile(t, p)
    if #t == 0 then return nil end
    local c = {}
    for i = 1, #t do c[i] = t[i] end
    table.sort(c)
    return c[clamp(floor(p * (#c - 1) + 1.5), 1, #c)]
end
local function median(t) return percentile(t, 0.5) end

local function utf8len(s)
    local n = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
end

local function otsu(widths, maxw)
    local hist = {}
    for i = 0, maxw do hist[i] = 0 end
    for _, w in ipairs(widths) do
        local k = min(w, maxw)
        hist[k] = hist[k] + 1
    end
    local total, sum = #widths, 0
    for i = 0, maxw do sum = sum + i * hist[i] end
    local sumB, wB, best, thr = 0, 0, -1, 1
    for t = 0, maxw do
        wB = wB + hist[t]
        if wB > 0 then
            local wF = total - wB
            if wF == 0 then break end
            sumB = sumB + t * hist[t]
            local mB, mF = sumB / wB, (sum - sumB) / wF
            local between = wB * wF * (mB - mF) ^ 2
            if between > best then best, thr = between, t + 1 end
        end
    end
    return thr
end

--- Lines and blank runs of one page.
-- pix: uint8_t* (8-bit gray), stride in bytes; ctx = { px = font size in px, x0, x1, y0, y1 = text box }
function Legibility.analyzePage(pix, stride, W_, H_, ctx)
    local px = ctx.px
    local corners = { pix[0], pix[W_ - 1], pix[(H_ - 1) * stride], pix[(H_ - 1) * stride + W_ - 1] }
    table.sort(corners)
    local bg = corners[2]
    local thr = 80
    local x0, x1 = max(0, ctx.x0 - 2), min(W_ - 1, ctx.x1 + 2)
    local y0, y1 = max(0, ctx.y0 - 2), min(H_ - 1, ctx.y1 + 2)

    local rows = {}
    for y = y0, y1 do
        local base, c = y * stride, 0
        for x = x0, x1 do
            local v = pix[base + x]
            if (v > bg and v - bg or bg - v) > thr then c = c + 1 end
        end
        rows[y] = c
    end

    -- bands of rows with ink, small gaps joined
    local merge_gap = max(1, floor(0.06 * px))
    local bands, y = {}, y0
    while y <= y1 do
        if rows[y] > 0 then
            local top, bot, gap = y, y, 0
            y = y + 1
            while y <= y1 do
                if rows[y] > 0 then
                    bot, gap = y, 0
                else
                    gap = gap + 1
                    if gap > merge_gap then break end
                end
                y = y + 1
            end
            bands[#bands + 1] = { top = top, bot = bot }
        else
            y = y + 1
        end
    end
    -- tiny bands (accents of capitals, dots) go with the next one
    local merged = {}
    for i = 1, #bands do
        local b, nb = bands[i], bands[i + 1]
        if (b.bot - b.top + 1) < 0.3 * px and nb and (nb.top - b.bot) < 0.3 * px then
            nb.top = b.top
        else
            merged[#merged + 1] = b
        end
    end
    -- bands too tall (descenders touching the next line) are split at the row with least ink
    local split = {}
    local function splitBand(b)
        if b.bot - b.top + 1 <= 1.45 * px then split[#split + 1] = b; return end
        local lo, hi = b.top + floor(0.55 * px), b.bot - floor(0.55 * px)
        if hi <= lo then split[#split + 1] = b; return end
        local by, bc = lo, math.huge
        for yy = lo, hi do
            if rows[yy] < bc then by, bc = yy, rows[yy] end
        end
        splitBand({ top = b.top, bot = by })
        splitBand({ top = by + 1, bot = b.bot })
    end
    for _, b in ipairs(merged) do splitBand(b) end

    local lines = {}
    local colAny, colMin, colMax = {}, {}, {}
    for _, b in ipairs(split) do
        local h = b.bot - b.top + 1
        if h >= 0.45 * px and h <= 2.3 * px then
            local maxc = 0
            for yy = b.top, b.bot do if rows[yy] > maxc then maxc = rows[yy] end end
            local zt, zb
            for yy = b.top, b.bot do
                if rows[yy] >= 0.5 * maxc then zt = zt or yy; zb = yy end
            end
            local xh = zb - zt + 1
            local left, right
            for x = x0, x1 do
                local any, mn, mx = false, nil, nil
                for yy = b.top, b.bot do
                    local v = pix[yy * stride + x]
                    if (v > bg and v - bg or bg - v) > thr then
                        any = true
                        mn = mn or yy
                        mx = yy
                    end
                end
                colAny[x], colMin[x], colMax[x] = any, mn, mx
                if any then left = left or x; right = x end
            end
            if left then
                local runs, x = {}, left
                while x <= right do
                    if not colAny[x] then
                        local a = x
                        while x <= right and not colAny[x] do x = x + 1 end
                        runs[#runs + 1] = { a = a, b = x - 1, w = x - a }
                    else
                        x = x + 1
                    end
                end
                -- hyphen at the end: thin ink in the middle of the x-height at the right end
                local hyph, xs, hl = false, right, nil
                local limit = max(left, right - floor(0.6 * px))
                while xs >= limit do
                    if colAny[xs] then
                        local mn, mx = colMin[xs], colMax[xs]
                        if mn >= zt + 0.2 * xh and mx <= zb - 0.15 * xh and (mx - mn) <= 0.32 * xh then
                            hl = xs
                        else
                            break
                        end
                    end
                    xs = xs - 1
                end
                if hl then
                    local wdt = right - hl + 1
                    if wdt >= 0.12 * px and wdt <= 0.45 * px and xs >= left then hyph = true end
                end
                lines[#lines + 1] = { top = b.top, bot = b.bot, left = left, right = right,
                                      zt = zt, zb = zb, xh = xh, runs = runs, hyph = hyph }
            end
        end
    end
    return { lines = lines, y1 = ctx.y1 }
end

--- Measurements over the pooled pages (nil, reason when there is not enough text)
function Legibility.metrics(pages, px)
    local widths = {}
    for _, pg in ipairs(pages) do
        for _, ln in ipairs(pg.lines) do
            for _, r in ipairs(ln.runs) do widths[#widths + 1] = r.w end
        end
    end
    if #widths < 50 then return nil, "not enough text" end
    local T = clamp(otsu(widths, floor(2 * px)), max(2, floor(0.06 * px)), max(3, floor(0.35 * px)))

    local natural, full_lines, xhs, pitches, measure_px, inks = {}, {}, {}, {}, {}, {}
    local chars, linewidth, nlines, npages = 0, 0, 0, 0
    local fill_bad, fill_n = 0, 0
    local hyph, ladders, river_cost = 0, 0, 0
    for _, pg in ipairs(pages) do
        local ls = pg.lines
        if #ls >= 6 then
            npages = npages + 1
            local lefts, rights = {}, {}
            for _, ln in ipairs(ls) do lefts[#lefts + 1] = ln.left; rights[#rights + 1] = ln.right end
            local tL, tR = percentile(lefts, 0.1), percentile(rights, 0.9)
            measure_px[#measure_px + 1] = tR - tL
            local tol = max(2, 0.04 * px)
            local prev_full, run_h = nil, 0
            for li, ln in ipairs(ls) do
                local gaps = {}
                for _, r in ipairs(ln.runs) do
                    if r.w >= T then gaps[#gaps + 1] = { a = r.a, b = r.b, w = r.w } end
                end
                ln.gaps = gaps
                local left_ok = ln.left <= tL + 2.2 * px
                ln.full = left_ok and ln.right >= tR - tol and #gaps >= 3
                if left_ok and not ln.full and ln.right < tR - 0.6 * px and #gaps >= 2 then
                    for _, g in ipairs(gaps) do natural[#natural + 1] = g.w end
                end
                if ln.full then
                    full_lines[#full_lines + 1] = ln
                    xhs[#xhs + 1] = ln.xh
                    inks[#inks + 1] = ln.bot - ln.top + 1
                    if ln.hyph then
                        hyph = hyph + 1
                        run_h = run_h + 1
                        if run_h == 3 then ladders = ladders + 1 end
                    else
                        run_h = 0
                    end
                else
                    run_h = 0
                end
                linewidth = linewidth + (ln.right - ln.left)
                nlines = nlines + 1
                if li > 1 then
                    local d = ln.top - ls[li - 1].top
                    if d < 2.5 * px then pitches[#pitches + 1] = d end
                end
                if ln.full and prev_full and ls[li - 1] == prev_full then
                    for _, g in ipairs(gaps) do
                        local best = 0
                        for _, hg in ipairs(prev_full.gaps) do
                            local ov = min(g.b, hg.b) - max(g.a, hg.a) + 1
                            if ov >= 0.5 * min(g.w, hg.w) then best = max(best, hg.rlen or 1) end
                        end
                        g.rlen = best + 1
                        if g.rlen >= 3 then river_cost = river_cost + 1 end
                    end
                else
                    for _, g in ipairs(gaps) do g.rlen = 1 end
                end
                prev_full = ln.full and ln or nil
            end
            chars = chars + (pg.chars or 0)
            local pitch = median(pitches) or 1.3 * px
            local gap_lines = (pg.y1 - ls[#ls].bot) / pitch
            fill_n = fill_n + 1
            if gap_lines >= 1.3 and gap_lines <= 6 then fill_bad = fill_bad + 1 end
        end
    end
    if #full_lines < Legibility.MIN_FULL_LINES then return nil, "not enough justified lines" end

    local s
    if #natural >= 15 then
        s = median(natural)
    else
        local means = {}
        for _, ln in ipairs(full_lines) do
            local t = 0
            for _, g in ipairs(ln.gaps) do t = t + g.w end
            means[#means + 1] = t / #ln.gaps
        end
        s = percentile(means, 0.2)
    end
    local bad_sum, loose = 0, 0
    for _, ln in ipairs(full_lines) do
        local t = 0
        for _, g in ipairs(ln.gaps) do t = t + g.w end
        local r = (t / #ln.gaps - s) / s
        local b = r >= 0 and 100 * r ^ 3 or 50 * (-r) ^ 3
        bad_sum = bad_sum + min(b, 1000)
        if r > 1 then loose = loose + 1 end
    end
    local nf = #full_lines
    local measure = median(measure_px)
    local cpl
    if chars > 0 and linewidth > 0 then
        cpl = measure * chars / linewidth
    else
        cpl = measure / (0.48 * px)
    end
    return {
        xh_px = median(xhs), pitch_px = median(pitches), ink_px = median(inks), cpl = cpl, space_px = s,
        stretch = bad_sum / nf / 100, loose = loose / nf, hyph = hyph / nf,
        ladders = ladders * 100 / nf, rivers = river_cost * 100 / nf,
        pagefill = fill_n > 0 and fill_bad / fill_n or 0,
        n_full = nf, n_pages = npages,
    }
end

local SHORT = {
    size = "x-height", measure = "line length", stretch = "spacing", loose = "loose lines",
    hyph = "hyphens", ladder = "hyphens", rivers = "rivers", leading = "line spacing",
    margin = "margins", expand = "expansion", pagefill = "page fill",
}

--- The problem that costs most, in two or three words ("small text"), or nil when none is worth naming
function Legibility.reason(parts, xh_mm, lf, target, cpl)
    local worst, wv = nil, 0
    for k, v in pairs(parts) do
        if v > wv then worst, wv = k, v end
    end
    if not worst or wv < Legibility.REASON_MIN then return nil end
    local seen = xh_mm * Legibility.BAND_DISTANCE / Legibility.VIEW_DISTANCE
    if worst == "size" then return seen < Legibility.XH_MIN and "small text" or "big text" end
    if worst == "leading" then return lf < target and "tight lines" or "loose lines" end
    if worst == "measure" then return cpl < 62 and "short lines" or "long lines" end
    if worst == "margin" then return "narrow margins" end
    if worst == "stretch" or worst == "loose" then return "wide spaces" end
    return SHORT[worst]
end

--- Penalties, score 0-100 and letter.
-- p = { dpi, margin_px, word_expansion, xh_mm, rem }. xh_mm: the x-height of the fonts menu (getFontXHeightInfo, with the
-- rem factor of the book and the style tweaks), the same the top bar and the menu show; used unless it is far from
-- the one measured on the page (more than XH_FONT_TRUST apart: a wrong font file). Without it, the measured one.
-- (Before: p.xh_mm was only shown in the details and the x-height used was always the measured one,
-- measured on the page, so it does not depend on the font name, NV fonts included)
function Legibility.grade(m, p)
    local W = Legibility.W
    local mm = 25.4 / p.dpi
    local xh_measured = m.xh_px * mm
    local xh_mm = xh_measured
    if p.xh_mm and p.xh_mm > 0 and xh_measured > 0 then
        local ratio = p.xh_mm / xh_measured
        if ratio >= 1 / Legibility.XH_FONT_TRUST and ratio <= Legibility.XH_FONT_TRUST then xh_mm = p.xh_mm end
    end
    local parts = {}
    -- the same mm seen from VIEW_DISTANCE instead of BAND_DISTANCE
    local seen = xh_mm * Legibility.BAND_DISTANCE / Legibility.VIEW_DISTANCE
    local below = Legibility.XH_MIN - seen
    local above = seen - Legibility.XH_MAX
    parts.size = W.size * (((below > 0 and below) or (above > 0 and above) or 0) / 0.15) ^ 2
    local cpl = m.cpl
    local out = cpl < 50 and (50 - cpl) or (cpl > 75 and (cpl - 75) or 0)
    parts.measure = W.measure * ((out / 5) ^ 2 + ((cpl - 62) / 20) ^ 2)
    parts.stretch = W.stretch * m.stretch
    parts.loose = W.loose * 10 * m.loose
    parts.hyph = W.hyph * 3 * m.hyph
    parts.ladder = W.ladder * 0.5 * m.ladders
    parts.rivers = W.rivers * 0.1 * m.rivers
    -- Line spacing, the same scale as the top bar (TopBar:classifyLeading): lF = distance between baselines in
    -- x-heights, compared with safe_min = (ascender + descender) / x-height, the least that does not make the lines
    -- touch. collision < safe_min, compact < +0.15, balanced < +0.40, airy < +0.60, very airy above.
    -- Everything measured on the page (real distance between lines and real ink of the letters), so it does not
    -- depend on the font name or on the line-height of the book.
    -- p.leading = { xh_px, safe_min } from pagetextinfo: x-height and safe_min of the font, the same as the top bar;
    -- the distance between lines is the real one, measured on the page (the top bar shows this same lF). Without them, measured on the page: real distance between baselines and ink of the letters (+0.35:
    -- the ascender of the font metrics leaves room for accents, the ink does not)
    local lf, safe_min
    if p.leading and p.leading.xh_px and p.leading.safe_min and m.pitch_px then
        -- real distance between lines (measured) in x-heights of the font, safe_min of the font
        lf, safe_min = m.pitch_px / p.leading.xh_px, p.leading.safe_min
    else
        lf = m.pitch_px and m.xh_px and m.xh_px > 0 and m.pitch_px / m.xh_px or nil
        safe_min = m.ink_px and m.xh_px and m.xh_px > 0 and (m.ink_px / m.xh_px + 0.35) or nil
    end
    local target, leading_class = nil, "?"
    if lf and safe_min then
        local lo, hi = safe_min + Legibility.LEADING_BALANCED[1], safe_min + Legibility.LEADING_BALANCED[2]
        target = (lo + hi) / 2
        local d = lf < lo and (lo - lf) or (lf > hi and (lf - hi) or 0)
        parts.leading = W.leading * (d / 0.15) ^ 2
        local o = lf - safe_min
        leading_class = o < 0 and "collision" or o < 0.15 and "compact" or o < 0.40 and "balanced"
            or o < 0.60 and "airy" or "very airy"
    else
        parts.leading = 0
        lf, target = 0, 0
    end
    local side = (p.margin_px or 0) * mm
    parts.margin = W.margin * (side < 3 and (3 - side) ^ 2 or 0)
    parts.expand = W.expand * 0.3 * ((p.word_expansion or 0) / 5)
    parts.pagefill = W.pagefill * m.pagefill
    local total = 0
    for _, v in pairs(parts) do total = total + v end
    local score = floor(100 * exp(-total / Legibility.SCALE) + 0.5)
    local letter = "E"
    for _, g in ipairs(Legibility.GRADES) do
        if score >= g[1] then letter = g[2]; break end
    end
    local category = "Bad"
    for _, c in ipairs(Legibility.CATEGORIES) do
        if score >= c[1] then category = c[2]; break end
    end
    return { score = score, letter = letter, category = category, penalty = total, parts = parts,
             margin_mm = side, expansion = p.word_expansion or 0, cpl = cpl,
             rem = p.rem,
             xh_mm = xh_mm, xh_mm_font = p.xh_mm, xh_mm_measured = xh_measured, leading = lf, leading_target = target,
             leading_class = leading_class, safe_min = safe_min,
             reason = Legibility.reason(parts, xh_mm, lf, target, cpl) }
end

----------------------------------------------------------------------------
-- Tracker: pages of the current settings
----------------------------------------------------------------------------
local Tracker = {}
Tracker.__index = Tracker

function Legibility.newTracker()
    return setmetatable({ hash = nil, pages = {}, order = {}, result = nil }, Tracker)
end

function Tracker:reset(hash)
    self.hash = hash
    self.pages = {}
    self.order = {}
    self.result = nil
    self.metrics = nil
end

function Tracker:has(hash, pageno)
    return self.hash == hash and self.pages[pageno] ~= nil
end

--- Analyzes the page drawn in bb (any Blitbuffer type) and updates the grade.
-- info = { hash, pageno, px, box = {x0,y0,x1,y1}, chars, dpi, xh_mm, margin_px, word_expansion }
-- Returns true when the grade changed.
function Tracker:addPage(bb, info)
    if self.hash ~= info.hash then self:reset(info.hash) end
    if self.pages[info.pageno] then return false end
    local Blitbuffer = require("ffi/blitbuffer")
    local gray = bb
    if bb:getType() ~= Blitbuffer.TYPE_BB8 then
        gray = Blitbuffer.new(bb.w, bb.h, Blitbuffer.TYPE_BB8)
        gray:blitFrom(bb, 0, 0, 0, 0, bb.w, bb.h)
    end
    local pix = ffi.cast("uint8_t*", gray.data)
    local b = info.box
    local pg = Legibility.analyzePage(pix, tonumber(gray.stride), gray.w, gray.h,
        { px = info.px, x0 = b[1], y0 = b[2], x1 = b[3], y1 = b[4] })
    if gray ~= bb then gray:free() end
    pg.chars = info.chars
    self.pages[info.pageno] = pg
    table.insert(self.order, info.pageno)
    while #self.order > Legibility.MAX_PAGES do
        self.pages[table.remove(self.order, 1)] = nil
    end
    local list = {}
    for _, n in ipairs(self.order) do list[#list + 1] = self.pages[n] end
    local m = Legibility.metrics(list, info.px)
    local old = self.result and self.result.score
    if m then
        self.metrics = m
        self.result = Legibility.grade(m, info)
    else
        self.metrics = nil
        self.result = nil
    end
    return (self.result and self.result.score) ~= old
end

--- Text for the top bar: "A", "87" or "A87" (fmt = "letter", "percent", "both"); "" with no grade yet
function Tracker:text(fmt)
    local r = self.result
    if not r then return "" end
    if fmt == "percent" then return tostring(r.score) end
    if fmt == "both" then return r.letter .. r.score end
    return r.letter
end

--- "87 Good" or "32 Bad (small text)"; "" with no figure
function Tracker:label()
    local r = self.result
    if not r then return "" end
    return r.score .. " " .. r.category .. (r.reason and (" (" .. r.reason .. ")") or "")
end

--- Texts for the big overlay: { "A 87", "main problem" } (the second one only when it really costs points)
function Tracker:overlayTexts()
    local r = self.result
    if not r then return { "No data" } end
    -- the number (0-100) and its word, "87 Good": no letter and no problem name (the breakdown is in Tracker:details())
    return { self:label() }
end

--- The parameters for the word counter banner, in 4 short lines: each one with what was measured (units attached:
-- 1.78mm) and the points it costs alone (100 * (1 - exp(-penalty / SCALE)), -0 = perfect). The multiplying
-- weights go after the value (x10); the band ones (x-height, line length, line spacing, margins) are squared
-- distances out of their band. Last item: total penalty.
function Tracker:detailLines()
    local r, m = self.result, self.metrics
    if not (r and m) then return {} end
    local S, W = Legibility.SCALE, Legibility.W
    local function c(k)
        return string.format("-%d", floor(100 * (1 - exp(-(r.parts[k] or 0) / S)) + 0.5))
    end
    local function w(k, base)
        local f = base * (W[k] or 1)
        return f ~= 1 and string.format("x%g", f) or ""
    end
    local sep = " \194\183 "
    local rem = r.rem and string.format(" rem%.2f", r.rem) or ""
    return {
        string.format("xH %.2fmm%s %s", r.xh_mm, rem, c("size")) .. sep
            .. string.format("%.0fcpl %s", m.cpl, c("measure")) .. sep
            .. string.format("lF %.2f %s %s", r.leading, r.leading_class or "", c("leading")),
        string.format("stretch %.2f %s", m.stretch, c("stretch")) .. sep
            .. string.format("loose %.0f%%%s %s", 100 * m.loose, w("loose", 10), c("loose")) .. sep
            .. string.format("hyph %.0f%%%s %s", 100 * m.hyph, w("hyph", 3), c("hyph")),
        string.format("ladders %.1f%s %s", m.ladders, w("ladder", 0.5), c("ladder")) .. sep
            .. string.format("rivers %.0f%s %s", m.rivers, w("rivers", 0.1), c("rivers")) .. sep
            .. string.format("margins %.1fmm %s", r.margin_mm or 0, c("margin")),
        string.format("exp %d%% %s", r.expansion or 0, c("expand")) .. sep
            .. string.format("fill %.0f%% %s", 100 * m.pagefill, c("pagefill")) .. sep
            .. string.format("P %.1f (%dp, %dl)", r.penalty, m.n_pages, m.n_full),
    }
end

--- Multi-line breakdown for the details popup
function Tracker:details()
    local r, m = self.result, self.metrics
    if not r then
        return "Not enough text measured yet with the current settings. Turn a few pages."
    end
    local names = {
        { "size", "x-height" }, { "measure", "line length" }, { "stretch", "space stretch" },
        { "loose", "loose lines" }, { "hyph", "hyphens" }, { "ladder", "hyphen ladders" },
        { "rivers", "rivers" }, { "leading", "line spacing" }, { "margin", "side margins" },
        { "expand", "word expansion" }, { "pagefill", "page fill" },
    }
    local out = {
        string.format("Legibility %d %s, penalty %.1f", r.score, r.category, r.penalty),
        string.format("%d pages, %d justified lines", m.n_pages, m.n_full),
        "",
        string.format("x-height %.2f mm on the page%s (%.2f–%.2f at %d cm)", r.xh_mm,
            r.xh_mm_font and string.format(", %.2f by the font menu", r.xh_mm_font) or "",
            Legibility.XH_MIN * Legibility.VIEW_DISTANCE / Legibility.BAND_DISTANCE,
            Legibility.XH_MAX * Legibility.VIEW_DISTANCE / Legibility.BAND_DISTANCE, Legibility.VIEW_DISTANCE / 10),
        string.format("%.0f characters per line (50–75)", m.cpl),
        string.format("lF %.2f (%s), balanced %.2f–%.2f", r.leading, r.leading_class,
            (r.safe_min or 0) + Legibility.LEADING_BALANCED[1], (r.safe_min or 0) + Legibility.LEADING_BALANCED[2]),
        string.format("hyphens on %.0f%% of lines, %d rivers per 100 lines", 100 * m.hyph, floor(m.rivers + 0.5)),
        string.format("space stretch %.2f, loose lines %.0f%%", m.stretch, 100 * m.loose),
        "",
        "Penalties (0 = perfect):",
    }
    local sorted = {}
    for _, n in ipairs(names) do sorted[#sorted + 1] = n end
    table.sort(sorted, function(a, b) return (r.parts[a[1]] or 0) > (r.parts[b[1]] or 0) end)
    for _, n in ipairs(sorted) do
        local v = r.parts[n[1]] or 0
        if v >= 0.05 then out[#out + 1] = string.format("  %s %.1f", n[2], v) end
    end
    return table.concat(out, "\n")
end

Legibility.utf8len = utf8len

return Legibility
