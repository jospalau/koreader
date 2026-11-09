--[[
2-bookshelf-bar-styles.lua  (KOReader userpatch)     version 1.0.0-beta.2

Adds sixteen progress bar styles to Bookshelf.

Minimal
  Dots           dots that grow in size as you read
  Segments       ten rounded segments filling up, the current one partly
  Ruler          a ruler whose ticks darken, with a small cursor
  Ribbon         a bookmark ribbon with a notched end
Nature
  Leaves         a wavy stem with alternating leaves, a fresh leaf at the
                 tip and a small flower once the book is finished
  Ivy            a darker twin of Leaves: an ivy vine with lobed leaves,
                 curly tendrils and a curl at the end
  Tendril        a bare vine that grows nothing but curls
  Bee trail      a bee following a dotted path towards a daisy
  Sakura         drifting cherry petals and a blossom at the end
  Mushrooms      mushrooms sprouting along a mossy ground line, with a big
                 toadstool at the end
Stationery
  Pencil         a pencil-drawn line, a tilted pencil at its tip and a
                 dashed guide line ahead
Sky
  Constellation  stars joined by thin lines; the ones still ahead are dots,
                 and the last star grows when the book is finished
  Moon phases    a row of moons waxing from new to full
Seasonal
  Snowflakes     snowflakes appearing one by one
  Fairy lights   a string of lights that grows, ending in a star
Animals
  Cat & yarn     a kitten chasing a ball of yarn and napping next to it at
                 the end

Shapes are drawn with soft (anti-aliased) edges. On colour screens the
styles use their own colours, on greyscale screens shades of grey.

Install: copy this file to  koreader/patches/  (on Kobo:
/mnt/onboard/.adds/koreader/patches/) and restart KOReader.
Then, in the editor of a line containing %bar, tap "Bar: ..." until the
style you want shows up. Raise the bar height (around 200%): the drawings
need at least ~20 px to read well.

If the patch is removed, Bookshelf draws unknown styles as "bordered":
no errors, no settings to fix.
]]

local MODULE = "lib/bookshelf_bar_paint"
local logger = require("logger")

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local sin, cos, abs, sqrt, PI = math.sin, math.cos, math.abs, math.sqrt, math.pi
local rad = math.rad

-- ── shapes as signed distance functions ─────────────────────────────────────
-- A shape is { sd = function(x, y) -> distance (negative inside), x0, y0, x1, y1 }.

local function shape(sd, x0, y0, x1, y1) return { sd = sd, x0 = x0, y0 = y0, x1 = x1, y1 = y1 } end

local function circle(cx, cy, r)
    return shape(function(x, y)
        local dx, dy = x - cx, y - cy
        return sqrt(dx * dx + dy * dy) - r
    end, cx - r, cy - r, cx + r, cy + r)
end

local function ellipse(cx, cy, rx, ry)
    return shape(function(x, y)
        local px, py = (x - cx) / rx, (y - cy) / ry
        local k0 = sqrt(px * px + py * py)
        local qx, qy = (x - cx) / (rx * rx), (y - cy) / (ry * ry)
        local k1 = sqrt(qx * qx + qy * qy)
        if k1 == 0 then return -min(rx, ry) end
        return k0 * (k0 - 1) / k1
    end, cx - rx, cy - ry, cx + rx, cy + ry)
end

local function segDist(x, y, ax, ay, bx, by)
    local ex, ey = bx - ax, by - ay
    local wx, wy = x - ax, y - ay
    local l = ex * ex + ey * ey
    local t = l > 0 and (wx * ex + wy * ey) / l or 0
    t = t < 0 and 0 or (t > 1 and 1 or t)
    local dx, dy = wx - ex * t, wy - ey * t
    return sqrt(dx * dx + dy * dy)
end

-- a thick polyline with round ends; pts = { x1, y1, x2, y2, ... }
local function stroke(pts, r)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for i = 1, #pts, 2 do
        x0, x1 = min(x0, pts[i]), max(x1, pts[i])
        y0, y1 = min(y0, pts[i + 1]), max(y1, pts[i + 1])
    end
    local n = #pts
    return shape(function(x, y)
        local d = math.huge
        if n == 2 then return sqrt((x - pts[1]) ^ 2 + (y - pts[2]) ^ 2) - r end
        for i = 1, n - 3, 2 do
            local s = segDist(x, y, pts[i], pts[i + 1], pts[i + 2], pts[i + 3])
            if s < d then d = s end
        end
        return d - r
    end, x0 - r, y0 - r, x1 + r, y1 + r)
end

local function line(ax, ay, bx, by, r) return stroke({ ax, ay, bx, by }, r) end

-- a closed polygon (any simple polygon, convex or not)
local function polygon(p)
    local n = #p / 2
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for i = 1, #p, 2 do
        x0, x1 = min(x0, p[i]), max(x1, p[i])
        y0, y1 = min(y0, p[i + 1]), max(y1, p[i + 1])
    end
    return shape(function(x, y)
        local d = math.huge
        local s = 1
        local j = n
        for i = 1, n do
            local vix, viy, vjx, vjy = p[2 * i - 1], p[2 * i], p[2 * j - 1], p[2 * j]
            local ex, ey = vjx - vix, vjy - viy
            local wx, wy = x - vix, y - viy
            local l = ex * ex + ey * ey
            local t = l > 0 and (wx * ex + wy * ey) / l or 0
            t = t < 0 and 0 or (t > 1 and 1 or t)
            local bx, by = wx - ex * t, wy - ey * t
            local dd = bx * bx + by * by
            if dd < d then d = dd end
            local c1, c2, c3 = y >= viy, y < vjy, ex * wy > ey * wx
            if (c1 and c2 and c3) or (not c1 and not c2 and not c3) then s = -s end
            j = i
        end
        return s * sqrt(d)
    end, x0, y0, x1, y1)
end

-- grow (r > 0) or shrink (r < 0) a shape: also rounds its corners
local function offset(a, r)
    return shape(function(x, y) return a.sd(x, y) - r end, a.x0 - r, a.y0 - r, a.x1 + r, a.y1 + r)
end

local function union(a, b, k)          -- k > 0: smooth blend between the two
    return shape(function(x, y)
        local da, db = a.sd(x, y), b.sd(x, y)
        if not k then return min(da, db) end
        local h = max(k - abs(da - db), 0) / k
        return min(da, db) - h * h * k / 4
    end, min(a.x0, b.x0), min(a.y0, b.y0), max(a.x1, b.x1), max(a.y1, b.y1))
end

local function intersect(a, b)
    return shape(function(x, y) return max(a.sd(x, y), b.sd(x, y)) end,
        max(a.x0, b.x0), max(a.y0, b.y0), min(a.x1, b.x1), min(a.y1, b.y1))
end

-- a wavy band following y = fy(x) between x0 and x1, half-thickness r
local function wave(fy, x0, x1, r)
    local ylo, yhi = math.huge, -math.huge
    for x = floor(x0), ceil(x1) do
        local v = fy(x)
        ylo, yhi = min(ylo, v), max(yhi, v)
    end
    return shape(function(x, y)
        if x < x0 then return sqrt((x - x0) ^ 2 + (y - fy(x0)) ^ 2) - r end
        if x > x1 then return sqrt((x - x1) ^ 2 + (y - fy(x1)) ^ 2) - r end
        local s = (fy(x + 0.5) - fy(x - 0.5))
        return abs(y - fy(x)) / sqrt(1 + s * s) - r
    end, x0 - r, ylo - r, x1 + r, yhi + r)
end

-- quadratic curve as a list of points
local function bez(ax, ay, cx, cy, bx, by, n)
    n = n or 12
    local pts = {}
    for i = 0, n do
        local t = i / n
        local u = 1 - t
        pts[#pts + 1] = u * u * ax + 2 * u * t * cx + t * t * bx
        pts[#pts + 1] = u * u * ay + 2 * u * t * cy + t * t * by
    end
    return pts
end

-- an almond-shaped leaf/bulb from its base (bx, by) towards angle ang
local function almond(bx, by, ang, len, wid, expo)
    expo = expo or 0.8
    local ca, sa = cos(ang), sin(ang)
    local pts, back = {}, {}
    local n = 10
    for i = 0, n do
        local t = i / n
        local u = len * t
        local h = wid * sin(PI * t) ^ expo
        pts[#pts + 1] = bx + ca * u - sa * h
        pts[#pts + 1] = by + sa * u + ca * h
        back[#back + 1] = { bx + ca * u + sa * h, by + sa * u - ca * h }
    end
    for i = #back - 1, 2, -1 do
        pts[#pts + 1] = back[i][1]
        pts[#pts + 1] = back[i][2]
    end
    return polygon(pts)
end

-- a star polygon with k points
local function star(cx, cy, k, R, r, rot)
    local p = {}
    for i = 0, 2 * k - 1 do
        local a = (rot or -PI / 2) + i * PI / k
        local rr = (i % 2 == 0) and R or r
        p[#p + 1] = cx + rr * cos(a)
        p[#p + 1] = cy + rr * sin(a)
    end
    return polygon(p)
end

-- ── canvas: paints shapes with soft edges ───────────────────────────────────
-- put(x, y, w, rgb, alpha) paints a horizontal run of w pixels.
local Canvas = {}
Canvas.__index = Canvas

local function newCanvas(put, bx, by, bw, bh)
    return setmetatable({ put = put, X0 = bx, Y0 = by, X1 = bx + bw - 1, Y1 = by + bh - 1 }, Canvas)
end

local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- fill with colour `fill`; if `line` is given, a border of width lw inside the edge
function Canvas:draw(s, fill, line_c, lw)
    if not s or (not fill and not line_c) then return end
    lw = (line_c and lw) or 0
    local X0, X1 = max(self.X0, floor(s.x0 - 1)), min(self.X1, ceil(s.x1 + 1))
    local Y0, Y1 = max(self.Y0, floor(s.y0 - 1)), min(self.Y1, ceil(s.y1 + 1))
    local put, sd = self.put, s.sd
    for py = Y0, Y1 do
        local rx, rc, rn = nil, nil, 0
        local function flush()
            if rx then put(rx, py, rn, rc, 1) end
            rx, rc, rn = nil, nil, 0
        end
        for px = X0, X1 do
            local d = sd(px + 0.5, py + 0.5)
            local a = 0.5 - d
            a = a < 0 and 0 or (a > 1 and 1 or a)
            if a > 0.004 then
                local col
                if lw > 0 then
                    local ai = 0.5 - (d + lw)
                    ai = ai < 0 and 0 or (ai > 1 and 1 or ai)
                    if fill then
                        local t = ai / a
                        col = t >= 0.999 and fill or (t <= 0.001 and line_c or mix(line_c, fill, t))
                    else
                        col, a = line_c, a - ai
                    end
                else
                    col = fill
                end
                if a >= 0.996 then
                    if rx and rc == col and rx + rn == px then
                        rn = rn + 1
                    else
                        flush(); rx, rc, rn = px, col, 1
                    end
                else
                    flush()
                    if a > 0.004 then put(px, py, 1, col, a) end
                end
            else
                flush()
            end
        end
        flush()
    end
end

-- ── styles ──────────────────────────────────────────────────────────────────
-- Every style is fn(cv, X, Y, W, H, f, pal). Sizes are designed for a 28 px
-- bar and scale with H (u = H / 28).

local function outlineWidth(u) return max(1, 1.05 * u) end

local function flower(cv, cx, cy, fr, pal, lw)
    local pr = fr * 0.42
    for k = 0, 4 do
        local a = rad(-90 + k * 72)
        cv:draw(circle(cx + fr * 0.56 * cos(a), cy + fr * 0.56 * sin(a), pr), pal.petal, pal.petal_line, lw)
    end
    cv:draw(circle(cx, cy, fr * 0.3), pal.middle, pal.petal_line, lw)
end


-- the flower that blooms at the end of Leaves
local function prettyFlower(cv, cx, cy, fr, pal, lw, u)
    -- two leaves tucked behind the flower, on the stem side
    cv:draw(almond(cx - fr * 0.35, cy, rad(-150), fr * 0.95, fr * 0.32), pal.leaf, pal.leaf_line, lw)
    cv:draw(almond(cx - fr * 0.35, cy, rad(150), fr * 0.85, fr * 0.30), pal.leaf, pal.leaf_line, lw)
    for k = 0, 4 do
        local a = rad(-90 + 18 + k * 72)
        cv:draw(union(circle(cx + cos(a) * fr * 0.6, cy + sin(a) * fr * 0.6, fr * 0.36),
                line(cx, cy, cx + cos(a) * fr * 0.3, cy + sin(a) * fr * 0.3, fr * 0.13), fr * 0.35),
            pal.petal, pal.petal_line, lw)
        cv:draw(line(cx + cos(a) * fr * 0.4, cy + sin(a) * fr * 0.4, cx + cos(a) * fr * 0.66, cy + sin(a) * fr * 0.66,
            0.3 * u), pal.petal_vein)
    end
    cv:draw(circle(cx, cy, fr * 0.3), pal.middle, pal.petal_line, lw)
    for k = 0, 2 do
        local a = rad(-60 + k * 120)
        cv:draw(circle(cx + cos(a) * fr * 0.12, cy + sin(a) * fr * 0.12, 0.65 * u), pal.seed)
    end
end

local function leaves(cv, X, Y, W, H, f, pal)
    local u = H / 28
    local mid = Y + H / 2
    local amp, period = 2 * u, 90 * u
    local function yAt(x) return mid + amp * sin(2 * PI * (x - X) / period) end
    local lw = outlineWidth(u)
    local done = f >= 0.995
    local fr = 12.5 * u
    local endx = X + W - 1 - (done and (2 * fr + u) or 11 * u)
    local tip = X + 2 * u + (endx - X - 2 * u) * f
    local L, Wd = 12.5 * u, 4.2 * u
    if not done then cv:draw(wave(yAt, tip, X + W - 1 - u, 0.6 * u), pal.track) end
    local function leaf(x, ang, len, wid)
        cv:draw(almond(x, yAt(x), ang, len, wid), pal.leaf, pal.leaf_line, lw)
        if len >= 11 then
            local ca, sa = cos(ang), sin(ang)
            cv:draw(line(x + ca * len * 0.2, yAt(x) + sa * len * 0.2, x + ca * len * 0.62, yAt(x) + sa * len * 0.62,
                0.35 * u), pal.leaf_line)
        end
    end
    if f <= 0 then
        cv:draw(wave(yAt, X + u, X + 4 * u, 1.6 * u), pal.stem)
        leaf(X + 3 * u, rad(-52), L * 0.8, Wd * 0.85)
        leaf(X + 3 * u, rad(52), L * 0.7, Wd * 0.85)
        return
    end
    cv:draw(wave(yAt, X + u, tip, 1.6 * u), pal.stem)
    local up, x = true, X + 8 * u
    while x < tip - 7 * u do
        leaf(x, up and rad(-52) or rad(52), L, Wd)
        x = x + 17 * u
        up = not up
    end
    if done then
        prettyFlower(cv, X + W - 1 - fr - 0.5 * u, mid, fr, pal, lw, u)
    else
        local slope = math.atan((yAt(tip) - yAt(tip - 1)))
        leaf(tip - u, slope - rad(22), L * 1.0, Wd)
    end
end



-- a curl that leaves the point (px, py) heading forwards and winds inwards,
-- thinning from r0 to r1 like a real tendril; up = it curls upwards
local function curl(px, py, R, up, turns, r0, r1)
    local a0 = up and PI / 2 or -PI / 2              -- start point relative to the centre
    local dir = up and -1 or 1                       -- so the curl leaves heading right
    local cx, cy = px - R * cos(a0), py - R * sin(a0)
    local T = (turns or 1.3) * 2 * PI
    local n = 36
    local xs, ys, rs = {}, {}, {}
    for i = 0, n do
        local t = T * i / n
        local a = a0 + dir * t
        local rr = R * (1 - 0.78 * t / T)
        xs[i] = cx + rr * cos(a)
        ys[i] = cy + rr * sin(a)
        rs[i] = r0 + (r1 - r0) * i / n
    end
    return shape(function(x, y)
        local d = math.huge
        for i = 0, n - 1 do
            local v = segDist(x, y, xs[i], ys[i], xs[i + 1], ys[i + 1]) - (rs[i] + rs[i + 1]) / 2
            if v < d then d = v end
        end
        return d
    end, cx - R - r0, cy - R - r0, cx + R + r0, cy + R + r0)
end

-- an ivy leaf: five pointed lobes around a heart-shaped base; base at (bx, by)
local function ivyLeaf(cv, bx, by, ang, L, pal, lw, u)
    local lobes = { { 0, 1.0, 0.24 }, { 62, 0.78, 0.21 }, { -62, 0.78, 0.21 }, { 122, 0.5, 0.18 }, { -122, 0.5, 0.18 } }
    local s
    for _, l in ipairs(lobes) do
        local a = ang + rad(l[1])
        local lobe = almond(bx - cos(a) * 0.06 * L, by - sin(a) * 0.06 * L, a, L * l[2], L * l[3], 0.7)
        s = s and union(s, lobe, 0.12 * L) or lobe
    end
    s = union(s, circle(bx + cos(ang) * 0.2 * L, by + sin(ang) * 0.2 * L, 0.26 * L), 0.1 * L)
    cv:draw(s, pal.leaf, pal.leaf_line, lw)
    for i = 1, 3 do
        local a = ang + rad(lobes[i][1])
        local len = L * lobes[i][2] * 0.62
        cv:draw(line(bx, by, bx + cos(a) * len, by + sin(a) * len, 0.32 * u), pal.vein)
    end
end

local function ivy(cv, X, Y, W, H, f, pal)
    local u = H / 28
    local mid = Y + H / 2
    local amp, period = 1.6 * u, 70 * u
    local function yAt(x) return mid + amp * sin(2 * PI * (x - X) / period) end
    local lw = outlineWidth(u)
    local done = f >= 0.995
    local endx = X + W - 1 - (done and 11 * u or 9 * u)
    local tip = X + 2 * u + (endx - X - 2 * u) * f
    if not done then cv:draw(wave(yAt, tip, X + W - 1 - u, 0.55 * u), pal.track) end
    if f <= 0 then
        ivyLeaf(cv, X + 3 * u, yAt(X + 3 * u), rad(-60), 7 * u, pal, lw, u)
        return
    end
    cv:draw(wave(yAt, X + u, tip, 1.3 * u), pal.stem)
    local up, x, i = true, X + 9 * u, 0
    while x < tip - 7 * u do
        local size = ({ 1.0, 0.72, 1.15, 0.85, 0.66, 1.05, 0.9 })[i % 7 + 1]
        local y = yAt(x)
        local a = up and rad(-70) or rad(70)
        -- a short leaf stalk, then the leaf
        local sx, sy = x + cos(a) * 2.2 * u, y + sin(a) * 2.2 * u
        cv:draw(line(x, y, sx, sy, 0.55 * u), pal.stem)
        ivyLeaf(cv, sx, sy, a, 11 * u * size, pal, lw, u)
        -- a curly tendril in every other gap
        if i % 2 == 1 and x + 9 * u < tip then
            local tx = x + 9 * u
            local ty = yAt(tx)
            local d = up and 1 or -1
            cv:draw(stroke(bez(tx, ty, tx + 2 * u, ty + d * 4 * u, tx + 4.5 * u, ty + d * 3 * u, 10), 0.4 * u), pal.stem)
            cv:draw(stroke(bez(tx + 4.5 * u, ty + d * 3 * u, tx + 5.6 * u, ty + d * 1.6 * u, tx + 4.2 * u, ty + d * 1.4 * u, 8),
                0.4 * u), pal.stem)
        end
        x = x + 18 * u
        up = not up
        i = i + 1
    end
    if done then
        -- the vine ends in a single curl
        cv:draw(curl(tip - 0.5 * u, yAt(tip), 4.6 * u, true, 1.15, 1.3 * u, 0.45 * u), pal.stem)
    else
        local slope = math.atan(yAt(tip) - yAt(tip - 1))
        ivyLeaf(cv, tip - u, yAt(tip - u), slope - rad(30), 6.5 * u, pal, lw, u)
    end
end


local function tendril(cv, X, Y, W, H, f, pal)
    local u = H / 28
    local mid = Y + H / 2
    local amp, period = 1.6 * u, 70 * u
    local function yAt(x) return mid + amp * sin(2 * PI * (x - X) / period) end
    local done = f >= 0.995
    local endx = X + W - 1 - (done and 13 * u or 8 * u)
    local tip = X + 2 * u + (endx - X - 2 * u) * f
    if not done then cv:draw(wave(yAt, tip, X + W - 1 - u, 0.55 * u), pal.track) end
    if f <= 0 then
        cv:draw(curl(X + 2 * u, yAt(X + 2 * u), 3.2 * u, true, 1.2, 0.8 * u, 0.35 * u), pal.stem)
        return
    end
    cv:draw(wave(yAt, X + u, tip, 1.15 * u), pal.stem)
    local up, x, i = true, X + 8 * u, 0
    while x < tip - 6 * u do
        local v = (i * 0.618034 + 0.25) % 1
        local R = (2.8 + 3.4 * v) * u
        cv:draw(curl(x, yAt(x), R, up, 1.2 + 0.4 * v, (0.8 + 0.2 * v) * u, 0.32 * u), pal.stem)
        x = x + (12 + 5 * v) * u
        up = not up
        i = i + 1
    end
    if done then
        cv:draw(curl(tip - 0.5 * u, yAt(tip), 5.2 * u, true, 1.2, 1.15 * u, 0.4 * u), pal.stem)
    else
        cv:draw(curl(tip - 0.5 * u, yAt(tip), 2.4 * u, up, 1.1, 0.9 * u, 0.35 * u), pal.stem)
    end
end

local function pencil(cv, X, Y, W, H, f, pal)
    local u = H / 28
    local lw = outlineWidth(u)
    local ang = rad(-35)
    local plen, pw = 30 * u, 8.6 * u
    local ca, sa = cos(ang), sin(ang)
    local reserve = plen * ca + pw * 0.5 + u
    local base = Y + H - 6 * u
    local tip = X + 1.5 * u + (W - 1.5 * u - reserve) * f
    local function yAt(x)
        local i = (x - X) / u
        return base + u * (0.6 * sin(i * 0.21) + 0.4 * sin(i * 0.057 + 1.3))
    end
    -- dashed guide
    local x = tip + 4 * u
    while x < X + W - 2 * u do
        cv:draw(line(x, base, min(x + 3 * u, X + W - 2 * u), base, 0.5 * u), pal.track)
        x = x + 7 * u
    end
    if f > 0 then cv:draw(wave(yAt, X + 1.2 * u, tip, 1.15 * u), pal.graphite) end
    local tx, ty = tip, (f > 0) and yAt(tip) or base
    local nx, ny = -sa, ca
    local function P(a, b) return tx + ca * a + nx * b, ty + sa * a + ny * b end
    local hw = pw / 2
    local function quad(u0, u1, w0, w1)
        local ax, ay = P(u0, -w0); local bx, by = P(u1, -w1)
        local cx, cy = P(u1, w1); local dx, dy = P(u0, w0)
        return polygon({ ax, ay, bx, by, cx, cy, dx, dy })
    end
    local uc, ub, uf = plen * 0.30, plen * 0.78, plen * 0.88
    cv:draw(offset(quad(uf, plen - 1.2 * u, hw - 1.2 * u, hw - 1.2 * u), 1.2 * u), pal.eraser, pal.outline, lw)
    cv:draw(quad(ub, uf + 0.6 * u, hw, hw), pal.ferrule, pal.outline, lw)
    cv:draw(quad(uc - 0.5 * u, ub + 0.5 * u, hw, hw), pal.body, pal.outline, lw)
    cv:draw(quad(uc, ub, hw * 0.12, hw * 0.12), pal.body_dark)
    local ax, ay = P(0, 0); local bx, by = P(uc, -hw); local cx, cy = P(uc, hw)
    cv:draw(offset(polygon({ ax, ay, bx, by, cx, cy }), 0.2 * u), pal.wood, pal.outline, lw)
    local ul = plen * 0.11
    local lx, ly = P(ul, -hw * ul / uc); local mx, my = P(ul, hw * ul / uc)
    cv:draw(polygon({ ax, ay, lx, ly, mx, my }), pal.graphite)
end

local function constellation(cv, X, Y, W, H, f, pal)
    local u = H / 28
    local done = f >= 0.995
    local R = 5.6 * u
    local gap = max(R * 4, 44 * u)
    local n = max(2, floor((W - 2 * R) / gap) + 1)
    local stars = {}
    for i = 0, n - 1 do
        local jit = (i * 0.618034 + 0.35) % 1
        stars[i + 1] = { X + R + 1 + (W - 2 * R - 3) * i / (n - 1), Y + R + u + (H - 2 * R - 2 * u) * jit }
    end
    local pos = f * (n - 1)
    local reached = floor(pos)
    local lr = 0.55 * u
    for i = 1, reached do
        local a, b = stars[i], stars[i + 1]
        cv:draw(line(a[1], a[2], b[1], b[2], lr), pal.line)
    end
    if not done and reached + 2 <= n and f > 0 then
        local a, b = stars[reached + 1], stars[reached + 2]
        local t = pos - reached
        cv:draw(line(a[1], a[2], a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, lr), pal.line)
    end
    for i, s in ipairs(stars) do
        -- each star has its own size and tilt (fixed, so the sky never changes)
        local v = (i * 0.754877 + 0.1) % 1
        local size = ({ 0.72, 1.0, 0.85, 1.18 })[i % 4 + 1]
        local tilt = rad((v - 0.5) * 24)
        if f > 0 and i <= reached + 1 then
            local r = (done and i == n) and R * 1.45 or R * size
            cv:draw(offset(star(s[1], s[2], 4, r, r * 0.34, -PI / 2 + tilt), 0.35 * u), pal.star)
            if v < 0.35 and not (done and i == n) then   -- a tiny companion star
                cv:draw(circle(s[1] + r * 1.15, s[2] - r * 0.9, 0.75 * u), pal.star)
            end
        else
            cv:draw(circle(s[1], s[2], (0.8 + 0.5 * size) * u), pal.dot)
        end
    end
end

local function moonPhases(cv, X, Y, W, H, f, pal)
    local u = H / 28
    local lw = outlineWidth(u)
    local r = 9.5 * u
    local n = max(3, floor((W - 2 * r) / (2 * r + 9 * u)) + 1)
    local cy = Y + H / 2
    for i = 0, n - 1 do
        local cx = X + r + 0.5 + (W - 2 * r - 1) * i / (n - 1)
        if f > 0 and i <= f * (n - 1) + 1e-6 then
            local p = i / (n - 1)
            local disc = circle(cx, cy, r)
            cv:draw(disc, pal.dark, pal.line, lw)
            -- lit part: waxing from the right
            local k = 1 - 2 * p
            local lit
            if p >= 0.999 then
                lit = offset(disc, -lw)
            elseif k >= 0 then
                local e = ellipse(cx, cy, max(0.01, k * r), r)
                lit = shape(function(x, y) return max(disc.sd(x, y) + lw, -(x - cx), -e.sd(x, y)) end,
                    cx, cy - r, cx + r, cy + r)
            else
                local e = ellipse(cx, cy, -k * r, r)
                lit = shape(function(x, y) return max(disc.sd(x, y) + lw, min(-(x - cx), e.sd(x, y))) end,
                    cx - r, cy - r, cx + r, cy + r)
            end
            if p > 0 then cv:draw(lit, pal.lit) end
            if p >= 0.999 then
                cv:draw(circle(cx - 3 * u, cy - 2.5 * u, 1.8 * u), pal.crater)
                cv:draw(circle(cx + 2.8 * u, cy + 2.6 * u, 1.3 * u), pal.crater)
                cv:draw(circle(cx + 2.2 * u, cy - 3.6 * u, 0.9 * u), pal.crater)
            end
        else
            cv:draw(circle(cx, cy, 1.1 * u), pal.dot)
        end
    end
end

local function snowflake(cx, cy, r, u)
    -- one flat list of segments, checked in a single loop (faster on device)
    local segs = {}
    local function seg(ax, ay, bx, by, w) segs[#segs + 1] = { ax, ay, bx, by, w } end
    for k = 0, 2 do
        local a = rad(90 + k * 60)
        local ca, sa = cos(a), sin(a)
        seg(cx - r * ca, cy - r * sa, cx + r * ca, cy + r * sa, 0.75 * u)
        for _, sg in ipairs({ -1, 1 }) do
            local bx, by = cx + sg * r * 0.6 * ca, cy + sg * r * 0.6 * sa
            local base = a + (sg < 0 and PI or 0)
            for _, ba in ipairs({ rad(55), rad(-55) }) do
                local b = base + ba
                seg(bx, by, bx + r * 0.36 * cos(b), by + r * 0.36 * sin(b), 0.6 * u)
            end
        end
    end
    local core = 1.5 * u
    local reach = r + u
    return shape(function(x, y)
        local dx, dy = x - cx, y - cy
        local dc = sqrt(dx * dx + dy * dy)
        if dc > reach + 2 then return dc - reach end
        local d = dc - core
        for i = 1, #segs do
            local sg = segs[i]
            local v = segDist(x, y, sg[1], sg[2], sg[3], sg[4]) - sg[5]
            if v < d then d = v end
        end
        return d
    end, cx - reach, cy - reach, cx + reach, cy + reach)
end

local function snowflakes(cv, X, Y, W, H, f, pal)
    local u = H / 28
    local done = f >= 0.995
    local step = 29 * u
    local n = max(3, floor((W - 2 * u) / step))
    local s = (W - 2 * u) / n
    local cy = Y + H / 2
    for i = 0, n - 1 do
        local cx = X + u + s * (i + 0.5)
        if f > 0 and i <= f * (n - 1) + 1e-6 then
            local r = (done and i == n - 1) and 12.5 * u or ((i % 2 == 1) and 10.5 * u or 8.5 * u)
            cv:draw(snowflake(cx, cy, r, u), pal.flake)
        else
            cv:draw(circle(cx, cy, 1.1 * u), pal.dot)
        end
    end
end


-- a white daisy, used by Bee trail
local function daisy(cv, cx, cy, fr, pal, lw, u)
    for k = 0, 7 do
        local a = rad(-90 + 22.5 + k * 45)
        cv:draw(line(cx + cos(a) * fr * 0.3, cy + sin(a) * fr * 0.3, cx + cos(a) * fr * 0.78, cy + sin(a) * fr * 0.78,
            fr * 0.2), pal.daisy, pal.daisy_line, lw)
    end
    cv:draw(circle(cx, cy, fr * 0.32), pal.middle, pal.daisy_line, lw)
    for k = 0, 2 do
        local a = rad(-60 + k * 120)
        cv:draw(circle(cx + cos(a) * fr * 0.12, cy + sin(a) * fr * 0.12, 0.65 * u), pal.seed)
    end
end

local function beeTrail(cv, X, Y, W, H, f, pal)
    local u = H / 28
    local lw = outlineWidth(u)
    local mid = Y + H / 2
    local fr = 12.5 * u
    local fx = X + W - 1 - fr - 0.5 * u
    local function path(x) return mid + 6 * u * sin((x - X) / (16 * u)) end
    local endx = fx - fr - 10 * u
    local tip = X + 12 * u + (endx - X - 12 * u) * f
    local x = X + 2 * u
    while x < fx - fr - 2 * u do
        cv:draw(circle(x, path(x), 1.05 * u), x <= tip - 9 * u and pal.trail or pal.track)
        x = x + 5 * u
    end
    daisy(cv, fx, mid, fr, pal, lw, u)
    local by = max(path(tip) - 2 * u, Y + 11 * u)   -- keep the wings inside the bar
    cv:draw(ellipse(tip - 2.4 * u, by - 5.6 * u, 3.1 * u, 4.2 * u), pal.wing, pal.wing_line, lw)
    cv:draw(ellipse(tip + 2.6 * u, by - 6.2 * u, 3.1 * u, 4.2 * u), pal.wing, pal.wing_line, lw)
    cv:draw(line(tip - 7 * u, by + 0.3 * u, tip - 9.6 * u, by + 1.1 * u, 0.6 * u), pal.line)
    local body = ellipse(tip, by, 7.2 * u, 5.2 * u)
    cv:draw(body, pal.body, pal.line, lw)
    local inner = offset(body, -lw * 0.6)
    for _, sx in ipairs({ -3.2, 0, 3.2 }) do
        cv:draw(intersect(inner, line(tip + sx * u, by - 6 * u, tip + sx * u, by + 6 * u, (sx == 0 and 1.1 or 0.8) * u)),
            pal.stripe)
    end
    cv:draw(circle(tip + 4.9 * u, by - 1.2 * u, 0.85 * u), pal.line)
end

local function fairyLights(cv, X, Y, W, H, f, pal)
    local u = H / 28
    local lw = outlineWidth(u)
    local mid = Y + H / 2
    local amp, period = 2 * u, 90 * u
    local function yAt(x) return mid + amp * sin(2 * PI * (x - X) / period) end
    local done = f >= 0.995
    local endx = X + W - 1 - (done and 25 * u or 10 * u)
    local tip = X + 2 * u + (endx - X - 2 * u) * f
    if not done then cv:draw(wave(yAt, tip, X + W - 1 - u, 0.6 * u), pal.track) end
    if f > 0 then cv:draw(wave(yAt, X + u, tip, 1.5 * u), pal.wire) end
    local function bulb(x, ang, colr, scale)
        scale = scale or 1
        local y = yAt(x)
        local ca, sa = cos(ang), sin(ang)
        cv:draw(line(x, y, x + ca * 3.2 * u, y + sa * 3.2 * u, 1.6 * u), pal.cap)
        local bx, by = x + ca * 3 * u, y + sa * 3 * u
        cv:draw(almond(bx, by, ang, 9.5 * u * scale, 4.4 * u * scale, 0.5), colr, pal.line, lw)
        local hx, hy = bx + ca * 5.5 * u * scale - sa * 1.4 * u, by + sa * 5.5 * u * scale + ca * 1.4 * u
        cv:draw(circle(hx, hy, 0.8 * u), pal.shine)
    end
    local up, x, k = true, X + 12 * u, 0
    while x < tip - 8 * u do
        bulb(x, up and rad(-58) or rad(58), pal.bulbs[k % #pal.bulbs + 1])
        x = x + 26 * u
        up = not up
        k = k + 1
    end
    if done then
        local ex = tip
        local cx, cy = ex + 12 * u, yAt(ex) + 1.5 * u
        cv:draw(line(ex - u, yAt(ex), cx - 7 * u, cy - 0.5 * u, 1.5 * u), pal.wire)
        cv:draw(line(cx - 8.6 * u, cy - 0.4 * u, cx - 6 * u, cy, 1.8 * u), pal.cap)
        cv:draw(offset(star(cx, cy, 5, 10 * u, 4.8 * u, -PI / 2), 1.1 * u), pal.star, pal.line, lw)
        cv:draw(circle(cx - 2.6 * u, cy - 2.6 * u, 1 * u), pal.shine)
    elseif f > 0 then
        local slope = math.atan(yAt(tip) - yAt(tip - 1))
        bulb(tip - u, slope - rad(20), pal.bulbs[k % #pal.bulbs + 1], 0.95)
    end
end


-- a cherry petal: rounded, with a small notch at its tip; base at (bx, by)
local function sakuraPetal(bx, by, ang, len, wid, u)
    local loc = { 0, 0, 0.2, 0.5, 0.45, 0.9, 0.7, 1, 0.9, 0.78, 1, 0.38, 0.84, 0,
                  1, -0.38, 0.9, -0.78, 0.7, -1, 0.45, -0.9, 0.2, -0.5 }
    local ca, sa = cos(ang), sin(ang)
    local pts = {}
    for i = 1, #loc, 2 do
        local a, b = loc[i] * len, loc[i + 1] * wid
        pts[#pts + 1] = bx + ca * a - sa * b
        pts[#pts + 1] = by + sa * a + ca * b
    end
    return offset(polygon(pts), 0.35 * u)
end

local function sakuraFlower(cv, cx, cy, r, u, pal, lw)
    for k = 0, 4 do
        local a = rad(-90 + k * 72)
        cv:draw(sakuraPetal(cx + cos(a) * 0.8 * u, cy + sin(a) * 0.8 * u, a, r, r * 0.5, u), pal.petal, pal.line, lw)
    end
    cv:draw(circle(cx, cy, r * 0.26), pal.center)
    for k = 0, 4 do
        local a = rad(-54 + k * 72)
        cv:draw(line(cx, cy, cx + cos(a) * r * 0.5, cy + sin(a) * r * 0.5, 0.35 * u), pal.stamen)
        cv:draw(circle(cx + cos(a) * r * 0.52, cy + sin(a) * r * 0.52, 0.8 * u), pal.stamen)
    end
end

local function sakura(cv, X, Y, W, H, f, pal)
    local u = H / 28
    local lw = outlineWidth(u)
    local mid = Y + H / 2
    local done = f >= 0.995
    local fr = 12.5 * u
    local endx = X + W - 1 - (done and (2 * fr + 2 * u) or 6 * u)
    local tip = X + 5 * u + (endx - X - 5 * u) * f
    local step = 10 * u
    local i, x = 0, X + 8 * u
    while x < X + W - 3 * u do
        local v = (i * 0.618034 + 0.2) % 1
        local w2 = (i * 0.414214 + 0.7) % 1
        if f > 0 and x <= tip and (not done or x < endx - 2 * u) then
            local y = mid + (v - 0.5) * 6 * u
            local size = 0.85 + 0.25 * w2
            local ang = rad(((i % 2 == 0) and -35 or 35) + (w2 - 0.5) * 40)
            cv:draw(sakuraPetal(x - 3.5 * u, y, ang, 7.5 * u * size, 3.6 * u * size, u),
                pal.petal, pal.line, lw)
        elseif x > tip + 4 * u then
            cv:draw(circle(x, mid + (v - 0.5) * 4 * u, 0.9 * u), pal.track)
        end
        x = x + step
        i = i + 1
    end
    if done then sakuraFlower(cv, X + W - 1 - fr - u, mid, fr, u, pal, lw) end
end

-- a mushroom standing on the ground at (x, gy); kind 1 = spotted toadstool, 2 = round brown cap
local function mushroom(cv, x, gy, s, kind, u, pal, lw)
    local sh, sw = (kind == 1 and 7 or 5.5) * u * s, (kind == 1 and 3.2 or 2.8) * u * s
    local stem = offset(polygon({ x - sw / 2, gy, x + sw / 2, gy, x + sw * 0.38, gy - sh, x - sw * 0.38, gy - sh }), 0.6 * u)
    cv:draw(stem, pal.stem, pal.line, lw)
    local crx, cry = (kind == 1 and 7 or 4.8) * u * s, (kind == 1 and 5.2 or 4.6) * u * s
    local cyc = gy - sh + 0.8 * u
    local half = shape(function(px, py) return py - cyc end, x - crx, cyc - cry, x + crx, cyc)
    local cap = offset(intersect(ellipse(x, cyc, crx, cry), half), 0.5 * u)
    cv:draw(cap, kind == 1 and pal.cap or pal.cap2, pal.line, lw)
    if kind == 1 then
        local inner = offset(cap, -lw)
        for _, d in ipairs({ { -0.45, -0.35, 1.0 }, { 0.15, -0.7, 0.8 }, { 0.55, -0.25, 0.9 }, { -0.1, -0.15, 0.6 } }) do
            cv:draw(intersect(inner, circle(x + d[1] * crx, cyc + d[2] * cry, d[3] * 1.3 * u * s)), pal.dots)
        end
    end
end

local function mushrooms(cv, X, Y, W, H, f, pal)
    local u = H / 28
    local lw = outlineWidth(u)
    local gy = Y + H - 3 * u
    local function g(x) return gy + 0.8 * u * sin((x - X) / (9 * u)) end
    local done = f >= 0.995
    local endx = X + W - 1 - (done and 20 * u or 6 * u)
    local tip = X + 2 * u + (endx - X - 2 * u) * f
    if not done then cv:draw(wave(g, tip, X + W - 1 - u, 0.5 * u), pal.track) end
    if f > 0 then cv:draw(wave(g, X + u, done and X + W - 1 - u or tip, 1.0 * u), pal.ground) end
    local i, x = 0, X + 8 * u
    while x < tip - 6 * u and (not done or x < endx - 8 * u) do
        local v = (i * 0.618034 + 0.3) % 1
        local s = 0.92 + 0.42 * v
        mushroom(cv, x, g(x), s, (i % 3 == 1) and 2 or 1, u, pal, lw)
        -- a tuft of grass now and then
        if i % 2 == 0 then
            local gx = x + 9 * u
            cv:draw(stroke(bez(gx, g(gx), gx - 0.5 * u, g(gx) - 2.5 * u, gx - 1.8 * u, g(gx) - 4 * u, 6), 0.45 * u), pal.ground)
            cv:draw(stroke(bez(gx + u, g(gx), gx + 1.2 * u, g(gx) - 3 * u, gx + 2.2 * u, g(gx) - 4.6 * u, 6), 0.45 * u), pal.ground)
        end
        x = x + (21 + 6 * v) * u
        i = i + 1
    end
    if done then
        mushroom(cv, X + W - 1 - 11 * u, g(X + W - 1 - 11 * u), 1.6, 1, u, pal, lw)
    elseif f > 0 then
        mushroom(cv, tip, g(tip), 0.55, 1, u, pal, lw)   -- a little one just sprouting
    end
end

-- a kitten sitting in profile, facing right; (x, y) = ground under its chest
local function catSitting(cv, x, y, u, pal, lw)
    local function P(a, b) return x + a * u, y + b * u end
    local tail = stroke(bez(x - 5 * u, y - 2.2 * u, x - 12.5 * u, y - 2 * u, x - 11 * u, y - 10.5 * u, 14), 1.35 * u)
    local body = ellipse(x - 1 * u, y - 5.8 * u, 6.2 * u, 5.8 * u)
    local head = circle(x + 3.6 * u, y - 13.6 * u, 6.2 * u)
    local ax, ay = P(-0.6, -17.6); local bx, by = P(0.4, -23.8); local cx, cy = P(4, -19.6)
    local ear1 = offset(polygon({ ax, ay, bx, by, cx, cy }), 0.6 * u)
    ax, ay = P(4.6, -19.8); bx, by = P(9.2, -23.2); cx, cy = P(9.4, -16.6)
    local ear2 = offset(polygon({ ax, ay, bx, by, cx, cy }), 0.6 * u)
    local s = union(union(union(union(body, head, 2.5 * u), ear1, 1.2 * u), ear2, 1.2 * u), tail, 1.6 * u)
    cv:draw(s, pal.cat, pal.line, lw)
    -- front leg, eye, nose, cheek
    cv:draw(line(x + 2.6 * u, y - 4.6 * u, x + 2.6 * u, y - 0.9 * u, 0.5 * u), pal.line)
    cv:draw(ellipse(x + 6 * u, y - 14.4 * u, 1.0 * u, 1.3 * u), pal.line)
    cv:draw(circle(x + 9.5 * u, y - 12.6 * u, 0.75 * u), pal.nose)
    cv:draw(circle(x + 5.6 * u, y - 11.2 * u, 1.2 * u), pal.cheek)
end

-- a kitten curled up asleep, head to the right; (x, y) = ground at its middle
local function catSleeping(cv, x, y, u, pal, lw)
    local body = ellipse(x - 1 * u, y - 5.4 * u, 9.6 * u, 5.4 * u)
    local head = circle(x + 6.4 * u, y - 7 * u, 5.2 * u)
    local ear1 = offset(polygon({ x + 2.6 * u, y - 10.4 * u, x + 3.2 * u, y - 15.6 * u, x + 6.4 * u, y - 11.8 * u }), 0.6 * u)
    local ear2 = offset(polygon({ x + 6.6 * u, y - 12 * u, x + 9.6 * u, y - 15.4 * u, x + 10.6 * u, y - 9.6 * u }), 0.6 * u)
    local s = union(union(union(body, head, 2.5 * u), ear1, 1.2 * u), ear2, 1.2 * u)
    cv:draw(s, pal.cat, pal.line, lw)
    -- the tail wraps around the front, its tip under the chin
    local tail = stroke(bez(x - 9.4 * u, y - 4.2 * u, x - 3 * u, y + 0.4 * u, x + 5.2 * u, y - 2.6 * u, 16), 1.5 * u)
    cv:draw(tail, pal.cat, pal.line, lw)
    -- closed eye, cheek
    cv:draw(stroke(bez(x + 6.8 * u, y - 7.8 * u, x + 8.2 * u, y - 6.4 * u, x + 9.6 * u, y - 7.8 * u, 8), 0.5 * u), pal.line)
    cv:draw(circle(x + 9.6 * u, y - 5.2 * u, 1.2 * u), pal.cheek)
end

local function yarnBall(cv, x, y, r, u, pal, lw)
    local ball = circle(x, y, r)
    cv:draw(ball, pal.yarn, pal.line, lw)
    local inner = offset(ball, -lw * 0.5)
    local w = 0.5 * u
    for _, c in ipairs({
        bez(x - r * 0.9, y - r * 0.3, x, y + r * 0.3, x + r * 0.9, y - r * 0.5),
        bez(x - r * 0.8, y + r * 0.5, x, y + r * 1.0, x + r * 0.8, y + r * 0.35),
        bez(x - r * 0.25, y - r * 1.0, x + r * 0.6, y, x - r * 0.05, y + r),
    }) do
        cv:draw(intersect(inner, stroke(c, w)), pal.yarn_line)
    end
end

local function catAndYarn(cv, X, Y, W, H, f, pal)
    local u = H / 28
    local lw = outlineWidth(u)
    local ground = Y + H - 0.8 * u
    local yr = 5.4 * u
    local yy = ground - yr
    local ty = yy + 3 * u
    local function threadY(x) return ty + 1.3 * u * sin((x - X) / (6 * u)) end
    if f < 0.995 then
        local tip = X + 30 * u + (W - 7 * u - 30 * u) * f
        cv:draw(wave(threadY, X + u, tip - yr * 0.6, 0.8 * u), pal.thread)
        local x = tip + yr + 5 * u
        while x < X + W - 2 * u do
            cv:draw(circle(x, ty, 0.9 * u), pal.track)
            x = x + 6 * u
        end
        catSitting(cv, tip - 18 * u, ground, u, pal, lw)
        yarnBall(cv, tip, yy, yr, u, pal, lw)
    else
        local gx = X + W - 1 - yr - 0.5 * u
        cv:draw(wave(threadY, X + u, gx - yr * 0.6, 0.8 * u), pal.thread)
        catSleeping(cv, gx - yr - 11 * u, ground, u, pal, lw)
        yarnBall(cv, gx, yy, yr, u, pal, lw)
    end
end


-- ── minimal ─────────────────────────────────────────────────────────────────
local function dots(cv, X, Y, W, H, f, pal)
    local u = H / 28
    local mid = Y + H / 2
    local step = 9 * u
    local n = max(5, floor((W - 8 * u) / step) + 1)
    local pos = f * (n - 1)
    for i = 0, n - 1 do
        local x = X + 4 * u + (W - 8 * u) * i / (n - 1)
        if f > 0 and i <= pos + 1e-6 then
            local r = (1.2 + 2.4 * i / (n - 1)) * u
            cv:draw(circle(x, mid, r), pal.fill)
        else
            cv:draw(circle(x, mid, 1.0 * u), pal.track)
        end
    end
    -- the dot being reached grows in as you read
    local i = floor(pos) + 1
    if f > 0 and i <= n - 1 then
        local t = pos - floor(pos)
        local x = X + 4 * u + (W - 8 * u) * i / (n - 1)
        local r = (1.2 + 2.4 * i / (n - 1)) * u * t
        if r > 0.6 * u then cv:draw(circle(x, mid, r), pal.fill) end
    end
end

local function segments(cv, X, Y, W, H, f, pal)
    local u = H / 28
    local mid = Y + H / 2
    local n, gap, hh = 10, 4 * u, 3.4 * u
    local sw = (W - 2 * u - gap * (n - 1)) / n
    local fillto = X + u + (W - 2 * u) * f
    local lw = max(1, 0.9 * u)
    for i = 0, n - 1 do
        local x0 = X + u + i * (sw + gap)
        local pill = stroke({ x0 + hh, mid, x0 + sw - hh, mid }, hh)
        if fillto >= x0 + sw then
            cv:draw(pill, pal.fill)
        else
            cv:draw(pill, nil, pal.track, lw)
            if fillto > x0 then
                local cut = shape(function(x, y) return x - fillto end, x0 - 1, mid - hh, fillto, mid + hh)
                cv:draw(intersect(pill, cut), pal.fill)
            end
        end
    end
end

local function ruler(cv, X, Y, W, H, f, pal)
    local u = H / 28
    local base = Y + H - 7 * u
    local L0, L1 = X + 4 * u, X + W - 4 * u
    local tip = L0 + (L1 - L0) * f
    local lr = 0.45 * u
    cv:draw(line(L0, base, L1, base, lr), pal.track)
    local i, x = 0, L0
    while x <= L1 + 0.01 do
        local h = (i % 10 == 0) and 11 * u or ((i % 5 == 0) and 7 * u or 3.5 * u)
        cv:draw(line(x, base, x, base - h, lr), x <= tip and pal.fill or pal.track)
        x = x + (L1 - L0) / (floor((L1 - L0) / (5 * u)))
        i = i + 1
    end
    if f > 0 then
        cv:draw(line(L0, base, tip, base, 1.0 * u), pal.fill)
        cv:draw(offset(polygon({ tip, base + 2 * u, tip - 3.2 * u, base + 5.6 * u, tip + 3.2 * u, base + 5.6 * u }),
            0.4 * u), pal.fill)
    end
end

local function ribbon(cv, X, Y, W, H, f, pal)
    local u = H / 28
    local mid = Y + H / 2
    local hh = 4.6 * u
    cv:draw(line(X + u, mid, X + W - u, mid, 0.5 * u), pal.track)
    if f <= 0 then return end
    local tip = X + 7 * u + (W - 8 * u) * f
    local notch = 3.6 * u
    local band = polygon({ X + u, mid - hh, tip, mid - hh, tip - notch, mid, tip, mid + hh, X + u, mid + hh })
    cv:draw(offset(band, -0.3 * u), pal.fill)
    -- a soft fold line along the ribbon
    cv:draw(line(X + 2 * u, mid - hh * 0.45, tip - notch - 1.5 * u, mid - hh * 0.45, 0.45 * u), pal.fold)
end

-- ── colours ─────────────────────────────────────────────────────────────────
-- For each style: a colour palette, a greyscale palette, and which entries
-- take the colours picked in Bookshelf's menu (fill / track).
local K, D, G, LG, WH = { 0, 0, 0 }, { 85, 85, 85 }, { 136, 136, 136 }, { 204, 204, 204 }, { 255, 255, 255 }

local FLOWER_C = { petal = { 248, 170, 200 }, petal_line = { 196, 64, 126 }, middle = { 250, 200, 70 } }
local FLOWER_G = { petal = WH, petal_line = K, middle = G }
local function with(t, extra)
    local r = {}
    for k, v in pairs(t) do r[k] = v end
    for k, v in pairs(extra) do r[k] = v end
    return r
end

local STYLES = {
    -- minimal
    { name = "Dots", paint = dots, color = { fill = { 40, 40, 40 }, track = LG }, grey = { fill = K, track = LG },
      fill = { "fill" }, bg = { "track" } },
    { name = "Segments", paint = segments, color = { fill = { 40, 40, 40 }, track = LG }, grey = { fill = K, track = LG },
      fill = { "fill" }, bg = { "track" } },
    { name = "Ruler", paint = ruler, color = { fill = { 40, 40, 40 }, track = LG }, grey = { fill = K, track = LG },
      fill = { "fill" }, bg = { "track" } },
    { name = "Ribbon", paint = ribbon,
      color = { fill = { 196, 64, 70 }, fold = { 222, 110, 112 }, track = LG }, grey = { fill = D, fold = G, track = LG },
      derive = { fold = { "tint", 0.3 } }, fill = { "fill" }, bg = { "track" } },
    { name = "Leaves", paint = leaves,
      color = with(FLOWER_C, { stem = { 92, 156, 88 }, leaf = { 132, 190, 112 }, leaf_line = { 58, 116, 62 }, track = LG,
                               petal_vein = { 236, 140, 178 }, seed = { 214, 150, 40 } }),
      grey = with(FLOWER_G, { stem = D, leaf = G, leaf_line = K, track = LG, petal_vein = LG, seed = K }),
      derive = { leaf_line = { "shade", 0.55 }, stem = { "shade", 0.8 } }, fill = { "leaf", "stem" }, bg = { "track" } },
    { name = "Ivy", paint = ivy,
      color = { stem = { 74, 58, 46 }, leaf = { 46, 92, 58 }, leaf_line = { 20, 40, 26 }, vein = { 88, 138, 96 },
                berry = { 42, 40, 62 }, shine = { 170, 170, 196 }, track = { 190, 190, 190 } },
      grey = { stem = K, leaf = D, leaf_line = K, vein = G, berry = K, shine = LG, track = LG },
      derive = { leaf_line = { "shade", 0.45 }, vein = { "tint", 0.35 } }, fill = { "leaf" }, bg = { "track" } },
    { name = "Tendril", paint = tendril,
      color = { stem = { 92, 140, 86 }, track = { 196, 210, 192 } },
      grey = { stem = D, track = LG },
      fill = { "stem" }, bg = { "track" } },
    { name = "Bee trail", paint = beeTrail,
      color = with(FLOWER_C, { daisy = WH, daisy_line = { 120, 120, 120 }, seed = { 214, 150, 40 }, trail = { 90, 90, 90 }, track = LG, body = { 252, 206, 70 }, stripe = { 40, 40, 40 },
                               wing = { 235, 245, 255 }, wing_line = { 140, 160, 180 }, line = K }),
      grey = with(FLOWER_G, { daisy = WH, daisy_line = K, seed = K, trail = K, track = LG, body = WH, stripe = K, wing = WH, wing_line = G, line = K }),
      fill = { "trail" }, bg = { "track" } },
    { name = "Sakura", paint = sakura,
      color = { petal = { 250, 196, 214 }, line = { 206, 108, 146 }, center = { 236, 130, 166 }, stamen = { 196, 70, 110 },
                track = { 240, 210, 222 } },
      grey = { petal = LG, line = D, center = G, stamen = K, track = LG },
      derive = { line = { "shade", 0.65 }, center = { "shade", 0.82 }, stamen = { "shade", 0.5 } }, fill = { "petal" }, bg = { "track" } },
    { name = "Mushrooms", paint = mushrooms,
      color = { cap = { 214, 70, 60 }, cap2 = { 186, 136, 90 }, dots = WH, stem = { 248, 240, 226 }, line = { 60, 45, 40 },
                ground = { 104, 146, 78 }, track = LG },
      grey = { cap = D, cap2 = G, dots = WH, stem = WH, line = K, ground = D, track = LG },
      fill = { "ground" }, bg = { "track" } },
    { name = "Pencil", paint = pencil,
      color = { graphite = { 70, 70, 78 }, track = { 190, 190, 190 }, wood = { 236, 200, 150 }, body = { 246, 196, 60 },
                body_dark = { 222, 160, 30 }, ferrule = { 175, 175, 182 }, eraser = { 240, 140, 160 }, outline = { 50, 50, 50 } },
      grey = { graphite = D, track = LG, wood = WH, body = LG, body_dark = G, ferrule = G, eraser = WH, outline = K },
      fill = { "graphite" }, bg = { "track" } },
    { name = "Constellation", paint = constellation,
      color = { star = { 46, 58, 128 }, line = { 120, 132, 190 }, dot = { 190, 190, 205 } },
      grey = { star = K, line = G, dot = LG },
      derive = { line = { "tint", 0.45 } }, fill = { "star" }, bg = { "dot" } },
    { name = "Moon phases", paint = moonPhases,
      color = { dark = { 70, 78, 110 }, lit = { 252, 238, 180 }, line = { 40, 44, 70 }, crater = { 230, 214, 150 }, dot = LG },
      grey = { dark = D, lit = WH, line = K, crater = LG, dot = LG },
      derive = { line = { "shade", 0.55 } }, fill = { "dark" }, bg = { "dot" } },
    { name = "Snowflakes", paint = snowflakes,
      color = { flake = { 70, 130, 190 }, dot = { 190, 205, 220 } },
      grey = { flake = K, dot = LG },
      fill = { "flake" }, bg = { "dot" } },
    { name = "Fairy lights", paint = fairyLights,
      color = { wire = { 60, 90, 60 }, track = LG, cap = { 40, 40, 40 }, line = { 40, 40, 40 }, shine = WH,
                star = { 252, 210, 80 },
                bulbs = { { 240, 110, 110 }, { 252, 206, 90 }, { 120, 190, 120 }, { 120, 160, 230 } } },
      grey = { wire = D, track = LG, cap = K, line = K, shine = WH, star = LG, bulbs = { LG } },
      fill = { "wire" }, bg = { "track" } },
    { name = "Cat & yarn", paint = catAndYarn,
      color = { cat = { 238, 170, 100 }, line = { 60, 45, 40 }, nose = { 220, 110, 120 }, cheek = { 245, 150, 140 },
                yarn = { 236, 140, 170 }, yarn_line = { 180, 70, 110 }, thread = { 214, 100, 140 }, track = LG },
      grey = { cat = G, line = K, nose = K, cheek = G, yarn = LG, yarn_line = D, thread = D, track = LG },
      fill = { "thread" }, bg = { "track" } },
}
local BY_NAME = {}
for _, s in ipairs(STYLES) do BY_NAME[s.name] = s end

local function rgbOf(c)
    if type(c) ~= "cdata" then return nil end
    local ok, v = pcall(function() return c:getColorRGB32() end)
    if ok and v then return { v.r, v.g, v.b } end
end

-- Bookshelf's own default bar colours (and their night-mode inverses). A reader
-- who tapped "Default" in the colour picker has one of these stored as a
-- "picked" colour; treat it as not picked, so the styles keep their own colours.
local function isBookshelfDefault(c)
    return c and c[1] == c[2] and c[2] == c[3] and (c[1] == 0x40 or c[1] == 0xBF)
end

local function adjust(c, how, t)
    if how == "shade" then return { c[1] * t, c[2] * t, c[3] * t } end
    return { c[1] + (255 - c[1]) * t, c[2] + (255 - c[2]) * t, c[3] + (255 - c[3]) * t }
end

local function palette(def, colors, color_screen)
    local pal = {}
    for k, v in pairs(color_screen and def.color or def.grey) do pal[k] = v end
    if colors then
        local fill, bg = rgbOf(colors.fill), rgbOf(colors.bg)
        if isBookshelfDefault(fill) then fill = nil end
        if isBookshelfDefault(bg) then bg = nil end
        if fill then
            for _, k in ipairs(def.fill) do pal[k] = fill end
            -- outlines and details follow the picked colour, so nothing keeps
            -- the style's own hue next to it
            for k, d in pairs(def.derive or {}) do pal[k] = adjust(fill, d[1], d[2]) end
        end
        if bg then
            for _, k in ipairs(def.bg) do pal[k] = bg end
        elseif colors.bg == false then
            for _, k in ipairs(def.bg) do pal[k] = nil end
        end
    end
    return pal
end

-- ── hooking into Bookshelf ──────────────────────────────────────────────────
local function install(P)
    if type(P) ~= "table" or P.__bar_styles or type(P.paintProgressBar) ~= "function" then return end
    P.__bar_styles = true
    if type(P.BAR_STYLES) == "table" then
        for _, s in ipairs(STYLES) do table.insert(P.BAR_STYLES, s.name) end
    end
    local orig = P.paintProgressBar
    local Blitbuffer = require("ffi/blitbuffer")
    local Screen = require("device").screen
    P.paintProgressBar = function(bb, x, y, w, h, fraction, ticks, style, orientation, reverse, colors, markers)
        local def = BY_NAME[style]
        if def then
            if orientation ~= "vertical" and not reverse and w >= 40 and h >= 10 then
                local ok, err = pcall(function()
                    local put = function(px, py, n, c, a)
                        local r, g, b = floor(c[1] + 0.5), floor(c[2] + 0.5), floor(c[3] + 0.5)
                        if a >= 0.996 then
                            bb:paintRectRGB32(px, py, n, 1, Blitbuffer.ColorRGB32(r, g, b, 0xFF))
                        else
                            bb:blendRectRGB32(px, py, n, 1, Blitbuffer.ColorRGB32(r, g, b, floor(a * 255 + 0.5)))
                        end
                    end
                    local cv = newCanvas(put, x, y, w, h)
                    def.paint(cv, x, y, w, h, math.max(0, math.min(1, fraction or 0)),
                        palette(def, colors, Screen:isColorEnabled()))
                end)
                if ok then return end
                logger.warn("bookshelf-bar-styles:", err)
            end
            style = "rounded"
        end
        return orig(bb, x, y, w, h, fraction, ticks, style, orientation, reverse, colors, markers)
    end
    logger.info("bookshelf-bar-styles: styles added")
end

-- Bookshelf loads its painter only when it draws the first bar: catch that
-- require and add the styles (once).
if package.loaded[MODULE] then
    install(package.loaded[MODULE])
else
    local orig_require = require
    local done = false
    _G.require = function(name, ...)
        local m = orig_require(name, ...)
        if not done and name == MODULE then
            done = true
            local ok, err = pcall(install, m)
            if not ok then logger.warn("bookshelf-bar-styles:", err) end
        end
        return m
    end
end

-- exposed only for testing outside KOReader
return { styles = STYLES, canvas = newCanvas, palette = palette }
