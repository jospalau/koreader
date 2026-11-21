local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local Device = require("device")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local Screen = Device.screen

local HAS_COLOR = true
if Screen.isColorScreen then HAS_COLOR = Screen:isColorScreen() and true or false end

local MAX_DRAW_COMMANDS = 12000

local DEFAULTS = {
    enabled = true,
    style = "greek",
    thickness = 2,
    inset = 28,
    color = "#000000",
}

local STYLES = {
    { value = "greek", label = _("Greek key") },
    { value = "aztec", label = _("Aztec") },
    { value = "film", label = _("Film strip") },
    { value = "circuit", label = _("Circuit") },
    { value = "brick", label = _("Brickwork") },
    { value = "checker", label = _("Chess") },
    { value = "marquee", label = _("Marquee") },
    { value = "chain", label = _("Chain") },
    { value = "halftone", label = _("Halftone") },
    { value = "battlements", label = _("Battlements") },
    { value = "chevron", label = _("Chevron") },
    { value = "ogham", label = _("Ogham") },
    { value = "plus", label = _("Plus") },
}

local VALID_STYLES = {}
for _idx, style in ipairs(STYLES) do
    VALID_STYLES[style.value] = true
end

local THICKNESS_OPTIONS = {
    { value = 1, label = _("Fine (1 px)") },
    { value = 2, label = _("Regular (2 px)") },
    { value = 3, label = _("Bold (3 px)") },
    { value = 4, label = _("Extra bold (4 px)") },
    { value = 5, label = _("Ultra bold (5 px)") },
    { value = 6, label = _("Heavy (6 px)") },
    { value = 8, label = _("Black (8 px)") },
}

local INSET_OPTIONS = {
    { value = 14, label = _("Very close (14 px)") },
    { value = 20, label = _("Close (20 px)") },
    { value = 28, label = _("Normal (28 px)") },
    { value = 38, label = _("Wide (38 px)") },
    { value = 50, label = _("Very wide (50 px)") },
}

local COLORS = {
    { label = _("Red"),     hex = "#D84343" },
    { label = _("Coral"),   hex = "#E8673C" },
    { label = _("Orange"),  hex = "#E8871E" },
    { label = _("Amber"),   hex = "#EBA70F" },
    { label = _("Gold"),    hex = "#CDAA2B" },
    { label = _("Lime"),    hex = "#8FB83A" },
    { label = _("Green"),   hex = "#4FA24A" },
    { label = _("Mint"),    hex = "#3DB38C" },
    { label = _("Teal"),    hex = "#2FA39E" },
    { label = _("Cyan"),    hex = "#2BB5C9" },
    { label = _("Sky"),     hex = "#4A9FE0" },
    { label = _("Blue"),    hex = "#3F7FDB" },
    { label = _("Navy"),    hex = "#4A62B3" },
    { label = _("Indigo"),  hex = "#6366CC" },
    { label = _("Violet"),  hex = "#8A63D2" },
    { label = _("Purple"),  hex = "#A55CC0" },
    { label = _("Magenta"), hex = "#C9459F" },
    { label = _("Pink"),    hex = "#E0679F" },
    { label = _("Rose"),    hex = "#DE5A6A" },
    { label = _("Brown"),   hex = "#9A6A47" },
    { label = _("Tan"),     hex = "#B8935F" },
    { label = _("Olive"),   hex = "#9A9A3A" },
    { label = _("Slate"),   hex = "#6F8799" },
    { label = _("Gray"),    hex = "#8A8A8A" },
}

---------------------------------------------------------------------------
-- Drawing primitives (every design is built from filled rectangles)
---------------------------------------------------------------------------

local function round(value)
    return math.floor(value + 0.5)
end

local function rect(bb, x, y, w, h)
    x = math.floor(x)
    y = math.floor(y)
    w = math.floor(w)
    h = math.floor(h)
    if w > 0 and h > 0 then
        bb:paintRect(x, y, w, h)
    end
end

local function hline(bb, x, y, length, thickness)
    rect(bb, x, y, length, thickness)
end

local function vline(bb, x, y, length, thickness)
    rect(bb, x, y, thickness, length)
end

local function outline(bb, x, y, w, h, thickness)
    if w <= 0 or h <= 0 then return end
    hline(bb, x, y, w, thickness)
    hline(bb, x, y + h - thickness, w, thickness)
    vline(bb, x, y, h, thickness)
    vline(bb, x + w - thickness, y, h, thickness)
end

local function inner_outline(bb, left, top, w, h, gap)
    if w > gap * 2 + 40 and h > gap * 2 + 40 then
        outline(bb, left + gap, top + gap, w - gap * 2, h - gap * 2, 1)
    end
end

local function dot(bb, cx, cy, size)
    local half = math.floor(size / 2)
    rect(bb, cx - half, cy - half, size, size)
end

local function bulb(bb, cx, cy, size)
    if size < 3 then
        dot(bb, cx, cy, size)
        return
    end
    local half = math.floor(size / 2)
    rect(bb, cx - half, cy - half + 1, size, size - 2)
    rect(bb, cx - half + 1, cy - half, size - 2, size)
end

-- Walks the rectangle clockwise from the top-left corner. Every side is split
-- into an even number of equal segments, so patterns land exactly on the four
-- corners and alternating patterns stay in phase around the frame.
-- callback(x1, y1, x2, y2, inward_x, inward_y, index, is_corner)
local function each_perimeter_segment(left, top, right, bottom, step, callback)
    local function split(length)
        local count = math.max(2, 2 * round(length / step / 2))
        return count, length / count
    end

    local nx, sx = split(right - left)
    local ny, sy = split(bottom - top)
    local index = 0

    for i = 0, nx - 1 do
        callback(left + i * sx, top, left + (i + 1) * sx, top, 0, 1, index, i == 0)
        index = index + 1
    end
    for i = 0, ny - 1 do
        callback(right, top + i * sy, right, top + (i + 1) * sy, -1, 0, index, i == 0)
        index = index + 1
    end
    for i = 0, nx - 1 do
        callback(right - i * sx, bottom, right - (i + 1) * sx, bottom, 0, -1, index, i == 0)
        index = index + 1
    end
    for i = 0, ny - 1 do
        callback(left, bottom - i * sy, left, bottom - (i + 1) * sy, 1, 0, index, i == 0)
        index = index + 1
    end
end

-- Rectangle in band-local coordinates: u runs along the side, v runs from the
-- outer edge towards the page center. (ax, ay) and (bx, by) map u and v to the
-- screen.
local function band_rect(bb, ox, oy, ax, ay, bx, by, u, v, du, dv)
    local x1 = ox + ax * u + bx * v
    local y1 = oy + ay * u + by * v
    local x2 = ox + ax * (u + du) + bx * (v + dv)
    local y2 = oy + ay * (u + du) + by * (v + dv)
    rect(bb, math.min(x1, x2), math.min(y1, y2), math.abs(x2 - x1), math.abs(y2 - y1))
end

-- Calls callback(ox, oy, ax, ay, bx, by, length) once per side, with the four
-- corner squares (band x band) excluded from `length`. Every side is the same
-- band rotated, so patterns flow around the page without breaking.
local function each_side(left, top, right, bottom, band, callback)
    local w = right - left
    local h = bottom - top
    callback(left + band, top, 1, 0, 0, 1, w - band * 2)
    callback(right, top + band, 0, 1, -1, 0, h - band * 2)
    callback(right - band, bottom, -1, 0, 0, -1, w - band * 2)
    callback(left, bottom - band, 0, -1, 1, 0, h - band * 2)
end

local function each_corner(left, top, right, bottom, band, callback)
    callback(left, top)
    callback(right - band, top)
    callback(left, bottom - band)
    callback(right - band, bottom - band)
end

local function corner_dot(bb, x, y, band, s)
    outline(bb, x, y, band, band, s)
    rect(bb, x + 2 * s, y + 2 * s, s, s)
end

local function corner_cross(bb, x, y, band, s)
    outline(bb, x, y, band, band, s)
    local cx = x + math.floor(band / 2)
    local cy = y + math.floor(band / 2)
    rect(bb, cx - math.floor(s / 2), y + s, s, band - 2 * s)
    rect(bb, x + s, cy - math.floor(s / 2), band - 2 * s, s)
end

---------------------------------------------------------------------------
-- Styles
---------------------------------------------------------------------------

-- One meander side: a rail plus hooks (5 cells wide and tall, cell = s px) spread
-- evenly, with a closing post so both ends of every side look identical.
local function key_side(bb, ox, oy, ax, ay, bx, by, length, s)
    band_rect(bb, ox, oy, ax, ay, bx, by, 0, 0, length, s)

    local span = length - 3 * s
    local units = math.floor(span / (6 * s))
    if units < 1 then return end
    local period = span / units

    for k = 0, units - 1 do
        local u = s + round(k * period)
        band_rect(bb, ox, oy, ax, ay, bx, by, u, 0, s, 5 * s)
        band_rect(bb, ox, oy, ax, ay, bx, by, u, 4 * s, 5 * s, s)
        band_rect(bb, ox, oy, ax, ay, bx, by, u + 4 * s, 2 * s, s, 3 * s)
        band_rect(bb, ox, oy, ax, ay, bx, by, u + 2 * s, 2 * s, 3 * s, s)
        band_rect(bb, ox, oy, ax, ay, bx, by, u + 2 * s, 0, s, 3 * s)
    end
    band_rect(bb, ox, oy, ax, ay, bx, by, length - 2 * s, 0, s, 5 * s)
end

local function draw_greek(bb, left, top, right, bottom, thickness)
    local w = right - left
    local h = bottom - top
    local s = math.max(2, thickness + 1)
    local band = s * 5
    if w < band * 4 or h < band * 4 then return end

    each_corner(left, top, right, bottom, band, function(x, y)
        corner_dot(bb, x, y, band, s)
    end)
    each_side(left, top, right, bottom, band, function(ox, oy, ax, ay, bx, by, length)
        key_side(bb, ox, oy, ax, ay, bx, by, length, s)
    end)
    inner_outline(bb, left, top, w, h, band + 3)
end

local function draw_checker(bb, left, top, right, bottom, thickness)
    local c = math.max(4, thickness * 2 + 2)
    local rows = 2
    local w = right - left
    local h = bottom - top
    local nx = math.floor(w / c)
    local ny = math.floor(h / c)
    if nx < rows * 2 + 4 or ny < rows * 2 + 4 then return end

    local ox = left + math.floor((w - nx * c) / 2)
    local oy = top + math.floor((h - ny * c) / 2)

    local function cell(i, j)
        if (i + j) % 2 == 0 then
            rect(bb, ox + i * c, oy + j * c, c, c)
        end
    end

    for i = 0, nx - 1 do
        for j = 0, rows - 1 do
            cell(i, j)
            cell(i, ny - 1 - j)
        end
    end
    for j = rows, ny - 1 - rows do
        for i = 0, rows - 1 do
            cell(i, j)
            cell(nx - 1 - i, j)
        end
    end

    outline(bb, ox - 3, oy - 3, nx * c + 6, ny * c + 6, 1)
    outline(bb, ox + rows * c + 3, oy + rows * c + 3,
        (nx - rows * 2) * c - 6, (ny - rows * 2) * c - 6, 1)
end

local function draw_marquee(bb, left, top, right, bottom, thickness)
    local big = math.max(5, thickness * 2 + 3)
    local small = math.max(2, thickness)
    local half = math.floor(big / 2)

    each_perimeter_segment(left + half, top + half, right - half - 1, bottom - half - 1,
        big + 5, function(x1, y1, _x2, _y2, _nx, _ny, index)
            if index % 2 == 0 then
                bulb(bb, round(x1), round(y1), big)
            else
                dot(bb, round(x1), round(y1), small)
            end
        end)

    inner_outline(bb, left, top, right - left, bottom - top, big + 4)
end

-- Hollow link with softened corners (the corner pixel is left out).
local function link_ring(bb, cx, cy, w, h, t)
    local x = cx - math.floor(w / 2)
    local y = cy - math.floor(h / 2)
    hline(bb, x + 1, y, w - 2, t)
    hline(bb, x + 1, y + h - t, w - 2, t)
    vline(bb, x, y + 1, h - 2, t)
    vline(bb, x + w - t, y + 1, h - 2, t)
end

local function draw_chain(bb, left, top, right, bottom, thickness)
    local ring_t = math.max(1, math.floor((thickness + 1) / 2))
    local bar_len = 6 + 2 * ring_t
    local step = math.min(7 + thickness * 2, 3 + bar_len)
    local ring_w = step * 2 - 4
    local ring_h = step + 1
    local bar_h = ring_t + 2
    local corner = ring_h + 2
    local m = math.floor(corner / 2) + 1

    each_perimeter_segment(left + m, top + m, right - m - 1, bottom - m - 1, step,
        function(x1, y1, _x2, y2, _nx, _ny, index, is_corner)
            local cx, cy = round(x1), round(y1)
            local horizontal = (y1 == y2)
            if is_corner then
                link_ring(bb, cx, cy, corner, corner, ring_t)
            elseif index % 2 == 0 then
                if horizontal then
                    link_ring(bb, cx, cy, ring_w, ring_h, ring_t)
                else
                    link_ring(bb, cx, cy, ring_h, ring_w, ring_t)
                end
            elseif horizontal then
                rect(bb, cx - bar_len / 2, cy - math.floor(bar_h / 2), bar_len, bar_h)
            else
                rect(bb, cx - math.floor(bar_h / 2), cy - bar_len / 2, bar_h, bar_len)
            end
        end)
end

local function draw_halftone(bb, left, top, right, bottom, thickness)
    local pitch = 10 + thickness
    local base = thickness + 3
    local sizes = { base, math.max(1, base - 2), math.max(1, base - 4) }
    local w = right - left
    local h = bottom - top

    for ring = 1, #sizes do
        local inset = (ring - 1) * pitch + math.floor(sizes[1] / 2)
        if w - inset * 2 < 40 or h - inset * 2 < 40 then break end
        local size = sizes[ring]
        each_perimeter_segment(left + inset, top + inset, right - inset - 1, bottom - inset - 1,
            pitch, function(x1, y1)
                bulb(bb, round(x1), round(y1), size)
            end)
    end
end

local function draw_battlements(bb, left, top, right, bottom, thickness)
    local t = thickness
    local m = thickness + 5
    local tower = m * 3
    local w = right - left
    local h = bottom - top
    if w < tower * 4 or h < tower * 4 then return end

    outline(bb, left, top, w, h, t)

    each_corner(left, top, right, bottom, tower, function(x, y)
        outline(bb, x, y, tower, tower, t)
        rect(bb, x + math.floor(tower / 2) - 1, y + math.floor(tower / 4), 2, math.floor(tower / 2))
    end)

    -- Merlons grow inwards from the wall, skipping the corner towers.
    local keep = tower + math.floor(m / 2)
    local half = math.floor(m / 2)
    each_perimeter_segment(left + t, top + t, right - t, bottom - t, m * 2,
        function(x1, y1, _x2, _y2, nx, ny, index, is_corner)
            if is_corner or index % 2 ~= 0 then return end
            local cx, cy = round(x1), round(y1)
            if ny ~= 0 then
                if cx - left < keep or right - cx < keep then return end
                rect(bb, cx - half, math.min(cy, cy + ny * m), m, m)
            else
                if cy - top < keep or bottom - cy < keep then return end
                rect(bb, math.min(cx, cx + nx * m), cy - half, m, m)
            end
        end)

    local g = t + m + 3
    hline(bb, left + tower, top + g, w - tower * 2, 1)
    hline(bb, left + tower, bottom - g - 1, w - tower * 2, 1)
    vline(bb, left + g, top + tower, h - tower * 2, 1)
    vline(bb, right - g - 1, top + tower, h - tower * 2, 1)
end

local function draw_aztec(bb, left, top, right, bottom, thickness)
    local w = right - left
    local h = bottom - top
    local s = math.max(2, thickness + 1)
    local band = s * 5
    if w < band * 4 or h < band * 4 then return end

    each_corner(left, top, right, bottom, band, function(x, y)
        corner_dot(bb, x, y, band, s)
    end)

    each_side(left, top, right, bottom, band, function(ox, oy, ax, ay, bx, by, length)
        band_rect(bb, ox, oy, ax, ay, bx, by, 0, 0, length, s)

        -- n + 1 pyramids with a square in every notch, including the two notches
        -- next to the corner blocks. The leftover length is spread evenly.
        local n = math.floor((length - 14 * s) / (10 * s))
        if n < 1 then return end
        local period = (length - 14 * s) / n

        for k = 0, n do
            local u = 2 * s + round(k * period)
            for row = 0, 3 do
                band_rect(bb, ox, oy, ax, ay, bx, by,
                    u + (1 + row) * s, (1 + row) * s, (8 - 2 * row) * s, s)
            end
        end
        for j = 0, n + 1 do
            local center = 2 * s + (j - 0.5) * period + 5 * s
            band_rect(bb, ox, oy, ax, ay, bx, by, round(center - s), 3 * s, 2 * s, 2 * s)
        end
    end)

    inner_outline(bb, left, top, w, h, band + 3)
end

local function draw_film(bb, left, top, right, bottom, thickness)
    local w = right - left
    local h = bottom - top
    local r = thickness + 1
    local band = r * 4
    if w < band * 4 or h < band * 4 then return end

    each_corner(left, top, right, bottom, band, function(x, y)
        outline(bb, x, y, band, band, r)
    end)

    each_side(left, top, right, bottom, band, function(ox, oy, ax, ay, bx, by, length)
        band_rect(bb, ox, oy, ax, ay, bx, by, 0, 0, length, r)
        band_rect(bb, ox, oy, ax, ay, bx, by, 0, 3 * r, length, r)

        local holes = math.floor((length - r) / (3 * r))
        if holes < 1 then
            band_rect(bb, ox, oy, ax, ay, bx, by, 0, r, length, 2 * r)
            return
        end
        local used = holes * 3 * r + r
        local start = math.floor((length - used) / 2)
        band_rect(bb, ox, oy, ax, ay, bx, by, 0, r, start, 2 * r)
        band_rect(bb, ox, oy, ax, ay, bx, by, start + used, r, length - start - used, 2 * r)
        for k = 0, holes do
            band_rect(bb, ox, oy, ax, ay, bx, by, start + k * 3 * r, r, r, 2 * r)
        end
    end)

    inner_outline(bb, left, top, w, h, band + 3)
end

local function draw_circuit(bb, left, top, right, bottom, thickness)
    local w = right - left
    local h = bottom - top
    local lw = math.max(1, round(thickness / 2))
    local sc = math.ceil(lw / 2)
    local band = 22 * sc
    if w < band * 4 or h < band * 4 then return end

    each_corner(left, top, right, bottom, band, function(x, y)
        outline(bb, x, y, band, band, thickness)
        rect(bb, x + 7 * sc, y + 7 * sc, 8 * sc, 8 * sc)
    end)

    each_side(left, top, right, bottom, band, function(ox, oy, ax, ay, bx, by, length)
        local function br(u, v, du, dv)
            band_rect(bb, ox, oy, ax, ay, bx, by, u, v, du, dv)
        end
        br(0, 0, length, thickness)

        local period = 36 * sc
        local units = math.floor(length / period)
        if units < 1 then return end
        local start = math.floor((length - units * period) / 2)

        for k = 0, units - 1 do
            local u = start + k * period
            -- A: short branch ending in a hollow square pad.
            br(u + 4 * sc, 0, lw, 9 * sc)
            br(u + 1 * sc, 9 * sc, 7 * sc, lw)
            br(u + 1 * sc, 16 * sc - lw, 7 * sc, lw)
            br(u + 1 * sc, 9 * sc, lw, 7 * sc)
            br(u + 8 * sc - lw, 9 * sc, lw, 7 * sc)
            -- B: branch with a right-angle jog ending in a solid pad.
            br(u + 15 * sc, 0, lw, 6 * sc + lw)
            br(u + 15 * sc, 6 * sc, 9 * sc + lw, lw)
            br(u + 24 * sc, 6 * sc, lw, 8 * sc)
            br(u + 22 * sc, 14 * sc, 5 * sc, 5 * sc)
            -- C: stub ending in a via.
            br(u + 31 * sc, 0, lw, 6 * sc)
            br(u + 30 * sc, 6 * sc, 3 * sc, 3 * sc)
        end
    end)

    inner_outline(bb, left, top, w, h, band + 2)
end

local function draw_brick(bb, left, top, right, bottom, thickness)
    local w = right - left
    local h = bottom - top
    local lw = math.max(1, round(thickness * 0.6))
    local rh = 5 + lw * 2
    local band = rh * 3 + lw
    local brick = rh * 2 + 4
    if w < band * 4 or h < band * 4 then return end

    local inset = thickness + 3
    each_corner(left, top, right, bottom, band, function(x, y)
        outline(bb, x, y, band, band, thickness)
        outline(bb, x + inset, y + inset, band - inset * 2, band - inset * 2, lw)
    end)

    each_side(left, top, right, bottom, band, function(ox, oy, ax, ay, bx, by, length)
        local function br(u, v, du, dv)
            band_rect(bb, ox, oy, ax, ay, bx, by, u, v, du, dv)
        end
        br(0, 0, length, thickness)
        br(0, rh, length, lw)
        br(0, rh * 2, length, lw)
        br(0, rh * 3, length, lw)

        local base = math.floor((length % brick) / 2)
        for course = 0, 2 do
            local u = base + ((course % 2 == 1) and math.floor(brick / 2) or 0)
            while u + lw <= length do
                if u > 0 then
                    br(u, course * rh, lw, rh + lw)
                end
                u = u + brick
            end
        end
    end)
end

local function draw_chevron(bb, left, top, right, bottom, thickness)
    local s = math.max(2, thickness + 1)
    local band = s * 7
    local w = right - left
    local h = bottom - top
    if w < band * 4 or h < band * 4 then return end

    each_corner(left, top, right, bottom, band, function(x, y)
        outline(bb, x, y, band, band, s)
        local cx = x + math.floor(band / 2)
        local cy = y + math.floor(band / 2)
        local arm = s * 2
        for i = 0, arm - 1 do
            rect(bb, cx - i - math.floor(s / 2), cy - arm + i, s, s)
            rect(bb, cx + i - math.floor(s / 2), cy - arm + i, s, s)
        end
    end)

    each_side(left, top, right, bottom, band, function(ox, oy, ax, ay, bx, by, length)
        local function br(u, v, du, dv)
            band_rect(bb, ox, oy, ax, ay, bx, by, u, v, du, dv)
        end
        br(0, 0, length, s)
        br(0, 6 * s, length, s)

        local n_periods = math.floor((length - 2 * s) / (6 * s))
        if n_periods < 1 then
            br(0, 3 * s, length, s)
            return
        end

        -- 6 cells per period plus 1 extra cell: the pattern starts and ends in
        -- the same "valley" (height 4), so both ends of every side look identical.
        local n_sub = n_periods * 6 + 1
        local span = length - 2 * s
        local heights = { 4, 3, 2, 1, 2, 3 }

        -- Cell edges are whole pixels computed from the exact fraction: u2 of cell
        -- k is the same expression as u1 of cell k + 1, so cells always touch with
        -- no gaps or overlaps at any screen size.
        for k = 0, n_sub - 1 do
            local u1 = round(s + k * span / n_sub)
            local u2 = round(s + (k + 1) * span / n_sub)
            if u2 > u1 then
                br(u1, heights[(k % 6) + 1] * s, u2 - u1, 2 * s)
            end
        end
    end)
end

local function draw_ogham(bb, left, top, right, bottom, thickness)
    local s = math.max(2, thickness + 1)
    local band = s * 5
    local w = right - left
    local h = bottom - top
    if w < band * 4 or h < band * 4 then return end

    each_corner(left, top, right, bottom, band, function(x, y)
        corner_cross(bb, x, y, band, s)
    end)

    local notch_heights = { 1, 2, 3, 2, 1, 2, 3, 1 }

    each_side(left, top, right, bottom, band, function(ox, oy, ax, ay, bx, by, length)
        local function br(u, v, du, dv)
            band_rect(bb, ox, oy, ax, ay, bx, by, u, v, du, dv)
        end
        br(0, 0, length, s)
        br(0, 4 * s, length, s)

        -- Minimum gap of 2s between notches and at both ends, then a single
        -- margin is recomputed so ALL gaps are identical:
        --   [margin][notch][margin][notch] ... [notch][margin]
        local min_gap = 2 * s
        local count = math.floor((length - min_gap) / (s + min_gap))
        if count < 1 then return end
        local margin = (length - count * s) / (count + 1)

        for k = 0, count - 1 do
            local u = margin + k * (s + margin)
            br(u, s, s, notch_heights[(k % #notch_heights) + 1] * s)
        end
    end)
end

local function draw_plus(bb, left, top, right, bottom, thickness)
    local s = math.max(2, thickness + 1)
    local band = s * 5
    local w = right - left
    local h = bottom - top
    if w < band * 4 or h < band * 4 then return end

    each_corner(left, top, right, bottom, band, function(x, y)
        corner_cross(bb, x, y, band, s)
    end)

    each_side(left, top, right, bottom, band, function(ox, oy, ax, ay, bx, by, length)
        local function br(u, v, du, dv)
            band_rect(bb, ox, oy, ax, ay, bx, by, u, v, du, dv)
        end
        br(0, 0, length, s)
        br(0, 4 * s, length, s)

        local cross_w = 3 * s
        local min_gap = 2 * s
        local count = math.floor((length - min_gap) / (cross_w + min_gap))
        if count < 1 then return end
        local margin = (length - count * cross_w) / (count + 1)

        for k = 0, count - 1 do
            local u = margin + k * (cross_w + margin)
            br(u, 2 * s, 3 * s, s)
            br(u + s, s, s, 3 * s)
        end
    end)
end

local DRAW_STYLE = {
    greek = draw_greek,
    aztec = draw_aztec,
    film = draw_film,
    circuit = draw_circuit,
    brick = draw_brick,
    checker = draw_checker,
    marquee = draw_marquee,
    chain = draw_chain,
    halftone = draw_halftone,
    battlements = draw_battlements,
    chevron = draw_chevron,
    ogham = draw_ogham,
    plus = draw_plus,
}

---------------------------------------------------------------------------
-- Geometry cache: the frame is stored as a short list of merged rectangles
---------------------------------------------------------------------------

local function compress_rows(rows)
    local row_numbers = {}
    for y in pairs(rows) do
        row_numbers[#row_numbers + 1] = y
    end
    table.sort(row_numbers)

    local commands = {}
    local active = {}
    local previous_y = nil

    for _idx, y in ipairs(row_numbers) do
        if previous_y and y ~= previous_y + 1 then
            active = {}
        end

        local spans = rows[y]
        table.sort(spans, function(a, b) return a[1] < b[1] end)

        local merged = {}
        for _i, span in ipairs(spans) do
            local last = merged[#merged]
            if last and span[1] <= last[2] + 1 then
                if span[2] > last[2] then last[2] = span[2] end
            else
                merged[#merged + 1] = { span[1], span[2] }
            end
        end

        local next_active = {}
        for _i, span in ipairs(merged) do
            local key = span[1] * 65536 + span[2]
            local command = active[key]
            if command then
                command[4] = command[4] + 1
            else
                command = { span[1], y, span[2] - span[1] + 1, 1 }
                commands[#commands + 1] = command
            end
            next_active[key] = command
        end
        active = next_active
        previous_y = y
    end

    return commands
end

local function build_geometry(sw, sh, style, thickness, inset)
    local rows = {}
    local count = 0
    local canvas = {}

    function canvas:paintRect(x, y, w, h)
        if count >= MAX_DRAW_COMMANDS then return end
        count = count + 1
        for row_y = y, y + h - 1 do
            local row = rows[row_y]
            if not row then
                row = {}
                rows[row_y] = row
            end
            row[#row + 1] = { x, x + w - 1 }
        end
    end

    local draw = DRAW_STYLE[style] or draw_greek
    draw(canvas, inset, inset, sw - inset, sh - inset, thickness)
    return compress_rows(rows)
end

local cfg = {}
local MAX_CACHED_SIZES = 3

local geometry_by_size = {}
local geometry_count = 0
local cached_style, cached_thickness, cached_inset = nil, nil, nil

-- Returns the merged rectangles for this screen size, or false when the screen
-- is too small for a frame. Geometry is kept per size, so rotating back to a
-- size used before costs nothing.
local function get_geometry(sw, sh)
    local style, thickness, requested = cfg.style, cfg.thickness, cfg.inset
    if style ~= cached_style or thickness ~= cached_thickness or requested ~= cached_inset then
        cached_style, cached_thickness, cached_inset = style, thickness, requested
        geometry_by_size, geometry_count = {}, 0
    end

    local key = sw * 65536 + sh
    local rects = geometry_by_size[key]
    if rects == nil then
        if geometry_count >= MAX_CACHED_SIZES then
            geometry_by_size, geometry_count = {}, 0
        end
        local inset = math.max(6, math.min(requested, math.floor(math.min(sw, sh) * 0.20)))
        if sw - inset * 2 >= 60 and sh - inset * 2 >= 60 then
            rects = build_geometry(sw, sh, style, thickness, inset)
        else
            rects = false
        end
        geometry_by_size[key] = rects
        geometry_count = geometry_count + 1
    end
    return rects
end

local function parse_hex(value)
    if type(value) ~= "string" then return nil end
    local hex = value:match("^#(%x%x%x%x%x%x)$")
    if not hex then return nil end
    return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

local function clamp(value, fallback, min_value, max_value)
    value = tonumber(value) or fallback
    return math.max(min_value, math.min(max_value, math.floor(value + 0.5)))
end

local settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/marginstyles.lua")

do
    local enabled = settings:readSetting("enabled")
    if enabled == nil then enabled = DEFAULTS.enabled end
    cfg.enabled = enabled and true or false

    local style = settings:readSetting("style")
    cfg.style = VALID_STYLES[style] and style or DEFAULTS.style

    cfg.thickness = clamp(settings:readSetting("thickness"), DEFAULTS.thickness, 1, 8)
    cfg.inset = clamp(settings:readSetting("inset"), DEFAULTS.inset, 14, 50)

    local color = settings:readSetting("color")
    cfg.color = parse_hex(color) and color or DEFAULTS.color
end

-- nil means plain black (the original gray path). Otherwise the chosen color.
-- It is painted as is in night mode too, so the frame looks exactly like the
-- swatch shown in the color dialog (same as the paper dots tint).
local frame_rgb = nil

local function rebuild_color()
    frame_rgb = nil
    if not HAS_COLOR or cfg.color == DEFAULTS.color then return end
    local r, g, b = parse_hex(cfg.color)
    if r then
        frame_rgb = Blitbuffer.ColorRGB32(r, g, b, 0xFF)
    end
end
rebuild_color()

local attached_view = nil

local function refresh()
    local view = attached_view
    if view and view.dialog then
        UIManager:setDirty(view.dialog, "partial")
    end
end

local function set_value(key, value)
    cfg[key] = value
    settings:saveSetting(key, value)
    settings:flush()
    if key == "color" then rebuild_color() end
    refresh()
end

local function reset_defaults()
    for key, value in pairs(DEFAULTS) do
        cfg[key] = value
        settings:saveSetting(key, value)
    end
    settings:flush()
    rebuild_color()
    refresh()
end

-- Registered as a ReaderView module: it is painted with the page, before
-- menus and dialogs, so it can never cover them.
local layer = {}

function layer:paintTo(bb, x, y)
    if not cfg.enabled then return end

    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    if not sw or not sh or sw < 100 or sh < 100 then return end

    local rects = get_geometry(sw, sh)
    if not rects then return end

        if frame_rgb then
        for i = 1, #rects do
            local r = rects[i]
            bb:paintRectRGB32(x + r[1], y + r[2], r[3], r[4], frame_rgb)
        end
    else
        local black = Blitbuffer.COLOR_BLACK
        for i = 1, #rects do
            local r = rects[i]
            bb:paintRect(x + r[1], y + r[2], r[3], r[4], black)
        end
    end
end

local function choice_items(key, options)
    local items = {}
    for _idx, option in ipairs(options) do
        local value = option.value
        items[#items + 1] = {
            text = option.label,
            radio = true,
            checked_func = function() return cfg[key] == value end,
            callback = function() set_value(key, value) end,
        }
    end
    return items
end

local function color_label()
    if cfg.color == DEFAULTS.color then return _("Black") end
    for _idx, color in ipairs(COLORS) do
        if color.hex == cfg.color then return T(_("Custom: %1"), color.label) end
    end
    return _("Custom color")
end

local function show_color_dialog(touchmenu_instance)
    local buttons = {}
    local row = {}
    local dialog

    for index, color in ipairs(COLORS) do
        local entry = color
        local r, g, b = parse_hex(entry.hex)
        row[#row + 1] = {
            text = entry.label,
            background = Blitbuffer.ColorRGB32(r, g, b, 0xFF),
            callback = function()
                UIManager:close(dialog)
                set_value("color", entry.hex)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        }
        if #row == 4 or index == #COLORS then
            buttons[#buttons + 1] = row
            row = {}
        end
    end

    buttons[#buttons + 1] = {
        {
            text = _("Cancel"),
            callback = function() UIManager:close(dialog) end,
        },
    }

    dialog = ButtonDialog:new{
        title = _("Choose a frame color"),
        width_factor = 0.92,
        colorful = true,
        buttons = buttons,
    }
    UIManager:show(dialog)
end

local function color_item()
    return {
        text_func = function() return T(_("Color: %1"), color_label()) end,
        sub_item_table = {
            {
                text = _("Black"),
                radio = true,
                keep_menu_open = true,
                checked_func = function() return cfg.color == DEFAULTS.color end,
                callback = function(inst)
                    set_value("color", DEFAULTS.color)
                    if inst then inst:updateItems() end
                end,
            },
            {
                text_func = function()
                    if cfg.color ~= DEFAULTS.color then return color_label() end
                    return _("Choose custom color…")
                end,
                radio = true,
                keep_menu_open = true,
                checked_func = function() return cfg.color ~= DEFAULTS.color end,
                callback = function(inst) show_color_dialog(inst) end,
            },
        },
    }
end

local Margins = {}

function Margins.attach(view)
    if not view then return end
    attached_view = view
    view:registerViewModule("paperdots_margins", layer)
end

function Margins.release()
    attached_view = nil
end

function Margins.toggle()
    set_value("enabled", not cfg.enabled)
    return cfg.enabled
end

-- true only while a book is open and the frame is enabled
function Margins.isActive()
    return cfg.enabled and attached_view ~= nil
end

function Margins.menuItem()
    local items = {
        {
            text = _("Enable"),
            checked_func = function() return cfg.enabled end,
            callback = function() set_value("enabled", not cfg.enabled) end,
            separator = true,
        },
        { text = _("Style"), sub_item_table = choice_items("style", STYLES) },
        { text = _("Line thickness"), sub_item_table = choice_items("thickness", THICKNESS_OPTIONS) },
        { text = _("Distance from edge"), sub_item_table = choice_items("inset", INSET_OPTIONS) },
    }
    if HAS_COLOR then items[#items + 1] = color_item() end
    items[#items + 1] = { text = _("Reset defaults"), callback = reset_defaults }
    return { text = _("Margin styles"), sub_item_table = items }
end

return Margins