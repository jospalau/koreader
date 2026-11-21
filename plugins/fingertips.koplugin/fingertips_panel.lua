--[[
FingerTips: geometry and drawing of the lifted panel and the selection handles.

The panel is the page itself, shifted up by the lift and cut to a rounded
box: the selected part of one line plus a margin of context (a little of the
text around it). Inside, the selection keeps its shading and the context is
drawn lighter.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local ffi = require("ffi")
local logger = require("logger")

local Screen = Device.screen

local Panel = {}

-- Context around the selection, in line heights.
Panel.CONTEXT_SIDE = 1.0   -- about three letters left and right
Panel.CONTEXT_V = 0.5      -- half a line above and below
-- How dark the context stays: 1 = as on the page, 0 = invisible.
local CONTEXT_INK = 0.33

local ARC_STEPS = 8 -- segments per rounded corner

local function sign(v)
    if v > 0 then return 1 elseif v < 0 then return -1 end
    return 0
end

-- Outline of a polygon with rounded corners, as a flat {x1, y1, x2, y2...}
-- list. With inset > 0, the outline is pulled inward by that much: corners
-- keep their arc centres, so convex radii shrink and concave ones grow,
-- which keeps the band between the two outlines exactly `inset` wide.
local function roundedPath(corners, radii, inset)
    local n = #corners
    local pts = {}
    for i = 1, n do
        local c = corners[i]
        local p = corners[(i - 2) % n + 1]
        local q = corners[i % n + 1]
        local d1x, d1y = sign(c.x - p.x), sign(c.y - p.y) -- incoming direction
        local d2x, d2y = sign(q.x - c.x), sign(q.y - c.y) -- outgoing direction
        local convex = (d1x * d2y - d1y * d2x) > 0
        -- sum of the inward normals of both edges (a diagonal, inward)
        local nx, ny = -d1y - d2y, d1x + d2x
        local vx, vy = c.x + inset * nx, c.y + inset * ny
        local r = radii[i]
        if inset > 0 then
            r = convex and math.max(0, r - inset) or (r + inset)
        end
        if r <= 0 then
            pts[#pts + 1] = vx
            pts[#pts + 1] = vy
        else
            local s = convex and 1 or -1 -- convex centres inside, concave outside
            local cx, cy = vx + s * r * nx, vy + s * r * ny
            local a1 = math.atan2(vy - d1y * r - cy, vx - d1x * r - cx)
            local a2 = math.atan2(vy + d2y * r - cy, vx + d2x * r - cx)
            local da = a2 - a1
            if da > math.pi then da = da - 2 * math.pi
            elseif da < -math.pi then da = da + 2 * math.pi end
            for k = 0, ARC_STEPS do
                local a = a1 + da * k / ARC_STEPS
                pts[#pts + 1] = cx + r * math.cos(a)
                pts[#pts + 1] = cy + r * math.sin(a)
            end
        end
    end
    return pts
end

-- Sets mask bytes to `value` (default 1) for pixels whose centre is inside
-- the closed path (even-odd rule). The mask covers the screen area
-- (ox, oy, w, h).
local function fillPath(mask, w, h, ox, oy, pts, value)
    value = value or 1
    local n = #pts / 2
    local min_y, max_y = math.huge, -math.huge
    for i = 2, #pts, 2 do
        if pts[i] < min_y then min_y = pts[i] end
        if pts[i] > max_y then max_y = pts[i] end
    end
    local row0 = math.max(0, math.floor(min_y - oy))
    local row1 = math.min(h - 1, math.ceil(max_y - oy))
    local xs = {}
    for row = row0, row1 do
        local y = oy + row + 0.5
        local cnt = 0
        for i = 0, n - 1 do
            local j = (i + 1) % n
            local y1, y2 = pts[2 * i + 2], pts[2 * j + 2]
            if (y1 <= y and y2 > y) or (y2 <= y and y1 > y) then
                local x1, x2 = pts[2 * i + 1], pts[2 * j + 1]
                cnt = cnt + 1
                xs[cnt] = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
            end
        end
        for k = 2, cnt do -- insertion sort, cnt is small
            local v, m = xs[k], k - 1
            while m >= 1 and xs[m] > v do
                xs[m + 1] = xs[m]
                m = m - 1
            end
            xs[m + 1] = v
        end
        local base = row * w
        for k = 1, cnt - 1, 2 do
            local xa = math.max(0, math.ceil(xs[k] - ox - 0.5))
            local xb = math.min(w - 1, math.floor(xs[k + 1] - ox - 0.5))
            for x = xa, xb do
                mask[base + x] = value
            end
        end
    end
end

-- Box blur of a w x h byte mask, in place (outside the mask counts as 0).
-- Two passes give a soft, roughly Gaussian edge.
local function averageLineHeight(lines)
    local h = 0
    for i = 1, #lines do h = h + lines[i].h end
    return h / #lines
end
Panel.averageLineHeight = averageLineHeight

-- The two handles: a thin bar along the selection's edge plus a round knob,
-- above the start and below the end (as on phones).
function Panel.handleGeometry(lines)
    local first, last = lines[1], lines[#lines]
    local line_h = averageLineHeight(lines)
    local bar_w = math.max(2, Screen:scaleBySize(2))
    local r = math.max(3, math.floor(line_h * 0.2 + 0.5))
    local start = {
        x = first.x, top = first.y, bottom = first.y + first.h,
        knob_x = first.x, knob_y = first.y - r,
    }
    local stop = {
        x = last.x + last.w, top = last.y, bottom = last.y + last.h,
        knob_x = last.x + last.w, knob_y = last.y + last.h + r,
    }
    local function rect(hd)
        return Geom:new{
            x = hd.x - r - 1, y = math.min(hd.top, hd.knob_y - r) - 1,
            w = 2 * r + 2, h = math.max(hd.bottom, hd.knob_y + r) - math.min(hd.top, hd.knob_y - r) + 2,
        }
    end
    return {
        start = start, stop = stop, r = r, bar_w = bar_w,
        region = rect(start):combine(rect(stop)),
    }
end

-- Draws the handles into bb, with (dx, dy) added to their positions.
local function drawHandles(bb, hg, dx, dy)
    for _, hd in ipairs({ hg.start, hg.stop }) do
        local x = math.floor(hd.x + dx - hg.bar_w / 2 + 0.5)
        bb:paintRect(x, math.floor(hd.top + dy), hg.bar_w, math.floor(hd.bottom - hd.top), Blitbuffer.COLOR_BLACK)
        bb:paintCircle(math.floor(hd.knob_x + dx + 0.5), math.floor(hd.knob_y + dy + 0.5), hg.r, Blitbuffer.COLOR_BLACK)
    end
end

--[[
Works out what to draw. lines: screen boxes of the selected lines, top to
bottom. opts: lift (line heights), border and radius (screen-scaled units),
with_handles, and panel_line: the line box
the panel copies (no panel without one). All the selected lines stay dark in
the copy.
Returns nil when there is nothing to draw.
]]
function Panel.computeLayout(lines, opts)
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local layout = { parts = {} }
    local region

    if opts.with_handles then
        layout.handles = Panel.handleGeometry(lines)
        region = layout.handles.region
        local s, e = layout.handles.start, layout.handles.stop
        table.insert(layout.parts, string.format("h%d,%d,%d,%d,%d,%d", s.x, s.top, s.bottom, e.x, e.top, e.bottom))
    end

    if opts.panel_line then
        local panel = Panel.computePanel(opts.panel_line, opts, screen_w, screen_h, lines)
        if panel then
            layout.panel = panel
            region = region and region:combine(panel.region) or panel.region
            table.insert(layout.parts, panel.key)
        end
    end

    if not region then return nil end
    layout.region = region:intersect(Geom:new{ x = 0, y = 0, w = screen_w, h = screen_h })
    layout.key = table.concat(layout.parts, ";")
    return layout
end

-- line: the line box to copy; keep_lines: the selected lines (left dark).
function Panel.computePanel(line, opts, screen_w, screen_h, keep_lines)
    local border = math.max(1, Screen:scaleBySize(opts.border))
    local radius = Screen:scaleBySize(opts.radius)

    local line_h = line.h
    local lift = math.floor(line_h * opts.lift + 0.5)
    local ctx_side = math.floor(line_h * Panel.CONTEXT_SIDE + 0.5)
    local ctx_v = math.floor(line_h * Panel.CONTEXT_V + 0.5)

    -- Above the line; or, at the top of the screen where there's no room,
    -- below the whole selection with the same gap.
    local dy = -lift
    if line.y + dy - ctx_v - border < 0 then
        local last = keep_lines[#keep_lines]
        dy = (last.y + last.h - line.y) + (lift - line_h)
    end
    dy = math.floor(dy + 0.5)

    -- The line plus context on all four sides, plus the outline.
    local x0 = math.max(0, line.x - ctx_side - border)
    local x1 = math.min(screen_w, line.x + line.w + ctx_side + border)
    local y0 = math.max(0, line.y + dy - ctx_v - border)
    local y1 = math.min(screen_h, line.y + line.h + dy + ctx_v + border)
    local corners = { { x = x0, y = y0 }, { x = x1, y = y0 }, { x = x1, y = y1 }, { x = x0, y = y1 } }
    local r = math.min(radius, (x1 - x0) / 2, (y1 - y0) / 2)
    local radii = { r, r, r, r }
    local shapes = { {
        outer = roundedPath(corners, radii, 0),
        inner = roundedPath(corners, radii, border),
        corners = corners,
    } }
    local bx0, by0, bx1, by1 = x0, y0, x1, y1

    bx0, by0 = math.max(0, math.floor(bx0)), math.max(0, math.floor(by0))
    bx1, by1 = math.min(screen_w, math.ceil(bx1)), math.min(screen_h, math.ceil(by1))
    if bx1 <= bx0 or by1 <= by0 then return nil end

    local parts = { "p" .. dy }
    for i = 1, #shapes do
        for _, c in ipairs(shapes[i].corners) do
            parts[#parts + 1] = c.x .. "," .. c.y
        end
        parts[#parts + 1] = "|"
    end
    for i = 1, #keep_lines do
        local l = keep_lines[i]
        parts[#parts + 1] = string.format("%d,%d,%d,%d", l.x, l.y, l.w, l.h)
    end

    return {
        dy = dy,
        lines = keep_lines, -- the selected parts stay dark in the copy
        shapes = shapes,
        region = Geom:new{ x = bx0, y = by0, w = bx1 - bx0, h = by1 - by0 },
        key = table.concat(parts, ";"),
    }
end

-- Pixel layouts we edit directly: bytes per pixel, colour channels. Grey
-- e-ink Kobos draw in 8-bit grey, colour ones (and the desktop) in RGB32.
-- Anything else is handled in 8-bit grey.
local function pixelFormat(bbtype)
    if bbtype == Blitbuffer.TYPE_BB8 then return 1, 1 end
    if bbtype == Blitbuffer.TYPE_BBRGB32 then return 4, 3 end -- R, G, B, alpha
end

local function newBuffer(w, h, bbtype)
    local ok, bb = pcall(Blitbuffer.new, w, h, bbtype)
    if ok then return bb end
    logger.warn("FingerTips: could not allocate a", w, "x", h, "buffer")
end

local LIGHTEN = ffi.new("uint8_t[256]")
for v = 0, 255 do
    LIGHTEN[v] = 255 - math.floor((255 - v) * CONTEXT_INK + 0.5)
end

-- Draws the layout onto bb (the screen-sized page buffer at x, y), after the
-- page and its highlights are already there.
function Panel.paint(bb, x, y, layout)
    x, y = x or 0, y or 0
    local panel = layout.panel
    if not panel then
        if layout.handles then drawHandles(bb, layout.handles, x, y) end
        return
    end

    local t0 = os.clock()
    local reg = panel.region
    local w, h = reg.w, reg.h
    local bbtype = bb:getType()
    local bpp, nch = pixelFormat(bbtype)
    if not bpp then
        bbtype = Blitbuffer.TYPE_BB8
        bpp, nch = pixelFormat(bbtype)
    end
    local content = newBuffer(w, h, bbtype)
    local canvas = newBuffer(w, h, bbtype)
    if not (content and canvas) then
        if content then content:free() end
        if canvas then canvas:free() end
        if layout.handles then drawHandles(bb, layout.handles, x, y) end
        return
    end

    -- 1. The panel's contents: the page shifted by the lift, taken before
    --    anything else is drawn on top of it.
    content:fill(Blitbuffer.COLOR_WHITE)
    local sx0, sy0 = reg.x, reg.y - panel.dy -- where the contents come from
    local cx0, cy0 = math.max(0, sx0), math.max(0, sy0)
    local cx1 = math.min(bb:getWidth() - x, sx0 + w)
    local cy1 = math.min(bb:getHeight() - y, sy0 + h)
    if cx1 > cx0 and cy1 > cy0 then
        content:blitFrom(bb, cx0 - sx0, cy0 - sy0, x + cx0, y + cy0, cx1 - cx0, cy1 - cy0)
    end

    -- 2. Lighten the context: everything but the selected lines.
    local keep = ffi.new("uint8_t[?]", w * h)
    for _, l in ipairs(panel.lines) do
        local kx0 = math.max(0, math.floor(l.x - reg.x))
        local kx1 = math.min(w, math.ceil(l.x + l.w - reg.x))
        local ky0 = math.max(0, math.floor(l.y + panel.dy - reg.y))
        local ky1 = math.min(h, math.ceil(l.y + l.h + panel.dy - reg.y))
        for row = ky0, ky1 - 1 do
            local base = row * w
            for col = kx0, kx1 - 1 do keep[base + col] = 1 end
        end
    end
    do
        local px = ffi.cast("uint8_t*", content.data)
        local stride = tonumber(content.stride)
        for row = 0, h - 1 do
            local m, base = row * w, row * stride
            for col = 0, w - 1 do
                if keep[m + col] == 0 then
                    local o = base + col * bpp
                    for k = 0, nch - 1 do px[o + k] = LIGHTEN[px[o + k]] end
                end
            end
        end
    end

    -- 3. The handles, in the copy too.
    if layout.handles then
        drawHandles(content, layout.handles, -reg.x, panel.dy - reg.y)
    end

    -- 4. What's on the page where the panel goes (kept outside the outline),
    --    with the page's own handles on it.
    if layout.handles then drawHandles(bb, layout.handles, x, y) end
    canvas:blitFrom(bb, 0, 0, x + reg.x, y + reg.y, w, h)

    -- 5. Which pixels are outline and which are inside it.
    local outer = ffi.new("uint8_t[?]", w * h)
    local inner = ffi.new("uint8_t[?]", w * h)
    for _, shape in ipairs(panel.shapes) do
        fillPath(outer, w, h, reg.x, reg.y, shape.outer)
        fillPath(inner, w, h, reg.x, reg.y, shape.inner)
    end

    -- 6. Combine: inside -> contents, outline band -> black, else page.
    local cstride, tstride = tonumber(canvas.stride), tonumber(content.stride)
    if bpp == 4 then
        local cpx = ffi.cast("uint32_t*", canvas.data)
        local tpx = ffi.cast("uint32_t*", content.data)
        local black = 0xFF000000 -- opaque black: alpha 0xFF, RGB 0
        cstride, tstride = cstride / 4, tstride / 4
        for row = 0, h - 1 do
            local m, c, t = row * w, row * cstride, row * tstride
            for col = 0, w - 1 do
                if inner[m + col] == 1 then
                    cpx[c + col] = tpx[t + col]
                elseif outer[m + col] == 1 then
                    cpx[c + col] = black
                end
            end
        end
    else
        local cpx = ffi.cast("uint8_t*", canvas.data)
        local tpx = ffi.cast("uint8_t*", content.data)
        for row = 0, h - 1 do
            local m, c, t = row * w, row * cstride, row * tstride
            for col = 0, w - 1 do
                if inner[m + col] == 1 then
                    cpx[c + col] = tpx[t + col]
                elseif outer[m + col] == 1 then
                    cpx[c + col] = 0
                end
            end
        end
    end
    bb:blitFrom(canvas, x + reg.x, y + reg.y, 0, 0, w, h)
    content:free()
    canvas:free()
    logger.dbg(string.format("FingerTips: painted %d line(s) in %.1f ms", #panel.lines, (os.clock() - t0) * 1000))
end

return Panel
