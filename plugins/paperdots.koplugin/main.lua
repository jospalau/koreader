local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Notification = require("ui/widget/notification")
local LuaSettings = require("luasettings")
local SpinWidget = require("ui/widget/spinwidget")
local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local ffi = require("ffi")
local logger = require("logger")
local _ = require("gettext")
local ok_margins, Margins = pcall(require, "paperdots_margins")
if not ok_margins then
    logger.warn("paperdots: margins module unavailable:", Margins)
    Margins = nil
end

local Screen = Device.screen

-- The tint only makes sense on color screens; grayscale e-readers never use it.
local HAS_COLOR = true
if Screen.isColorScreen then HAS_COLOR = Screen:isColorScreen() and true or false end

local TILE = 256
local SEED = 12345
local WHITE_THRESHOLD = 0xF0
local WHITE_SCALED = WHITE_THRESHOLD * 16384
local PALETTE_SIZE = 16
local HALF = PALETTE_SIZE / 2
local LINEN_SEG = 8
local LINEN_PRESENCE = 65
local LAID_SEG = 12
local LAID_PRESENCE = 80
local HB_LEN = 8

local GLOBAL_DEFAULTS = {
    enabled = true,
    book_only = false,
    hide_on_menus = false,
    hide_on_night = false,
    fast_paint_disabled = false, -- fast painting is on by default where supported
    page_anim = false,
    page_anim_style = "wipe",
    page_anim_steps = 3,
    page_anim_skip_comics = false, -- no page animation in comics / manga archives
    tint = "neutral",
    custom_tint = "#C46A45",
    style = "random",
}

local STYLE_DEFAULTS = {
    random = { density = 3, dot_size = 1, dot_min = 0x60, dot_max = 0xA0 },
    newsprint = { density = 8, dot_size = 2, dot_min = 0x60, dot_max = 0xA0 },
    fibers = { density = 4, dot_size = 1, dot_min = 0x60, dot_max = 0xA0, fiber_length = 8 },
    linen = { density = 6, dot_size = 1, dot_min = 0x70, dot_max = 0xB0 },
    crosshatch = { density = 6, dot_size = 1, dot_min = 0x70, dot_max = 0xA0 },
    diagonal = { density = 6, dot_size = 1, dot_min = 0x70, dot_max = 0xA0, direction = "slash" },
    laid = { density = 3, dot_size = 1, dot_min = 0x80, dot_max = 0xC0 },
    dotgrid = { density = 3, dot_size = 2, dot_min = 0x60, dot_max = 0xA0 },
    herringbone = { density = 4, dot_size = 1, dot_min = 0x70, dot_max = 0xA0 },
}

local settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/paperdots.lua")

local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

local cfg = {}
for key, default in pairs(GLOBAL_DEFAULTS) do
    local value = settings:readSetting(key)
    if value == nil then value = default end
    cfg[key] = value
end
if not STYLE_DEFAULTS[cfg.style] then cfg.style = "random" end

local saved_styles = settings:readSetting("styles")
if type(saved_styles) ~= "table" then saved_styles = {} end
cfg.styles = {}
for name, defaults in pairs(STYLE_DEFAULTS) do
    local entry = copy(defaults)
    local saved = saved_styles[name]
    if type(saved) == "table" then
        for key, default_val in pairs(defaults) do
            local saved_val = saved[key]
            if type(default_val) == "number" and type(saved_val) == "number" then
                entry[key] = saved_val
            elseif type(default_val) == "string" and type(saved_val) == "string" then
                entry[key] = saved_val
            end
        end
    end
    cfg.styles[name] = entry
end

for _idx, key in ipairs({ "density", "dot_size", "dot_min", "dot_max", "fiber_length" }) do
    local legacy = settings:readSetting(key)
    if type(legacy) == "number" and saved_styles[cfg.style] == nil
        and cfg.styles[cfg.style][key] ~= nil then
        cfg.styles[cfg.style][key] = legacy
    end
    if legacy ~= nil then settings:delSetting(key) end
end

local function clampSavedInteger(value, fallback, min_value, max_value)
    if type(value) ~= "number" or value ~= value
        or value == math.huge or value == -math.huge then
        value = fallback
    end
    value = math.floor(value + 0.5)
    return math.max(min_value, math.min(max_value, value))
end

-- Keep persisted values inside the same limits exposed by the menu. This also
-- protects pattern builders from invalid values in an old/corrupt settings file.
for name, entry in pairs(cfg.styles) do
    local defaults = STYLE_DEFAULTS[name]
    entry.density = clampSavedInteger(entry.density, defaults.density, 1, 30)
    entry.dot_size = clampSavedInteger(entry.dot_size, defaults.dot_size, 1, 4)
    entry.dot_min = clampSavedInteger(entry.dot_min, defaults.dot_min, 0, 239)
    entry.dot_max = clampSavedInteger(entry.dot_max, defaults.dot_max, entry.dot_min, 239)
    if defaults.fiber_length then
        entry.fiber_length = clampSavedInteger(entry.fiber_length, defaults.fiber_length, 3, 20)
    end
    if defaults.direction and entry.direction ~= "slash" and entry.direction ~= "backslash" then
        entry.direction = defaults.direction
    end
end

local function S()
    return cfg.styles[cfg.style]
end

local function saveSettings()
    for key in pairs(GLOBAL_DEFAULTS) do
        settings:saveSetting(key, cfg[key])
    end
    settings:saveSetting("styles", cfg.styles)
    settings:flush()
end

local function round(v)
    return math.floor(v + 0.5)
end

local function makePalette()
    local s = S()
    local palette = {}
    for i = 1, PALETTE_SIZE do
        palette[i] = Blitbuffer.Color8(math.floor(s.dot_min + (s.dot_max - s.dot_min) * (i - 1) / (PALETTE_SIZE - 1)))
    end
    return palette
end

local function hash(r, c)
    local s = (r * 7919 + c * 104729 + 1) % 2147483647
    s = (s * 16807) % 2147483647
    s = (s * 16807) % 2147483647
    return s
end

local function lowerBound(ys, n, target)
    local lo, hi = 1, n + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if ys[mid] < target then lo = mid + 1 else hi = mid end
    end
    return lo
end

local tile, ordered, linen, crosshatch, diagonal, laid, dotgrid, herringbone

-- Builders (run only when a style or one of its settings changes)
local function buildTile()
    local s = S()
    local size = s.dot_size
    local n = math.max(1, math.floor(TILE * TILE * (s.density / 100) / (size * size)))
    local seed = SEED
    local function rand()
        seed = (seed * 16807) % 2147483647
        return seed / 2147483647
    end
    local pts = {}
    for i = 1, n do
        pts[i] = {
            x = math.floor(rand() * TILE),
            y = math.floor(rand() * TILE),
            c = Blitbuffer.Color8(math.floor(s.dot_min + rand() * (s.dot_max - s.dot_min))),
        }
    end
    table.sort(pts, function(a, b) return a.y < b.y end)
    local xs, ys, cs = {}, {}, {}
    for i = 1, n do
        xs[i], ys[i], cs[i] = pts[i].x, pts[i].y, pts[i].c
    end
    tile = { n = n, xs = xs, ys = ys, cs = cs }

    -- Secondary index sorted by x, used by the column-major iterator in
    -- rotated mode. Same dots, different traversal order.
    local x_order = {}
    for i = 1, n do x_order[i] = i end
    table.sort(x_order, function(a, b) return xs[a] < xs[b] end)
    local x_first = {}
    for i = 1, n do
        local xv = xs[x_order[i]]
        if not x_first[xv] then x_first[xv] = i end
    end
    tile.x_order = x_order
    tile.x_first = x_first
end

local function buildOrdered()
    local s = S()
    local size = s.dot_size
    local step = math.max(size, round(size * math.sqrt(50 / s.density)))
    ordered = { step = step, palette = makePalette() }
end

local function bresenham(ex, ey)
    local xs, ys = {}, {}
    local x, y = 0, 0
    local dx, dy = math.abs(ex), ey
    local sx = ex >= 0 and 1 or -1
    local err = dx - dy
    for _g = 1, 64 do
        xs[#xs + 1], ys[#ys + 1] = x, y
        if x == ex and y == ey then break end
        local e2 = 2 * err
        if e2 >= -dy then err = err - dy; x = x + sx end
        if e2 <= dx then err = err + dx; y = y + 1 end
    end
    return xs, ys
end

-- Bake the current tile (points already wrapped to TILE x TILE) into the
-- sorted arrays the Random painters expect.
local function bakeTile(pts)
    local n = #pts
    table.sort(pts, function(a, b) return a.y < b.y end)
    local xs, ys, cs = {}, {}, {}
    for i = 1, n do
        xs[i], ys[i], cs[i] = pts[i].x, pts[i].y, pts[i].c
    end
    local x_order = {}
    for i = 1, n do x_order[i] = i end
    table.sort(x_order, function(a, b) return xs[a] < xs[b] end)
    local x_first = {}
    for i = 1, n do
        local xv = xs[x_order[i]]
        if not x_first[xv] then x_first[xv] = i end
    end
    tile = { n = n, xs = xs, ys = ys, cs = cs, x_order = x_order, x_first = x_first }
end

-- Fibers are baked into one wrapped tile so they reuse the Random painters.
-- Wrapping is exact because the pattern repeats every TILE pixels: a fiber
-- crossing a tile edge reappears on the opposite side of the same tile.
local function buildFibers()
    local s = S()
    local size = s.dot_size
    local maxlen = s.fiber_length
    local minlen = math.max(2, math.floor(maxlen / 2))
    local avg = (minlen + maxlen) / 2
    local count = math.max(1, math.floor(TILE * TILE * (s.density / 100) / (avg * size)))
    local seed = SEED
    local function rand()
        seed = (seed * 16807) % 2147483647
        return seed / 2147483647
    end
    local seen, pts = {}, {}
    for _i = 1, count do
        local fx = math.floor(rand() * TILE)
        local fy = math.floor(rand() * TILE)
        local len = minlen + math.floor(rand() * (maxlen - minlen + 1))
        local ang = rand() * math.pi
        local ex = round(math.cos(ang) * (len - 1))
        local ey = round(math.sin(ang) * (len - 1))
        local gray = math.floor(s.dot_min + rand() * (s.dot_max - s.dot_min))
        local color = Blitbuffer.Color8(gray)
        local pxs, pys = bresenham(ex, ey)
        for k = 1, #pxs do
            local x = (fx + pxs[k]) % TILE
            local y = (fy + pys[k]) % TILE
            local key = y * TILE + x
            if not seen[key] then
                seen[key] = true
                pts[#pts + 1] = { x = x, y = y, c = color }
            end
        end
    end
    bakeTile(pts)
end

local function buildLinen()
    local s = S()
    local size = s.dot_size
    local spacing = math.max(size * 2, round(130 * size / s.density))
    linen = { spacing = spacing, palette = makePalette() }
end

local function buildCrosshatch()
    local s = S()
    local size = s.dot_size
    local step = math.max(size * 2, round(130 * size / s.density))
    crosshatch = { step = step, size = size, palette = makePalette() }
end

local function buildDiagonal()
    local s = S()
    local size = s.dot_size
    local step = math.max(size * 2, round(130 * size / s.density))
    diagonal = { step = step, size = size, palette = makePalette(), direction = s.direction }
end

local function buildLaid()
    local s = S()
    local size = s.dot_size
    local sp = math.max(size * 2, round(60 * size / s.density))
    laid = { sp = sp, chain = sp * 12, size = size, palette = makePalette() }
end

local function buildDotGrid()
    local s = S()
    local size = s.dot_size
    local sp = math.max(size + 2, round(size * math.sqrt(100 / s.density)))
    dotgrid = { sp = sp, size = size, palette = makePalette() }
end

local function buildHerringbone()
    local s = S()
    local size = s.dot_size
    local cell = math.max(HB_LEN + 2, round(math.sqrt(HB_LEN * size * 100 / s.density)))
    herringbone = { cell = cell, size = size, palette = makePalette() }
end

local function rebuild()
    if cfg.style == "newsprint" then
        buildOrdered()
    elseif cfg.style == "fibers" then
        buildFibers()
    elseif cfg.style == "linen" then
        buildLinen()
    elseif cfg.style == "crosshatch" then
        buildCrosshatch()
    elseif cfg.style == "diagonal" then
        buildDiagonal()
    elseif cfg.style == "laid" then
        buildLaid()
    elseif cfg.style == "dotgrid" then
        buildDotGrid()
    elseif cfg.style == "herringbone" then
        buildHerringbone()
    else
        buildTile()
    end
end

-- Fast path, gray_direct, paintAt
local use_paintrect = false
local verified = false

local fast_data, fast_pitch, fast_w, fast_h
local fast_rot, fast_pw, fast_ph, fast_inv -- rotation, physical size, night-mode inversion
local fast_addr, fast_addr_w, fast_addr_h, fast_addr_pitch, fast_addr_rot, fast_addr_inv
local fast_ok = false
-- With software night mode the stored bytes are the inverse of what we draw, so
-- the "pixel is near-white" test (stored luminance sum) is flipped around this.
local FAST_INV_LIMIT = 255 * 16382 - WHITE_SCALED
local fast_disabled = false
-- Fast painting writes straight into a 32-bit RGB buffer, so it only applies
-- to screens that use one (typically Android and color e-ink). Grayscale
-- buffers already have their own direct path. Checked once, on first use.
local fast_supported -- nil = not checked yet
local function fastSupported()
    if fast_supported == nil then
        local ok, bb_type = pcall(function() return Screen.bb:getType() end)
        if not ok or bb_type == nil then return false end -- screen not ready, retry later
        fast_supported = Blitbuffer.TYPE_BBRGB32 ~= nil and bb_type == Blitbuffer.TYPE_BBRGB32
    end
    return fast_supported
end

-- Logical (rotated) coordinates to the byte offset inside the raw buffer.
local function fastOffset(x, y, rot, pw, ph, pitch)
    if rot == 1 then
        x, y = pw - y - 1, x
    elseif rot == 2 then
        x, y = pw - x - 1, ph - y - 1
    elseif rot == 3 then
        x, y = y, ph - x - 1
    end
    return y * pitch + x * 4
end

local function fastSelfTest(bb, data, pitch, w, h, rot, pw, ph, inv)
    if pitch < pw * 4 or w < 16 or h < 16 then return false end
    local probes = {
        { 0, 0 }, { w - 1, 0 }, { 0, h - 1 }, { w - 1, h - 1 },
        { math.floor(w / 3), math.floor(h / 5) },
        { math.floor(w * 2 / 3), math.floor(h * 4 / 5) },
        { 7, 3 }, { 3, 7 },
    }
    for _idx, p in ipairs(probes) do
        local x, y = p[1], p[2]
        local c = bb:getPixel(x, y)
        local cr, cg, cb = c.r, c.g, c.b
        local test = 40 + (x * 7 + y * 13) % 150
        bb:setPixel(x, y, Blitbuffer.Color8(test))
        local o = fastOffset(x, y, rot, pw, ph, pitch)
        local r, g, b = data[o], data[o + 1], data[o + 2]
        bb:setPixel(x, y, Blitbuffer.ColorRGB32(cr, cg, cb, 0xFF))
        local want = inv and 255 - test or test
        if r ~= want or g ~= want or b ~= want then return false end
    end
    return true
end

local function fastSetup(bb, w, h)
    if Blitbuffer.TYPE_BBRGB32 == nil or bb:getType() ~= Blitbuffer.TYPE_BBRGB32 then return end

    local rot, inv = bb:getRotation(), bb:getInverse() == 1
    local pw, ph = tonumber(bb.w), tonumber(bb.h)
    local data = ffi.cast("uint8_t*", bb.data)
    local pitch = tonumber(bb.stride)
    local addr = tonumber(ffi.cast("uintptr_t", data))

    -- Re-run the self test whenever the buffer, its size, rotation or inversion changes.
    if addr ~= fast_addr or w ~= fast_addr_w or h ~= fast_addr_h or pitch ~= fast_addr_pitch
        or rot ~= fast_addr_rot or inv ~= fast_addr_inv then
        fast_addr, fast_addr_w, fast_addr_h, fast_addr_pitch = addr, w, h, pitch
        fast_addr_rot, fast_addr_inv = rot, inv
        fast_ok = fastSelfTest(bb, data, pitch, w, h, rot, pw, ph, inv)
        logger.info("paperdots: fast painting self test", fast_ok and "passed" or "failed",
            "rotation", rot, "inverse", inv)
    end

    if fast_ok then
        fast_data, fast_pitch, fast_w, fast_h = data, pitch, w, h
        fast_rot, fast_pw, fast_ph, fast_inv = rot, pw, ph, inv
    end
end

local function prepareFastPath(bb, w, h)
    fast_data = nil
    if fast_disabled or cfg.fast_paint_disabled or not fastSupported() then return end
    local ok, err = pcall(fastSetup, bb, w, h)
    if not ok then
        fast_data = nil
        fast_disabled = true
        logger.warn("paperdots: fast painting unavailable:", err)
    end
end

local function verifyFirstPaint(bb, px, py, paint_color, expected_gray)
    verified = true
    local back = bb:getPixel(px, py):getColor8().a
    if math.abs(back - expected_gray) > 24 then
        use_paintrect = true
        bb:paintRect(px, py, 1, 1, paint_color)
        logger.info("paperdots: setPixel mismatch (wanted", expected_gray, "got", back, "), using paintRect")
    end
end

-- Rotated/plain BB8 buffers can make the generic getPixel/setPixel path very
-- expensive: each call repeats logical-to-physical coordinate conversion and
-- allocates a Blitbuffer.Color8 cdata object. For 8-bit grayscale buffers we
-- cache the raw pointer and rotation metadata once per applyDots call, then
-- address the physical framebuffer directly. This preserves the white-pixel
-- test and the Blitbuffer inverse semantics, without allocating anything per
-- pixel. It is also what keeps rotated and portrait refreshes fast on
-- devices where the default path would otherwise accumulate GC pressure.
local gray_direct = nil
-- Keep the context per call (rather than mutating a singleton) so a nested
-- paint call cannot overwrite an outer call's buffer metadata.
local gray_direct_last_type = nil
local gray_direct_last_w, gray_direct_last_h = nil, nil
local gray_direct_last_rotation, gray_direct_last_stride, gray_direct_last_inverse = nil, nil, nil

local function prepareGrayDirect(bb)
    local type_id = bb:getType()
    if type_id ~= Blitbuffer.TYPE_BB8 then
        if type_id ~= gray_direct_last_type then
            gray_direct_last_type = type_id
            logger.info("paperdots: BB8 direct access not applicable", "type=" .. tostring(type_id))
        end
        return nil
    end

    local ctx = {
        data = ffi.cast("uint8_t*", bb.data),
        stride = tonumber(bb.stride),
        physical_w = tonumber(bb.w),
        physical_h = tonumber(bb.h),
        rotation = bb:getRotation(),
        inverse = bb:getInverse(),
    }
    if not ctx.data or not ctx.stride or ctx.stride < ctx.physical_w then
        return nil
    end

    if type_id ~= gray_direct_last_type
        or ctx.physical_w ~= gray_direct_last_w
        or ctx.physical_h ~= gray_direct_last_h
        or ctx.rotation ~= gray_direct_last_rotation
        or ctx.stride ~= gray_direct_last_stride
        or ctx.inverse ~= gray_direct_last_inverse then
        gray_direct_last_type = type_id
        gray_direct_last_w, gray_direct_last_h = ctx.physical_w, ctx.physical_h
        gray_direct_last_rotation, gray_direct_last_stride = ctx.rotation, ctx.stride
        gray_direct_last_inverse = ctx.inverse
        local key = tostring(ctx.physical_w) .. "x" .. tostring(ctx.physical_h)
            .. ":r" .. tostring(ctx.rotation) .. ":s" .. tostring(ctx.stride)
            .. ":inv" .. tostring(ctx.inverse)
        logger.info("paperdots: BB8 direct access enabled", key)
    end
    return ctx
end

-- Paper tint (color screens only). Dots are still computed as gray shades;
-- with a tint selected they are converted at paint time to a color of the
-- same luminance, so the "only paint on near-white pixels" test keeps working
-- and repainting a region never stacks dots. Neutral leaves the original gray
-- code path untouched, and grayscale (BB8) buffers ignore the tint.
-- Custom colors are stored as #RRGGBB and use the same luminance-preserving
-- conversion as the built-in tints.
local function parseHexColor(value)
    if type(value) ~= "string" then return nil end
    local hex = value:match("^%s*(.-)%s*$")
    if not hex then return nil end
    hex = hex:gsub("^#", "")
    if #hex == 3 and hex:match("^%x%x%x$") then
        hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
    end
    if #hex ~= 6 or not hex:match("^%x%x%x%x%x%x$") then return nil end
    local r = tonumber(hex:sub(1, 2), 16)
    local g = tonumber(hex:sub(3, 4), 16)
    local b = tonumber(hex:sub(5, 6), 16)
    return { r / 255, g / 255, b / 255 }, "#" .. hex:upper()
end

local _saved_custom_rgb, normalized_custom_tint = parseHexColor(cfg.custom_tint)
cfg.custom_tint = normalized_custom_tint or GLOBAL_DEFAULTS.custom_tint

local TINTS = {
    { id = "neutral", label = _("Neutral grey") },
}

-- Extra colors are offered as a visual palette, not as additional fixed tints.
-- ButtonDialog uses KOReader's native Button widget to display each swatch.
local CUSTOM_TINTS = {
    { label = _("Red"),     hex = "#E57373" },
    { label = _("Coral"),   hex = "#F08A5D" },
    { label = _("Orange"),  hex = "#F4A261" },
    { label = _("Amber"),   hex = "#E9B44C" },
    { label = _("Gold"),    hex = "#E8C547" },
    { label = _("Lime"),    hex = "#B8CC5A" },
    { label = _("Green"),   hex = "#75B66A" },
    { label = _("Mint"),    hex = "#69BFA3" },
    { label = _("Teal"),    hex = "#55B5AE" },
    { label = _("Cyan"),    hex = "#69C6CF" },
    { label = _("Sky"),     hex = "#7ABEE8" },
    { label = _("Blue"),    hex = "#6599E6" },
    { label = _("Navy"),    hex = "#5475B8" },
    { label = _("Indigo"),  hex = "#7777C8" },
    { label = _("Violet"),  hex = "#9877D6" },
    { label = _("Purple"),  hex = "#B07CC6" },
    { label = _("Magenta"), hex = "#CE78B9" },
    { label = _("Pink"),    hex = "#E58AB5" },
    { label = _("Rose"),    hex = "#E68C91" },
    { label = _("Peach"),   hex = "#EFAE8E" },
    { label = _("Brown"),   hex = "#A87959" },
    { label = _("Tan"),     hex = "#C39A6B" },
    { label = _("Olive"),   hex = "#A7A64B" },
    { label = _("Slate"),   hex = "#8597A8" },
}

-- lookup tables indexed by gray value 0..255 (nil while the tint is neutral)
local tint_r, tint_g, tint_b, tint_colors

local function rebuildTint()
    tint_r, tint_g, tint_b, tint_colors = nil, nil, nil, nil
    local found, rgb = false, nil

    if not HAS_COLOR then return end -- grayscale screen: always the plain gray path    
    
    if cfg.tint == "custom" then
        rgb = parseHexColor(cfg.custom_tint)
        found = rgb ~= nil
        if not found then
            cfg.custom_tint = GLOBAL_DEFAULTS.custom_tint
            rgb = parseHexColor(cfg.custom_tint)
            found = rgb ~= nil
        end
    else
        for _idx, t in ipairs(TINTS) do
            if t.id == cfg.tint then found, rgb = true, t.rgb end
        end
    end

    if not found then cfg.tint = "neutral" end
    if not rgb then return end

    -- Scale the selected RGB color so its luminance matches each source gray.
    -- For very saturated colors, a direct channel clamp would change the hue.
    -- Instead, reduce saturation toward the matching neutral gray just enough
    -- to stay inside RGB range. This keeps the original luminance/white-pixel
    -- behavior while allowing strong custom colors to remain recognizably true.
    local luminance = 4897 * rgb[1] + 9617 * rgb[2] + 1868 * rgb[3]
    tint_r, tint_g, tint_b, tint_colors = {}, {}, {}, {}
    if luminance <= 0 then
        -- Pure black has no hue or usable luminance, but it is still a valid
        -- custom choice: render every dot as black rather than dividing by 0.
        for v = 0, 255 do
            tint_r[v], tint_g[v], tint_b[v] = 0, 0, 0
            tint_colors[v] = Blitbuffer.ColorRGB32(0, 0, 0, 0xFF)
        end
        return
    end
    local k = 16384 / luminance
    for v = 0, 255 do
        local target_r = v * rgb[1] * k
        local target_g = v * rgb[2] * k
        local target_b = v * rgb[3] * k
        local sat = 1

        local dr, dg, db = target_r - v, target_g - v, target_b - v
        if dr > 0 then sat = math.min(sat, (255 - v) / dr)
        elseif dr < 0 then sat = math.min(sat, -v / dr) end
        if dg > 0 then sat = math.min(sat, (255 - v) / dg)
        elseif dg < 0 then sat = math.min(sat, -v / dg) end
        if db > 0 then sat = math.min(sat, (255 - v) / db)
        elseif db < 0 then sat = math.min(sat, -v / db) end
        sat = math.max(0, math.min(1, sat))

        local r = math.max(0, math.min(255, math.floor(v + dr * sat)))
        local g = math.max(0, math.min(255, math.floor(v + dg * sat)))
        local b = math.max(0, math.min(255, math.floor(v + db * sat)))
        tint_r[v], tint_g[v], tint_b[v] = r, g, b
        tint_colors[v] = Blitbuffer.ColorRGB32(r, g, b, 0xFF)
    end
end
rebuildTint()

local function paintAt(bb, px, py, color)
        local d = fast_data
    if d then
        if px < 0 or py < 0 or px >= fast_w or py >= fast_h then return end
        -- logical -> physical coordinates (rotated screens)
        local qx, qy = px, py
        local rot = fast_rot
        if rot == 1 then
            qx, qy = fast_pw - py - 1, px
        elseif rot == 2 then
            qx, qy = fast_pw - px - 1, fast_ph - py - 1
        elseif rot == 3 then
            qx, qy = py, fast_ph - px - 1
        end
        local o = qy * fast_pitch + qx * 4
        local v = color.a
        if fast_inv then
            -- software night mode: stored bytes are 255 - what we draw
            if 4897 * d[o] + 9617 * d[o + 1] + 1868 * d[o + 2] > FAST_INV_LIMIT then return end
            if tint_r then
                d[o], d[o + 1], d[o + 2] = 255 - tint_r[v], 255 - tint_g[v], 255 - tint_b[v]
            else
                v = 255 - v
                d[o], d[o + 1], d[o + 2] = v, v, v
            end
            return
        end
        if 4897 * d[o] + 9617 * d[o + 1] + 1868 * d[o + 2] < WHITE_SCALED then return end
        if tint_r then
            d[o], d[o + 1], d[o + 2] = tint_r[v], tint_g[v], tint_b[v]
        else
            d[o], d[o + 1], d[o + 2] = v, v, v
        end
        return
    end

    local g = gray_direct
    if g then
        if px < 0 or py < 0 then return end
        local physical_x, physical_y
        if g.rotation == 0 then
            physical_x, physical_y = px, py
        elseif g.rotation == 1 then
            physical_x, physical_y = g.physical_w - py - 1, px
        elseif g.rotation == 2 then
            physical_x, physical_y = g.physical_w - px - 1, g.physical_h - py - 1
        else
            physical_x, physical_y = py, g.physical_h - px - 1
        end
        if physical_x < 0 or physical_y < 0
            or physical_x >= g.physical_w or physical_y >= g.physical_h then
            return
        end
        local offset = physical_y * g.stride + physical_x
        local raw = g.data[offset]
        local current = g.inverse == 1 and (255 - raw) or raw
        if current < WHITE_THRESHOLD then return end
        local value = color.a
        g.data[offset] = g.inverse == 1 and (255 - value) or value
        return
    end

    -- Fallback for exotic buffers that do not expose data/stride.
    if bb:getPixel(px, py):getColor8().a < WHITE_THRESHOLD then return end
    local pc = tint_colors and tint_colors[color.a] or color
    if use_paintrect then
        bb:paintRect(px, py, 1, 1, pc)
    else
        bb:setPixel(px, py, pc)
        if not verified then
            local expected_gray = color.a
            if tint_r then
                expected_gray = math.floor((4897 * tint_r[color.a]
                    + 9617 * tint_g[color.a] + 1868 * tint_b[color.a]) / 16384)
            end
            verifyFirstPaint(bb, px, py, pc, expected_gray)
        end
    end
end

local function paintRectClipped(bb, rx, ry, rw, rh, x1, y1, x2, y2, color)
    local ax, ay = math.max(rx, x1), math.max(ry, y1)
    local bx, by = math.min(rx + rw, x2), math.min(ry + rh, y2)
    for py = ay, by - 1 do
        for px = ax, bx - 1 do
            paintAt(bb, px, py, color)
        end
    end
end

-- Row-major painters
local function applyRandom(bb, x1, y1, x2, y2, size)
    local n, xs, ys, cs = tile.n, tile.xs, tile.ys, tile.cs
    local single = size == 1

    local tx0, tx1 = math.floor((x1 - size + 1) / TILE), math.floor((x2 - 1) / TILE)
    local ty0, ty1 = math.floor((y1 - size + 1) / TILE), math.floor((y2 - 1) / TILE)

    for ty = ty0, ty1 do
        local oy = ty * TILE
        for tx = tx0, tx1 do
            local ox = tx * TILE
            if ox >= x1 and oy >= y1
                and ox + TILE + size - 1 <= x2 and oy + TILE + size - 1 <= y2 then
                if single then
                    for i = 1, n do
                        paintAt(bb, ox + xs[i], oy + ys[i], cs[i])
                    end
                else
                    for i = 1, n do
                        local dx, dy, color = ox + xs[i], oy + ys[i], cs[i]
                        for j = 0, size - 1 do
                            for k = 0, size - 1 do
                                paintAt(bb, dx + k, dy + j, color)
                            end
                        end
                    end
                end
            else
                local last_y = y2 - 1 - oy
                for i = lowerBound(ys, n, y1 - oy - size + 1), n do
                    local ry = ys[i]
                    if ry > last_y then break end
                    local dx, dy = ox + xs[i], oy + ry
                    if dx < x2 and dx + size > x1 then
                        local color = cs[i]
                        if single then
                            if dy >= y1 and dy < y2 and dx >= x1 and dx < x2 then
                                paintAt(bb, dx, dy, color)
                            end
                        else
                            for j = 0, size - 1 do
                                local py = dy + j
                                if py >= y1 and py < y2 then
                                    for k = 0, size - 1 do
                                        local px = dx + k
                                        if px >= x1 and px < x2 then
                                            paintAt(bb, px, py, color)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function applyOrdered(bb, x1, y1, x2, y2, size)
    local step, palette = ordered.step, ordered.palette
    local col_step = step * 2
    local single = size == 1

    local r0 = math.max(0, math.ceil((y1 - size + 1) / step))
    local r1 = math.floor((y2 - 1) / step)
    for r = r0, r1 do
        local dy = r * step
        local off = (r % 2 == 1) and step or 0
        local c0 = math.max(0, math.ceil((x1 - size + 1 - off) / col_step))
        local c1 = math.floor((x2 - 1 - off) / col_step)
        for c = c0, c1 do
            local dx = c * col_step + off
            local color = palette[hash(r, c) % PALETTE_SIZE + 1]
            if single then
                if dy >= y1 and dy < y2 and dx >= x1 and dx < x2 then
                    paintAt(bb, dx, dy, color)
                end
            else
                for j = 0, size - 1 do
                    local py = dy + j
                    if py >= y1 and py < y2 then
                        for k = 0, size - 1 do
                            local px = dx + k
                            if px >= x1 and px < x2 then
                                paintAt(bb, px, py, color)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function applyLinen(bb, x1, y1, x2, y2, size)
    local sp, palette = linen.spacing, linen.palette

    local r0 = math.max(0, math.ceil((y1 - size + 1) / sp))
    local r1 = math.floor((y2 - 1) / sp)
    local m0, m1 = math.floor(x1 / LINEN_SEG), math.floor((x2 - 1) / LINEN_SEG)
    for r = r0, r1 do
        local ty = r * sp
        for m = m0, m1 do
            local h = hash(r, m)
            if h % 100 < LINEN_PRESENCE then
                local color = palette[math.floor(h / 100) % PALETTE_SIZE + 1]
                paintRectClipped(bb, m * LINEN_SEG, ty, LINEN_SEG, size, x1, y1, x2, y2, color)
            end
        end
    end

    local c0 = math.max(0, math.ceil((x1 - size + 1) / sp))
    local c1 = math.floor((x2 - 1) / sp)
    local n0, n1 = math.floor(y1 / LINEN_SEG), math.floor((y2 - 1) / LINEN_SEG)
    for c = c0, c1 do
        local tx = c * sp
        for m = n0, n1 do
            local h = hash(c + 50000, m)
            if h % 100 < LINEN_PRESENCE then
                local color = palette[math.floor(h / 100) % PALETTE_SIZE + 1]
                paintRectClipped(bb, tx, m * LINEN_SEG, size, LINEN_SEG, x1, y1, x2, y2, color)
            end
        end
    end
end

local function applyCrosshatch(bb, x1, y1, x2, y2)
    local step, size, palette = crosshatch.step, crosshatch.size, crosshatch.palette
    local single = size == 1

    for y = y1, y2 - 1 do
        local c0 = step * math.ceil((x1 - y) / step)
        local c1 = step * math.floor((x2 - 1 - y) / step)
        for c = c0, c1, step do
            local h = hash(c, math.floor(y / LINEN_SEG))
            if h % 100 < LINEN_PRESENCE then
                local color = palette[math.floor(h / 100) % PALETTE_SIZE + 1]
                local px0 = y + c
                if single then
                    if px0 >= x1 and px0 < x2 then paintAt(bb, px0, y, color) end
                else
                    for k = 0, size - 1 do
                        local px = px0 + k
                        if px >= x1 and px < x2 then paintAt(bb, px, y, color) end
                    end
                end
            end
        end
        local d0 = step * math.ceil((x1 + y) / step)
        local d1 = step * math.floor((x2 - 1 + y) / step)
        for c = d0, d1, step do
            local h = hash(c + 500000, math.floor(y / LINEN_SEG))
            if h % 100 < LINEN_PRESENCE then
                local color = palette[math.floor(h / 100) % PALETTE_SIZE + 1]
                local px0 = c - y
                if single then
                    if px0 >= x1 and px0 < x2 then paintAt(bb, px0, y, color) end
                else
                    for k = 0, size - 1 do
                        local px = px0 + k
                        if px >= x1 and px < x2 then paintAt(bb, px, y, color) end
                    end
                end
            end
        end
    end
end

local function applyDiagonal(bb, x1, y1, x2, y2)
    local step, size, palette = diagonal.step, diagonal.size, diagonal.palette
    local single = size == 1
    local backslash = diagonal.direction == "backslash"

    for y = y1, y2 - 1 do
        local c0, c1, base
        if backslash then
            c0 = step * math.ceil((x1 - y) / step)
            c1 = step * math.floor((x2 - 1 - y) / step)
            base = y
        else
            c0 = step * math.ceil((x1 + y) / step)
            c1 = step * math.floor((x2 - 1 + y) / step)
            base = -y
        end
        for c = c0, c1, step do
            local color = palette[hash(c, 0) % PALETTE_SIZE + 1]
            local px0 = base + c
            if single then
                if px0 >= x1 and px0 < x2 then paintAt(bb, px0, y, color) end
            else
                for k = 0, size - 1 do
                    local px = px0 + k
                    if px >= x1 and px < x2 then paintAt(bb, px, y, color) end
                end
            end
        end
    end
end

local function applyLaid(bb, x1, y1, x2, y2)
    local sp, chain, size, palette = laid.sp, laid.chain, laid.size, laid.palette

    local c0 = math.max(1, math.ceil((x1 - size + 1) / chain))
    local c1 = math.floor((x2 - 1) / chain)
    for c = c0, c1 do
        local color = palette[1 + hash(c, 7) % 4]
        paintRectClipped(bb, c * chain, y1, size, y2 - y1, x1, y1, x2, y2, color)
    end

    local r0 = math.max(1, math.ceil((y1 - size + 1) / sp))
    local r1 = math.floor((y2 - 1) / sp)
    local m0, m1 = math.floor(x1 / LAID_SEG), math.floor((x2 - 1) / LAID_SEG)
    for r = r0, r1 do
        local ty = r * sp
        for m = m0, m1 do
            local h = hash(r, m)
            if h % 100 < LAID_PRESENCE then
                local color = palette[HALF + 1 + math.floor(h / 100) % HALF]
                paintRectClipped(bb, m * LAID_SEG, ty, LAID_SEG, size, x1, y1, x2, y2, color)
            end
        end
    end
end

local function applyDotGrid(bb, x1, y1, x2, y2)
    local sp, size, palette = dotgrid.sp, dotgrid.size, dotgrid.palette

    local r0 = math.max(1, math.ceil((y1 - size + 1) / sp))
    local r1 = math.floor((y2 - 1) / sp)
    local c0 = math.max(1, math.ceil((x1 - size + 1) / sp))
    local c1 = math.floor((x2 - 1) / sp)

    for r = r0, r1 do
        local dy = r * sp
        for c = c0, c1 do
            local dx = c * sp
            local color = palette[hash(r, c) % PALETTE_SIZE + 1]
            if size == 1 then
                paintAt(bb, dx, dy, color)
            else
                for j = 0, size - 1 do
                    local py = dy + j
                    if py >= y1 and py < y2 then
                        for k = 0, size - 1 do
                            local px = dx + k
                            if px >= x1 and px < x2 then
                                paintAt(bb, px, py, color)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function applyHerringbone(bb, x1, y1, x2, y2)
    local cell, size, palette = herringbone.cell, herringbone.size, herringbone.palette
    local half = math.floor(cell / 2)

    local c0 = math.floor((x1 - HB_LEN - size + 1) / cell)
    local c1 = math.floor((x2 - 1) / cell)

    for c = c0, c1 do
        local ox = c * cell
        local odd = c % 2 == 1
        local off = odd and half or 0

        local r0 = math.ceil((y1 - HB_LEN + 1 - off) / cell)
        local r1 = math.floor((y2 - 1 - off) / cell)

        for r = r0, r1 do
            local oy = r * cell + off
            local color = palette[hash(r, c) % PALETTE_SIZE + 1]
            for k = 0, HB_LEN - 1 do
                local py = oy + (odd and (HB_LEN - 1 - k) or k)
                if py >= y1 and py < y2 then
                    local px0 = ox + k
                    for a = 0, size - 1 do
                        local px = px0 + a
                        if px >= x1 and px < x2 then
                            paintAt(bb, px, py, color)
                        end
                    end
                end
            end
        end
    end
end

-- Column-major painters (direction-aware)
--
-- Physical mapping (KOReader's Blitbuffer with rotation):
--   rot=0: physical_x = px,           physical_y = py
--   rot=1: physical_x = 1071 - py,    physical_y = px
--   rot=2: physical_x = 1071 - px,    physical_y = 1447 - py
--   rot=3: physical_x = py,           physical_y = 1447 - px
--
-- For forward-sequential physical writes we need physical_x to INCREASE as
-- the inner loop runs. In column-major, the inner loop is py. So:
--   rot=3: py++ -> physical_x++  -> OK (natural)
--   rot=1: py++ -> physical_x--  -> REVERSE ty
--   rot=2: py++ -> physical_x--  -> REVERSE ty
--   rot=0: py++ -> physical_y++  -> row-major is fine; column-major here
--                                    gives strided physical access, so it is
--                                    only used when size == 1 and the caller
--                                    has explicitly chosen it.
--
-- Additionally for rot=2, physical_y = 1447 - px, so px++ gives backward
-- rows. Reverse the outer x iteration too.
local function column_direction()
    if gray_direct then return gray_direct.rotation end
    if fast_data then return fast_rot end
    return 0
end

local function applyRandomColumns(bb, x1, y1, x2, y2)
    local n, xs, ys, cs = tile.n, tile.xs, tile.ys, tile.cs
    local x_order, x_first = tile.x_order, tile.x_first
    local rot = column_direction()

    local tx_min = math.floor(x1 / TILE)
    local tx_max = math.floor((x2 - 1) / TILE)
    local ty_min = math.floor(y1 / TILE)
    local ty_max = math.floor((y2 - 1) / TILE)

    -- Inner (py) direction: reverse for rot=1 and rot=2
    local ty_from, ty_to, ty_step = ty_min, ty_max, 1
    if rot == 1 or rot == 2 then
        ty_from, ty_to, ty_step = ty_max, ty_min, -1
    end

    -- Outer (px) direction: reverse for rot=2
    local tx_from, tx_to, tx_step = tx_min, tx_max, 1
    local xv_from, xv_to, xv_step = 0, TILE - 1, 1
    if rot == 2 then
        tx_from, tx_to, tx_step = tx_max, tx_min, -1
        xv_from, xv_to, xv_step = TILE - 1, 0, -1
    end

    for tx = tx_from, tx_to, tx_step do
        local x_tile_base = tx * TILE
        for xv = xv_from, xv_to, xv_step do
            local x_logical = x_tile_base + xv
            if x_logical >= x1 and x_logical < x2 then
                local start = x_first[xv]
                if start then
                    local i = start
                    while i <= n do
                        local dot = x_order[i]
                        if xs[dot] ~= xv then break end
                        local yv = ys[dot]
                        local color = cs[dot]
                        for ty = ty_from, ty_to, ty_step do
                            local y_logical = ty * TILE + yv
                            if y_logical >= y1 and y_logical < y2 then
                                paintAt(bb, x_logical, y_logical, color)
                            end
                        end
                        i = i + 1
                    end
                end
            end
        end
    end
end

local function applyOrderedColumns(bb, x1, y1, x2, y2)
    local step, palette = ordered.step, ordered.palette
    local col_step = step * 2
    local rot = column_direction()

    local r0 = math.max(0, math.ceil(y1 / step))
    local r1 = math.floor((y2 - 1) / step)
    local r_from, r_to, r_step = r0, r1, 1
    if rot == 1 or rot == 2 then
        r_from, r_to, r_step = r1, r0, -1
    end

    -- Even rows (r % 2 == 0): dots at x = c * col_step
    local c_lo = math.ceil(x1 / col_step)
    local c_hi = math.floor((x2 - 1) / col_step)
    local cc_from, cc_to, cc_step = c_lo, c_hi, 1
    if rot == 2 then cc_from, cc_to, cc_step = c_hi, c_lo, -1 end
    for c = cc_from, cc_to, cc_step do
        local x_logical = c * col_step
        for r = r_from, r_to, r_step do
            if r % 2 == 0 then
                local color = palette[hash(r, c) % PALETTE_SIZE + 1]
                paintAt(bb, x_logical, r * step, color)
            end
        end
    end

    -- Odd rows (r % 2 == 1): dots at x = c * col_step + step
    c_lo = math.ceil((x1 - step) / col_step)
    c_hi = math.floor((x2 - 1 - step) / col_step)
    cc_from, cc_to, cc_step = c_lo, c_hi, 1
    if rot == 2 then cc_from, cc_to, cc_step = c_hi, c_lo, -1 end
    for c = cc_from, cc_to, cc_step do
        local x_logical = c * col_step + step
        for r = r_from, r_to, r_step do
            if r % 2 == 1 then
                local color = palette[hash(r, c) % PALETTE_SIZE + 1]
                paintAt(bb, x_logical, r * step, color)
            end
        end
    end
end

-- Herringbone: iterate logical x columns. For each px, find cells whose
-- stroke passes through that column and paint the corresponding pixel.
local function applyHerringboneColumns(bb, x1, y1, x2, y2)
    local cell, palette = herringbone.cell, herringbone.palette
    local HB = HB_LEN
    local half = math.floor(cell / 2)
    local rot = column_direction()
    local reverse_y = (rot == 1 or rot == 2)

    local px_from, px_to, px_step = x1, x2 - 1, 1
    if rot == 2 then px_from, px_to, px_step = x2 - 1, x1, -1 end

    for px = px_from, px_to, px_step do
        local c_min = math.max(0, math.ceil((px - HB + 1) / cell))
        local c_max = math.floor(px / cell)
        for c = c_min, c_max do
            local k = px - c * cell
            if k >= 0 and k < HB then
                local odd = c % 2 == 1
                local off = odd and half or 0
                local r0 = math.ceil((y1 - HB + 1 - off) / cell)
                local r1 = math.floor((y2 - 1 - off) / cell)
                local r_from, r_to, r_step = r0, r1, 1
                if reverse_y then
                    r_from, r_to, r_step = r1, r0, -1
                end
                for r = r_from, r_to, r_step do
                    local oy = r * cell + off
                    local py = oy + (odd and (HB - 1 - k) or k)
                    if py >= y1 and py < y2 then
                        local color = palette[hash(r, c) % PALETTE_SIZE + 1]
                        paintAt(bb, px, py, color)
                    end
                end
            end
        end
    end
end

-- Dot grid: iterate px columns.
local function applyDotGridColumns(bb, x1, y1, x2, y2)
    local sp, palette = dotgrid.sp, dotgrid.palette
    local rot = column_direction()
    local reverse_y = (rot == 1 or rot == 2)

    local px_from, px_to, px_step = x1, x2 - 1, 1
    if rot == 2 then px_from, px_to, px_step = x2 - 1, x1, -1 end

    for px = px_from, px_to, px_step do
        if px > 0 and px % sp == 0 then
            local c = px / sp
            local r0 = math.max(1, math.ceil(y1 / sp))
            local r1 = math.floor((y2 - 1) / sp)
            local r_from, r_to, r_step = r0, r1, 1
            if reverse_y then
                r_from, r_to, r_step = r1, r0, -1
            end
            for r = r_from, r_to, r_step do
                local py = r * sp
                if py >= y1 and py < y2 then
                    local color = palette[hash(r, c) % PALETTE_SIZE + 1]
                    paintAt(bb, px, py, color)
                end
            end
        end
    end
end

-- Column-major variants below are used only for dot_size == 1 and 90-degree
-- rotations. They preserve each style's original pattern coordinates and the
-- original precedence at intersections while making framebuffer writes
-- sequential in physical memory.
local function applyLinenColumns(bb, x1, y1, x2, y2)
    local sp, palette = linen.spacing, linen.palette
    local reverse_y = column_direction() == 1
    local r0 = math.max(0, math.ceil(y1 / sp))
    local r1 = math.floor((y2 - 1) / sp)
    local m0 = math.floor(y1 / LINEN_SEG)
    local m1 = math.floor((y2 - 1) / LINEN_SEG)

    for px = x1, x2 - 1 do
        -- Horizontal threads are painted first, as in applyLinen, so they win
        -- at intersections with vertical threads.
        local m = math.floor(px / LINEN_SEG)
        local r_from, r_to, r_step = r0, r1, 1
        if reverse_y then r_from, r_to, r_step = r1, r0, -1 end
        for r = r_from, r_to, r_step do
            local h = hash(r, m)
            if h % 100 < LINEN_PRESENCE then
                paintAt(bb, px, r * sp, palette[math.floor(h / 100) % PALETTE_SIZE + 1])
            end
        end

        if px % sp == 0 then
            local c = px / sp
            local from, to, step = m0, m1, 1
            local k_from, k_to, k_step = 0, LINEN_SEG - 1, 1
            if reverse_y then
                from, to, step = m1, m0, -1
                k_from, k_to, k_step = LINEN_SEG - 1, 0, -1
            end
            for segment = from, to, step do
                local h = hash(c + 50000, segment)
                if h % 100 < LINEN_PRESENCE then
                    local color = palette[math.floor(h / 100) % PALETTE_SIZE + 1]
                    local base_y = segment * LINEN_SEG
                    for k = k_from, k_to, k_step do
                        local py = base_y + k
                        if py >= y1 and py < y2 then paintAt(bb, px, py, color) end
                    end
                end
            end
        end
    end
end

local function applyCrosshatchColumns(bb, x1, y1, x2, y2)
    local step, palette = crosshatch.step, crosshatch.palette
    local reverse_y = column_direction() == 1

    for px = x1, x2 - 1 do
        -- First diagonal family: c = px - py, matching the first row-major pass.
        local first = y1 + ((px - y1) % step)
        if first <= y2 - 1 then
            if reverse_y then
                local last = y2 - 1 - ((y2 - 1 - first) % step)
                for py = last, first, -step do
                    local c = px - py
                    local h = hash(c, math.floor(py / LINEN_SEG))
                    if h % 100 < LINEN_PRESENCE then
                        paintAt(bb, px, py, palette[math.floor(h / 100) % PALETTE_SIZE + 1])
                    end
                end
            else
                for py = first, y2 - 1, step do
                    local c = px - py
                    local h = hash(c, math.floor(py / LINEN_SEG))
                    if h % 100 < LINEN_PRESENCE then
                        paintAt(bb, px, py, palette[math.floor(h / 100) % PALETTE_SIZE + 1])
                    end
                end
            end
        end

        -- Second family is deliberately painted second, preserving overlap rules.
        first = y1 + ((-px - y1) % step)
        if first <= y2 - 1 then
            if reverse_y then
                local last = y2 - 1 - ((y2 - 1 - first) % step)
                for py = last, first, -step do
                    local c = px + py
                    local h = hash(c + 500000, math.floor(py / LINEN_SEG))
                    if h % 100 < LINEN_PRESENCE then
                        paintAt(bb, px, py, palette[math.floor(h / 100) % PALETTE_SIZE + 1])
                    end
                end
            else
                for py = first, y2 - 1, step do
                    local c = px + py
                    local h = hash(c + 500000, math.floor(py / LINEN_SEG))
                    if h % 100 < LINEN_PRESENCE then
                        paintAt(bb, px, py, palette[math.floor(h / 100) % PALETTE_SIZE + 1])
                    end
                end
            end
        end
    end
end

local function applyDiagonalColumns(bb, x1, y1, x2, y2)
    local step, palette = diagonal.step, diagonal.palette
    local backslash = diagonal.direction == "backslash"
    local reverse_y = column_direction() == 1

    for px = x1, x2 - 1 do
        local residue = backslash and px or -px
        local first = y1 + ((residue - y1) % step)
        if first <= y2 - 1 then
            if reverse_y then
                local last = y2 - 1 - ((y2 - 1 - first) % step)
                for py = last, first, -step do
                    local c = backslash and (px - py) or (px + py)
                    paintAt(bb, px, py, palette[hash(c, 0) % PALETTE_SIZE + 1])
                end
            else
                for py = first, y2 - 1, step do
                    local c = backslash and (px - py) or (px + py)
                    paintAt(bb, px, py, palette[hash(c, 0) % PALETTE_SIZE + 1])
                end
            end
        end
    end
end

local function applyLaidColumns(bb, x1, y1, x2, y2)
    local sp, chain, palette = laid.sp, laid.chain, laid.palette
    local reverse_y = column_direction() == 1
    local r0 = math.max(1, math.ceil(y1 / sp))
    local r1 = math.floor((y2 - 1) / sp)
    local r_from, r_to, r_step = r0, r1, 1
    if reverse_y then r_from, r_to, r_step = r1, r0, -1 end

    for px = x1, x2 - 1 do
        -- The vertical chain is first in the original painter and therefore
        -- retains precedence where it crosses a horizontal laid segment.
        if px % chain == 0 then
            local c = px / chain
            if c >= 1 then
                local color = palette[1 + hash(c, 7) % 4]
                if reverse_y then
                    for py = y2 - 1, y1, -1 do paintAt(bb, px, py, color) end
                else
                    for py = y1, y2 - 1 do paintAt(bb, px, py, color) end
                end
            end
        end

        local m = math.floor(px / LAID_SEG)
        for r = r_from, r_to, r_step do
            local h = hash(r, m)
            if h % 100 < LAID_PRESENCE then
                paintAt(bb, px, r * sp, palette[HALF + 1 + math.floor(h / 100) % HALF])
            end
        end
    end
end

local function paintStyle(bb, style, x1, y1, x2, y2, size, use_columns)
    if style == "newsprint" then
        if use_columns then
            applyOrderedColumns(bb, x1, y1, x2, y2)
        else
            applyOrdered(bb, x1, y1, x2, y2, size)
        end
    elseif style == "linen" then
        if use_columns then
            applyLinenColumns(bb, x1, y1, x2, y2)
        else
            applyLinen(bb, x1, y1, x2, y2, size)
        end
    elseif style == "crosshatch" then
        if use_columns then
            applyCrosshatchColumns(bb, x1, y1, x2, y2)
        else
            applyCrosshatch(bb, x1, y1, x2, y2)
        end
    elseif style == "diagonal" then
        if use_columns then
            applyDiagonalColumns(bb, x1, y1, x2, y2)
        else
            applyDiagonal(bb, x1, y1, x2, y2)
        end
    elseif style == "laid" then
        if use_columns then
            applyLaidColumns(bb, x1, y1, x2, y2)
        else
            applyLaid(bb, x1, y1, x2, y2)
        end
    elseif style == "dotgrid" then
        if use_columns then
            applyDotGridColumns(bb, x1, y1, x2, y2)
        else
            applyDotGrid(bb, x1, y1, x2, y2)
        end
    elseif style == "herringbone" then
        if use_columns then
            applyHerringboneColumns(bb, x1, y1, x2, y2)
        else
            applyHerringbone(bb, x1, y1, x2, y2)
        end
    elseif use_columns then
        applyRandomColumns(bb, x1, y1, x2, y2)
    else
        applyRandom(bb, x1, y1, x2, y2, size)
    end
end

local function applyDots(x, y, w, h)
    local bb = Screen.bb
    if not bb then return end
    local bw, bh = bb:getWidth(), bb:getHeight()

    x = x or 0
    y = y or 0
    w = w or bw
    h = h or bh

    local x1, y1 = math.max(x, 0), math.max(y, 0)
    local x2, y2 = math.min(x + w, bw), math.min(y + h, bh)
    if x2 <= x1 or y2 <= y1 then return end

    prepareFastPath(bb, bw, bh)

    -- Reuse the BB8 context and preserve any outer context in case this hook is
    -- reached through a nested KOReader paint/refresh call.
    local previous_gray_direct = gray_direct
    gray_direct = prepareGrayDirect(bb)

    local style, size = cfg.style, S().dot_size
    local rot = column_direction()
    local use_columns = (gray_direct ~= nil or fast_data ~= nil) and size == 1
        and (rot == 1 or rot == 3)

    local ok, err = pcall(paintStyle, bb, style, x1, y1, x2, y2, size, use_columns)
    gray_direct = previous_gray_direct
    if not ok then error(err, 0) end
end

rebuild()

-- On Android KOReader's C blitter ignores the invert flag, so in night mode the
-- screen buffer still holds the normal (day) picture and the display inverts it
-- at the very end. Dots must be painted as in day mode: clear the flag while painting.
local IS_ANDROID = os.getenv("IS_ANDROID") ~= nil
    or (Device.isAndroid ~= nil and Device:isAndroid() and true or false)
local applyDotsRaw = applyDots
applyDots = function(x, y, w, h)
    local bb = Screen.bb
    if not bb then return end
    if IS_ANDROID and bb:getInverse() == 1 then
        bb:setInverse(0)
        local ok, err = pcall(applyDotsRaw, x, y, w, h)
        bb:setInverse(1)
        if not ok then error(err, 0) end
        return
    end
    return applyDotsRaw(x, y, w, h)
end

-- Hooks
local function isNightMode()
    local ok, val = pcall(function() return Screen.night_mode end)
    if ok and type(val) == "boolean" then return val end
    ok, val = pcall(function() return G_reader_settings and G_reader_settings:isTrue("night_mode") end)
    if ok and type(val) == "boolean" then return val end
    return false
end

local active_reader = nil

local function refreshHookActive()
    if not cfg.enabled then return false end
    if cfg.hide_on_night and isNightMode() then return false end
    if not cfg.book_only then return true end
    return active_reader ~= nil and not cfg.hide_on_menus
end

local BASE_METHODS = {
    "refreshFull", "refreshPartial", "refreshFlashPartial",
    "refreshUI", "refreshFlashUI", "refreshFast", "refreshA2",
    "refreshNoMergePartial",
}

-- avoids painting twice when a refresh function calls another one
local in_refresh = false

-- Page turn animations. On a page change a few quick frames are drawn from
-- the previous screen and the new page, moving toward the side you turned to
-- (forward: the new page comes from the right, backward: from the left; the
-- other way around for right-to-left books). Frames are plain C blits; the
-- paper dots travel with the page, and the last frame is the normal refresh.
local usleep = require("ffi/util").usleep
local PAGE_ANIM_STYLES = {
    { id = "wipe", label = _("Wipe") },
    { id = "blinds", label = _("Blinds") },
}

local page_anim_pending = false
local page_anim_dir = 1
local page_anim_last_page, page_anim_last_doc = nil, nil
local page_anim_old, page_anim_new -- helper buffers, same layout as the screen

-- Highest number of steps the menu offers, and its default. Change them here.
local PAGE_ANIM_MAX_STEPS = 15
local PAGE_ANIM_DEFAULT_STEPS = 3

-- Comic and manga archives (CBZ, CBR, CB7, CBT).
local function pageAnimIsComic(doc)
    local file = doc and doc.file
    return type(file) == "string" and file:lower():match("%.cb[7rtz]$") ~= nil
end

-- Used by the menu and by the gesture.
local function setPageAnim(on)
    cfg.page_anim = on and true or false
    page_anim_last_page = nil
    page_anim_pending = false
    if not cfg.page_anim then
        if page_anim_old then page_anim_old:free() end
        if page_anim_new then page_anim_new:free() end
        page_anim_old, page_anim_new = nil, nil
    end
    saveSettings()
end

local function pageAnimBuffer(buf, bb)
    if not (buf and buf.w == bb.w and buf.h == bb.h and tonumber(buf.stride) == tonumber(bb.stride)
        and buf:getType() == bb:getType()) then
        if buf then buf:free() end
        buf = Blitbuffer.new(bb.w, bb.h, bb:getType(), nil, tonumber(bb.stride))
    end
    buf:setRotation(bb:getRotation())
    buf:setInverse(bb:getInverse())
    return buf
end

-- Called just before a new page is painted, while the screen still shows the old one.
local function pageAnimSnapshot(bb)
    page_anim_old = pageAnimBuffer(page_anim_old, bb)
    ffi.copy(page_anim_old.data, bb.data, tonumber(bb.stride) * tonumber(bb.h))
end

-- Logical (rotated) rectangle -> rectangle in the unrotated buffer. Blits between
-- rotated buffers are ~10x slower than plain row copies, so frames are composed
-- in the unrotated layout (same pixels, same result).
local function physRect(rot, pw, ph, x, y, w, h)
    if rot == 1 then return pw - y - h, x, h, w end
    if rot == 2 then return pw - x - w, ph - y - h, w, h end
    if rot == 3 then return y, ph - x - w, h, w end
    return x, y, w, h
end

local PAGE_ANIM_BLINDS = 5 -- slats of the Blinds style

-- Returns true when the transition was shown (the finished page, dots included,
-- is then left in the screen buffer for the normal refresh), "done" when it is already
-- completely on screen (e-ink: the animations only touch thin strips, and a whole-page
-- refresh afterwards would redraw identical content, a visible flash), and false when
-- nothing was animated.
local function pageAnimFrames(x, y, w, h)
    local bb = Screen.bb
    local old = page_anim_old
    -- C blits only (they work in software night mode too while both buffers share
    -- the same inversion; otherwise KOReader would fall back to a very slow path)
    if not old or not (bb.canUseCbbTogether and bb:canUseCbbTogether(old)) then return false end
    if old.w ~= bb.w or old.h ~= bb.h or tonumber(old.stride) ~= tonumber(bb.stride)
        or old:getRotation() ~= bb:getRotation() then
        return false
    end
    local bw, bh = bb:getWidth(), bb:getHeight()
    local rx = math.max(0, math.floor(x or 0))
    local ry = math.max(0, math.floor(y or 0))
    local rw = math.min(bw - rx, math.floor(w or bw))
    local rh = math.min(bh - ry, math.floor(h or bh))
    if rx ~= 0 or rw < bw or rh < 0.6 * bh then return false end -- whole-page refreshes only

    -- the new page, with its dots, is the picture we end on
    if refreshHookActive() then applyDots(rx, ry, rw, rh) end
    local new = pageAnimBuffer(page_anim_new, bb)
    page_anim_new = new
    local size = tonumber(bb.stride) * tonumber(bb.h)
    ffi.copy(new.data, bb.data, size)

    local style, dir = cfg.page_anim_style, page_anim_dir
    if style ~= "blinds" then style = "wipe" end -- also covers removed styles
    local steps = math.max(1, math.min(PAGE_ANIM_MAX_STEPS, math.floor(tonumber(cfg.page_anim_steps) or PAGE_ANIM_DEFAULT_STEPS)))
    local eink = Device:hasEinkScreen()
    local rot, pw, ph = bb:getRotation(), tonumber(bb.w), tonumber(bb.h)
    local function blit(dst, src, dx, dy, sx, sy, w, h)
        if w <= 0 or h <= 0 then return end
        local dpx, dpy, bw2, bh2 = physRect(rot, pw, ph, dx, dy, w, h)
        local spx, spy = physRect(rot, pw, ph, sx, sy, w, h)
        dst:blitFrom(src, dpx, dpy, spx, spy, bw2, bh2)
    end
    local function setRot(r) bb:setRotation(r); old:setRotation(r); new:setRotation(r) end
    local edges = {}
    for k = 0, PAGE_ANIM_BLINDS do edges[k] = math.floor(k * bw / PAGE_ANIM_BLINDS) end
    local function revealed(k, p) -- columns of slat k already showing the new page
        return math.floor((edges[k + 1] - edges[k]) * p + 0.5)
    end
    -- e-ink: one thin update per strip. Elsewhere one update over their bounding box.
    local function refreshStrips(strips)
        if eink then
            for _i, st in ipairs(strips) do
                if st[2] > 0 then Screen:refreshUI(st[1], ry, st[2], rh) end
            end
        else
            local x0, x1 = bw, 0
            for _i, st in ipairs(strips) do
                if st[2] > 0 then x0 = math.min(x0, st[1]); x1 = math.max(x1, st[1] + st[2]) end
            end
            if x1 > x0 then Screen:refreshUI(x0, ry, x1 - x0, rh) end
        end
    end

    local prev_s, prev_p, p = 0, 0, 0
    local ok, err = pcall(function()
        -- Start from the previous page once. Each subsequent frame only copies
        -- the newly revealed strips; already revealed/hidden areas do not need
        -- to be blitted again. This preserves the exact composition while
        -- avoiding repeated large C blits on every animation step.
        setRot(0)
        blit(bb, old, 0, ry, 0, ry, bw, rh)

        for i = 1, steps do
            p = 1 - (1 - i / (steps + 1)) ^ 2 -- ease-out
            local s = math.floor(bw * p + 0.5)
            local strips = {}
            setRot(0) -- compose in the unrotated layout
            if style == "blinds" then
                for k = 0, PAGE_ANIM_BLINDS - 1 do
                    local e0, e1 = edges[k], edges[k + 1]
                    local r, r_prev = revealed(k, p), revealed(k, prev_p)
                    local delta = r - r_prev
                    if dir > 0 then
                        blit(bb, new, e1 - r, ry, e1 - r, ry, delta, rh)
                        strips[#strips + 1] = { e1 - r, delta }
                    else
                        blit(bb, new, e0 + r_prev, ry, e0 + r_prev, ry, delta, rh)
                        strips[#strips + 1] = { e0 + r_prev, delta }
                    end
                end
            else -- wipe: copy only the newly uncovered strip
                local delta = s - prev_s
                if dir > 0 then
                    blit(bb, new, bw - s, ry, bw - s, ry, delta, rh)
                    strips[1] = { bw - s, delta }
                else
                    blit(bb, new, prev_s, ry, prev_s, ry, delta, rh)
                    strips[1] = { prev_s, delta }
                end
            end
            setRot(rot)
            refreshStrips(strips)
            if not eink then usleep(12000) end
            prev_s, prev_p = s, p
        end
        if eink then
            -- Everything is already in place: draw what is left (the part not yet
            -- uncovered) with the same fast refresh, and let the caller skip the
            -- whole-page refresh that would only flash.
            ffi.copy(bb.data, new.data, size)
            local rest = {}
            if style == "blinds" then
                for k = 0, PAGE_ANIM_BLINDS - 1 do
                    local e0, e1 = edges[k], edges[k + 1]
                    local r = revealed(k, p)
                    if dir > 0 then rest[#rest + 1] = { e0, e1 - r - e0 }
                    else rest[#rest + 1] = { e0 + r, e1 - e0 - r } end
                end
            elseif dir > 0 then
                rest[1] = { 0, bw - prev_s }
            else
                rest[1] = { prev_s, bw - prev_s }
            end
            refreshStrips(rest)
        end
    end)
    setRot(rot) -- never leave the screen buffer unrotated, even after an error
    ffi.copy(bb.data, new.data, size) -- always leave the finished page behind
    if not ok then
        logger.warn("paperdots: page animation error", err)
        return false
    end
    if eink then return "done" end
    return true
end

local function pageAnimStyleName()
    for _idx, s in ipairs(PAGE_ANIM_STYLES) do
        if s.id == cfg.page_anim_style then return s.label end
    end
    return PAGE_ANIM_STYLES[1].label
end

local function pageAnimStyleItems()
    local items = {}
    for _idx, s in ipairs(PAGE_ANIM_STYLES) do
        local id = s.id
        items[#items + 1] = {
            text = s.label,
            radio = true,
            keep_menu_open = true,
            checked_func = function() return cfg.page_anim_style == id end,
            callback = function(inst)
                cfg.page_anim_style = id
                saveSettings()
                if inst then inst:updateItems() end
            end,
        }
    end
    return items
end

if not Screen._paper_dots_hooked then
    Screen._paper_dots_hooked = true
    local hooked = 0
    for _idx, base in ipairs(BASE_METHODS) do
        for _idx2, name in ipairs({ base, base .. "Imp" }) do
            local orig = Screen[name]
            if type(orig) == "function" then
                Screen[name] = function(self, x, y, w, h, ...)
                    if in_refresh then return orig(self, x, y, w, h, ...) end
                    in_refresh = true
                    local animated = false
                    if page_anim_pending then
                        page_anim_pending = false
                        local ok_a, res_a = pcall(pageAnimFrames, x, y, w, h)
                        if ok_a then
                            animated = res_a
                        else
                            logger.warn("paperdots: page animation error", res_a)
                        end
                    end
                    if refreshHookActive() and not animated then
                        local ok, err = pcall(applyDots, x, y, w, h)
                        if not ok then logger.warn("paperdots: error", err) end
                    end
                    if animated == "done" and not (name:find("Full") or name:find("Flash")) then
                        in_refresh = false
                        return -- the animation already drew the finished page
                    end                    
                    local target = orig
if not animated
    and name == "refreshPartialImp"
    and Margins and Margins.isActive()
    and Device:hasEinkScreen() and not isNightMode()
    and x == 0 and y == 0 and w == Screen:getWidth() and h == Screen:getHeight()
    and Screen.refreshUIImp then
    target = Screen.refreshUIImp -- same waveform the page animation uses
end
local ok2, a, b = pcall(target, self, x, y, w, h, ...)
                    in_refresh = false
                    if not ok2 then error(a, 0) end
                    return a, b
                end
                hooked = hooked + 1
            end
        end
    end
    logger.info("paperdots: hooked", hooked, "refresh functions")
end

-- dots are painted right after the page, so menus drawn later cover them
local ok_rv, ReaderView = pcall(require, "apps/reader/modules/readerview")
if ok_rv and type(ReaderView) == "table" and not ReaderView._paper_dots_hooked then
    ReaderView._paper_dots_hooked = true
    local orig_paintTo = ReaderView.paintTo
    ReaderView.paintTo = function(self, bb, x, y)
        if cfg.page_anim and bb == Screen.bb then
            local ok_p, page = pcall(function() return self.ui:getCurrentPage() end)
            if self.ui and self.ui.document ~= page_anim_last_doc then
                page_anim_last_doc = self.ui.document -- another book: no animation on its first page
                page_anim_last_page = nil
                page_anim_pending = false
            end
            local skip = (cfg.page_anim_skip_comics and pageAnimIsComic(self.ui and self.ui.document))
                or self.page_scroll or self.view_mode == "scroll"
            if ok_p and page and not skip then            
                if page_anim_last_page and page ~= page_anim_last_page then
                    local forward = page > page_anim_last_page
                    if self.inverse_reading_order then forward = not forward end
                    page_anim_dir = forward and 1 or -1
                    page_anim_pending = true
                    pageAnimSnapshot(bb) -- the screen still shows the old page
                end
                page_anim_last_page = page
            else
                page_anim_last_page = nil
            end
        end
        local res = orig_paintTo(self, bb, x, y)
        if cfg.enabled and cfg.book_only and cfg.hide_on_menus
            and not (cfg.hide_on_night and isNightMode()) and bb == Screen.bb then
            local ok, err = pcall(applyDots)
            if not ok then logger.warn("paperdots: error", err) end
        end
        return res
    end
    logger.info("paperdots: hooked ReaderView.paintTo")
end

-- Avoid rebuilding large pattern tables for unrelated toggles (enable,
-- visibility, fast-paint) or color-only changes.
local function onChanged(rebuild_pattern, rebuild_tint)
    if rebuild_tint then rebuildTint() end
    if rebuild_pattern then rebuild() end
    saveSettings()
    UIManager:setDirty("all", "full")
end

-- Plugin object
local PaperDots = WidgetContainer:extend{
    name = "paperdots",
    is_doc_only = false, -- also available from the file browser
}

function PaperDots:onDispatcherRegisterActions()
    Dispatcher:registerAction("paperdots", {
        category = "none",
        event = "PaperDotsToggle",
        title = _("Toggle paper dots"),
        general = true,
    })
    Dispatcher:registerAction("paperdots_page_anim", {
        category = "none",
        event = "PaperDotsTogglePageAnim",
        title = _("Toggle paper dots page animation"),
        general = true,
    })   
    Dispatcher:registerAction("paperdots_margins", {
        category = "none",
        event = "PaperDotsToggleMargins",
        title = _("Toggle paper dots margins"),
        general = true,
    }) 
end

function PaperDots:init()
    if self.ui and self.ui.document then
        active_reader = self
    end
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function PaperDots:onPaperDotsToggle()
    cfg.enabled = not cfg.enabled
    onChanged(false, false)
    return true
end

function PaperDots:onPaperDotsTogglePageAnim()
    setPageAnim(not cfg.page_anim)
    Notification:notify(cfg.page_anim and _("Page animation: on") or _("Page animation: off"))
    return true
end

function PaperDots:onPaperDotsToggleMargins()
    if not Margins then return true end
    local on = Margins.toggle()
    Notification:notify(on and _("Margins: on") or _("Margins: off"))
    return true
end

function PaperDots:onReaderReady()
    if Margins then Margins.attach(self.ui and self.ui.view) end
end

function PaperDots:onCloseDocument()
    if active_reader == self then active_reader = nil end
    if Margins then Margins.release() end
end

function PaperDots:onCloseWidget()
    if active_reader == self then active_reader = nil end
end

-- Menu
local function showSpin(touchmenu_instance, title, key, min, max, step, hold)
    local style = cfg.style
    UIManager:show(SpinWidget:new{
        title_text = title,
        value = cfg.styles[style][key],
        value_min = min,
        value_max = max,
        value_step = step,
        value_hold_step = hold,
        default_value = STYLE_DEFAULTS[style][key],
        ok_text = _("Set"),
        callback = function(spin)
            local s = cfg.styles[style]
            s[key] = spin.value
            if key == "dot_min" and s.dot_min > s.dot_max then
                s.dot_max = s.dot_min
            elseif key == "dot_max" and s.dot_max < s.dot_min then
                s.dot_min = s.dot_max
            end
            onChanged(true, false)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
end

-- grouped by look: dots, strokes, lines
local STYLE_LIST = {
    { id = "random", label = _("Random") },
    { id = "newsprint", label = _("Newsprint") },
    { id = "dotgrid", label = _("Dot grid"), separator = true },
    { id = "fibers", label = _("Fibers") },
    { id = "herringbone", label = _("Herringbone"), separator = true },
    { id = "linen", label = _("Linen") },
    { id = "crosshatch", label = _("Cross-hatch") },
    { id = "diagonal", label = _("Diagonal lines") },
    { id = "laid", label = _("Laid paper") },
}

local function styleName()
    for _idx, s in ipairs(STYLE_LIST) do
        if s.id == cfg.style then return s.label end
    end
    return _("Random")
end

local function styleItems()
    local items = {}
    for _idx, s in ipairs(STYLE_LIST) do
        local id = s.id
        items[#items + 1] = {
            text = s.label,
            radio = true,
            keep_menu_open = true,
            separator = s.separator,
            checked_func = function() return cfg.style == id end,
            callback = function(inst)
                cfg.style = id
                onChanged(true, false)
                if inst then inst:updateItems() end
            end,
        }
    end
    return items
end

local function tintName()
    if cfg.tint == "custom" then
        for _idx, tint in ipairs(CUSTOM_TINTS) do
            if tint.hex == cfg.custom_tint then
                return T(_("Custom: %1"), tint.label)
            end
        end
        return _("Custom color")
    end
    for _idx, t in ipairs(TINTS) do
        if t.id == cfg.tint then return t.label end
    end
    return _("Neutral grey")
end

local function showCustomTintDialog(touchmenu_instance)
    local buttons = {}
    local row = {}
    local dialog

    local function applyColor(tint)
        if dialog then UIManager:close(dialog) end
        cfg.custom_tint = tint.hex
        cfg.tint = "custom"
        onChanged(false, true)
        if touchmenu_instance then touchmenu_instance:updateItems() end
    end

    for index, tint in ipairs(CUSTOM_TINTS) do
        local selected_tint = tint
        local rgb = parseHexColor(selected_tint.hex)
        local background = Blitbuffer.ColorRGB32(
            math.floor(rgb[1] * 255 + 0.5),
            math.floor(rgb[2] * 255 + 0.5),
            math.floor(rgb[3] * 255 + 0.5),
            0xFF
        )

        row[#row + 1] = {
            text = selected_tint.label,
            background = background,
            callback = function()
                applyColor(selected_tint)
            end,
        }

        if #row == 4 or index == #CUSTOM_TINTS then
            buttons[#buttons + 1] = row
            row = {}
        end
    end

    buttons[#buttons + 1] = {
        {
            text = _("Cancel"),
            callback = function()
                if dialog then UIManager:close(dialog) end
            end,
        },
    }

    dialog = ButtonDialog:new{
        title = _("Choose a dot color"),
        width_factor = 0.92,
        colorful = true,
        buttons = buttons,
    }
    UIManager:show(dialog)
end

local function tintItems()
    local items = {}
    for _idx, t in ipairs(TINTS) do
        local id = t.id
        items[#items + 1] = {
            text = t.label,
            radio = true,
            keep_menu_open = true,
            checked_func = function() return cfg.tint == id end,
            callback = function(inst)
                cfg.tint = id
                onChanged(false, true)
                if inst then inst:updateItems() end
            end,
        }
    end
    items[#items + 1] = {
        text_func = function()
            if cfg.tint == "custom" then return tintName() end
            return _("Choose custom color…")
        end,
        radio = true,
        keep_menu_open = true,
        checked_func = function() return cfg.tint == "custom" end,
        callback = function(inst)
            showCustomTintDialog(inst)
        end,
    }
    return items
end

local function directionName()
    return S().direction == "backslash" and "\\" or "/"
end

local function directionItems()
    return {
        {
            text = "/",
            radio = true,
            keep_menu_open = true,
            checked_func = function() return S().direction ~= "backslash" end,
            callback = function(inst)
                S().direction = "slash"
                onChanged(true, false)
                if inst then inst:updateItems() end
            end,
        },
        {
            text = "\\",
            radio = true,
            keep_menu_open = true,
            checked_func = function() return S().direction == "backslash" end,
            callback = function(inst)
                S().direction = "backslash"
                onChanged(true, false)
                if inst then inst:updateItems() end
            end,
        },
    }
end

local function visibilityItems()
    return {
        {
            text = _("Only inside books"),
            help_text = _("Dots are only drawn while a book is open, not in the file browser or other screens."),
            checked_func = function() return cfg.book_only end,
            callback = function()
                cfg.book_only = not cfg.book_only
                onChanged(false, false)
            end,
        },
        {
            text = _("Hide dots on menus"),
            help_text = _("Keeps dots on the book page only, without dots on menus and dialogs shown over it. Requires 'Only inside books'."),
            enabled_func = function() return cfg.book_only end,
            checked_func = function() return cfg.hide_on_menus end,
            callback = function()
                cfg.hide_on_menus = not cfg.hide_on_menus
                onChanged(false, false)
            end,
        },
        {
            text = _("Disable in night/dark mode"),
            help_text = _("Turns dots off automatically while night mode is on. Detection may not work on every KOReader version."),
            checked_func = function() return cfg.hide_on_night end,
            callback = function()
                cfg.hide_on_night = not cfg.hide_on_night
                onChanged(false, false)
            end,
        },
    }
end

local function advancedItems()
    return {
        {
            text = _("Fast painting"),
            help_text = _("Writes pixels straight into the screen buffer instead of going through one KOReader call per pixel, which can be much faster. On by default on screens that support it and unavailable on the rest. It checks itself on first use and falls back automatically if something is off. Turn it off if dots look wrong."),
            enabled_func = function() return fastSupported() end,
            checked_func = function() return fastSupported() and not cfg.fast_paint_disabled end,
            callback = function()
                cfg.fast_paint_disabled = not cfg.fast_paint_disabled
                -- forget earlier failures so the option is tried again
                fast_disabled = false
                fast_addr = nil
                onChanged(false, false)
            end,
        },
    }
end

function PaperDots:addToMainMenu(menu_items)
    -- reader menu tabs: navi, typeset, setting, tools, search, filemanager, main
    -- file browser menu tabs: filemanager_settings, setting, tools, search, plus_menu, main
    local hint = (self.ui and self.ui.document) and "typeset" or "filemanager_settings"

    menu_items.paper_dots = {
        text = _("Paper dots"),
        sorting_hint = hint,
        sub_item_table = {
            {
                text = _("Enable"),
                checked_func = function() return cfg.enabled end,
                callback = function()
                    cfg.enabled = not cfg.enabled
                    onChanged(false, false)
                end,
                separator = true,
            },

            -- current style and its settings
            {
                text_func = function() return T(_("Style: %1"), styleName()) end,
                help_text = _("Density, size, and shades are saved separately for each style."),
                sub_item_table = styleItems(),
            },
            {
                text_func = function() return T(_("%1 settings"), styleName()) end,
                sub_item_table = {
                    {
                        text_func = function() return T(_("Density: %1%"), S().density) end,
                        keep_menu_open = true,
                        callback = function(inst)
                            showSpin(inst, _("Density (% of pixels)"), "density", 1, 30, 1, 5)
                        end,
                    },
                    {
                        text_func = function() return T(_("Dot size: %1 px"), S().dot_size) end,
                        keep_menu_open = true,
                        callback = function(inst)
                            showSpin(inst, _("Dot size / line thickness (px)"), "dot_size", 1, 4, 1, 1)
                        end,
                    },
                    {
                        text_func = function() return T(_("Fiber length: %1 px"), S().fiber_length or 0) end,
                        enabled_func = function() return cfg.style == "fibers" end,
                        keep_menu_open = true,
                        callback = function(inst)
                            showSpin(inst, _("Longest fiber (px)"), "fiber_length", 3, 20, 1, 5)
                        end,
                    },
                    {
                        text_func = function() return T(_("Direction: %1"), directionName()) end,
                        enabled_func = function() return cfg.style == "diagonal" end,
                        sub_item_table = directionItems(),
                    },
                    {
                        text_func = function() return T(_("Darkest dot: %1"), S().dot_min) end,
                        keep_menu_open = true,
                        callback = function(inst)
                            showSpin(inst, _("Darkest shade (0 = black)"), "dot_min", 0, 239, 8, 32)
                        end,
                    },
                    {
                        text_func = function() return T(_("Lightest dot: %1"), S().dot_max) end,
                        keep_menu_open = true,
                        callback = function(inst)
                            showSpin(inst, _("Lightest shade"), "dot_max", 0, 239, 8, 32)
                        end,
                    },
                    {
                        text = _("Reset this style to defaults"),
                        keep_menu_open = true,
                        callback = function(inst)
                            cfg.styles[cfg.style] = copy(STYLE_DEFAULTS[cfg.style])
                            onChanged(true, false)
                            if inst then inst:updateItems() end
                        end,
                        separator = true,
                    },
                },
            },
            {
                is_tint_menu = true, -- removed below on grayscale screens
                text_func = function() return T(_("Tint: %1"), tintName()) end,
                help_text = _("Choose Neutral grey or a color from the visual palette. Dot luminance is preserved."),
                sub_item_table = tintItems(),
            },
            {
                text = _("Page turn animation"),
                sub_item_table = {
                    {
                        text = _("Animate page turns"),
                        help_text = _("Shows a quick transition when the page changes, moving toward the side you turned to, so you can tell going forward from going back."),
                        checked_func = function() return cfg.page_anim end,
                        callback = function() setPageAnim(not cfg.page_anim) end,
                        separator = true,
                    },
                    {
                        text = _("Not in comics / manga"),
                        help_text = _("Turns the animation off for comic and manga archives (CBZ, CBR, CB7, CBT)."),
                        checked_func = function() return cfg.page_anim_skip_comics end,
                        callback = function()
                            cfg.page_anim_skip_comics = not cfg.page_anim_skip_comics
                            page_anim_last_page = nil
                            page_anim_pending = false
                            saveSettings()
                        end,
                    },
                    {
                        text_func = function() return T(_("Style: %1"), pageAnimStyleName()) end,
                        sub_item_table = pageAnimStyleItems(),
                    },
                    {
                        text_func = function() return T(_("Steps: %1"), cfg.page_anim_steps) end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            UIManager:show(SpinWidget:new{
                                title_text = _("Animation steps"),
                                value = cfg.page_anim_steps,
                                value_min = 1,
                                value_max = PAGE_ANIM_MAX_STEPS,
                                value_step = 1,
                                default_value = PAGE_ANIM_DEFAULT_STEPS,
                                ok_text = _("Set"),
                                callback = function(spin)
                                    cfg.page_anim_steps = spin.value
                                    saveSettings()
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end,
                            })
                        end,
                    },
                },
            },

            -- set-and-forget options
            {
                text = _("Where to show dots"),
                sub_item_table = visibilityItems(),
            },
            {
                text = _("Advanced"),
                sub_item_table = advancedItems(),
            },
        },
    }

    if Margins and self.ui and self.ui.document then
        local items = menu_items.paper_dots.sub_item_table
        table.insert(items, #items - 1, Margins.menuItem())
    end    
    
    if not HAS_COLOR then
        local items = menu_items.paper_dots.sub_item_table
        for i = #items, 1, -1 do
            if items[i].is_tint_menu then table.remove(items, i) end
        end
    end
end

return PaperDots