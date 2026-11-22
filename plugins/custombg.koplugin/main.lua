-- custombg.koplugin/main.lua
-- Full version: native background + per-document settings + global default

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local ReaderRolling = require("apps/reader/modules/readerrolling")
local InfoMessage = require("ui/widget/infomessage")
local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local SpinWidget = require("ui/widget/spinwidget")
local ConfirmBox = require("ui/widget/confirmbox")
local InputDialog = require("ui/widget/inputdialog")
local Size = require("ui/size")
local Screen = require("device").screen
local bit = require("bit")
local T = require("ffi/util").template

-- ======================================================================
-- Own settings file: <koreader>/settings/custombg.lua
-- Every setting of this plugin lives here, NOT in settings.reader.lua and NOT in the book sidecar.
-- ======================================================================
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local _cfg_store = LuaSettings:open(DataStorage:getSettingsDir() .. "/custombg.lua")
local CFG = {
    readSetting = function(_, key) return _cfg_store:readSetting(key) end,
    saveSetting = function(_, key, value)
        _cfg_store:saveSetting(key, value)
        pcall(function() _cfg_store:flush() end)
    end,
    flush = function() pcall(function() _cfg_store:flush() end) end,
}

-- One-time migration: move keys that older versions wrote into the global KOReader settings into the own file
-- (the value is copied only if the own file does not have it yet, then removed from the global settings).
do
    local function is_ours(k)
        return type(k) == "string" and (k:sub(1, 9) == "custombg_" or k:sub(1, 13) == "custom_bg_see"
            or k:sub(1, 9) == "fs_lines_" or k:sub(1, 9) == "fs_style_" or k == "fs_double_gap")
    end
    local gs = rawget(_G, "G_reader_settings")
    if gs and type(gs.data) == "table" then
        local moved = {}
        for k in pairs(gs.data) do
            if is_ours(k) then moved[#moved + 1] = k end
        end
        if #moved > 0 then
            for _, k in ipairs(moved) do
                if _cfg_store:readSetting(k) == nil then
                    _cfg_store:saveSetting(k, gs:readSetting(k))
                end
                gs:saveSetting(k, nil)
            end
            pcall(function() _cfg_store:flush() end)
            pcall(function() gs:flush() end)
        end
    end
end

-- ======================================================================
-- Custom background + ruled (stationery) horizontal/vertical lines (native background edition + global default)
-- ======================================================================
local CustomBg = WidgetContainer:extend{
    name = "custombg",
    is_doc_only = false,
    cache_day = nil,
    cache_night = nil,
    scanning = false,
    hooked_readerrolling = false,
    pending_bg_name = nil,
    pending_bg_color = nil,
    color_cache = {},
    fs_enabled = false,
    fs_line_direction = 1,
    fs_v_font_enable = true,
    fs_v_font_family = "FZKai-Z03",
    fs_offset_y = 2,
    fs_auto_offset = true,    -- centre the line in the inter-line gap, computed from the current font/layout
    fs_offset_adjust = 0,     -- manual fine-tune added on top of the automatic offset
    fs_offset_bias = 0,       -- auto-centre: extra downward shift, in % of the line box height
    fs_show_top_line = true,
    fs_is_dashed = false,
    fs_color_depth = 5,
    fs_dash_len = 10,
    fs_line_mode = 1,
    fs_width_ratio = 1000,
    fs_extend_px = 5,
    fs_gap_threshold = 2.5,
    fs_skip_titles = false,
    fs_title_threshold = 1.05,
    _fs_patched = false,
    fs_wave_mode = 0,
    fs_style_dash_dot = true,    -- default line style: long solid + dashed
    fs_style_heart_dash = false,
    fs_style_double_solid = false,
    fs_style_double_dash = false,
    fs_double_gap = 2,
    _last_night_mode = nil,
    _night_check_timer = nil,
    _bg_reapply_timer = nil,
    _bg_last_sw = nil,
    _bg_last_sh = nil,
}

-- ==================== Background features ====================
local BG_SCENE_KEY = "custombg_scene_mode"
local BG_LAST_USED_KEY = "custombg_last_used"
local BG_SEEN_FLAG_KEY = "custom_bg_seen_flag"
local DOC_BG_DAY = "custombg_day"
local DOC_BG_NIGHT = "custombg_night"
local SCENE_DAY = "day"
local SCENE_NIGHT = "night"
-- Separate global-default background keys for day/night (fix: the old single key left night mode with no default)
local GLOBAL_DEFAULT_BG_DAY_KEY = "custombg_global_default_bg_day"
local GLOBAL_DEFAULT_BG_NIGHT_KEY = "custombg_global_default_bg_night"
-- Compatibility with the legacy single default key
local GLOBAL_DEFAULT_BG_KEY = "custombg_global_default_bg"
local DOC_BG_NONE = ""                                       -- means explicitly no background
local DOC_BG_GLOBAL = "@global"                              -- this book explicitly uses the global default background
local NOFLASH_KEY = "custombg_noflash"                       -- avoid full-screen flashing on page turns while a background is shown (default: on)
local PAGE_REFRESH_KEY = "custombg_page_refresh"             -- page turns with a background: "ui" (default, no flash) / "partial" (crisper text)
local NODITHER_KEY = "custombg_no_dither"                     -- turn KOReader's software dithering off while a background is shown (default: OFF; only has an effect while a background is shown)
local SWIPE_ANIM_KEY = "custombg_swipe_anim"                -- Kindle page-turn animation while a background is shown: "keep" (default) / "off"
local TOGGLE_WITH_BG_KEY = "custombg_toggle_with_background"   -- the lines gesture (pagetextinfo) also switches the background: true (default) / false = lines only

local FS_KEYS = {
    enabled = "fs_lines_enabled",
    direction = "fs_lines_direction",
    v_font_enable = "fs_lines_v_font_enable",
    v_font_family = "fs_lines_v_font_family",
    offset_y = "fs_lines_offset_y",
    auto_offset = "fs_lines_auto_offset",
    offset_adjust = "fs_lines_offset_adjust",
    offset_bias = "fs_lines_offset_bias",
    show_top = "fs_lines_show_top",
    dashed = "fs_lines_dashed",
    color_depth = "fs_lines_color_depth",
    dash_len = "fs_lines_dash_len",
    mode = "fs_lines_mode",
    width_ratio = "fs_lines_width_ratio",
    extend = "fs_lines_extend",
    gap_threshold = "fs_lines_gap_threshold",
    skip_titles = "fs_lines_skip_titles",
    title_threshold = "fs_lines_title_threshold",
    wave_mode = "fs_lines_wave_mode",
    style_dash_dot = "fs_style_dash_dot",
    style_heart_dash = "fs_style_heart_dash",
    style_double_solid = "fs_style_double_solid",
    style_double_dash = "fs_style_double_dash",
    double_gap = "fs_double_gap",
}

-- Path hash (djb2): maps paths containing Chinese/special characters to a unique cache name, avoiding name collisions
local function hashString(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + string.byte(s, i)) % 2147483648
    end
    return string.format("%x", h)
end

local function getPluginDir()
    local info = debug.getinfo(1, "S")
    local script_path = info.source:sub(2)
    return script_path:match("(.*/)")
end

local function getBackgroundsFolder()
    local plugin_dir = getPluginDir()
    local candidates = {
        plugin_dir .. "../backgrounds/",
        plugin_dir .. "backgrounds/",
        "/mnt/onboard/.adds/koreader/backgrounds/",
        "/mnt/us/koreader/backgrounds/",
    }
    for _, path in ipairs(candidates) do
        local attr = lfs.attributes(path)
        if attr and attr.mode == "directory" then return path end
    end
    local default = plugin_dir .. "backgrounds/"
    pcall(function() lfs.mkdir(default) end)
    return default
end

local function getCacheDir()
    local dir = getPluginDir() .. "cache/"
    pcall(function() lfs.mkdir(dir) end)
    return dir
end

-- Speed: on a grayscale e-ink screen (Kindle Paperwhite etc.) the background is stored as an 8-bit grayscale PNG.
-- crengine decodes/blits this image on every page paint; an RGB image is ~3x more data to decode and convert for nothing.
-- Only done when the screen is positively known to be grayscale; colour screens keep the old behaviour.
local function isGrayscaleScreen()
    local ok, is_color = pcall(function()
        if type(Screen.isColorScreen) == "function" then return Screen:isColorScreen() end
        if type(Device.hasColorScreen) == "function" then return Device:hasColorScreen() end
        return nil
    end)
    return ok and is_color == false
end

-- Returns a new 8-bit grayscale copy of bb and frees bb. On any failure returns bb unchanged.
local function toGrayscaleBB(bb)
    local ok, gray = pcall(function()
        local g = Blitbuffer.new(bb:getWidth(), bb:getHeight(), Blitbuffer.TYPE_BB8)
        g:fill(Blitbuffer.COLOR_WHITE)   -- transparent areas of the source end up white, not black
        g:blitFrom(bb, 0, 0, 0, 0, bb:getWidth(), bb:getHeight())
        return g
    end)
    if ok and gray then
        bb:free()
        return gray
    end
    return bb
end

-- Cache file tag: grayscale caches get their own name, so old RGB caches are never reused (and vice versa)
local function bgCacheTag()
    return isGrayscaleScreen() and "g8_" or ""
end

local function getScaledPath(source_path)
    if not source_path or source_path == "" then return nil end
    local screen_w = Device.screen:getWidth()
    local screen_h = Device.screen:getHeight()
    -- Fix: the original implementation used gsub("[^%w%.%-]","_"), which replaced every multi-byte character (e.g. Chinese) with "_",
    -- so images with different names got the same cache filename, hit the same cache and showed each other's picture.
    -- Now the full path is hashed, so each source file gets a unique cache entry (also distinguished by screen resolution).
    local cache_name = hashString(source_path)
    local cache_path = getCacheDir() .. string.format("%s%dx%d_%s.png", bgCacheTag(), screen_w, screen_h, cache_name)
    do
        local cattr = lfs.attributes(cache_path)
        if cattr and cattr.mode == "file" and (cattr.size or 0) > 1024 then
            return cache_path
        end
    end
    local success, result = pcall(function()
        local RenderImage = require("ui/renderimage")
        local src_bb = RenderImage:renderImageFile(source_path, false, nil, nil)
        if not src_bb then return nil end
        local final_bb
        if src_bb:getWidth() == screen_w and src_bb:getHeight() == screen_h then
            final_bb = src_bb:copy()
        else
            final_bb = RenderImage:scaleBlitBuffer(src_bb, screen_w, screen_h, true)
        end
        src_bb:free()
        if not final_bb then return nil end
        if isGrayscaleScreen() then final_bb = toGrayscaleBB(final_bb) end
        if final_bb:writeToFile(cache_path, "png", 75) then
            final_bb:free()
            return cache_path
        else
            final_bb:free()
            return nil
        end
    end)
    if success and result then
        return result
    else
        return source_path
    end
end

-- Background cache used in pseudo-vertical mode (engine rotation patch active).
-- The engine viewport is swapped to (screen_h × screen_w) and the whole page is rotated by -90° to fit the screen,
-- so the background image handed to crengine must be "inversely pre-rotated" by 90°, otherwise it ends up lying sideways/distorted after rotation.
-- Derivation: screen pixel (sx,sy) is actually taken from engine viewport pixel (sy, screen_w-1-sx),
--       so the image F the engine needs satisfies F[i][j] = S[screen_w-1-j][i],
--       i.e. the screen image S rotated 90° counter-clockwise, which is exactly the result of Blitbuffer:rotatedCopy(90)
--       (verified: both the C and Lua blit paths of blitbuffer remap coordinates according to rotation).
local function getRotatedScaledPath(source_path)
    if not source_path or source_path == "" then return nil end
    local screen_w = Device.screen:getWidth()
    local screen_h = Device.screen:getHeight()
    local cache_path = getCacheDir() .. string.format("rot90_%s%dx%d_%s.png",
        bgCacheTag(), screen_w, screen_h, hashString(source_path))
    do
        local cattr = lfs.attributes(cache_path)
        if cattr and cattr.mode == "file" and (cattr.size or 0) > 1024 then
            return cache_path
        end
    end
    local success, result = pcall(function()
        local RenderImage = require("ui/renderimage")
        local src_bb = RenderImage:renderImageFile(source_path, false, nil, nil)
        if not src_bb then return nil end
        local base_bb
        if src_bb:getWidth() == screen_w and src_bb:getHeight() == screen_h then
            base_bb = src_bb:copy()
        else
            base_bb = RenderImage:scaleBlitBuffer(src_bb, screen_w, screen_h, true)
        end
        src_bb:free()
        if not base_bb then return nil end
        if isGrayscaleScreen() then base_bb = toGrayscaleBB(base_bb) end
        local rot_bb = nil
        if type(base_bb.rotatedCopy) == "function" then
            rot_bb = base_bb:rotatedCopy(90)
        end
        base_bb:free()
        if not rot_bb then return nil end
        local out = nil
        if rot_bb:writeToFile(cache_path, "png", 75) then out = cache_path end
        rot_bb:free()
        return out
    end)
    if success and result then
        return result
    else
        return source_path
    end
end

-- Choose the normal cache or the pre-rotated cache depending on whether the engine has been rotated
function CustomBg:getBgScaledPath(source_path)
    local doc = self.ui and self.ui.document
    if doc and doc._is_rotated_by_plugin then
        return getRotatedScaledPath(source_path)
    end
    return getScaledPath(source_path)
end

-- ======================================================================
-- Overlay ("pieces") mode
-- Instead of handing a full-screen image to crengine (which then treats the WHOLE page as "an image": dithering,
-- ghosting, flashing refreshes), the image is analysed once and only the parts that really contain something are kept:
--   * a picture at the bottom (or top / a corner)  -> ONE small piece
--   * a frame / border                              -> up to 4 thin strips around an empty centre
-- The pieces are 8-bit gray + alpha buffers (transparent where the image is just background), stored in a small cache file
-- and blitted by paintTo() over the page, after the text. The page itself stays a normal black-and-white text page.
-- If an image has too much content (a real full-page picture) the classic full-page background is used for it.
-- ======================================================================
local ffi = require("ffi")
local OVERLAY_KEY = "custombg_overlay"       -- true = pieces mode, default OFF (classic full-page background)
local OVERLAY_MAX_AREA = 0.45                -- more than this fraction of the screen covered by pieces -> classic background
local OVERLAY_TOL = 12                       -- gray difference from the image background that still counts as "background"

local function isOverlayMode()
    return CFG:readSetting(OVERLAY_KEY) == true
end

local function overlayCachePath(source_path)
    return getCacheDir() .. string.format("ovl2_%dx%d_%s.bin", Screen:getWidth(), Screen:getHeight(), hashString(source_path))
end

-- Returns a list of pieces { bb = BB8A, x, y, w, h }, an empty list (image is blank), or false (use the classic background)
local function buildOverlayPieces(source_path)
    local W, H = Screen:getWidth(), Screen:getHeight()
    local scaled = getScaledPath(source_path)
    if not scaled then return false, "no scaled image" end
    local RenderImage = require("ui/renderimage")
    local src = RenderImage:renderImageFile(scaled, false, nil, nil)
    if not src then return false, "image could not be decoded" end
    if src:getWidth() ~= W or src:getHeight() ~= H then
        local sc = RenderImage:scaleBlitBuffer(src, W, H, true)
        src:free()
        src = sc
        if not src then return false, "scaling failed" end
    end
    local gray = Blitbuffer.new(W, H, Blitbuffer.TYPE_BB8)
    gray:fill(Blitbuffer.COLOR_WHITE)
    gray:blitFrom(src, 0, 0, 0, 0, W, H)
    src:free()

    local gp = ffi.cast("uint8_t*", gray.data)
    local stride = tonumber(gray.stride)

    -- Background value of the image: median of the four corners
    local corners = { gp[0], gp[W - 1], gp[(H - 1) * stride], gp[(H - 1) * stride + W - 1] }
    table.sort(corners)
    local bg = corners[2]

    -- Tight bounding box of the content inside [x0,x1) x [y0,y1); returns nil when there is none. Max values are exclusive.
    local function contentBBox(x0, y0, x1, y1)
        if x1 <= x0 or y1 <= y0 then return nil end
        local minx, miny, maxx, maxy = x1, y1, x0 - 1, y0 - 1
        for y = y0, y1 - 1 do
            local row = y * stride
            for x = x0, x1 - 1 do
                local d = gp[row + x] - bg
                if d < 0 then d = -d end
                if d > OVERLAY_TOL then
                    if x < minx then minx = x end
                    if x > maxx then maxx = x end
                    if y < miny then miny = y end
                    maxy = y
                end
            end
        end
        if maxx < minx or maxy < miny then return nil end
        return minx, miny, maxx + 1, maxy + 1
    end

    local pieces_rects = {}
    local bx0, by0, bx1, by1 = contentBBox(0, 0, W, H)
    if not bx0 then
        gray:free()
        return {}
    end
    if (bx1 - bx0) * (by1 - by0) <= OVERLAY_MAX_AREA * W * H then
        -- one compact picture (e.g. characters at the bottom of the page)
        pieces_rects[1] = { bx0, by0, bx1, by1 }
    else
        -- spread over the page (frame / border): grow an empty rectangle from the centre, keep what is outside of it
        local function isContent(x, y)
            local d = gp[y * stride + x] - bg
            if d < 0 then d = -d end
            return d > OVERLAY_TOL
        end
        local function rowEmpty(y, x0, x1)
            local row = y * stride
            for x = x0, x1 - 1 do
                local d = gp[row + x] - bg
                if d < 0 then d = -d end
                if d > OVERLAY_TOL then return false end
            end
            return true
        end
        local function colEmpty(x, y0, y1)
            for y = y0, y1 - 1 do
                local d = gp[y * stride + x] - bg
                if d < 0 then d = -d end
                if d > OVERLAY_TOL then return false end
            end
            return true
        end
        local cx, cy = math.floor(W / 2), math.floor(H / 2)
        if isContent(cx, cy) then
            gray:free()
            return false, "centre of the image is not empty (full-page picture)"
        end
        local hx0, hy0, hx1, hy1 = cx, cy, cx + 1, cy + 1
        local moved = true
        while moved do
            moved = false
            if hy0 > 0 and rowEmpty(hy0 - 1, hx0, hx1) then hy0 = hy0 - 1; moved = true end
            if hy1 < H and rowEmpty(hy1, hx0, hx1) then hy1 = hy1 + 1; moved = true end
            if hx0 > 0 and colEmpty(hx0 - 1, hy0, hy1) then hx0 = hx0 - 1; moved = true end
            if hx1 < W and colEmpty(hx1, hy0, hy1) then hx1 = hx1 + 1; moved = true end
        end
        local strips = {
            { 0, 0, W, hy0 },        -- top
            { 0, hy1, W, H },        -- bottom
            { 0, hy0, hx0, hy1 },    -- left
            { hx1, hy0, W, hy1 },    -- right
        }
        for _, s in ipairs(strips) do
            local a, b, c, d = contentBBox(s[1], s[2], s[3], s[4])
            if a then pieces_rects[#pieces_rects + 1] = { a, b, c, d } end
        end
    end

    local area = 0
    for _, r in ipairs(pieces_rects) do area = area + (r[3] - r[1]) * (r[4] - r[2]) end
    if area > OVERLAY_MAX_AREA * W * H then
        gray:free()
        return false, string.format("pieces cover %d%% of the screen (limit %d%%)", math.floor(area * 100 / (W * H)), math.floor(OVERLAY_MAX_AREA * 100))
    end

    local pieces = {}
    for _, r in ipairs(pieces_rects) do
        local x0, y0, x1, y1 = r[1], r[2], r[3], r[4]
        local w, h = x1 - x0, y1 - y0
        local pb = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8A, nil, w * 2, w)
        local pstride = tonumber(pb.stride)
        ffi.fill(pb.data, pstride * h, 0)           -- everything transparent
        -- NOTE: for a BB8A buffer `data` is an array of Color8A structs, not bytes: write through a byte pointer
        local pp = ffi.cast("uint8_t*", pb.data)
        for y = 0, h - 1 do
            local srow = (y0 + y) * stride + x0
            local drow = y * pstride
            for x = 0, w - 1 do
                local v = gp[srow + x]
                local d = v - bg
                if d < 0 then d = -d end
                if d > OVERLAY_TOL then
                    pp[drow + 2 * x] = v
                    pp[drow + 2 * x + 1] = 255
                end
            end
        end
        pieces[#pieces + 1] = { bb = pb, x = x0, y = y0, w = w, h = h }
    end
    gray:free()
    return pieces
end

local function saveOverlayCache(path, pieces, why)
    local f = io.open(path, "wb")
    if not f then return end
    if pieces == false then
        f:write("FALLBACK " .. tostring(why):gsub("\n", " ") .. "\n")
    else
        f:write(string.format("%d\n", #pieces))
        for _, p in ipairs(pieces) do
            f:write(string.format("%d %d %d %d\n", p.x, p.y, p.w, p.h))
            f:write(ffi.string(p.bb.data, tonumber(p.bb.stride) * p.h))
        end
    end
    f:close()
end

-- Returns pieces (list, maybe empty) or false (classic background)
local function loadOverlayPieces(source_path)
    local path = overlayCachePath(source_path)
    local f = io.open(path, "rb")
    if f then
        local ok, res, err = pcall(function()
            local head = f:read("*l")
            if head and head:sub(1, 8) == "FALLBACK" then return false, "cached: " .. head:sub(10) end
            local n = tonumber(head)
            if not n then error("bad overlay cache") end
            local pieces = {}
            for i = 1, n do
                local line = f:read("*l")
                local x, y, w, h = line:match("^(%d+) (%d+) (%d+) (%d+)$")
                x, y, w, h = tonumber(x), tonumber(y), tonumber(w), tonumber(h)
                if not (x and y and w and h) then error("bad overlay cache entry") end
                local bytes = f:read(w * 2 * h)
                if not bytes or #bytes ~= w * 2 * h then error("short overlay cache") end
                local pb = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8A, nil, w * 2, w)
                ffi.copy(pb.data, bytes, #bytes)
                pieces[i] = { bb = pb, x = x, y = y, w = w, h = h }
            end
            return pieces
        end)
        f:close()
        if ok then return res, err end
        pcall(os.remove, path)   -- damaged cache: rebuild
    end
    local ok, pieces, why = pcall(buildOverlayPieces, source_path)
    if not ok then
        logger.warn("CustomBg: overlay build failed: " .. tostring(pieces))
        return false, "ERROR " .. tostring(pieces)
    end
    pcall(saveOverlayCache, path, pieces, why)
    return pieces, why
end

function CustomBg:_freeOverlay()
    if self._overlay then
        for _, p in ipairs(self._overlay) do
            pcall(function() p.bb:free() end)
        end
    end
    self._overlay = nil
end

-- Returns true when the pieces took over (the crengine background must then stay empty)
function CustomBg:_setOverlay(source_path)
    self:_freeOverlay()
    if not isOverlayMode() then self._overlay_info = "option is OFF"; return false end
    if not source_path then self._overlay_info = "no image"; return false end
    local ok, pieces, why = pcall(loadOverlayPieces, source_path)
    if not ok then self._overlay_info = "ERROR " .. tostring(pieces); return false end
    if pieces == false or pieces == nil then self._overlay_info = "classic background: " .. tostring(why); return false end
    local parts = {}
    for _, p in ipairs(pieces) do parts[#parts + 1] = string.format("%dx%d@%d,%d", p.w, p.h, p.x, p.y) end
    self._overlay_info = "ON, " .. #pieces .. " piece(s): " .. table.concat(parts, " ")
    self._overlay = pieces
    return true
end

function CustomBg:_paintOverlay(bb, x, y)
    local ov = self._overlay
    if not ov then return end
    for _, p in ipairs(ov) do
        pcall(bb.alphablitFrom, bb, p.bb, (x or 0) + p.x, (y or 0) + p.y, 0, 0, p.w, p.h)
    end
end

local function loadImageList(folder, scene_mode)
    local images = {}
    local attr_root = lfs.attributes(folder)
    if not attr_root or attr_root.mode ~= "directory" then
        return images
    end
    local ext_whitelist = {jpg=true, jpeg=true, png=true, webp=true, bmp=true, gif=true}
    for entry in lfs.dir(folder) do
        if entry ~= "." and entry ~= ".." then
            local fullpath = folder .. entry
            local attr = lfs.attributes(fullpath)
            if attr and attr.mode == "file" then
                local ext = entry:match("%.([^%.]+)$")
                if ext then
                    ext = ext:lower()
                    if ext_whitelist[ext] then
                        local base_name = entry:match("^(.-)%.[^.]+$")
                        if base_name and base_name ~= "" then
                            local is_night_suffix = base_name:sub(-6) == "-night"
                            local display_name
                            if scene_mode == SCENE_NIGHT then
                                if not is_night_suffix then goto continue end
                                display_name = base_name:sub(1, -7)
                            else
                                if is_night_suffix then goto continue end
                                display_name = base_name
                            end
                            images[display_name] = fullpath
                        end
                    end
                end
                ::continue::
            end
        end
    end
    local count = 0
    for _ in pairs(images) do count = count + 1 end
    return images
end

-- Backgrounds are listed in the order of their numeric filename prefix (01_..., 02_..., 10_...),
-- compared as NUMBERS (so 2 comes before 10 even without zero padding), and then alphabetically (case-insensitive).
-- Names without a numeric prefix go after the numbered ones, also in alphabetical order.
-- (The old "most recently used first" order is no longer applied; used_time is kept only for compatibility.)
function CustomBg:sortBgNameList(names, scene, used_time)
    local function parse(name)
        local digits, rest = name:match("^(%d+)[%s_%-%.]*(.*)$")
        if digits then
            return tonumber(digits), (rest or ""):lower(), name:lower()
        end
        return nil, name:lower(), name:lower()
    end
    table.sort(names, function(a, b)
        local na, ra, la = parse(a)
        local nb, rb, lb = parse(b)
        if na and nb then
            if na ~= nb then return na < nb end
            if ra ~= rb then return ra < rb end
            return la < lb
        elseif na then
            return true      -- numbered before non-numbered
        elseif nb then
            return false
        end
        if ra ~= rb then return ra < rb end
        return la < lb
    end)
end

function CustomBg:getCurrentImageCache()
    local scene = self:getSceneMode()
    return scene == SCENE_DAY and (self.cache_day or {}) or (self.cache_night or {})
end

function CustomBg:getUsageKey(name)
    local scene = self:getSceneMode()
    return scene == SCENE_NIGHT and name.."@night" or name
end

function CustomBg:getAllSeenFlag()
    local ok, data = pcall(function() return CFG:readSetting(BG_SEEN_FLAG_KEY) or {} end)
    return ok and data or {}
end

function CustomBg:markImageSeen(name)
    if not name then return end
    local flag_data = self:getAllSeenFlag()
    flag_data[self:getUsageKey(name)] = true
    CFG:saveSetting(BG_SEEN_FLAG_KEY, flag_data)
end

function CustomBg:isNewImage(name)
    return not self:getAllSeenFlag()[self:getUsageKey(name)]
end

function CustomBg:getSceneMode()
    local saved = CFG:readSetting(BG_SCENE_KEY)
    return (saved == SCENE_DAY or saved == SCENE_NIGHT) and saved or SCENE_DAY
end

-- Get the background used by the current document (document setting first; if unset, the global default; if there is no global default, nil)
function CustomBg:getCurrentDocBg()
    local val = self:readBgChoice()
    if val == nil then
        -- No choice stored yet: background OFF (it is only shown after the toggle is turned on)
        return nil
    elseif val == DOC_BG_GLOBAL then
        -- Book follows the global background: the selected global image, otherwise a random one
        local g = self:getGlobalDefaultBg()
        if g and g ~= "" and self:getCurrentImageCache()[g] then return g end
        return self:getRandomBg()
    elseif val == DOC_BG_NONE then
        return nil  -- explicitly no background
    else
        return val
    end
end

-- Random background (used when the book follows the global background but no global image is selected).
-- Chosen once per session and per day/night mode, so it does not change on every repaint.
function CustomBg:getRandomBg()
    local imgs = self:getCurrentImageCache()
    local scene = self:getSceneMode()
    if self._rand_bg and self._rand_bg_scene == scene and imgs[self._rand_bg] then
        return self._rand_bg
    end
    local names = {}
    for n in pairs(imgs) do names[#names + 1] = n end
    if #names == 0 then return nil end
    table.sort(names)
    if not self._rand_seeded then
        math.randomseed(os.time())
        self._rand_seeded = true
    end
    self._rand_bg = names[math.random(#names)]
    self._rand_bg_scene = scene
    return self._rand_bg
end

-- Save the document background setting; name=nil clears it (follow global), name="" means no background
function CustomBg:saveDocBg(name)
    local key = self:getSceneMode() == SCENE_DAY and DOC_BG_DAY or DOC_BG_NIGHT
    CFG:saveSetting(key, name)   -- nil clears it
    pcall(function() CFG:flush() end)
end

function CustomBg:getAllLastUsed()
    local ok, data = pcall(function() return CFG:readSetting(BG_LAST_USED_KEY) or {} end)
    return ok and data or {}
end

function CustomBg:setLastUsed(name)
    if not name then return end
    local used_data = self:getAllLastUsed()
    used_data[self:getUsageKey(name)] = os.time()
    CFG:saveSetting(BG_LAST_USED_KEY, used_data)
end

-- ===== Settings read/write (lines) =====
-- EVERYTHING is stored in the plugin's own settings file (CFG, settings/custombg.lua). Nothing goes to the book sidecar
-- or to settings.reader.lua.
-- (The names getDocSetting/saveDocSetting are kept so the rest of the plugin does not change.)
function CustomBg:getDocSetting(key, default)
    local val = CFG:readSetting(key)
    if val ~= nil then return val end
    return default
end

function CustomBg:saveDocSetting(key, value)
    CFG:saveSetting(key, value)
end

-- Current background choice (day or night): nil = off, "" = explicitly none, "@global" = global image, or an image name
function CustomBg:readBgChoice()
    local key = self:getSceneMode() == SCENE_DAY and DOC_BG_DAY or DOC_BG_NIGHT
    return CFG:readSetting(key)
end

-- One-time migration of OLD per-book values found in the sidecar:
-- each value is copied to the global settings only if there is no global value yet, then removed from the sidecar,
-- so the book sidecar ends up clean. (The first old book that is opened provides the initial global values.)
function CustomBg:migrateSidecarSettings()
    local ds = self.ui and self.ui.doc_settings
    if not ds then return end
    local keys = { DOC_BG_DAY, DOC_BG_NIGHT }
    for _, key in pairs(FS_KEYS) do keys[#keys + 1] = key end
    local moved = false
    for _, key in ipairs(keys) do
        local v = ds:readSetting(key)
        if v ~= nil then
            if CFG:readSetting(key) == nil then
                CFG:saveSetting(key, v)
            end
            ds:saveSetting(key, nil)
            moved = true
        end
    end
    if moved then pcall(function() CFG:flush() end) end
end

-- ===== Global default background operations (stored separately per scene) =====
function CustomBg:setGlobalDefaultBg(name)
    local scene = self:getSceneMode()
    local key = scene == SCENE_NIGHT and GLOBAL_DEFAULT_BG_NIGHT_KEY or GLOBAL_DEFAULT_BG_DAY_KEY
    CFG:saveSetting(key, name)
    pcall(function() CFG:flush() end)   -- do not wait for a clean exit to persist it
end

function CustomBg:getGlobalDefaultBg()
    local scene = self:getSceneMode()
    local key = scene == SCENE_NIGHT and GLOBAL_DEFAULT_BG_NIGHT_KEY or GLOBAL_DEFAULT_BG_DAY_KEY
    local val = CFG:readSetting(key)
    if val == nil then
        -- Legacy single global-default key compatibility (migration): old settings still apply after upgrading
        val = CFG:readSetting(GLOBAL_DEFAULT_BG_KEY)
    end
    return val
end

-- ===== Background loading: uses the native setBackgroundImage =====
-- Screen refresh after the background was (re)applied outside the menu: when opening a book, switching day/night,
-- rotating the screen. This used to be a full-screen flashing refresh (twice when opening a book: once from init and once
-- from onReadSettings). With "No-flash page turns" enabled (default) a non-flashing "ui" refresh is requested instead.
function CustomBg:_backgroundRefresh()
    -- While the book is being opened the reader is not on screen yet: KOReader paints it by itself when it shows it,
    -- so a refresh requested now would only redraw the previous screen (an extra, useless refresh before the book appears).
    local shown = false
    for _, w in ipairs(UIManager._window_stack or {}) do
        if w.widget == self.ui then shown = true; break end
    end
    if not shown and UIManager._window_stack ~= nil then return end
    UIManager:setDirty("all", self:isNoFlashEnabled() and "ui" or "full")
end

function CustomBg:loadBackgroundByName(name, from_menu)
    if not self.ui or not self.ui.document then return end
    self:invalidateLineCache()

    local use_name = name
    if use_name == nil then
        use_name = self:getCurrentDocBg()   -- may return nil
    end

    -- Pieces mode: the picture is painted by paintTo() and crengine gets NO background image
    local overlay_active = false
    do
        local imgs = self:getCurrentImageCache()
        if use_name and use_name ~= "" and imgs[use_name] then
            overlay_active = self:_setOverlay(imgs[use_name])
        else
            self:_freeOverlay()
        end
    end
    self._overlay_active = overlay_active

    if use_name and use_name ~= "" and not overlay_active then
        local images = self:getCurrentImageCache()
        if images[use_name] then
            local scaled = self:getBgScaledPath(images[use_name])
            if scaled then
                self.ui.document:setBackgroundImage(scaled)
            else
                self.ui.document:setBackgroundImage()
            end
        else
            self.ui.document:setBackgroundImage()
        end
    else
        self.ui.document:setBackgroundImage()
    end
    if self.ui.document.setBackgroundColor then
        self.ui.document:setBackgroundColor(0xFFFFFF)
    end
    -- Record the "applied" state (same dedup key as _reapplyBackgroundImage);
    -- the delayed fallback after opening a book uses it to skip re-applying + full refresh when nothing changed, avoiding a double flash
    self._bg_last_name = use_name
    self._bg_last_scene = self:getSceneMode()
    self._bg_last_dir = self.fs_line_direction
    self._bg_last_rot = (self.ui.document._is_rotated_by_plugin == true)
    self._bg_last_sw = Screen:getWidth()
    self._bg_last_sh = Screen:getHeight()
    self:_syncNoFlash()
    if from_menu then
        self:toggleRepaint("all")   -- picked in the menu: light repaint, the menu stays open
    else
        self:_backgroundRefresh()
    end
end

-- Apply background (save the document setting and load it)
function CustomBg:applyBackground(name)
    -- name: an image name, DOC_BG_NONE ("") for no background, or DOC_BG_GLOBAL to use the global default.
    -- nil also means "follow the global default" (other code, e.g. a gesture toggle, calls applyBackground(nil) for that).
    if name == nil then name = DOC_BG_GLOBAL end
    if name ~= nil and name ~= DOC_BG_NONE and name ~= DOC_BG_GLOBAL then
        -- An image was picked: it becomes THE global background image (for the current day/night mode),
        -- and the background is turned ON in this book (always following the global one).
        self:setGlobalDefaultBg(name)
        name = DOC_BG_GLOBAL
    end
    self:saveDocBg(name)
    self:loadBackgroundByName(nil, true)   -- resolves the saved choice (including the global default)
    local shown = self:getCurrentDocBg()
    if shown and shown ~= "" then
        self:setLastUsed(shown)
        self:markImageSeen(shown)
    end
end

function CustomBg:switchScene(new_scene)
    if new_scene == self:getSceneMode() then return end
    CFG:saveSetting(BG_SCENE_KEY, new_scene)
    local folder = getBackgroundsFolder()
    if new_scene == SCENE_DAY then
        self.cache_day = loadImageList(folder, SCENE_DAY)
    else
        self.cache_night = loadImageList(folder, SCENE_NIGHT)
    end
    -- Reload the current document setting or global default
    self:loadBackgroundByName(nil)
end

function CustomBg:refreshImageCache()
    if self.scanning then return end
    self.scanning = true
    UIManager:nextTick(function()
        local folder = getBackgroundsFolder()
        self.cache_day = loadImageList(folder, SCENE_DAY)
        self.cache_night = loadImageList(folder, SCENE_NIGHT)
        self.scanning = false
    end)
end

function CustomBg:hookReaderRolling()
    if CustomBg.hooked_readerrolling then return end
    CustomBg.hooked_readerrolling = true
    local orig_onReadSettings = ReaderRolling.onReadSettings
    ReaderRolling.onReadSettings = function(reader_rolling, ...)
        orig_onReadSettings(reader_rolling, ...)
        pcall(function()
            local plugin = reader_rolling.ui.custombg
            plugin:loadLineSettings()
            plugin:loadBackgroundByName(nil)
            -- Fallback: on some devices the rendering engine isn't ready during onReadSettings, or a later re-layout
            -- overrides the background property; force-apply once more after a delay so the background takes effect right after (re)opening a book
            plugin:_scheduleBgReapply(1.0)
        end)
    end
end

-- ===== Background re-apply (portrait/landscape adaptive) =====
-- Delayed forced re-apply of the background (bypasses dedup), used as the after-open fallback and for auto-adapting after rotation
function CustomBg:_scheduleBgReapply(delay)
    if self._bg_reapply_timer then
        UIManager:unschedule(self._bg_reapply_timer)
        self._bg_reapply_timer = nil
    end
    self._bg_reapply_timer = UIManager:scheduleIn(delay or 0.5, function()
        self._bg_reapply_timer = nil
        if self.ui and self.ui.document then
            -- Gentle fallback: if the first apply after opening already took effect (recorded state matches), do nothing,
            -- to avoid "first apply + fallback re-apply" each causing a full-screen refresh (a double flash on every book open);
            -- only apply and refresh once when the state really changed (overridden by re-layout / rotation / day-night switch)
            if self:_reapplyBackgroundImage(self.ui.document) then
                self:_backgroundRefresh()
            end
        end
    end)
end

-- Invalidate the dedup state for background name/scene/orientation (note: do NOT touch _bg_last_sw/sh,
-- screen width/height are maintained exclusively by _checkScreenGeom, otherwise they would be reset repeatedly causing a refresh storm)
function CustomBg:_invalidateBgDedup()
    self._bg_last_name = nil
    self._bg_last_scene = nil
    self._bg_last_dir = nil
end

-- KOReader screen rotation (portrait/landscape) event: force re-apply the background after the rotation re-layout finishes
function CustomBg:_onScreenOrientationChanged()
    -- KOReader calls ReaderView:onSetRotationMode on EVERY book open (from onReadSettings), even when the rotation does not
    -- change. Re-applying the background then (0.6 s later, with a screen refresh) caused a second "halo" refresh right after
    -- the book appeared. Only act when the screen size really changed; a 180 degree turn keeps the same size and the cached
    -- background image still fits. (_checkScreenGeom also catches real size changes before each page paint.)
    if Screen:getWidth() == self._bg_last_sw and Screen:getHeight() == self._bg_last_sh then
        return
    end
    self:_invalidateBgDedup()
    self:_scheduleBgReapply(0.6)
end

-- Lightweight check before each page paint for screen width/height changes (catch-all for every rotation path).
-- Only triggers on a real change, and the screen size is persisted here so it never contradicts itself by resetting repeatedly,
-- hence no full-screen forced refresh on every frame (no flicker storm).
function CustomBg:_checkScreenGeom()
    if not self.ui or not self.ui.document then return end
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    if sw == self._bg_last_sw and sh == self._bg_last_sh then
        return
    end
    self._bg_last_sw = sw
    self._bg_last_sh = sh
    self:_invalidateBgDedup()
    self:_scheduleBgReapply(0.4)
end

-- hook ReaderView:onSetRotationMode to capture KOReader's own portrait/landscape rotation
function CustomBg:hookScreenRotation()
    if CustomBg.hooked_rotation then return end
    CustomBg.hooked_rotation = true
    local ok, ReaderView = pcall(require, "apps/reader/modules/readerview")
    if not ok or not ReaderView or not ReaderView.onSetRotationMode then
        return
    end
    local orig_onSetRotationMode = ReaderView.onSetRotationMode
    ReaderView.onSetRotationMode = function(reader_view, mode, ...)
        orig_onSetRotationMode(reader_view, mode, ...)
        pcall(function()
            local plugin = reader_view.ui and reader_view.ui.custombg
            if plugin then plugin:_onScreenOrientationChanged() end
        end)
    end
end

-- ===== No-flash page turns =====
-- With a background image two things make KOReader flash the whole screen when turning pages:
--   1) ReaderView counts the drawn images of the page (document:getDrawnImagesStatistics()); a full-page background
--      counts as "image content" (coverage >= 7.5%), which turns on dithering and the "flash on pages with images" logic.
--   2) The page turn is requested as a "partial" refresh; a page that is no longer pure black and white
--      is refreshed with a waveform that visibly flashes. A "ui" refresh does not flash.
-- Both are handled here, only while a background is shown in the current book, and only if the option is enabled.
-- The periodic full refresh configured in KOReader ("Full refresh rate") keeps working.
-- Least intrusive by design: nothing is hooked unless it is needed. The hooks are installed when a background
-- becomes active in the open book and removed again when the background is turned off, the option is switched off,
-- or the book is closed (see _syncNoFlash / _releaseNoFlash).
function CustomBg:isNoFlashEnabled()
    return CFG:readSetting(NOFLASH_KEY) ~= false
end

-- Used by the pagetextinfo gesture: true = it cycles lines / background / lines + background (default),
-- false = it only toggles the ruled lines.
function CustomBg:isToggleWithBackground()
    return CFG:readSetting(TOGGLE_WITH_BG_KEY) ~= false
end

-- Refresh used for the page turns while a background is shown (only with No-flash page turns ON):
--   "ui"      (default) non-flashing, but text can look softer / ghost more
--   "partial" KOReader's own page-turn refresh: crisper text. The "background counts as an image" flash is still avoided.
function CustomBg:getPageRefreshMode()
    return CFG:readSetting(PAGE_REFRESH_KEY) == "partial" and "partial" or "ui"
end

function CustomBg:_wantsNoFlash()
    -- NOTE: also active in pieces mode: the gray pieces would flicker with KOReader's own page-turn refresh
    return self:isNoFlashEnabled()
       and self.ui and self.ui.document
       and self._bg_last_name ~= nil and self._bg_last_name ~= ""
end

-- ===== No dithering of the background =====
-- Devices without hardware dithering (e.g. Kindle Paperwhite 12) use KOReader's SOFTWARE dithering: Screen.sw_dithering is
-- passed to crengine, which then draws every image of the page, INCLUDING the page background, through an 8x8 ordered
-- dither (lvdrawbuf.cpp, dither_o8x8). That is the grainy/patterned look of the background.
-- While a background is shown (and the option is on) the flag is switched off, and it is put back as soon as the background
-- is turned off or the book is closed. Inline images of the book lose their dithering during that time too.
-- default OFF (only has an effect while a background is shown)
function CustomBg._noDitherOn()
    return CFG:readSetting(NODITHER_KEY) == true
end

function CustomBg:_wantsNoDither()
    return CustomBg._noDitherOn()
       and not self._overlay_active
       and self:isNoFlashEnabled()
       and self.ui and self.ui.document
       and self._bg_last_name ~= nil and self._bg_last_name ~= ""
end

function CustomBg:_syncDither()
    if self:_wantsNoDither() then
        if Screen.sw_dithering and not self._dither_suspended then
            self._dither_suspended = true
            Screen.sw_dithering = false
        end
    else
        self:_releaseDither()
    end
end

function CustomBg:_releaseDither()
    if self._dither_suspended then
        self._dither_suspended = nil
        Screen.sw_dithering = true
    end
end

-- Wrap UIManager.setDirty / UIManager._refresh (class-wide, but only while a book with a background is open).
-- KOReader counts only exact "partial" refreshes inside UIManager:_refresh and promotes every Nth one to a full refresh,
-- so a plain partial -> ui conversion would hide them from the counter and the periodic refresh would never happen.
-- Therefore: setDirty only marks that the request comes from the reader page; _refresh then replays the counter itself
--   * not due yet -> advance the counter by hand, request "ui" (no flash)
--   * due now     -> leave "partial", KOReader counts it and promotes it to the full refresh as usual
function CustomBg:_installRefreshHook()
    local h = CustomBg._refresh_hook
    if h then
        h.enabled = true
        return
    end
    local orig_setDirty, orig_refresh = UIManager.setDirty, UIManager._refresh
    if type(orig_setDirty) ~= "function" or type(orig_refresh) ~= "function" then
        return
    end
    h = { enabled = true, orig_setDirty = orig_setDirty, orig_refresh = orig_refresh }
    h.setDirty = function(um, widget, refreshtype, ...)
        local from_reader = false
        local plugin = CustomBg.active_instance
        -- Opening a book: ReaderUI:doShowReader calls UIManager:show(reader, "full"), which is a flashing full refresh
        -- (this is KOReader's own, not the plugin's). Turn that single request into a "ui" refresh.
        if h.enabled and refreshtype == "full" and widget ~= nil and plugin and plugin._open_pending and plugin:_wantsNoFlash() then
            local reader_ui = plugin.ui
            -- "all" is included: on some devices (seen on Kobo) a second full refresh is requested for every window
            -- shortly after the book is shown; the diagnostic log showed it as "setDirty all full"
            if widget == "all" or widget == reader_ui or (reader_ui.view ~= nil and widget == reader_ui.view.dialog) then
                plugin._open_pending = nil
                -- "ui": no flash (the previous screen may fade out slowly)
                return orig_setDirty(um, widget, "ui", ...)
            end
        end
        if h.enabled and refreshtype == "partial" and widget ~= nil and plugin and plugin:_wantsNoFlash()
           and plugin:getPageRefreshMode() == "ui"
           and not CustomBg._toggle_refresh then
            local reader_ui = plugin.ui
            from_reader = (widget == reader_ui) or (reader_ui.view ~= nil and widget == reader_ui.view.dialog)
        end
        if not from_reader then
            return orig_setDirty(um, widget, refreshtype, ...)
        end
        CustomBg._reader_partial = true
        local ok, err = pcall(orig_setDirty, um, widget, refreshtype, ...)
        CustomBg._reader_partial = false
        if not ok then error(err, 0) end
    end
    h.refresh = function(um, mode, region, dither)
        -- With software dithering switched off by this plugin (see _syncDither), the black "flash" refreshes that menus and
        -- dialogs request when they open / close ("flashui", "flashpartial") flash black over the background on some panels
        -- (Kindle PW12). Turn them into their non-flashing equivalents. "full" is left alone (periodic / explicit full refresh).
        if h.enabled and (mode == "flashui" or mode == "flashpartial" or mode == "partial") then
            local plugin = CustomBg.active_instance
            if plugin and plugin:_wantsNoDither() then
                if mode == "flashui" then
                    mode = "ui"
                elseif mode == "flashpartial" then
                    mode = "partial"
                elseif region and not CustomBg._reader_partial then
                    -- A regional "partial" (a dialog / menu closing) counts towards KOReader's "Full refresh rate" counter and,
                    -- when it is due, UIManager:_refresh promotes it to "flashui" = black flash over the dialog area.
                    -- (Same as KOReader's own "avoid_flashing_ui" setting does.) The reader's own page-turn partials keep counting.
                    mode = "ui"
                end
            end
        end
        if CustomBg._reader_partial and mode == "partial" then
            local n = um.FULL_REFRESH_COUNT
            if type(n) == "number" and type(um.refresh_count) == "number" then
                if n <= 0 or um.refresh_counted then
                    mode = "ui"   -- periodic refresh disabled, or this repaint was already counted
                elseif (um.refresh_count + 1) % n == n - 1 then
                    -- due now: keep "partial" so KOReader counts it and promotes it to the periodic full refresh
                else
                    um.refresh_count = (um.refresh_count + 1) % n
                    um.refresh_counted = true
                    mode = "ui"
                end
            else
                mode = "ui"       -- counter not readable on this version: plain conversion
            end
        end
        return orig_refresh(um, mode, region, dither)
    end
    -- Kindle (MTK) page-turn animation: KOReader asks for it on every page change, and it is applied to the next non-flashing
    -- refresh. With a background shown it can look wrong, so it can be switched off here (only while a background is shown).
    if type(Screen.setSwipeAnimations) == "function" then
        h.swipe_own = rawget(Screen, "setSwipeAnimations")
        local orig_swipe = Screen.setSwipeAnimations
        h.swipe = function(scr, enabled, ...)
            local plugin = CustomBg.active_instance
            if enabled and h.enabled and plugin and plugin:_wantsNoFlash()
               and CFG:readSetting(SWIPE_ANIM_KEY) == "off" then
                return
            end
            return orig_swipe(scr, enabled, ...)
        end
        Screen.setSwipeAnimations = h.swipe
    end
    UIManager.setDirty = h.setDirty
    UIManager._refresh = h.refresh
    CustomBg._refresh_hook = h
end

-- Put the original UIManager functions back. If another plugin wrapped them on top of ours in the meantime,
-- they cannot be restored safely: our wrappers then stay in place but turn into plain pass-throughs.
function CustomBg:_removeRefreshHook()
    local h = CustomBg._refresh_hook
    if not h then return end
    if UIManager.setDirty == h.setDirty and UIManager._refresh == h.refresh then
        if h.swipe and Screen.setSwipeAnimations == h.swipe then
            Screen.setSwipeAnimations = h.swipe_own   -- nil falls back to the normal method lookup
        end
        UIManager.setDirty = h.orig_setDirty
        UIManager._refresh = h.orig_refresh
        CustomBg._refresh_hook = nil
    else
        h.enabled = false
    end
end

-- Turn the whole feature on or off to match the current state (call after the background or the option changed)
function CustomBg:_syncNoFlash()
    self:_syncDither()
    if not self:_wantsNoFlash() then
        self:_releaseNoFlash()
        return
    end
    CustomBg.active_instance = self
    self:_installRefreshHook()
    -- Hide the background from the image statistics, so it never triggers dithering / flashing as "image content"
    local doc = self.ui.document
    if not doc._custombg_stats_hooked and type(doc.getDrawnImagesStatistics) == "function" then
        doc._custombg_stats_hooked = true
        doc.getDrawnImagesStatistics = function() return 0, 0 end
    end
end

function CustomBg:_releaseNoFlash()
    local doc = self.ui and self.ui.document
    if doc and doc._custombg_stats_hooked then
        doc.getDrawnImagesStatistics = nil    -- falls back to the original CreDocument method
        doc._custombg_stats_hooked = nil
    end
    if CustomBg.active_instance == self then
        CustomBg.active_instance = nil
        self:_removeRefreshHook()
    end
end

-- ===== Sleep icon (shown centered after double-tap screen-off) =====
local SLEEP_ICON_MODE_KEY = "custombg_sleep_icon_mode"   -- off / fixed / random
local SLEEP_ICON_NAME_KEY = "custombg_sleep_icon_name"   -- icon filename selected in fixed mode
local SLEEP_ICON_SIZE_KEY = "custombg_sleep_icon_size"   -- percentage of the screen's short side taken by the icon's longest side
local SLEEP_ICON_BG_KEY = "custombg_sleep_icon_bg"       -- screen-off background: transparent / white / black

function CustomBg:getSleepIconsFolder()
    local folder = getBackgroundsFolder() .. "sleep/"
    pcall(function() lfs.mkdir(folder) end)
    return folder
end

function CustomBg:loadSleepIconList()
    local folder = self:getSleepIconsFolder()
    local icons = {}
    local ext_whitelist = {png=true, jpg=true, jpeg=true, webp=true, bmp=true, gif=true}
    local attr = lfs.attributes(folder)
    if attr and attr.mode == "directory" then
        for entry in lfs.dir(folder) do
            if entry ~= "." and entry ~= ".." then
                local ext = entry:match("%.(%w+)$")
                if ext and ext_whitelist[ext:lower()] then
                    table.insert(icons, entry)
                end
            end
        end
        table.sort(icons)
    end
    return icons
end

function CustomBg:getSleepIconSizePct()
    local v = CFG:readSetting(SLEEP_ICON_SIZE_KEY)
    if v == 0 then return 0 end   -- 0 = fill the whole screen (proportional cover, edges cropped)
    return math.min(100, math.max(10, v or 45))
end

function CustomBg:getSleepIconBg()
    -- Transparent by default: uses KOReader's native "no fill" transparent wallpaper approach,
    -- with screensaver_background = "none" no base color is laid down,
    -- and areas of the composite image with alpha=0 fully show the picture from before screen-off; only the icon is visible
    return CFG:readSetting(SLEEP_ICON_BG_KEY) or "transparent"
end

-- Clear the sleep composite image cache (call after the icon size changes)
function CustomBg:clearSleepScreenCache()
    local dir = getCacheDir()
    local attr = lfs.attributes(dir)
    if not attr or attr.mode ~= "directory" then return end
    for entry in lfs.dir(dir) do
        if entry:sub(1, 6) == "sleep_" then
            pcall(os.remove, dir .. entry)
        end
    end
end

-- Generate the full-screen sleep image "background + centered icon" (sized for the upright orientation of the screen-off picture), with caching
-- Transparent mode: the canvas is not filled (calloc all zeros = alpha 0), the PNG keeps its alpha channel,
-- combined with screensaver_background="none" on screen-off this gives the native "no fill" transparent effect
function CustomBg:composeSleepScreen(icon_path)
    if not icon_path or icon_path == "" then return nil end
    -- The screen-off picture is always displayed upright (Portrait): if currently in landscape, swap width and height
    local w, h
    local rot = Screen:getRotationMode()
    if bit.band(rot, 1) == 1 then
        w, h = Screen:getHeight(), Screen:getWidth()
    else
        w, h = Screen:getWidth(), Screen:getHeight()
    end
    local pct = self:getSleepIconSizePct()
    local bg_mode = self:getSleepIconBg()
    -- The cache name must include the background mode: otherwise switching white/black/transparent would reuse a cached image with the old fill
    local cache_path = getCacheDir() .. string.format("sleep_%dx%d_%s_%d_%s.png", w, h, hashString(icon_path), pct, bg_mode)
    if lfs.attributes(cache_path, "mode") == "file" then return cache_path end
    local ok, result = pcall(function()
        local RenderImage = require("ui/renderimage")
        local icon = RenderImage:renderImageFile(icon_path, true, nil, nil)
        if not icon then return nil end
        local iw, ih = icon:getWidth(), icon:getHeight()
        if not iw or iw <= 0 or not ih or ih <= 0 then
            icon:free()
            return nil
        end
        -- Target size:
        -- pct=0  -> fill the whole screen: scale proportionally to cover the screen (short side aligned to the long-side direction),
        --           draw centered, crop whatever exceeds the screen;
        -- pct>0  -> longest side = screen short side * pct% (keep aspect ratio, centered)
        local tw, th
        if pct == 0 then
            local scale = math.max(w / iw, h / ih)
            tw = math.max(1, math.floor(iw * scale + 0.5))
            th = math.max(1, math.floor(ih * scale + 0.5))
        else
            local max_side = math.max(16, math.floor(math.min(w, h) * pct / 100 + 0.5))
            if iw >= ih then
                tw = max_side
                th = math.max(1, math.floor(ih * max_side / iw + 0.5))
            else
                th = max_side
                tw = math.max(1, math.floor(iw * max_side / ih + 0.5))
            end
            tw, th = math.min(tw, w), math.min(th, h)
        end
        local scaled = icon
        if tw ~= iw or th ~= ih then
            scaled = RenderImage:scaleBlitBuffer(icon, tw, th, true)
            icon:free()
        end
        local canvas = Blitbuffer.new(w, h, Blitbuffer.TYPE_BBRGB32)
        if bg_mode == "white" then
            canvas:fill(Blitbuffer.COLOR_WHITE)   -- white fill: black silhouette icons stay clearly visible
        elseif bg_mode == "black" then
            canvas:fill(Blitbuffer.COLOR_BLACK)   -- black fill
        end
        -- transparent (default): no fill, the canvas stays transparent, the icon floats directly over the screen-off picture
        if pct == 0 then
            -- Fill the whole screen: source image centered crop (crop the overflow), tiled from canvas (0,0)
            local sx = math.max(0, math.floor((tw - w) / 2))
            local sy = math.max(0, math.floor((th - h) / 2))
            canvas:blitFrom(scaled, 0, 0, sx, sy, math.min(w, tw), math.min(h, th))
        else
            canvas:blitFrom(scaled, math.floor((w - tw) / 2), math.floor((h - th) / 2), 0, 0, tw, th)
        end
        scaled:free()
        local written = canvas:writeToFile(cache_path, "png", 75)
        canvas:free()
        return written and cache_path or nil
    end)
    if ok and result then return result end
    return nil
end

-- hook Screensaver.setup: inject the "background + centered icon" picture at the moment of screen-off,
-- override only when this feature is enabled, without touching the system-wide screensaver settings
-- Transparent mode is equivalent to the native "screensaver_img_background=none" no-fill transparent wallpaper
function CustomBg:hookSleepScreen()
    if CustomBg.hooked_sleepscreen then return end
    CustomBg.hooked_sleepscreen = true
    local ok, Screensaver = pcall(require, "ui/screensaver")
    if not ok or type(Screensaver) ~= "table" or type(Screensaver.setup) ~= "function" then
        return
    end
    local orig_setup = Screensaver.setup
    Screensaver.setup = function(ss, ...)
        orig_setup(ss, ...)
        pcall(function()
            local mode = CFG:readSetting(SLEEP_ICON_MODE_KEY) or "off"
            if mode == "off" or not ss.ui then return end
            local folder = CustomBg:getSleepIconsFolder()
            local icon_file
            if mode == "random" then
                local icons = CustomBg:loadSleepIconList()
                if #icons > 0 then
                    icon_file = folder .. icons[math.random(#icons)]
                end
            elseif mode == "fixed" then
                local name = CFG:readSetting(SLEEP_ICON_NAME_KEY)
                if name and name ~= "" then icon_file = folder .. name end
            end
            if not icon_file or lfs.attributes(icon_file, "mode") ~= "file" then return end
            local composed = CustomBg:composeSleepScreen(icon_file)
            if composed then
                ss.image = nil
                ss.image_file = composed
                ss.screensaver_type = "random_image"   -- reuse the native image rendering path
                local bg_mode = self:getSleepIconBg()
                if bg_mode == "white" then
                    ss.screensaver_background = "white"
                elseif bg_mode == "black" then
                    ss.screensaver_background = "black"
                else
                    ss.screensaver_background = "none"   -- transparent: no background fill, keep the picture beneath the screen-off layer
                end
            end
        end)
    end
end

-- Sleep icon settings menu (re-scans the icon folder every time it is opened)
function CustomBg:getSleepIconMenu()
    local items = {}
    local function current_mode()
        return CFG:readSetting(SLEEP_ICON_MODE_KEY) or "off"
    end
    table.insert(items, {
        text = _("Off (use the system default screen-off picture)"),
        checked_func = function() return current_mode() == "off" end,
        callback = function()
            CFG:saveSetting(SLEEP_ICON_MODE_KEY, "off")
        end,
    })
    table.insert(items, {
        text = _("Show a random one on each screen-off"),
        checked_func = function() return current_mode() == "random" end,
        callback = function()
            CFG:saveSetting(SLEEP_ICON_MODE_KEY, "random")
        end,
    })
    -- Screen-off background and icon size go on the first page (right below "Show a random one on each screen-off")
    local bg_options = {
        { text = _("Transparent (default, nothing filled except the icon)"), bg = "transparent" },
        { text = _("White background (fills the whole screen)"), bg = "white" },
        { text = _("Black background (fills the whole screen)"), bg = "black" },
    }
    table.insert(items, {
        text = _("Screen-off background"),
        sub_item_table = (function()
            local bg_items = {}
            for _, opt in ipairs(bg_options) do
                table.insert(bg_items, {
                    text = opt.text,
                    checked_func = function()
                        return self:getSleepIconBg() == opt.bg
                    end,
                    callback = function()
                        CFG:saveSetting(SLEEP_ICON_BG_KEY, opt.bg)
                        self:clearSleepScreenCache()
                        if current_mode() == "fixed" then
                            local name = CFG:readSetting(SLEEP_ICON_NAME_KEY)
                            if name and name ~= "" then
                                self:composeSleepScreen(self:getSleepIconsFolder() .. name)
                            end
                        end
                    end,
                })
            end
            return bg_items
        end)(),
    })
    local size_options = {
        { text = _("Small (30% of short side)"), pct = 30 },
        { text = _("Medium (45% of short side)"), pct = 45 },
        { text = _("Large (60% of short side)"), pct = 60 },
        { text = _("Fit short side (100%)"), pct = 100 },
        { text = _("Fill whole screen (scaled proportionally, overflow cropped)"), pct = 0 },
    }
    table.insert(items, {
        text = _("Icon size"),
        sub_item_table = (function()
            local size_items = {}
            for _, opt in ipairs(size_options) do
                table.insert(size_items, {
                    text = opt.text,
                    checked_func = function()
                        return self:getSleepIconSizePct() == opt.pct
                    end,
                    callback = function()
                        CFG:saveSetting(SLEEP_ICON_SIZE_KEY, opt.pct)
                        self:clearSleepScreenCache()
                        -- If a fixed icon is currently selected, pre-generate it immediately at the new size
                        if current_mode() == "fixed" then
                            local name = CFG:readSetting(SLEEP_ICON_NAME_KEY)
                            if name and name ~= "" then
                                self:composeSleepScreen(self:getSleepIconsFolder() .. name)
                            end
                        end
                    end,
                })
            end
            return size_items
        end)(),
        -- The separator line is attached to this item: a standalone { separator = true } entry
        -- would render as an empty row (the ugly gap) in the touch menu
        separator = true,
    })
    -- Icon list (placed below; auto-paginates when there are many icons)
    local icons = self:loadSleepIconList()
    if #icons > 0 then
        for _, name in ipairs(icons) do
            table.insert(items, {
                text = name,
                checked_func = function()
                    return current_mode() == "fixed"
                       and CFG:readSetting(SLEEP_ICON_NAME_KEY) == name
                end,
                callback = function()
                    CFG:saveSetting(SLEEP_ICON_MODE_KEY, "fixed")
                    CFG:saveSetting(SLEEP_ICON_NAME_KEY, name)
                    -- Pre-generate the composite image so it shows instantly on screen-off
                    self:composeSleepScreen(self:getSleepIconsFolder() .. name)
                end,
            })
        end
    else
        table.insert(items, {
            text = _("(No icons found) How to add icons?"),
            keep_menu_open = true,
            callback = function()
                UIManager:show(InfoMessage:new{
                    text = T(_("Please put sleep icon images (png/jpg etc.) into the following folder:\n\n%1\n\nThen reopen this menu to select them."), self:getSleepIconsFolder()),
                })
            end,
        })
    end
    return items
end

-- ===== Line settings loading =====
function CustomBg:loadLineSettings()
    self:invalidateLineCache()
    self:migrateSidecarSettings()
    self.fs_enabled = CFG:readSetting(FS_KEYS.enabled) == true
    self.fs_line_direction = self:getDocSetting(FS_KEYS.direction, 1)
    self.fs_v_font_enable = self:getDocSetting(FS_KEYS.v_font_enable, true)
    self.fs_v_font_family = self:getDocSetting(FS_KEYS.v_font_family, "FZKai-Z03")
    self.fs_offset_y = self:getDocSetting(FS_KEYS.offset_y, 2)
    self.fs_auto_offset = self:getDocSetting(FS_KEYS.auto_offset, true)
    self.fs_offset_adjust = self:getDocSetting(FS_KEYS.offset_adjust, 0)
    self.fs_offset_bias = self:getDocSetting(FS_KEYS.offset_bias, 0)
    self.fs_show_top_line = self:getDocSetting(FS_KEYS.show_top, true)
    self.fs_is_dashed = self:getDocSetting(FS_KEYS.dashed, false)
    self.fs_color_depth = self:getDocSetting(FS_KEYS.color_depth, 5)
    self.fs_dash_len = math.max(2, self:getDocSetting(FS_KEYS.dash_len, 10))
    self.fs_line_mode = self:getDocSetting(FS_KEYS.mode, 1)
    self.fs_width_ratio = self:getDocSetting(FS_KEYS.width_ratio, 1000)
    self.fs_extend_px = self:getDocSetting(FS_KEYS.extend, 5)
    self.fs_gap_threshold = self:getDocSetting(FS_KEYS.gap_threshold, 2.5)
    self.fs_skip_titles = self:getDocSetting(FS_KEYS.skip_titles, false)
    self.fs_title_threshold = self:getDocSetting(FS_KEYS.title_threshold, 1.05)
    self.fs_wave_mode = self:getDocSetting(FS_KEYS.wave_mode, 0)
    self.fs_style_dash_dot = self:getDocSetting(FS_KEYS.style_dash_dot, true)
    self.fs_style_heart_dash = self:getDocSetting(FS_KEYS.style_heart_dash, false)
    self.fs_style_double_solid = self:getDocSetting(FS_KEYS.style_double_solid, false)
    self.fs_style_double_dash = self:getDocSetting(FS_KEYS.style_double_dash, false)
    self.fs_double_gap = math.max(0, self:getDocSetting(FS_KEYS.double_gap, 2))
end

function CustomBg:saveLineSetting(key, value)
    self:invalidateLineCache()
    self:saveDocSetting(key, value)
end

-- Public: switch the ruled lines on/off (used by the pagetextinfo gesture and available to any other plugin).
-- Stored in the plugin's own settings file, so it applies to every book.
function CustomBg:setLinesEnabled(on)
    self.fs_enabled = on and true or false
    CFG:saveSetting(FS_KEYS.enabled, self.fs_enabled)
    self:invalidateLineCache()
end

-- What happens after a setting changed while the menu is open:
--   "ui"      (default) the page is painted again and refreshed WITHOUT the full-screen flash
--   "partial" same, a bit cleaner text, still no flash
--   "full"    full-screen flashing refresh
--   false     no repaint at all: only the menu is updated (check marks), the page changes when the menu is closed
local REFRESH_ON_CHANGE = "ui"

-- Repaints the page behind the open menu, so the change can be seen while the menu stays open.
-- NOTE: UIManager:setDirty(nil, ...) only asks for a screen refresh, it does NOT repaint the widgets below the menu:
-- the page (background, ruled lines) behind it would not change until the menu was closed.
-- With "all" every window is marked dirty, so ReaderUI paints again and the menu is drawn on top of it.
function CustomBg:repaintView()
    if REFRESH_ON_CHANGE then
        UIManager:setDirty("all", REFRESH_ON_CHANGE)
    end
end

-- Refresh used when the background is switched on/off or changed (menu, gesture or another plugin's toggle).
-- "ui" everywhere. A "partial" special case for Kindle was tried and it flashes the same on that panel, so it was removed.
function CustomBg:getToggleRefreshMode()
    return "ui"
end

-- Repaint after the background was switched on/off or changed. Public: other plugins can call it instead of
-- UIManager:setDirty(widget, "ui"). The request is marked so the no-flash hook leaves it as it is.
function CustomBg:toggleRepaint(widget)
    CustomBg._toggle_refresh = true
    local ok, err = pcall(UIManager.setDirty, UIManager, widget or "all", self:getToggleRefreshMode())
    CustomBg._toggle_refresh = false
    if not ok then error(err, 0) end
end

-- A setting changed: update the menu (check marks / texts) and repaint the page behind it
function CustomBg:refreshView(touchmenu_instance)
    if touchmenu_instance and touchmenu_instance.updateItems then
        touchmenu_instance:updateItems()
    end
    self:repaintView()
end

-- ===== Underline settings reset =====
-- All underline settings are global (one set for every book). This restores the built-in defaults
-- (the on/off switch is kept).
function CustomBg:hasLineSettings()
    for _, key in pairs(FS_KEYS) do
        if key ~= FS_KEYS.enabled and CFG:readSetting(key) ~= nil then return true end
    end
    return false
end

function CustomBg:resetLineSettings()
    for _, key in pairs(FS_KEYS) do
        if key ~= FS_KEYS.enabled then
            CFG:saveSetting(key, nil)
        end
    end
    pcall(function() CFG:flush() end)
    self:loadLineSettings()
end

-- ===== Vertical layout patch =====
function CustomBg:applyVerticalEnginePatch()
    if self._fs_patched then return end
    if not self.ui or not self.ui.rolling then return end
    local rolling = self.ui.rolling
    self._fs_patched = true
    local orig_onPreRender = rolling.onPreRenderDocument
    rolling.onPreRenderDocument = function(self_rr)
        if orig_onPreRender then orig_onPreRender(self_rr) end
        local doc = self_rr.ui and self_rr.ui.document
        if doc and self.fs_line_direction == 2 then
            if self.fs_v_font_enable and self.fs_v_font_family ~= "" then
                local css = string.format("/* fs_lines_font_start */ body, p, div, span { font-family: '%s', sans-serif !important; } /* fs_lines_font_end */", self.fs_v_font_family)
                if doc.kopt then
                    local current_css = doc.kopt.css or ""
                    if not current_css:find("fs_lines_font_start") or doc._fs_font_applied ~= self.fs_v_font_family then
                        current_css = current_css:gsub("/%* fs_lines_font_start %*/.-/%* fs_lines_font_end %*/", "")
                        doc.kopt.css = current_css .. "\n" .. css
                        doc._fs_font_applied = self.fs_v_font_family
                    end
                elseif type(doc.setStyleSheet) == "function" then
                    local style_css = ""
                    if self_rr.ui and self_rr.ui.style and self_rr.ui.style.appended_css then
                        style_css = self_rr.ui.style.appended_css
                    end
                    if doc._fs_font_applied ~= self.fs_v_font_family or (not style_css:find("fs_lines_font_start")) then
                        local new_css = style_css:gsub("/%* fs_lines_font_start %*/.-/%* fs_lines_font_end %*/", "") .. "\n" .. css
                        if self_rr.ui and self_rr.ui.style then
                            self_rr.ui.style.appended_css = new_css
                        end
                        doc:setStyleSheet(doc.default_css, new_css)
                        doc._fs_font_applied = self.fs_v_font_family
                    end
                end
            end
            if not doc._is_rotated_by_plugin then
                doc._is_rotated_by_plugin = true
                if self_rr.ui.view and not self_rr.ui.view.inverse_reading_order then
                    self_rr.ui.view:onToggleReadingOrder()
                end
                -- Swap the crengine viewport: width and height exchanged so the engine lays out as "landscape",
                -- then rotate(-90) the whole result back onto the screen -> displayed on screen as vertical text.
                doc.setViewDimen = function(self_doc, dimen)
                    self_doc._document:setViewDimen(dimen.h, dimen.w)
                end
                doc:setViewDimen(Screen:getSize())
                doc.drawCurrentView = function(self_doc, target, x, y, rect, pos)
                    self_doc.orig_rect_w = rect.w
                    self_doc.orig_rect_h = rect.h
                    rect = rect:copy()
                    rect.w, rect.h = rect.h, rect.w
                    if self_doc.buffer and (self_doc.buffer.w ~= rect.w or self_doc.buffer.h ~= rect.h) then
                        self_doc.buffer:free()
                        self_doc.buffer = nil
                    end
                    if not self_doc.buffer then
                        self_doc.buffer = Blitbuffer.new(rect.w, rect.h, self_doc.render_color and Blitbuffer.TYPE_BBRGB32 or nil)
                    end
                    self_doc._drawn_images_count, self_doc._drawn_images_surface_ratio =
                        self_doc._document:drawCurrentPage(self_doc.buffer, self_doc.render_color, Screen.night_mode and self_doc._nightmode_images, self_doc._smooth_scaling, Screen.sw_dithering)
                    -- Rotate back to screen orientation and blit, then convert the buffer back to engine orientation for reuse next time
                    self_doc.buffer:rotate(-90)
                    target:blitFrom(self_doc.buffer, x, y, 0, 0, rect.h, rect.w)
                    self_doc.buffer:rotate(90)
                end
            end
        end
        -- Apply the background after the rotation patch: then the first application already sees the "rotated" state
        -- and uses the pre-rotated background cache directly, avoiding a wrongly oriented background on the first frame.
        -- This also fixes having to tap "Reading background" again manually after switching portrait/landscape reading direction.
        self:_reapplyBackgroundImage(doc)
    end
end

-- Before every render, make sure the background has been applied for the current "background name / scene / reading direction",
-- fixing the background not showing after switching reading orientation until "Reading background" was tapped again.
function CustomBg:_reapplyBackgroundImage(doc)
    if not doc or type(doc.setBackgroundImage) ~= "function" then return false end
    local name = self:getCurrentDocBg()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    -- In pseudo-vertical mode (engine rotation) the background must use the "pre-rotated 90°" cache image, so a change of rotation state must also trigger a re-apply
    local rot = (doc._is_rotated_by_plugin == true)
    if name == self._bg_last_name and self._bg_last_scene == self:getSceneMode()
       and self._bg_last_dir == self.fs_line_direction
       and self._bg_last_rot == rot
       and self._bg_last_sw == sw and self._bg_last_sh == sh then
        return false   -- state unchanged, no re-apply needed
    end
    self._bg_last_name = name
    self._bg_last_scene = self:getSceneMode()
    self._bg_last_dir = self.fs_line_direction
    self._bg_last_rot = rot
    self._bg_last_sw = sw
    self._bg_last_sh = sh
    local overlay_active = false
    do
        local imgs = self:getCurrentImageCache()
        if name and name ~= "" and imgs[name] then
            overlay_active = self:_setOverlay(imgs[name])
        else
            self:_freeOverlay()
        end
    end
    self._overlay_active = overlay_active
    if name and name ~= "" and not overlay_active then
        local images = self:getCurrentImageCache()
        if images[name] then
            local scaled = self:getBgScaledPath(images[name])
            if scaled then
                doc:setBackgroundImage(scaled)
            else
                doc:setBackgroundImage()
            end
        else
            doc:setBackgroundImage()
        end
    else
        doc:setBackgroundImage()
    end
    if doc.setBackgroundColor then doc:setBackgroundColor(0xFFFFFF) end
    self:_syncNoFlash()
    return true   -- a re-apply was actually performed
end

function CustomBg:restoreOriginalState()
    if not self.ui or not self.ui.document then return end
    local doc = self.ui.document
    if doc._is_rotated_by_plugin and doc._document and type(doc._document.setViewDimen) == "function" then
        local dimen = Screen:getSize()
        doc._document:setViewDimen(dimen.w, dimen.h)
    end
    if doc._is_rotated_by_plugin and self.ui.view and self.ui.view.inverse_reading_order then
        self.ui.view:onToggleReadingOrder()
    end
    -- Fully remove the patch: set to nil to fall back to CreDocument's original implementation
    -- (otherwise, even after switching back to a normal viewport, re-entering this book would keep rotating the whole page)
    doc.setViewDimen = nil
    doc.drawCurrentView = nil
    doc.orig_rect_w = nil
    doc.orig_rect_h = nil
    doc._is_rotated_by_plugin = nil
    if doc.kopt and doc.kopt.css then
        doc.kopt.css = doc.kopt.css:gsub("/%* fs_lines_font_start %*/.-/%* fs_lines_font_end %*/", "")
        doc.kopt.css = doc.kopt.css:gsub("\n\n+", "\n")
        if doc.kopt.css:match("^%s*$") then doc.kopt.css = nil end
    elseif type(doc.setStyleSheet) == "function" and doc._fs_font_applied then
        local current_css = ""
        if self.ui and self.ui.style and self.ui.style.appended_css then
            current_css = self.ui.style.appended_css
        end
        current_css = current_css:gsub("/%* fs_lines_font_start %*/.-/%* fs_lines_font_end %*/", "")
        if self.ui and self.ui.style then
            self.ui.style.appended_css = current_css
        end
        doc:setStyleSheet(doc.default_css, current_css)
        doc._fs_font_applied = nil
    end
end

function CustomBg:showReloadConfirm()
    UIManager:show(ConfirmBox:new{
        text = _("Layout direction or font settings have changed.\nDue to the rendering engine's strong caching, the book must be unloaded from memory before it can be re-laid out.\nReturn to the library now?\n(After returning, simply reopen this book for the change to take full effect)"),
        ok_text = _("Return to library"),
        cancel_text = _("Later"),
        ok_callback = function()
            self:restoreOriginalState()
            if self.ui and type(self.ui.onHome) == "function" then
                UIManager:nextTick(function()
                    self.ui:onHome()
                end)
            end
        end,
    })
end

-- ==================== Pattern templates ====================
local function getHeartPattern()
    return {
        {0,1,1,0,0,1,1,0},
        {1,1,1,1,1,1,1,1},
        {1,1,1,1,1,1,1,1},
        {1,1,1,1,1,1,1,1},
        {0,1,1,1,1,1,1,0},
        {0,0,1,1,1,1,0,0},
        {0,0,0,1,1,0,0,0},
        {0,0,0,0,0,0,0,0},
    }
end

-- ==================== Drawing helper functions ====================
function CustomBg:drawALine(bb, start_x, y, draw_width, thickness, color)
    local actual_w = draw_width
    local x = math.max(0, start_x)
    if actual_w <= 0 then return end

    local function drawSymbol(cx, cy, pattern, size)
        for row = 0, size - 1 do
            for col = 0, size - 1 do
                if pattern[row+1] and pattern[row+1][col+1] == 1 then
                    bb:setPixel(cx + col, cy + row, color)
                end
            end
        end
    end

    if self.fs_style_heart_dash then
        local size = 8
        local unit_len = 4
        local unit_gap = 6
        local heart = getHeartPattern()
        if actual_w < size * 2 + 4 then
            local cx = x + math.floor((actual_w - size) / 2)
            local cy = y - math.floor(size / 2)
            drawSymbol(cx, cy, heart, size)
            return
        end
        drawSymbol(x, y - math.floor(size/2), heart, size)
        local start_pos = x + size
        local end_pos = x + actual_w - size
        local inner_pos = start_pos
        while inner_pos < end_pos do
            local draw = math.min(unit_len, end_pos - inner_pos)
            bb:paintRect(inner_pos, y, draw, thickness, color)
            inner_pos = inner_pos + draw
            if inner_pos < end_pos then
                inner_pos = inner_pos + unit_gap
            end
        end
        drawSymbol(x + actual_w - size, y - math.floor(size/2), heart, size)
        return
    end

    if self.fs_style_dash_dot then
        local solid_len = 40
        local dash_len = 40
        local unit_len = 4
        local unit_gap = 6
        if actual_w < 2 * solid_len + dash_len then
            bb:paintRect(x, y, actual_w, thickness, color)
            return
        end
        bb:paintRect(x, y, solid_len, thickness, color)
        local right_start = x + actual_w - solid_len
        bb:paintRect(right_start, y, solid_len, thickness, color)
        local mid_start = x + solid_len
        local mid_end = right_start - 1
        local pos = mid_start
        local is_dash = true
        while pos <= mid_end do
            local remaining = mid_end - pos + 1
            local seg_len = is_dash and dash_len or solid_len
            if remaining < seg_len then
                seg_len = remaining
            end
            if is_dash then
                local inner_pos = pos
                local inner_end = pos + seg_len - 1
                while inner_pos <= inner_end do
                    local draw = math.min(unit_len, inner_end - inner_pos + 1)
                    bb:paintRect(inner_pos, y, draw, thickness, color)
                    inner_pos = inner_pos + draw
                    if inner_pos <= inner_end then
                        inner_pos = inner_pos + unit_gap
                    end
                end
            else
                bb:paintRect(pos, y, seg_len, thickness, color)
            end
            pos = pos + seg_len
            is_dash = not is_dash
        end
        return
    end

    -- Double solid / double dashed line: draw two parallel lines centered on y, spacing = line width + double-line gap
    if self.fs_style_double_solid or self.fs_style_double_dash then
        local sep = thickness + self.fs_double_gap
        local y1 = y - math.floor((thickness + self.fs_double_gap) / 2)
        local y2 = y1 + sep
        local dash = self.fs_dash_len
        local gap = math.max(1, math.floor(dash / 2))
        local step = dash + gap
        local is_dashed = self.fs_style_double_dash
        local is_c8 = Blitbuffer.isColor8(color)
        for _, ly in ipairs({ y1, y2 }) do
            if is_dashed then
                -- Align the phases of the two dashed lines to form a neat double dashed line
                for i = 0, actual_w - 1, step do
                    local cur_dash = math.min(dash, actual_w - i)
                    bb:paintRect(x + i, ly, cur_dash, thickness, color)
                end
            else
                if is_c8 then
                    bb:paintRect(x, ly, actual_w, thickness, color)
                else
                    bb:paintRectRGB32(x, ly, actual_w, thickness, color)
                end
            end
        end
        return
    end

    if self.fs_wave_mode > 0 then
        local gray_val = math.floor(255 - (self.fs_color_depth * 25.5))
        local wave_gray = math.max(0, gray_val - 50)
        local wave_color = Blitbuffer.Color8(wave_gray)
        if self.fs_wave_mode == 1 then
            local amp, period = 2, 20
            for i = 0, actual_w - 1 do
                local cur_x = x + i
                local dy = amp * math.sin(2 * math.pi * (i / period))
                local cur_y = math.floor(y + dy)
                bb:paintRect(cur_x, cur_y, 1, 2, wave_color)
            end
        elseif self.fs_wave_mode == 2 then
            local amp, period = 2, 12
            local offset = 2
            for i = 0, actual_w - 1 do
                local cur_x = x + i
                local dy = amp * math.sin(2 * math.pi * (i / period))
                local cur_y1 = math.floor(y - offset + dy)
                local cur_y2 = math.floor(y + offset + dy)
                bb:paintRect(cur_x, cur_y1, 1, 2, wave_color)
                bb:paintRect(cur_x, cur_y2, 1, 2, wave_color)
            end
        end
        return
    end

    if self.fs_is_dashed then
        local dash = self.fs_dash_len
        local gap = math.max(1, math.floor(dash / 2))
        local step = dash + gap
        for i = 0, actual_w - 1, step do
            local cur_dash = math.min(dash, actual_w - i)
            bb:paintRect(x + i, y, cur_dash, thickness, color)
        end
        return
    end

    if Blitbuffer.isColor8(color) then
        bb:paintRect(x, y, actual_w, thickness, color)
    else
        bb:paintRectRGB32(x, y, actual_w, thickness, color)
    end
end

function CustomBg:drawAVerticalLine(bb, x, start_y, draw_height, thickness, color)
    local actual_h = draw_height
    local y = math.max(0, start_y)
    if actual_h <= 0 then return end

    local function drawSymbol(cx, cy, pattern, size)
        for row = 0, size - 1 do
            for col = 0, size - 1 do
                if pattern[row+1] and pattern[row+1][col+1] == 1 then
                    bb:setPixel(cx + col, cy + row, color)
                end
            end
        end
    end

    if self.fs_style_heart_dash then
        local size = 8
        local unit_len = 4
        local unit_gap = 6
        local heart = getHeartPattern()
        if actual_h < size * 2 + 4 then
            local cy = y + math.floor((actual_h - size) / 2)
            local cx = x - math.floor(size / 2)
            drawSymbol(cx, cy, heart, size)
            return
        end
        drawSymbol(x - math.floor(size/2), y, heart, size)
        local start_pos = y + size
        local end_pos = y + actual_h - size
        local inner_pos = start_pos
        while inner_pos < end_pos do
            local draw = math.min(unit_len, end_pos - inner_pos)
            bb:paintRect(x, inner_pos, thickness, draw, color)
            inner_pos = inner_pos + draw
            if inner_pos < end_pos then
                inner_pos = inner_pos + unit_gap
            end
        end
        drawSymbol(x - math.floor(size/2), y + actual_h - size, heart, size)
        return
    end

    if self.fs_style_dash_dot then
        local solid_len = 40
        local dash_len = 40
        local unit_len = 4
        local unit_gap = 6
        if actual_h < 2 * solid_len + dash_len then
            bb:paintRect(x, y, thickness, actual_h, color)
            return
        end
        bb:paintRect(x, y, thickness, solid_len, color)
        local bottom_start = y + actual_h - solid_len
        bb:paintRect(x, bottom_start, thickness, solid_len, color)
        local mid_start = y + solid_len
        local mid_end = bottom_start - 1
        local pos = mid_start
        local is_dash = true
        while pos <= mid_end do
            local remaining = mid_end - pos + 1
            local seg_len = is_dash and dash_len or solid_len
            if remaining < seg_len then
                seg_len = remaining
            end
            if is_dash then
                local inner_pos = pos
                local inner_end = pos + seg_len - 1
                while inner_pos <= inner_end do
                    local draw = math.min(unit_len, inner_end - inner_pos + 1)
                    bb:paintRect(x, inner_pos, thickness, draw, color)
                    inner_pos = inner_pos + draw
                    if inner_pos <= inner_end then
                        inner_pos = inner_pos + unit_gap
                    end
                end
            else
                bb:paintRect(x, pos, thickness, seg_len, color)
            end
            pos = pos + seg_len
            is_dash = not is_dash
        end
        return
    end

    if self.fs_wave_mode > 0 then
        local gray_val = math.floor(255 - (self.fs_color_depth * 25.5))
        local wave_gray = math.max(0, gray_val - 50)
        local wave_color = Blitbuffer.Color8(wave_gray)
        if self.fs_wave_mode == 1 then
            local amp, period = 2, 20
            for i = 0, actual_h - 1 do
                local cur_y = y + i
                local dx = amp * math.sin(2 * math.pi * (i / period))
                local cur_x = math.floor(x + dx)
                bb:paintRect(cur_x, cur_y, 2, 1, wave_color)
            end
        elseif self.fs_wave_mode == 2 then
            local amp, period = 2, 12
            local offset = 2
            for i = 0, actual_h - 1 do
                local cur_y = y + i
                local dx = amp * math.sin(2 * math.pi * (i / period))
                local cur_x1 = math.floor(x - offset + dx)
                local cur_x2 = math.floor(x + offset + dx)
                bb:paintRect(cur_x1, cur_y, 2, 1, wave_color)
                bb:paintRect(cur_x2, cur_y, 2, 1, wave_color)
            end
        end
        return
    end

    -- Double solid / double dashed line: draw two parallel vertical lines centered on x, spacing = line width + double-line gap
    if self.fs_style_double_solid or self.fs_style_double_dash then
        local sep = thickness + self.fs_double_gap
        local x1 = x - math.floor((thickness + self.fs_double_gap) / 2)
        local x2 = x1 + sep
        local dash = self.fs_dash_len
        local gap = math.max(1, math.floor(dash / 2))
        local step = dash + gap
        local is_dashed = self.fs_style_double_dash
        local is_c8 = Blitbuffer.isColor8(color)
        for _, lx in ipairs({ x1, x2 }) do
            if is_dashed then
                for i = 0, actual_h - 1, step do
                    local cur_dash = math.min(dash, actual_h - i)
                    bb:paintRect(lx, y + i, thickness, cur_dash, color)
                end
            else
                if is_c8 then
                    bb:paintRect(lx, y, thickness, actual_h, color)
                else
                    bb:paintRectRGB32(lx, y, thickness, actual_h, color)
                end
            end
        end
        return
    end

    if self.fs_is_dashed then
        local dash = self.fs_dash_len
        local gap = math.max(1, math.floor(dash / 2))
        local step = dash + gap
        for i = 0, actual_h - 1, step do
            local cur_dash = math.min(dash, actual_h - i)
            bb:paintRect(x, y + i, thickness, cur_dash, color)
        end
        return
    end

    if Blitbuffer.isColor8(color) then
        bb:paintRect(x, y, thickness, actual_h, color)
    else
        bb:paintRectRGB32(x, y, thickness, actual_h, color)
    end
end

-- Un-instrumented originals, used when replaying cached draw ops
CustomBg._rawDrawALine = CustomBg.drawALine
CustomBg._rawDrawAVerticalLine = CustomBg.drawAVerticalLine

-- ==================== Main drawing function paintTo (draws lines only, not the background) ====================
-- Detect whether the screen region (x0,y0)-(x1,y1) contains actual text.
-- Used to tell apart two kinds of large inter-line gaps: blank lines between paragraphs (no underline wanted) and missed text lines (underline wanted).
-- When vertical=true, check whether the box's x falls inside the region (vertical column gaps), otherwise check y.
-- Returns true when detection is impossible (conservatively add the line, keeping the old behavior).
function CustomBg:gapHasText(x0, x1, y0, y1, vertical)
    local doc = self.ui and self.ui.document
    if not doc or type(doc.getTextFromPositions) ~= "function"
       or type(doc.getScreenBoxesFromPositions) ~= "function" then
        return true
    end
    local ok, r = pcall(doc.getTextFromPositions, doc,
        {x = x0, y = y0}, {x = x1, y = y1}, true)
    if not ok or not r or not r.pos0 or not r.pos1 or r.pos0 == r.pos1 then
        return false
    end
    local ok2, bxs = pcall(doc.getScreenBoxesFromPositions, doc, r.pos0, r.pos1, true)
    if not ok2 or type(bxs) ~= "table" then return false end
    for _, bx in ipairs(bxs) do
        if bx.w and bx.h and bx.w > 4 and bx.h > 4 then
            if vertical then
                if bx.x > x0 - 4 and (bx.x + bx.w) < x1 + 4 then return true end
            else
                if bx.y > y0 - 4 and (bx.y + bx.h) < y1 + 4 then return true end
            end
        end
    end
    return false
end

-- ===== Line-layer cache (speeds up page turns) =====
-- Computing the underline layout (text boxes, clustering, per-row refinement, gap checks) is the expensive part of a page paint.
-- We compute it once per page state, record the resulting drawing calls, and replay them on later repaints
-- (menus closing, highlights, footer updates, going back to a page, ...).
function CustomBg:_lineCacheKey(bb)
    local doc = self.ui.document
    local page_id
    if type(doc.getXPointer) == "function" then
        local ok, xp = pcall(doc.getXPointer, doc)
        if ok then page_id = xp end
    end
    if not page_id then
        page_id = self.ui.view and self.ui.view.state and self.ui.view.state.page
    end
    if not page_id then return nil end
    -- Layout signature: the xpointer of the page start and the buffer size stay the same after a font /
    -- size / spacing / margin change, so without this the cache replayed lines from the OLD layout
    -- until the document was reloaded. Every field is read defensively (may be nil on some versions).
    local font = self.ui.font
    local cfg = doc.configurable or {}
    local margins = cfg.h_page_margins
    if type(margins) == "table" then margins = table.concat(margins, ",") end
    local cur_page, page_count
    if type(doc.getCurrentPage) == "function" then
        local ok, v = pcall(doc.getCurrentPage, doc)
        if ok then cur_page = v end
    end
    if type(doc.getPageCount) == "function" then
        local ok, v = pcall(doc.getPageCount, doc)
        if ok then page_count = v end
    end
    local layout_sig = table.concat({
        tostring(font and font.font_face), tostring(cfg.font_size), tostring(cfg.line_spacing),
        tostring(margins), tostring(cfg.t_page_margin), tostring(cfg.b_page_margin),
        tostring(cfg.word_spacing), tostring(cfg.font_base_weight),
        tostring(cur_page), tostring(page_count),
    }, ":")
    return table.concat({
        tostring(page_id), layout_sig, bb:getWidth(), bb:getHeight(),
        tostring(doc._is_rotated_by_plugin), tostring(self.fs_line_direction),
        tostring(self.fs_line_mode), tostring(self.fs_color_depth), tostring(self.fs_is_dashed),
        tostring(self.fs_dash_len), tostring(self.fs_offset_y), tostring(self.fs_show_top_line),
        tostring(self.fs_auto_offset), tostring(self.fs_offset_adjust), tostring(self.fs_offset_bias),
        tostring(self.fs_width_ratio), tostring(self.fs_extend_px), tostring(self.fs_gap_threshold),
        tostring(self.fs_skip_titles), tostring(self.fs_title_threshold), tostring(self.fs_wave_mode),
        tostring(self.fs_style_dash_dot), tostring(self.fs_style_heart_dash),
        tostring(self.fs_style_double_solid), tostring(self.fs_style_double_dash),
        tostring(self.fs_double_gap), tostring(Screen.night_mode),
        tostring(self._line_cache_gen or 0),
    }, "|")
end

function CustomBg:invalidateLineCache()
    self._line_cache_gen = (self._line_cache_gen or 0) + 1
    self._line_cache = nil
end

-- Any re-layout (font, size, line spacing, margins, embedded fonts, ...) must drop the line cache,
-- otherwise the lines of the previous layout are replayed until the book is reloaded.
-- KOReader emits UpdatePos after nearly all of them; the others are a safety net.
-- These handlers return nothing, so the event keeps propagating to the other modules.
function CustomBg:onUpdatePos() self:invalidateLineCache() end
function CustomBg:onSetFont() self:invalidateLineCache() end
function CustomBg:onSetFontSize() self:invalidateLineCache() end
function CustomBg:onSetLineSpace() self:invalidateLineCache() end
function CustomBg:onSetPageMargins() self:invalidateLineCache() end
function CustomBg:onSetWordSpacing() self:invalidateLineCache() end
function CustomBg:onSetFontBaseWeight() self:invalidateLineCache() end
function CustomBg:onToggleEmbeddedFonts() self:invalidateLineCache() end
function CustomBg:onToggleEmbeddedStyleSheet() self:invalidateLineCache() end
function CustomBg:onRedrawCurrentView() self:invalidateLineCache() end

function CustomBg:paintTo(bb, x, y)
    -- Self-heal on screen orientation (width/height) change: re-adapt the background automatically after portrait/landscape switching, no need to tap "Reading background" manually
    self:_checkScreenGeom()
    self:_paintOverlay(bb, x, y)   -- pieces mode (no-op otherwise); the ruled lines below are drawn on top of it
    if not self.fs_enabled or not self.ui.document then return end
    if type(self.ui.document.getTextFromPositions) ~= "function" or
       type(self.ui.document.getScreenBoxesFromPositions) ~= "function" then
        return
    end

    local key = self:_lineCacheKey(bb)
    local cache = self._line_cache
    if key and cache and cache.key == key then
        -- Cache hit: just replay the recorded draw calls (no crengine queries)
        for _, op in ipairs(cache.ops) do
            if op[1] == 1 then
                self:_rawDrawALine(bb, op[2], op[3], op[4], op[5], op[6])
            else
                self:_rawDrawAVerticalLine(bb, op[2], op[3], op[4], op[5], op[6])
            end
        end
        return
    end

    -- Cache miss: compute while recording the draw calls
    local ops = {}
    local orig_h, orig_v = self._rawDrawALine, self._rawDrawAVerticalLine
    local saved_h, saved_v = self.drawALine, self.drawAVerticalLine
    self.drawALine = function(this, b, a1, a2, a3, a4, a5)
        ops[#ops + 1] = {1, a1, a2, a3, a4, a5}
        return orig_h(this, b, a1, a2, a3, a4, a5)
    end
    self.drawAVerticalLine = function(this, b, a1, a2, a3, a4, a5)
        ops[#ops + 1] = {2, a1, a2, a3, a4, a5}
        return orig_v(this, b, a1, a2, a3, a4, a5)
    end
    -- The drawing body is protected: if any step hits a nil field (differences between books/layouts),
    -- only log it and skip this draw, instead of aborting the whole page render or popping up a crash window
    local draw_ok, draw_err = pcall(self._paintLines, self, bb)
    -- restore the class methods (we shadowed them on the instance)
    self.drawALine, self.drawAVerticalLine = nil, nil
    if saved_h ~= CustomBg.drawALine then self.drawALine = saved_h end
    if saved_v ~= CustomBg.drawAVerticalLine then self.drawAVerticalLine = saved_v end
    if not draw_ok then
        self._line_cache = nil
    elseif key then
        self._line_cache = { key = key, ops = ops }
    end
end

-- ============ mode 4 (underline below text only) helper functions ============

-- Iterate UTF-8 characters one by one (Lua 5.1 has no utf8 library; determine the length from the first byte)
local function utf8_chars(s)
    local i = 1
    return function()
        if i > #s then return nil end
        local b = s:byte(i)
        local len = 1
        if b >= 0xF0 then len = 4 elseif b >= 0xE0 then len = 3
        elseif b >= 0xC0 then len = 2 end
        local ch = s:sub(i, i + len - 1)
        i = i + len
        return ch
    end
end

-- Whitespace-like characters: half-width space/tab/newline, full-width space (U+3000), no-break space (U+00A0)
local IS_WS_CHAR = {
    [" "] = true, ["\t"] = true, ["\n"] = true, ["\r"] = true,
    ["　"] = true, ["\194\160"] = true,
}

-- Whether any content remains after removing all whitespace (used to judge "is there punctuation hidden in the line-start indent area")
local function has_visible_char(s)
    if not s or s == "" then return false end
    for ch in utf8_chars(s) do
        if not IS_WS_CHAR[ch] then return true end
    end
    return false
end

-- Estimate the x/y offset of the "first visible character" within the line-start area:
-- the input is the text of that area and its pixel width. Weighted by character width (ASCII counts 0.5, full-width counts 1),
-- returns the offset in pixels; returns nil if the whole area is blank.
local function first_visible_offset(text, region_w)
    if not text or text == "" or region_w <= 0 then return nil end
    local total_units, vis_units = 0, nil
    for ch in utf8_chars(text) do
        if vis_units == nil and not IS_WS_CHAR[ch] then
            vis_units = total_units
        end
        total_units = total_units + ((#ch > 1) and 1.0 or 0.5)
    end
    if vis_units == nil or total_units <= 0 then return nil end
    local frac = vis_units / total_units
    if frac > 1 then frac = 1 end
    return math.floor(region_w * frac + 0.5)
end

function CustomBg:_paintLines(bb)
    local screen_w = bb:getWidth()
    local screen_h = bb:getHeight()

    -- ===== Coordinate system selection =====
    -- In pseudo-vertical mode (engine rotation patch active), the crengine viewport width/height are swapped,
    -- and the whole page is rotated by -90° before being blitted back to the screen. In that case:
    --   * fetching text boxes, clustering and judging gaps must all be done in the "engine coordinate system" (otherwise no lines are found -> not a single line is drawn);
    --   * the computed rectangles must be mapped back to screen coordinates before drawing (a horizontal line in the engine appears as a vertical line on screen).
    -- Mapping between engine coordinates (cx,cy) and screen coordinates (sx,sy) (derived for Blitbuffer rotation=3):
    --   sx = VH - 1 - cy ,  sy = cx        (VH = engine viewport height = screen_w)
    -- So the engine rectangle [cx, cx+w) × [cy, cy+t) maps to the screen rectangle:
    --   x = VH - cy - t ,  width t ; y = cx , height w
    local rotated = (self.ui.document._is_rotated_by_plugin == true)
    local VW, VH = screen_w, screen_h
    if rotated then VW, VH = screen_h, screen_w end

    local is_two_page = false
    local split_x = VW / 2
    if type(self.ui.document.getVisiblePageCount) == "function" then
        if self.ui.document:getVisiblePageCount() > 1 then
            is_two_page = true
            if type(self.ui.document.getPageOffsetX) == "function" then
                local current_page = self.ui.document:getCurrentPage(true)
                split_x = self.ui.document:getPageOffsetX(current_page + 1) or (VW / 2)
            end
        end
    end

    local res = self.ui.document:getTextFromPositions({x = 0, y = 0}, {x = VW, y = VH}, true)
    if not res or not res.pos0 or not res.pos1 then return end

    -- Box-fetching strategy (see cre.cpp getWordBoxesFromPositions):
    --   segments=true  -> crengine's native "whole line segment" rectangles, correctly split per line,
    --                     including line-start indent whitespace and leading/trailing punctuation;
    --   segments=false -> merged from visible word rectangles, starting at the first visible character of the line,
    --                     but with two low-level defects (confirmed in cre.cpp):
    --                     a) line breaks are detected by "wordRect.left < lastx" (x going backwards),
    --                        so a short line (<=3 chars) followed by an indented line does not move x backwards and the two lines are merged into one box;
    --                     b) leading/trailing punctuation belongs to no "word" and is simply discarded.
    -- Therefore line/column structure is always clustered with segments=true; mode 4 ("underline below text only")
    -- gets its "avoid indent, cover punctuation" behavior from the per-line word-box refinement in
    -- refine_row_bounds/refine_col_bounds below.
    local boxes = self.ui.document:getScreenBoxesFromPositions(res.pos0, res.pos1, true)
    if not boxes or #boxes == 0 then return end

    local gray_val = math.floor(255 - (self.fs_color_depth * 25.5))
    local line_color = Blitbuffer.Color8(math.max(0, math.min(255, gray_val)))
    local thickness = Size.line.medium or 2

    -- Plain-text formats (txt etc.): such books usually have no page numbers/headers,
    -- and short bottom lines are basically paragraph-final lines, so no "suspected footer" removal is done afterwards, avoiding missed underlines on the last lines
    local is_plain_text = (self.ui.document.is_txt == true)
    local doc_file = self.ui.document.file
    if type(doc_file) == "string" then
        local lower = doc_file:lower()
        if lower:find("%.txt$") or lower:find("%.txt%.zip$") then
            is_plain_text = true
        end
    end

    -- Drawing adapter from the engine coordinate system -> screen coordinate system
    local draw_h, draw_v
    if rotated then
        -- An engine "horizontal line" -> a vertical line on screen; an engine "vertical line" -> a horizontal line on screen
        draw_h = function(bbx, cx, cy, cw, t, c)
            self:drawAVerticalLine(bbx, VH - cy - t, cx, cw, t, c)
        end
        draw_v = function(bbx, cx, cy, t, ch, c)
            self:drawALine(bbx, VH - cy - ch, cx, ch, t, c)
        end
    else
        draw_h = function(bbx, cx, cy, cw, t, c)
            self:drawALine(bbx, cx, cy, cw, t, c)
        end
        draw_v = function(bbx, cx, cy, t, ch, c)
            self:drawAVerticalLine(bbx, cx, cy, ch, t, c)
        end
    end

    -- —— mode 4 only: per-row/per-column "word box" refinement ——
    -- Row-segment rectangles include indentation and punctuation at both ends; here a word-box query for "this row only" shrinks the start to the
    -- first visible character, then adds back the leading/trailing punctuation (word boxes discard punctuation).
    local refine_doc = self.ui.document

    -- Horizontal layout: refine one row (engine coordinates; in pseudo-vertical mode this row maps to a column on screen)
    local function refine_row_bounds(line)
        local row_h = line.bottom - line.y
        if row_h <= 0 then return end
        -- Only take the middle of the row as the query band, so character boxes from adjacent rows do not leak in
        local band_y0 = line.y + math.floor(row_h * 0.3)
        local band_y1 = line.bottom - math.floor(row_h * 0.3)
        if band_y1 <= band_y0 then band_y1 = band_y0 + 1 end
        local ok, r = pcall(refine_doc.getTextFromPositions, refine_doc,
            { x = line.min_x, y = band_y0 }, { x = line.max_x, y = band_y1 }, true)
        if not ok or not r or not r.pos0 or not r.pos1 then return end
        local ok2, wb = pcall(refine_doc.getScreenBoxesFromPositions, refine_doc,
            r.pos0, r.pos1, false)
        if not ok2 or type(wb) ~= "table" or #wb == 0 then return end
        local wmin, wmax
        for _, b in ipairs(wb) do
            if b.w and b.h and b.w > 0 and b.h > 0 then
                local top = math.max(b.y, line.y)
                local bot = math.min(b.y + b.h, line.bottom)
                if bot - top > row_h * 0.3 then
                    if not wmin or b.x < wmin then wmin = b.x end
                    local bx2 = b.x + b.w
                    if not wmax or bx2 > wmax then wmax = bx2 end
                end
            end
        end
        if not wmin then return end
        -- Start: first visible character; if it is preceded by line-start punctuation (non-whitespace), shift forward proportionally to character width to cover it
        local new_min = wmin
        if wmin - line.min_x >= 2 then
            local ok3, rt = pcall(refine_doc.getTextFromPositions, refine_doc,
                { x = line.min_x, y = band_y0 }, { x = wmin - 1, y = band_y1 }, true)
            local lead_text = (ok3 and rt and rt.text) or nil
            if lead_text and has_visible_char(lead_text) then
                local off = first_visible_offset(lead_text, wmin - line.min_x)
                if off then new_min = line.min_x + off end
            end
        end
        -- End: the row segment's right edge already includes trailing punctuation; if the word box is wider, take the wider one
        local new_max = line.max_x
        if wmax and wmax > new_max then new_max = wmax end
        line.min_x = new_min
        line.max_x = new_max
    end

    -- Vertical layout (true vertical, dir 3): refine one column (column start = top, trailing punctuation at the bottom)
    local function refine_col_bounds(col)
        local col_w = col.right - col.x
        if col_w <= 0 then return end
        local band_x0 = col.x + math.floor(col_w * 0.3)
        local band_x1 = col.right - math.floor(col_w * 0.3)
        if band_x1 <= band_x0 then band_x1 = band_x0 + 1 end
        local ok, r = pcall(refine_doc.getTextFromPositions, refine_doc,
            { x = band_x0, y = col.min_y }, { x = band_x1, y = col.max_y }, true)
        if not ok or not r or not r.pos0 or not r.pos1 then return end
        local ok2, wb = pcall(refine_doc.getScreenBoxesFromPositions, refine_doc,
            r.pos0, r.pos1, false)
        if not ok2 or type(wb) ~= "table" or #wb == 0 then return end
        local wmin, wmax
        for _, b in ipairs(wb) do
            if b.w and b.h and b.w > 0 and b.h > 0 then
                local left = math.max(b.x, col.x)
                local right = math.min(b.x + b.w, col.right)
                if right - left > col_w * 0.3 then
                    if not wmin or b.y < wmin then wmin = b.y end
                    local by2 = b.y + b.h
                    if not wmax or by2 > wmax then wmax = by2 end
                end
            end
        end
        if not wmin then return end
        local new_min = wmin
        if wmin - col.min_y >= 2 then
            local ok3, rt = pcall(refine_doc.getTextFromPositions, refine_doc,
                { x = band_x0, y = col.min_y }, { x = band_x1, y = wmin - 1 }, true)
            local lead_text = (ok3 and rt and rt.text) or nil
            if lead_text and has_visible_char(lead_text) then
                local off = first_visible_offset(lead_text, wmin - col.min_y)
                if off then new_min = col.min_y + off end
            end
        end
        local new_max = col.max_y
        if wmax and wmax > new_max then new_max = wmax end
        col.min_y = new_min
        col.max_y = new_max
    end

    -- In pseudo-vertical mode the engine is still horizontal internally, so it must go through the "horizontal-line branch" clustering and then be mapped to screen vertical lines;
    -- true vertical text (direction 3) leaves the engine unrotated, screen coordinates equal engine coordinates, so it goes through the vertical-line branch.
    if rotated or self.fs_line_direction == 1 then
        -- Horizontal line drawing (original logic kept intact)
        local raw_lines = {}
        -- Estimate the body line height as the clustering tolerance, so differing font sizes do not split one visual line into several / miss lines
        local all_h = {}
        for _, box in ipairs(boxes) do
            if box.h and box.h > 0 then all_h[#all_h + 1] = box.h end
        end
        table.sort(all_h)
        local median_h = all_h[math.floor(#all_h / 2)] or 20
        local merge_band = math.max(4, math.floor(median_h * 0.6))
        for _, box in ipairs(boxes) do
            -- Skip invalid char boxes (width/height 0 or negative) to avoid ghost lines
            if box.h and box.w and box.h > 0 and box.w > 0 then
                local box_page = (is_two_page and box.x >= split_x) and 2 or 1
                local found = nil
                for _, line in ipairs(raw_lines) do
                    if line.page == box_page then
                        -- Line clustering is based on "vertical overlap" rather than only comparing the top y:
                        -- formats like txt / html / fb2 often mix Chinese and English, superscripts/subscripts and punctuation,
                        -- so the y and h of char boxes within one visual line can differ a lot;
                        -- comparing only the top edge would split one line into two and draw two overlapping underlines.
                        local top = math.max(line.y, box.y)
                        local bot = math.min(line.bottom, box.y + box.h)
                        local overlap = bot - top
                        local min_h = math.min(line.bottom - line.y, box.h)
                        if (min_h > 0 and overlap > min_h * 0.35)
                           or math.abs(line.y - box.y) < merge_band then
                            found = line
                            break
                        end
                    end
                end
                if found then
                    found.y = math.min(found.y, box.y)
                    found.bottom = math.max(found.bottom, box.y + box.h)
                    found.min_x = math.min(found.min_x, box.x)
                    found.max_x = math.max(found.max_x, box.x + box.w)
                else
                    table.insert(raw_lines, {
                        page = box_page,
                        y = box.y, bottom = box.y + box.h,
                        min_x = box.x, max_x = box.x + box.w
                    })
                end
            end
        end
        table.sort(raw_lines, function(a, b) return a.y < b.y end)

        local pages_lines = {{}, {}}
        for _, line in ipairs(raw_lines) do
            table.insert(pages_lines[line.page], line)
        end

        for page_idx, p_lines in ipairs(pages_lines) do
            if #p_lines > 0 then
                local col_min_x = page_idx == 1 and 0 or split_x
                local col_max_x = page_idx == 1 and split_x or VW
                if not is_two_page then
                    col_min_x = 0
                    col_max_x = VW
                end
                local col_w = col_max_x - col_min_x

                local global_min_x = col_max_x
                local global_max_x = col_min_x
                local height_counts = {}
                for _, line in ipairs(p_lines) do
                    global_min_x = math.min(global_min_x, line.min_x)
                    global_max_x = math.max(global_max_x, line.max_x)
                    local h = math.floor((line.bottom - line.y) / 2) * 2
                    height_counts[h] = (height_counts[h] or 0) + 1
                end
                local global_width = global_max_x - global_min_x

                local max_count, body_h = 0, 20
                for h, c in pairs(height_counts) do
                    if c > max_count then max_count = c; body_h = h end
                end

                -- Only remove suspected footers (page numbers): bottom + very short + not left-aligned must all hold at once.
                -- The old criterion only looked at "bottom + short" and also deleted the last line of a paragraph at the bottom of the page, causing a missed underline on that last line.
                -- Plain-text formats such as txt / fb2 usually have no page numbers at all, and short bottom lines are basically paragraph-final lines,
                -- so no footer removal is done for such formats.
                local text_lines = {}
                for _, line in ipairs(p_lines) do
                    local is_footer = false
                    if (not is_plain_text)
                       and line.y > VH * 0.9
                       and ((line.max_x - line.min_x) < col_w * 0.2) then
                        -- Key criterion: page numbers are usually centered/right-aligned, whereas the last line of a paragraph always starts at the body's left margin.
                        -- Using "is it left-aligned" to tell them apart is far more reliable than "is there a gap above"
                        -- (paragraph spacing also creates gaps, which easily misjudges a paragraph's last line as a page number).
                        local left_offset = line.min_x - global_min_x
                        if left_offset > col_w * 0.15 then
                            is_footer = true
                        end
                    end
                    if not is_footer then
                        table.insert(text_lines, line)
                    end
                end
                if #text_lines > 0 then
                    local safe_line_height = math.floor(body_h * 1.5)
                    local gap_counts = {}
                    for i = 1, #text_lines - 1 do
                        local gap = text_lines[i+1].y - text_lines[i].y
                        gap = math.floor(gap / 2) * 2
                        gap_counts[gap] = (gap_counts[gap] or 0) + 1
                    end
                    local max_g_count, most_common_gap = 0, safe_line_height
                    for g, c in pairs(gap_counts) do
                        if c > max_g_count then max_g_count = c; most_common_gap = g end
                    end
                    local line_height = most_common_gap
                    if line_height < body_h then line_height = safe_line_height end
                    -- Fall back when the line height is abnormally large (suspected missed lines), to avoid misaligning the whole grid
                    if line_height > body_h * 2.2 then line_height = safe_line_height end

                    -- Vertical position of the line below each text row.
                    -- Auto: centre it in the gap between two consecutive line boxes (gap = pitch - box height),
                    -- so it follows the font, its size and the line spacing. If the pitch could not be measured
                    -- reliably (fallback was used), assume no extra leading. fs_offset_adjust fine-tunes on top.
                    local off_y = self.fs_offset_y
                    if self.fs_auto_offset then
                        local pitch_ok = (most_common_gap >= body_h and most_common_gap <= body_h * 2.2)
                        local pitch = pitch_ok and most_common_gap or body_h
                        -- The line box has more air above the letters (ascent metric > cap height) than below
                        -- (descent ~ descender ink), so the geometric centre sits too close to the descenders
                        -- of this row. Push the line down by a small fraction of the box height.
                        local bias = math.floor(body_h * self.fs_offset_bias / 100 + 0.5)
                        off_y = math.max(0, math.floor((pitch - body_h) / 2 + 0.5)) + bias + self.fs_offset_adjust
                    end

                    local function is_space_empty(pos)
                        for _, line in ipairs(text_lines) do
                            if pos > line.y + 4 and pos < line.bottom - 4 then return false end
                        end
                        return true
                    end

                    local function get_bounds(line_ref)
                        local sx, dw
                        if self.fs_line_mode == 1 then
                            sx, dw = col_min_x, col_w
                        elseif self.fs_line_mode == 2 then
                            dw = col_w * (self.fs_width_ratio / 1000)
                            sx = col_min_x + (col_w - dw) / 2
                        else
                            sx = global_min_x - self.fs_extend_px
                            dw = global_width + (self.fs_extend_px * 2)
                            if line_ref then
                                local left_gap = line_ref.min_x - global_min_x
                                local right_gap = global_max_x - line_ref.max_x
                                if left_gap > global_width * 0.15 and right_gap > global_width * 0.15 then
                                    sx = line_ref.min_x - self.fs_extend_px
                                    dw = (line_ref.max_x - line_ref.min_x) + (self.fs_extend_px * 2)
                                end
                            end
                        end
                        return sx, dw
                    end

                    local function draw_at(dy, ref)
                        local sx, dw = get_bounds(ref)
                        draw_h(bb, sx, dy, dw, thickness, line_color)
                    end

                    for i, line in ipairs(text_lines) do
                        line.is_title = false
                        if self.fs_skip_titles then
                            local line_h = line.bottom - line.y
                            local line_w = line.max_x - line.min_x
                            local is_short = line_w < (global_width * 0.85)
                            local is_taller = line_h >= (body_h * self.fs_title_threshold)
                            local left_margin = line.min_x - global_min_x
                            local right_margin = global_max_x - line.max_x
                            local is_centered = false
                            if is_short and left_margin > (global_width * 0.15) and right_margin > (global_width * 0.15) and math.abs(left_margin - right_margin) < (global_width * 0.15) then
                                is_centered = true
                            end
                            -- Judge a heading only from the "large gap before the line": a gap above means a chapter start (heading).
                            -- The gap after the line is not considered: a large gap after a line is a "chapter end" feature, which would misjudge the last (short) line
                            -- of the previous chapter as a heading and miss its underline.
                            local has_extra_gap = false
                            if is_short and i > 1 then
                                local prev_gap = line.y - text_lines[i-1].bottom
                                if prev_gap > line_height * 1.2 then has_extra_gap = true end
                            end
                            if is_short and (is_taller or is_centered or has_extra_gap) then
                                line.is_title = true
                            end
                        end
                    end

                    local first_normal_idx, last_normal_idx
                    for i = 1, #text_lines do
                        if not text_lines[i].is_title then first_normal_idx = i; break end
                    end
                    for i = #text_lines, 1, -1 do
                        if not text_lines[i].is_title then last_normal_idx = i; break end
                    end

                    if first_normal_idx then
                        if self.fs_line_mode == 4 then
                            -- First merge "lines" that almost coincide vertically, then draw:
                            -- different formats (txt/fb2/html etc.) return char-box heights inconsistently,
                            -- so one visual line may be split into several records, and drawing each one directly would produce
                            -- two underlines stuck together (looking like one thick or fuzzy line).
                            local merged = {}
                            local cur = nil
                            for i = first_normal_idx, last_normal_idx do
                                local line = text_lines[i]
                                if not line.is_title then
                                    if cur and math.abs(line.bottom - cur.bottom) <= 4 then
                                        cur.min_x = math.min(cur.min_x, line.min_x)
                                        cur.max_x = math.max(cur.max_x, line.max_x)
                                        cur.bottom = math.max(cur.bottom, line.bottom)
                                    else
                                        cur = {
                                            y = line.y,
                                            bottom = line.bottom,
                                            min_x = line.min_x,
                                            max_x = line.max_x,
                                        }
                                        merged[#merged + 1] = cur
                                    end
                                end
                            end
                            for _, line in ipairs(merged) do
                                -- Per-line refinement: start shrinks to the first visible character, leading/trailing punctuation is added back
                                refine_row_bounds(line)
                                local dy = line.bottom + off_y
                                local sx = line.min_x - self.fs_extend_px
                                local dw = (line.max_x - line.min_x) + self.fs_extend_px * 2
                                if dw > 0 then
                                    draw_h(bb, sx, dy, dw, thickness, line_color)
                                end
                            end
                        else
                            local first_line = text_lines[first_normal_idx]
                            local cur_y = first_line.bottom + off_y - line_height
                            if self.fs_show_top_line then
                                if is_space_empty(cur_y) then draw_at(cur_y, first_line) end
                                cur_y = cur_y - line_height
                                local top_gap = first_line.y
                                if top_gap < (line_height * self.fs_gap_threshold) then
                                    while cur_y > 0 do
                                        if is_space_empty(cur_y) then draw_at(cur_y, first_line) end
                                        cur_y = cur_y - line_height
                                    end
                                end
                            end

                            for i = first_normal_idx, last_normal_idx do
                                local line = text_lines[i]
                                if not line.is_title then
                                    local dy = line.bottom + off_y
                                    draw_at(dy, line)
                                    local next_normal_line = nil
                                    local next_idx = i + 1
                                    while next_idx <= last_normal_idx do
                                        if not text_lines[next_idx].is_title then
                                            next_normal_line = text_lines[next_idx]
                                            break
                                        end
                                        next_idx = next_idx + 1
                                    end
                                    if next_normal_line then
                                        local next_y = next_normal_line.y
                                        local gap_distance = next_y - dy
                                        if (next_idx == i + 1) and (gap_distance < (line_height * self.fs_gap_threshold)) then
                                            -- Gap smaller than one line height: normal line-height detection error, just add the line;
                                            -- gap of one line height or more: could be a blank line between paragraphs (no line wanted),
                                            -- or a missed text line (line wanted); confirm there is actually text in the gap before adding
                                            local need_fill = true
                                            if gap_distance >= line_height then
                                                need_fill = self:gapHasText(col_min_x, col_max_x, dy + 4, next_y - 4)
                                            end
                                            if need_fill then
                                                local f_y = dy + line_height
                                                while f_y < next_y - 2 do
                                                    if is_space_empty(f_y) then draw_at(f_y, nil) end
                                                    f_y = f_y + line_height
                                                end
                                            end
                                        end
                                    end
                                end
                            end

                            -- Last-row (bottom) boundary line: the text lines' own underlines are already guaranteed by the loop above.
                            -- This part draws the "outer grid extension line" at the position of the row below the text area:
                            -- - Full-screen grid / custom ratio modes (1/2): kept, the grid fills the page;
                            -- - Smart text-aligned mode (3): no longer added "forcibly". First use gapHasText to confirm
                            --   that there really is text below the paragraph (a continuation line or a missed line) before adding this row;
                            --   large blank areas caused by chapter ends / paragraph whitespace no longer get underlines.
                            local last_line = text_lines[last_normal_idx]
                            local bottom_gap = VH - last_line.bottom
                            local allow_bottom_grid = true
                            if self.fs_line_mode == 3 then
                                allow_bottom_grid = self:gapHasText(
                                    col_min_x, col_max_x,
                                    last_line.bottom + 4,
                                    last_line.bottom + line_height * 1.5)
                            end
                            if allow_bottom_grid then
                                local cur_y = last_line.bottom + off_y + line_height
                                if is_space_empty(cur_y) then draw_at(cur_y, last_line) end
                                -- Only full-screen grid style modes keep filling downward; smart-align mode only adds the immediately adjacent row,
                                -- to avoid the blank area at the end of a paragraph being filled with grid lines across the whole screen
                                if self.fs_line_mode ~= 3 and bottom_gap < (line_height * self.fs_gap_threshold) then
                                    cur_y = cur_y + line_height
                                    while cur_y < VH do
                                        if is_space_empty(cur_y) then draw_at(cur_y, last_line) end
                                        cur_y = cur_y + line_height
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

    else -- vertical line
        local raw_cols = {}
        -- Estimate the body column width as the x-clustering tolerance, to avoid missing columns
        local all_w = {}
        for _, box in ipairs(boxes) do
            if box.w and box.w > 0 then all_w[#all_w + 1] = box.w end
        end
        table.sort(all_w)
        local median_w = all_w[math.floor(#all_w / 2)] or 20
        local merge_band = math.max(4, math.floor(median_w * 0.6))
        for _, box in ipairs(boxes) do
            -- Skip invalid char boxes, to avoid ghost columns
            if box.h and box.w and box.h > 0 and box.w > 0 then
                local box_page = 1
                if is_two_page then
                    box_page = (box.y >= screen_h / 2) and 2 or 1
                end
                local found = nil
                for _, col in ipairs(raw_cols) do
                    if col.page == box_page then
                        -- Same as for horizontal lines: cluster by "horizontal overlap", compatible with variant characters / mixed text
                        local left = math.max(col.x, box.x)
                        local right = math.min(col.right, box.x + box.w)
                        local overlap = right - left
                        local min_w = math.min(col.right - col.x, box.w)
                        if (min_w > 0 and overlap > min_w * 0.35)
                           or math.abs(col.x - box.x) < merge_band then
                            found = col
                            break
                        end
                    end
                end
                if found then
                    found.x = math.min(found.x, box.x)
                    found.right = math.max(found.right, box.x + box.w)
                    found.min_y = math.min(found.min_y, box.y)
                    found.max_y = math.max(found.max_y, box.y + box.h)
                else
                    table.insert(raw_cols, {
                        page = box_page,
                        x = box.x, right = box.x + box.w,
                        min_y = box.y, max_y = box.y + box.h
                    })
                end
            end
        end
        table.sort(raw_cols, function(a, b) return a.x > b.x end)

        local pages_cols = {{}, {}}
        for _, col in ipairs(raw_cols) do
            table.insert(pages_cols[col.page], col)
        end

        for page_idx, p_cols in ipairs(pages_cols) do
            if #p_cols > 0 then
                local row_min_y = page_idx == 1 and 0 or (screen_h / 2)
                local row_max_y = page_idx == 1 and (screen_h / 2) or screen_h
                if not is_two_page then
                    row_min_y = 0
                    row_max_y = screen_h
                end
                local row_h = row_max_y - row_min_y

                local global_min_y = row_max_y
                local global_max_y = row_min_y
                local width_counts = {}
                for _, col in ipairs(p_cols) do
                    global_min_y = math.min(global_min_y, col.min_y)
                    global_max_y = math.max(global_max_y, col.max_y)
                    local w = math.floor((col.right - col.x) / 2) * 2
                    width_counts[w] = (width_counts[w] or 0) + 1
                end
                local global_height = global_max_y - global_min_y

                local max_count, body_w = 0, 20
                for w, c in pairs(width_counts) do
                    if c > max_count then max_count = c; body_w = w end
                end

                -- Only remove suspected page-number columns that are extremely close to the edge and very narrow, to avoid deleting the left-most (last) body column of vertical text
                -- (plain-text formats have no page numbers; skip this removal entirely)
                local text_cols = {}
                for _, col in ipairs(p_cols) do
                    local is_pagenum = (not is_plain_text)
                                   and (col.x < screen_w * 0.05)
                                   and ((col.max_y - col.min_y) < body_w * 0.7)
                    if not is_pagenum then
                        table.insert(text_cols, col)
                    end
                end
                if #text_cols > 0 then
                    local safe_col_width = math.floor(body_w * 1.5)
                    local gap_counts = {}
                    for i = 1, #text_cols - 1 do
                        local gap = text_cols[i].x - text_cols[i+1].x
                        gap = math.floor(gap / 2) * 2
                        gap_counts[gap] = (gap_counts[gap] or 0) + 1
                    end
                    local max_g_count, most_common_gap = 0, safe_col_width
                    for g, c in pairs(gap_counts) do
                        if c > max_g_count then max_g_count = c; most_common_gap = g end
                    end
                    local col_width = most_common_gap
                    if col_width < body_w then col_width = safe_col_width end
                    -- Fall back when the column width is abnormally large (suspected missed columns), to avoid misaligning the whole grid
                    if col_width > body_w * 2.2 then col_width = safe_col_width end

                    -- Same idea as the horizontal branch: centre the column line in the gap between columns
                    local off_x = self.fs_offset_y
                    if self.fs_auto_offset then
                        local pitch_ok = (most_common_gap >= body_w and most_common_gap <= body_w * 2.2)
                        local pitch = pitch_ok and most_common_gap or body_w
                        local bias = math.floor(body_w * self.fs_offset_bias / 100 + 0.5)
                        off_x = math.max(0, math.floor((pitch - body_w) / 2 + 0.5)) + bias + self.fs_offset_adjust
                    end

                    local function is_space_empty(pos)
                        for _, col in ipairs(text_cols) do
                            if pos > col.x + 4 and pos < col.right - 4 then return false end
                        end
                        return true
                    end

                    local function get_bounds(col_ref)
                        local sy, dh
                        if self.fs_line_mode == 1 then
                            sy, dh = row_min_y, row_h
                        elseif self.fs_line_mode == 2 then
                            dh = row_h * (self.fs_width_ratio / 1000)
                            sy = row_min_y + (row_h - dh) / 2
                        else
                            sy = global_min_y - self.fs_extend_px
                            dh = global_height + (self.fs_extend_px * 2)
                            if col_ref then
                                local top_gap = col_ref.min_y - global_min_y
                                local bottom_gap = global_max_y - col_ref.max_y
                                if top_gap > global_height * 0.15 and bottom_gap > global_height * 0.15 then
                                    sy = col_ref.min_y - self.fs_extend_px
                                    dh = (col_ref.max_y - col_ref.min_y) + (self.fs_extend_px * 2)
                                end
                            end
                        end
                        return sy, dh
                    end

                    local function draw_at(dx, ref)
                        local sy, dh = get_bounds(ref)
                        self:drawAVerticalLine(bb, dx, sy, dh, thickness, line_color)
                    end

                    for i, col in ipairs(text_cols) do
                        col.is_title = false
                        if self.fs_skip_titles then
                            local col_w = col.right - col.x
                            local col_h = col.max_y - col.min_y
                            local is_short = col_h < (global_height * 0.85)
                            local is_wider = col_w >= (body_w * self.fs_title_threshold)
                            local top_margin = col.min_y - global_min_y
                            local bottom_margin = global_max_y - col.max_y
                            local is_centered = false
                            if is_short and top_margin > (global_height * 0.15) and bottom_margin > (global_height * 0.15) and math.abs(top_margin - bottom_margin) < (global_height * 0.15) then
                                is_centered = true
                            end
                            -- Judge a heading only from the large gap before the column (on the right side), to avoid misjudging a chapter's last column (same logic as horizontal lines)
                            local has_extra_gap = false
                            if is_short and i > 1 then
                                local prev_gap = text_cols[i-1].x - col.right
                                if prev_gap > col_width * 1.2 then has_extra_gap = true end
                            end
                            if is_short and (is_wider or is_centered or has_extra_gap) then
                                col.is_title = true
                            end
                        end
                    end

                    local first_normal_idx, last_normal_idx
                    for i = 1, #text_cols do
                        if not text_cols[i].is_title then first_normal_idx = i; break end
                    end
                    for i = #text_cols, 1, -1 do
                        if not text_cols[i].is_title then last_normal_idx = i; break end
                    end

                    -- "Underline below text only" (for vertical text this means "left side of each column"): draw only over each column's actual text extent,
                    -- no grid extension lines. Also first merge "columns" whose x almost coincides, to avoid two vertical lines stuck together.
                    if first_normal_idx and self.fs_line_mode == 4 then
                        local merged = {}
                        local cur = nil
                        for i = first_normal_idx, last_normal_idx do
                            local c = text_cols[i]
                            if not c.is_title then
                                if cur and math.abs(c.x - cur.x) <= 4 then
                                    cur.min_y = math.min(cur.min_y, c.min_y)
                                    cur.max_y = math.max(cur.max_y, c.max_y)
                                else
                                    cur = { x = c.x, right = c.right, min_y = c.min_y, max_y = c.max_y }
                                    merged[#merged + 1] = cur
                                end
                            end
                        end
                        for _, c in ipairs(merged) do
                            -- Per-column refinement: start shrinks to the first visible character of the column, leading/trailing punctuation is added back
                            refine_col_bounds(c)
                            local dx = c.x - off_x
                            local sy = c.min_y - self.fs_extend_px
                            local dh = (c.max_y - c.min_y) + self.fs_extend_px * 2
                            if dh > 0 then
                                self:drawAVerticalLine(bb, dx, sy, dh, thickness, line_color)
                            end
                        end
                    elseif first_normal_idx then
                        local first_col = text_cols[first_normal_idx]
                        local cur_x = (first_col.x - off_x) + col_width
                        if is_space_empty(cur_x) then draw_at(cur_x, first_col) end
                        if self.fs_show_top_line then
                            cur_x = cur_x + col_width
                            local right_gap = screen_w - first_col.right
                            if right_gap < (col_width * self.fs_gap_threshold) then
                                while cur_x < screen_w do
                                    if is_space_empty(cur_x) then draw_at(cur_x, first_col) end
                                    cur_x = cur_x + col_width
                                end
                            end
                        end

                        for i = first_normal_idx, last_normal_idx do
                            local col = text_cols[i]
                            if not col.is_title then
                                local dx = col.x - off_x
                                draw_at(dx, col)
                                local next_normal_col = nil
                                local next_idx = i + 1
                                while next_idx <= last_normal_idx do
                                    if not text_cols[next_idx].is_title then
                                        next_normal_col = text_cols[next_idx]
                                        break
                                    end
                                    next_idx = next_idx + 1
                                end
                                if next_normal_col then
                                    local next_x = next_normal_col.right
                                    local gap_distance = dx - next_x
                                    if (next_idx == i + 1) and (gap_distance < (col_width * self.fs_gap_threshold)) then
                                        -- Same as the horizontal branch: a large gap needs confirmation that it really contains text (a missed column) before adding a line,
                                        -- blank columns between paragraphs get no line, to avoid vertical lines in blank areas
                                        local need_fill = true
                                        if gap_distance >= col_width then
                                            need_fill = self:gapHasText(next_x + 4, dx - 4, 0, screen_h, true)
                                        end
                                        if need_fill then
                                            local f_x = dx - col_width
                                            while f_x > next_normal_col.x + off_x + 2 do
                                                if is_space_empty(f_x) then draw_at(f_x, nil) end
                                                f_x = f_x - col_width
                                            end
                                        end
                                    end
                                end
                            end
                        end

                        -- Last column (left/final) boundary line: same as the horizontal branch --
                        -- in smart text-aligned mode (3) it is no longer added "forcibly": first use gapHasText to confirm there is really text to the right of the last column
                        -- (or below it, in two-page mode) before adding this column; blank areas at chapter ends no longer get vertical lines.
                        local last_col = text_cols[last_normal_idx]
                        local left_gap = last_col.x - 0
                        local allow_left_grid = true
                        if self.fs_line_mode == 3 then
                            -- Note: the vertical column structure only has x/right/min_y/max_y (no y/bottom),
                            -- so min_y/max_y must be used here; misusing y/bottom yields nil and aborts drawing
                            allow_left_grid = self:gapHasText(
                                last_col.right + 4, screen_w,
                                last_col.min_y - 4, last_col.max_y + 4, true)
                        end
                        if allow_left_grid then
                            local cur_x = (last_col.x - off_x) - col_width
                            if is_space_empty(cur_x) then draw_at(cur_x, last_col) end
                            -- Only full-screen grid style modes keep filling leftward; smart-align mode only adds the immediately adjacent column
                            if self.fs_line_mode ~= 3 and left_gap < (col_width * self.fs_gap_threshold) then
                                cur_x = cur_x - col_width
                                while cur_x > 0 do
                                    if is_space_empty(cur_x) then draw_at(cur_x, last_col) end
                                    cur_x = cur_x - col_width
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ==================== Initialization ====================
function CustomBg:init()
    self.ui.custombg = self
    -- Only the first "full" refresh requested for this book (the one done by KOReader when it shows the book) is softened;
    -- the flag also expires by itself so a later, explicit full refresh is never touched.
    self._open_pending = true
    UIManager:scheduleIn(5, function() self._open_pending = nil end)
    local folder = getBackgroundsFolder()
    self.cache_day = loadImageList(folder, SCENE_DAY)
    self.cache_night = loadImageList(folder, SCENE_NIGHT)
    self:hookReaderRolling()
    self:hookScreenRotation()
    self:hookSleepScreen()
    self:loadLineSettings()
    if self.ui.view then
        self.ui.view:registerViewModule("custombg_lines", self)
    end
    self:applyVerticalEnginePatch()
    self.ui.menu:registerToMainMenu(self)

    self:startNightModeChecker()
    self._bg_last_sw = Screen:getWidth()
    self._bg_last_sh = Screen:getHeight()
    local initial_scene = Screen.night_mode and SCENE_NIGHT or SCENE_DAY
    if self:getSceneMode() ~= initial_scene then
        self:switchScene(initial_scene)
    else
        self:loadBackgroundByName(nil)
    end
end

function CustomBg:startNightModeChecker()
    self._last_night_mode = Screen.night_mode
    self:_scheduleNightCheck()
end

function CustomBg:_scheduleNightCheck()
    self._night_check_timer = UIManager:scheduleIn(1.0, function()
        self:_checkNightMode()
    end)
end

function CustomBg:_checkNightMode()
    if not self.ui or not self.ui.document then
        if self._night_check_timer then
            UIManager:unschedule(self._night_check_timer)
            self._night_check_timer = nil
        end
        return
    end

    local current = Screen.night_mode
    if self._last_night_mode ~= current then
        self._last_night_mode = current
        local new_scene = current and SCENE_NIGHT or SCENE_DAY
        if self:getSceneMode() ~= new_scene then
            UIManager:nextTick(function()
                self:switchScene(new_scene)
            end)
            logger.dbg("CustomBg: Polling detected a night-mode change, switching to " .. new_scene)
        end
    end
    self:_scheduleNightCheck()
end

function CustomBg:onCloseDocument()
    self:_freeOverlay()
    self:_releaseNoFlash()
    self:_releaseDither()
    if self._night_check_timer then
        UIManager:unschedule(self._night_check_timer)
        self._night_check_timer = nil
    end
    if self._bg_reapply_timer then
        UIManager:unschedule(self._bg_reapply_timer)
        self._bg_reapply_timer = nil
    end
end

-- ==================== Menu ====================
function CustomBg:addToMainMenu(menu_items)
    local anchor = self.ui.typeset and "typeset" or "setting"
    menu_items.custombg = {
        text = _("Reading Background & Underlines"),
        sorting_hint = anchor,
        sub_item_table = {
            {
                text = _("Sleep icon (shown centered on screen-off)"),
                sub_item_table_func = function()
                    return self:getSleepIconMenu()
                end,
            },
            {
                text = _("Ruled lines (horizontal/vertical)"),
                sub_item_table = {
                    {
                        text = _("Reset underline settings to built-in defaults"),
                        enabled_func = function() return self:hasLineSettings() end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local prev_dir = self.fs_line_direction
                            self:resetLineSettings()
                            self:refreshView(touchmenu_instance)
                            if prev_dir ~= self.fs_line_direction then self:showReloadConfirm() end
                        end,
                    },
                    {
                        text = _("Enable / disable full-screen ruled lines"),
                        checked_func = function() return self.fs_enabled end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self.fs_enabled = not self.fs_enabled
                            self:saveDocSetting(FS_KEYS.enabled, self.fs_enabled)
                            self:refreshView(touchmenu_instance)
                        end,
                    },
                    {
                        text = _("Lines gesture also toggles the background"),
                        help_text = _(
                            "ON: the gesture that toggles the ruled lines (pagetextinfo) cycles: lines only, background only, " ..
                            "lines + background, nothing.\n\n" ..
                            "OFF: the gesture only toggles the ruled lines; the background is not touched."),
                        checked_func = function() return self:isToggleWithBackground() end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            CFG:saveSetting(TOGGLE_WITH_BG_KEY, not self:isToggleWithBackground())
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    },
                    {
                        text = _("Layout and line direction"),
                        sub_item_table = {
                            {
                                text = _("Horizontal layout (normal books, draws horizontal lines)"),
                                checked_func = function() return self.fs_line_direction == 1 end,
                                callback = function()
                                    self.fs_line_direction = 1
                                    self:saveDocSetting(FS_KEYS.direction, 1)
                                    self:showReloadConfirm()
                                end,
                            },
                            {
                                text = _("Pseudo-vertical layout (turn a normal book vertical: rotates the engine, draws column lines)"),
                                checked_func = function() return self.fs_line_direction == 2 end,
                                callback = function()
                                    self.fs_line_direction = 2
                                    self:saveDocSetting(FS_KEYS.direction, 2)
                                    self:showReloadConfirm()
                                end,
                            },
                            {
                                text = _("True vertical books (native vertical text: no rotation, draws column lines)"),
                                checked_func = function() return self.fs_line_direction == 3 end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    local prev = self.fs_line_direction
                                    self.fs_line_direction = 3
                                    self:saveDocSetting(FS_KEYS.direction, 3)
                                    if prev == 2 then
                                        -- Just switched away from "pseudo-vertical": first remove the rotation patch, then prompt to reload
                                        self:restoreOriginalState()
                                        self:showReloadConfirm()
                                    else
                                        -- Switching between true vertical / horizontal does not change the engine state, takes effect immediately
                                        self:refreshView(touchmenu_instance)
                                    end
                                end,
                            },
                            {
                                text = _("How to choose between the three modes?"),
                                keep_menu_open = true,
                                callback = function()
                                    UIManager:show(InfoMessage:new{
                                        text = _(
                                            "1) Horizontal layout: the vast majority of horizontally typeset books; underlines are horizontal lines.\n\n" ..
                                            "2) Pseudo-vertical layout: forcibly turns a [horizontal book] into vertical text for reading. " ..
                                            "The plugin swaps the engine viewport's width and height and rotates the whole page; the background image is pre-rotated to match. " ..
                                            "This mode changes the engine layout; you must return to the library and reopen the book for it to take full effect.\n\n" ..
                                            "3) True vertical books: the book itself is vertical (e.g. writing-mode: vertical in EPUB), " ..
                                            "so the text on screen is already laid out in columns. This mode does [NOT] rotate the engine, " ..
                                            "it only clusters by column and draws a vertical line on the left of each column; the reading background fills the whole screen normally and takes effect immediately.\n\n" ..
                                            "How to tell: with no mode enabled, if the text in the book already runs in vertical columns, choose 3; " ..
                                            "if it is still in horizontal lines and you want vertical text, choose 2.")
                                    })
                                end,
                            },
                        }
                    },
                    {
                        text = _("Vertical layout - dedicated font settings"),
                        enabled_func = function()
                            return self.fs_line_direction == 2 or self.fs_line_direction == 3
                        end,
                        sub_item_table = {
                            {
                                text = _("Enable font override for vertical layout"),
                                checked_func = function() return self.fs_v_font_enable end,
                                callback = function()
                                    self.fs_v_font_enable = not self.fs_v_font_enable
                                    self:saveDocSetting(FS_KEYS.v_font_enable, self.fs_v_font_enable)
                                    self:showReloadConfirm()
                                end,
                            },
                            {
                                text = _("Choose from the system font list"),
                                enabled_func = function() return self.fs_v_font_enable end,
                                sub_item_table_func = function()
                                    local font_options = {}
                                    local cre_engine = require("document/credocument"):engineInit()
                                    if cre_engine and type(cre_engine.getFontFaces) == "function" then
                                        local faces = cre_engine.getFontFaces()
                                        local seen = {}
                                        for _, face in ipairs(faces) do
                                            if not seen[face] then
                                                table.insert(font_options, {
                                                    text = face,
                                                    checked_func = function() return self.fs_v_font_family == face end,
                                                    callback = function()
                                                        self.fs_v_font_family = face
                                                        self:saveDocSetting(FS_KEYS.v_font_family, self.fs_v_font_family)
                                                        self:showReloadConfirm()
                                                    end,
                                                })
                                                seen[face] = true
                                            end
                                        end
                                        table.sort(font_options, function(a, b) return a.text:lower() < b.text:lower() end)
                                    end
                                    if #font_options == 0 then
                                        table.insert(font_options, { text = _("No usable fonts found, please check the system fonts"), enabled = false })
                                    end
                                    return font_options
                                end,
                            },
                            {
                                text = _("Manually enter an external font family name"),
                                enabled_func = function() return self.fs_v_font_enable end,
                                callback = function()
                                    local input_dialog
                                    input_dialog = InputDialog:new{
                                        title = _("Please enter the font Family Name you changed to\nFor example: FZKai-Z03"),
                                        input = self.fs_v_font_family,
                                        buttons = {
                                            {
                                                {
                                                    text = _("Cancel"),
                                                    id = "close",
                                                    callback = function()
                                                        UIManager:close(input_dialog)
                                                    end,
                                                },
                                                {
                                                    text = _("Save"),
                                                    is_enter_default = true,
                                                    callback = function()
                                                        self.fs_v_font_family = input_dialog:getInputText()
                                                        self:saveDocSetting(FS_KEYS.v_font_family, self.fs_v_font_family)
                                                        UIManager:close(input_dialog)
                                                        self:showReloadConfirm()
                                                    end,
                                                },
                                            }
                                        },
                                    }
                                    UIManager:show(input_dialog)
                                    input_dialog:onShowKeyboard()
                                end,
                            }
                        }
                    },
                    {
                        text = _("Line width and alignment mode"),
                        sub_item_table = {
                            {
                                text = _("Full-screen line mode"),
                                checked_func = function() return self.fs_line_mode == 1 end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self.fs_line_mode = 1
                                    self:saveDocSetting(FS_KEYS.mode, 1)
                                    self:refreshView(touchmenu_instance)
                                end,
                            },
                            {
                                text = _("Custom ratio mode (1000 = full screen)"),
                                checked_func = function() return self.fs_line_mode == 2 end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self.fs_line_mode = 2
                                    self:saveDocSetting(FS_KEYS.mode, 2)
                                    self:refreshView(touchmenu_instance)
                                end,
                            },
                            {
                                text = _("Smart text-aligned mode"),
                                checked_func = function() return self.fs_line_mode == 3 end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self.fs_line_mode = 3
                                    self:saveDocSetting(FS_KEYS.mode, 3)
                                    self:refreshView(touchmenu_instance)
                                end,
                            },
                            {
                                text = _("Underline below text only (no blank guide cells)"),
                                checked_func = function() return self.fs_line_mode == 4 end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self.fs_line_mode = 4
                                    self:saveDocSetting(FS_KEYS.mode, 4)
                                    self:refreshView(touchmenu_instance)
                                end,
                            },
                        }
                    },
                    {
                        text = _("Set line length ratio (1000 = full screen)"),
                        enabled_func = function() return self.fs_line_mode == 2 end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            UIManager:show(SpinWidget:new{
                                value = self.fs_width_ratio,
                                value_min = 50,
                                value_max = 1000,
                                value_step = 50,
                                title_text = _("Adjust length: 1000 = full screen, 500 = half (centered)"),
                                callback = function(spin)
                                    self.fs_width_ratio = spin.value
                                    self:saveDocSetting(FS_KEYS.width_ratio, self.fs_width_ratio)
                                    self:refreshView(touchmenu_instance)
                                end,
                            })
                        end,
                    },
                    {
                        text = _("Smart mode: extra pixels at both ends"),
                        enabled_func = function() return self.fs_line_mode == 3 or self.fs_line_mode == 4 end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            UIManager:show(SpinWidget:new{
                                value = self.fs_extend_px,
                                value_min = -200,
                                value_max = 200,
                                value_step = 5,
                                title_text = _("When hugging the text, how many extra pixels to draw at both ends"),
                                callback = function(spin)
                                    self.fs_extend_px = spin.value
                                    self:saveDocSetting(FS_KEYS.extend, self.fs_extend_px)
                                    self:refreshView(touchmenu_instance)
                                end,
                            })
                        end,
                    },
                    {
                        text = _("Smart avoidance and layout detection"),
                        sub_item_table = {
                            {
                                text = _("No underline for large text / headings"),
                                checked_func = function() return self.fs_skip_titles end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self.fs_skip_titles = not self.fs_skip_titles
                                    self:saveDocSetting(FS_KEYS.skip_titles, self.fs_skip_titles)
                                    self:refreshView(touchmenu_instance)
                                end,
                            },
                            {
                                text = _("Heading detection threshold (10 = 1x)"),
                                enabled_func = function() return self.fs_skip_titles end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    UIManager:show(SpinWidget:new{
                                        value = self.fs_title_threshold * 10,
                                        value_min = 10,
                                        value_max = 30,
                                        value_step = 1,
                                        title_text = _("Smaller values are more sensitive. [Automatic spacing inference] is now supported"),
                                        callback = function(spin)
                                            self.fs_title_threshold = spin.value / 10.0
                                            self:saveDocSetting(FS_KEYS.title_threshold, self.fs_title_threshold)
                                            self:refreshView(touchmenu_instance)
                                        end,
                                    })
                                end,
                            },
                            {
                                text = _("Image / large-whitespace avoidance threshold"),
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    UIManager:show(SpinWidget:new{
                                        value = self.fs_gap_threshold * 10,
                                        value_min = 15,
                                        value_max = 100,
                                        value_step = 5,
                                        title_text = _("Default 25 (i.e. 2.5x). Lower it to avoid images more easily"),
                                        callback = function(spin)
                                            self.fs_gap_threshold = spin.value / 10.0
                                            self:saveDocSetting(FS_KEYS.gap_threshold, self.fs_gap_threshold)
                                            self:refreshView(touchmenu_instance)
                                        end,
                                    })
                                end,
                            },
                        }
                    },
                    {
                        text = _("More detailed settings"),
                        sub_item_table = {
                            {
                                text = _("Show outer border line (first row)"),
                                checked_func = function() return self.fs_show_top_line end,
                                enabled_func = function() return self.fs_line_mode ~= 4 end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self.fs_show_top_line = not self.fs_show_top_line
                                    self:saveDocSetting(FS_KEYS.show_top, self.fs_show_top_line)
                                    self:refreshView(touchmenu_instance)
                                end,
                            },
                            {
                                text = _("Dashed line mode"),
                                checked_func = function() return self.fs_is_dashed end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self.fs_is_dashed = not self.fs_is_dashed
                                    self:saveDocSetting(FS_KEYS.dashed, self.fs_is_dashed)
                                    if self.fs_is_dashed then
                                        self.fs_wave_mode = 0
                                        self.fs_style_dash_dot = false
                                        self.fs_style_heart_dash = false
                                        self.fs_style_double_solid = false
                                        self.fs_style_double_dash = false
                                        self:saveDocSetting(FS_KEYS.wave_mode, 0)
                                        self:saveDocSetting(FS_KEYS.style_dash_dot, false)
                                        self:saveDocSetting(FS_KEYS.style_heart_dash, false)
                                        self:saveDocSetting(FS_KEYS.style_double_solid, false)
                                        self:saveDocSetting(FS_KEYS.style_double_dash, false)
                                    end
                                    self:refreshView(touchmenu_instance)
                                end,
                            },
                            {
                                text = _("Wavy line mode"),
                                sub_item_table = {
                                    {
                                        text = _("Off"),
                                        checked_func = function() return self.fs_wave_mode == 0 end,
                                        keep_menu_open = true,
                                        callback = function(touchmenu_instance)
                                            self.fs_wave_mode = 0
                                            self:saveDocSetting(FS_KEYS.wave_mode, 0)
                                            self:refreshView(touchmenu_instance)
                                        end,
                                    },
                                    {
                                        text = _("Small waves"),
                                        checked_func = function() return self.fs_wave_mode == 1 end,
                                        keep_menu_open = true,
                                        callback = function(touchmenu_instance)
                                            self.fs_wave_mode = 1
                                            self.fs_is_dashed = false
                                            self.fs_style_dash_dot = false
                                            self.fs_style_heart_dash = false
                                            self.fs_style_double_solid = false
                                            self.fs_style_double_dash = false
                                            self:saveDocSetting(FS_KEYS.wave_mode, 1)
                                            self:saveDocSetting(FS_KEYS.dashed, false)
                                            self:saveDocSetting(FS_KEYS.style_dash_dot, false)
                                            self:saveDocSetting(FS_KEYS.style_heart_dash, false)
                                            self:saveDocSetting(FS_KEYS.style_double_solid, false)
                                            self:saveDocSetting(FS_KEYS.style_double_dash, false)
                                            self:refreshView(touchmenu_instance)
                                        end,
                                    },
                                    {
                                        text = _("Double waves"),
                                        checked_func = function() return self.fs_wave_mode == 2 end,
                                        keep_menu_open = true,
                                        callback = function(touchmenu_instance)
                                            self.fs_wave_mode = 2
                                            self.fs_is_dashed = false
                                            self.fs_style_dash_dot = false
                                            self.fs_style_heart_dash = false
                                            self.fs_style_double_solid = false
                                            self.fs_style_double_dash = false
                                            self:saveDocSetting(FS_KEYS.wave_mode, 2)
                                            self:saveDocSetting(FS_KEYS.dashed, false)
                                            self:saveDocSetting(FS_KEYS.style_dash_dot, false)
                                            self:saveDocSetting(FS_KEYS.style_heart_dash, false)
                                            self:saveDocSetting(FS_KEYS.style_double_solid, false)
                                            self:saveDocSetting(FS_KEYS.style_double_dash, false)
                                            self:refreshView(touchmenu_instance)
                                        end,
                                    },
                                }
                            },
                            {
                                text = _("Long solid + long dashed mode"),
                                checked_func = function() return self.fs_style_dash_dot end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self.fs_style_dash_dot = not self.fs_style_dash_dot
                                    if self.fs_style_dash_dot then
                                        self.fs_is_dashed = false
                                        self.fs_wave_mode = 0
                                        self.fs_style_heart_dash = false
                                        self.fs_style_double_solid = false
                                        self.fs_style_double_dash = false
                                        self:saveDocSetting(FS_KEYS.dashed, false)
                                        self:saveDocSetting(FS_KEYS.wave_mode, 0)
                                        self:saveDocSetting(FS_KEYS.style_heart_dash, false)
                                        self:saveDocSetting(FS_KEYS.style_double_solid, false)
                                        self:saveDocSetting(FS_KEYS.style_double_dash, false)
                                    end
                                    self:saveDocSetting(FS_KEYS.style_dash_dot, self.fs_style_dash_dot)
                                    self:refreshView(touchmenu_instance)
                                end,
                            },
                            {
                                text = _("Heart dashed line mode"),
                                checked_func = function() return self.fs_style_heart_dash end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self.fs_style_heart_dash = not self.fs_style_heart_dash
                                    if self.fs_style_heart_dash then
                                        self.fs_is_dashed = false
                                        self.fs_wave_mode = 0
                                        self.fs_style_dash_dot = false
                                        self.fs_style_double_solid = false
                                        self.fs_style_double_dash = false
                                        self:saveDocSetting(FS_KEYS.dashed, false)
                                        self:saveDocSetting(FS_KEYS.wave_mode, 0)
                                        self:saveDocSetting(FS_KEYS.style_dash_dot, false)
                                        self:saveDocSetting(FS_KEYS.style_double_solid, false)
                                        self:saveDocSetting(FS_KEYS.style_double_dash, false)
                                    end
                                    self:saveDocSetting(FS_KEYS.style_heart_dash, self.fs_style_heart_dash)
                                    self:refreshView(touchmenu_instance)
                                end,
                            },
                            {
                                text = _("Double solid line mode (two parallel solid lines)"),
                                checked_func = function() return self.fs_style_double_solid end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self.fs_style_double_solid = not self.fs_style_double_solid
                                    if self.fs_style_double_solid then
                                        self.fs_is_dashed = false
                                        self.fs_wave_mode = 0
                                        self.fs_style_dash_dot = false
                                        self.fs_style_heart_dash = false
                                        self.fs_style_double_dash = false
                                        self:saveDocSetting(FS_KEYS.dashed, false)
                                        self:saveDocSetting(FS_KEYS.wave_mode, 0)
                                        self:saveDocSetting(FS_KEYS.style_dash_dot, false)
                                        self:saveDocSetting(FS_KEYS.style_heart_dash, false)
                                        self:saveDocSetting(FS_KEYS.style_double_dash, false)
                                    end
                                    self:saveDocSetting(FS_KEYS.style_double_solid, self.fs_style_double_solid)
                                    self:refreshView(touchmenu_instance)
                                end,
                            },
                            {
                                text = _("Double dashed line mode (two parallel dashed lines)"),
                                checked_func = function() return self.fs_style_double_dash end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self.fs_style_double_dash = not self.fs_style_double_dash
                                    if self.fs_style_double_dash then
                                        self.fs_is_dashed = false
                                        self.fs_wave_mode = 0
                                        self.fs_style_dash_dot = false
                                        self.fs_style_heart_dash = false
                                        self.fs_style_double_solid = false
                                        self:saveDocSetting(FS_KEYS.dashed, false)
                                        self:saveDocSetting(FS_KEYS.wave_mode, 0)
                                        self:saveDocSetting(FS_KEYS.style_dash_dot, false)
                                        self:saveDocSetting(FS_KEYS.style_heart_dash, false)
                                        self:saveDocSetting(FS_KEYS.style_double_solid, false)
                                    end
                                    self:saveDocSetting(FS_KEYS.style_double_dash, self.fs_style_double_dash)
                                    self:refreshView(touchmenu_instance)
                                end,
                            },
                            {
                                text = _("Double-line spacing"),
                                enabled_func = function()
                                    return self.fs_style_double_solid or self.fs_style_double_dash
                                end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    UIManager:show(SpinWidget:new{
                                        value = self.fs_double_gap,
                                        value_min = 0,
                                        value_max = 20,
                                        value_step = 1,
                                        callback = function(spin)
                                            self.fs_double_gap = spin.value
                                            self:saveDocSetting(FS_KEYS.double_gap, self.fs_double_gap)
                                            self:refreshView(touchmenu_instance)
                                        end,
                                    })
                                end,
                            },
                            {
                                text = _("Dash segment length"),
                                enabled_func = function()
                                    return self.fs_is_dashed or self.fs_style_double_dash
                                end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    UIManager:show(SpinWidget:new{
                                        value = self.fs_dash_len,
                                        value_min = 2,
                                        value_max = 100,
                                        value_step = 1,
                                        callback = function(spin)
                                            self.fs_dash_len = spin.value
                                            self:saveDocSetting(FS_KEYS.dash_len, self.fs_dash_len)
                                            self:refreshView(touchmenu_instance)
                                        end,
                                    })
                                end,
                            },
                            {
                                text = _("Auto-center line position (adapts to font, size and spacing)"),
                                help_text = _(
                                    "ON: the plugin computes where to draw each line from the current font, size and line spacing " ..
                                    "(centered in the gap between two text rows).\n\n" ..
                                    "OFF: lines use the fixed offset set in \"Line position offset fine-tuning\".\n\n" ..
                                    "Related options:\n" ..
                                    "- \"Auto-center: shift down (%)\": general correction, proportional to the line height (only with auto ON).\n" ..
                                    "- \"Line position offset fine-tuning\": correction in fixed pixels, for one specific font or book."),
                                checked_func = function() return self.fs_auto_offset end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self.fs_auto_offset = not self.fs_auto_offset
                                    self:saveDocSetting(FS_KEYS.auto_offset, self.fs_auto_offset)
                                    self:refreshView(touchmenu_instance)
                                end,
                            },
                            {
                                text_func = function()
                                    return _("Auto-center: shift down (% of line height)") .. ": " .. self.fs_offset_bias
                                end,
                                enabled_func = function() return self.fs_auto_offset end,
                                help_text = _(
                                    "Only used with \"Auto-center line position\" ON.\n\n" ..
                                    "Moves every line down by a percentage of the text row height, so it scales with the font size. " ..
                                    "The row box has more empty space above the letters than below, so the exact geometric centre " ..
                                    "sits too close to the descenders; this compensates for it.\n\n" ..
                                    "Raise it if descenders (g, j, p, q, y) touch the line. " ..
                                    "Lower it if the line sits too far from the text. Default: 0."),
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    UIManager:show(SpinWidget:new{
                                        value = self.fs_offset_bias,
                                        value_min = 0,
                                        value_max = 25,
                                        value_step = 1,
                                        title_text = _("Shift down (% of line height)"),
                                        callback = function(spin)
                                            self.fs_offset_bias = spin.value
                                            self:saveDocSetting(FS_KEYS.offset_bias, self.fs_offset_bias)
                                            self:refreshView(touchmenu_instance)
                                        end,
                                    })
                                end,
                            },
                            {
                                -- With auto-centre on this is a +/- adjustment on top of the automatic value;
                                -- with it off it is the fixed offset used before.
                                help_text = _(
                                    "Correction in fixed pixels, the same for any font size.\n\n" ..
                                    "Auto-center ON: added on top of the automatic position (shown as \"auto +N\"). " ..
                                    "Use it to retouch one specific font or book.\n\n" ..
                                    "Auto-center OFF: this is the fixed distance from the text row to the line; " ..
                                    "no automatic calculation and no percentage are applied."),
                                text_func = function()
                                    if self.fs_auto_offset then
                                        return _("Line position offset fine-tuning") .. " (auto " .. string.format("%+d", self.fs_offset_adjust) .. ")"
                                    end
                                    return _("Line position offset fine-tuning") .. ": " .. self.fs_offset_y
                                end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    UIManager:show(SpinWidget:new{
                                        value = self.fs_auto_offset and self.fs_offset_adjust or self.fs_offset_y,
                                        value_min = -100,
                                        value_max = 100,
                                        value_step = 1,
                                        callback = function(spin)
                                            if self.fs_auto_offset then
                                                self.fs_offset_adjust = spin.value
                                                self:saveDocSetting(FS_KEYS.offset_adjust, self.fs_offset_adjust)
                                            else
                                                self.fs_offset_y = spin.value
                                                self:saveDocSetting(FS_KEYS.offset_y, self.fs_offset_y)
                                            end
                                            self:refreshView(touchmenu_instance)
                                        end,
                                    })
                                end,
                            },
                            {
                                text_func = function()
                                    return "Color depth: " .. self.fs_color_depth
                                end,
                                sub_item_table_func = function()
                                    return {
                                        {
                                            text = "-",
                                            keep_menu_open = true,
                                            enabled_func = function()
                                                return self.fs_color_depth > 1
                                            end,
                                            callback = function(touchmenu_instance)
                                                if self.fs_color_depth > 1 then
                                                    self.fs_color_depth = self.fs_color_depth - 1
                                                    self:saveDocSetting(FS_KEYS.color_depth, self.fs_color_depth)
                                                    self:repaintView()
                                                    touchmenu_instance:updateItems()
                                                end
                                            end,
                                        },
                                        {
                                            text_func = function()
                                                return tostring(self.fs_color_depth)
                                            end,
                                            enabled = false,
                                        },
                                        {
                                            text = "+",
                                            keep_menu_open = true,
                                            enabled_func = function()
                                                return self.fs_color_depth < 15
                                            end,
                                            callback = function(touchmenu_instance)
                                                if self.fs_color_depth < 15 then
                                                    self.fs_color_depth = self.fs_color_depth + 1
                                                    self:saveDocSetting(FS_KEYS.color_depth, self.fs_color_depth)
                                                    self:repaintView()
                                                    touchmenu_instance:updateItems()
                                                end
                                            end,
                                        },
                                    }
                                end,
                            },
                        }
                    },
                }
            },
            -- Custom reading background (including global default)
            {
                text = _("Custom reading background"),
                sub_item_table_func = function()
                    local sub = {}
                    local bg_path = getBackgroundsFolder()
                    local scene = self:getSceneMode()
                    local scene_text = scene == SCENE_DAY and _("Day") or _("Night")
                    local current_bg_name = self:getCurrentDocBg() or _("No background")
                    table.insert(sub, {
                        text = _("Current mode: ") .. scene_text,
                        keep_menu_open = true,
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = _("The background mode automatically follows the system night mode.\nWhen you toggle night mode, the background switches to the matching day/night background."),
                            })
                        end,
                    })
                    table.insert(sub, {
                        text = _("Refresh image list"),
                        callback = function() self:refreshImageCache() end,
                        enabled_func = function() return not self.scanning end
                    })
                    table.insert(sub, {
                        text = _("Background folder: ") .. bg_path,
                        keep_menu_open = true,
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = _("Background images folder:\n") .. bg_path.."\nNight mode only loads images whose filename ends with -night; day mode excludes images ending with -night",
                            })
                        end,
                    })
                    table.insert(sub, {
                        -- text_func: recomputed on every menu update, so it follows the background picked in this same menu
                        text_func = function()
                            return _("Current background: ") .. (self:getCurrentDocBg() or _("No background"))
                        end,
                        keep_menu_open = true,
                        callback = function() end,
                    })

                    local max_pct = tostring(math.floor(OVERLAY_MAX_AREA * 100)) .. "%"
                    local pieces_help = _(
                        "ON: the background image is analysed once and only the parts that contain something are kept: " ..
                        "a picture at the bottom becomes one small piece, a frame becomes up to four thin strips.\n\n" ..
                        "The image is NOT sent to the rendering engine (crengine) any more. Crengine only draws the text: " ..
                        "a plain black-and-white page without images, so KOReader does not dither it and does not treat it as " ..
                        "\"a page with images\". The pieces are painted afterwards by the plugin, on top of the page, " ..
                        "without dithering. Result: no grain, no ghosting and no black flashes when menus and dialogs open or close. " ..
                        "The dithering option below is ignored in this mode; \"No-flash page turns\" still applies, " ..
                        "so the drawings do not flicker when you turn the page.\n\n" ..
                        "Size limit: the pieces may cover at most ") .. max_pct .. _(
                        " of the screen. If the centre of the image is not empty, or the pieces cover more than that " ..
                        "(a real full-page picture or texture), the image is drawn the classic way. " ..
                        "Diagnostics shows the reason (\"Pieces mode now\").\n\n" ..
                        "The background colour of the image is read from its corners and becomes transparent. " ..
                        "The pieces are gray and are painted after the text, so keep the picture inside the page margin, " ..
                        "not over the text.\n\n" ..
                        "The first time an image is used it is analysed and cached; afterwards it loads at once.\n\n" ..
                        "OFF: classic full-page background. On the Kindle it flickers and dithering has to be disabled " ..
                        "(see the no-dithering option below).")
                    table.insert(sub, {
                        text = _("Draw as pieces (bottom picture / frame) instead of a full-page background"),
                        help_text = pieces_help,
                        -- Long press: same text, smaller letters so that all of it fits on the screen
                        hold_callback = function()
                            local Font = require("ui/font")
                            UIManager:show(InfoMessage:new{
                                text = pieces_help,
                                face = Font:getFace("infofont", 16),
                                width = math.floor(Screen:getWidth() * 0.92),
                                show_icon = false,
                            })
                        end,
                        checked_func = function() return isOverlayMode() end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            CFG:saveSetting(OVERLAY_KEY, not isOverlayMode())
                            self:_invalidateBgDedup()
                            self:loadBackgroundByName(nil, true)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    })

                    table.insert(sub, {
                        text = _("No-flash page turns (avoid full-screen flashing with a background)"),
                        help_text = _(
                            "ON: while a background is shown, page turns use a non-flashing refresh and the background is not " ..
                            "treated as image content.\n\n" ..
                            "The periodic full refresh set in KOReader (Full refresh rate) still happens as configured.\n\n" ..
                            "OFF: KOReader's own behaviour (may flash on every page)."),
                        checked_func = function() return self:isNoFlashEnabled() end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            CFG:saveSetting(NOFLASH_KEY, not self:isNoFlashEnabled())
                            self:_syncNoFlash()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    })

                    table.insert(sub, {
                        text = _("No dithering of the background (removes the grain on devices with software dithering)"),
                        help_text = _(
                            "Only available while a background image is shown and No-flash page turns is ON.\n\n" ..
                            "ON: while a background is shown, KOReader's software dithering is switched off, so the background is drawn " ..
                            "smooth instead of with a grainy pattern (typical of the Kindle Paperwhite 12). " ..
                            "With the \"ui\" page-turn refresh it can make page turns smear more; it works best with \"partial\". OFF by default.\n\n" ..
                            "While it is active, the black flash that menus and dialogs cause when they open and close is also avoided.\n\n" ..
                            "Images inside the book are not dithered either while a background is shown. Dithering comes back " ..
                            "when the background is turned off or the book is closed.\n\n" ..
                            "OFF: KOReader's own behaviour."),
                        -- Only useful while a background image is shown and No-flash page turns is ON: greyed out (and ignored) otherwise
                        enabled_func = function()
                            return self:isNoFlashEnabled() and self.ui ~= nil and self.ui.document ~= nil
                                and self._bg_last_name ~= nil and self._bg_last_name ~= ""
                        end,
                        checked_func = function() return CustomBg._noDitherOn() end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            CFG:saveSetting(NODITHER_KEY, not CustomBg._noDitherOn())
                            self:_syncDither()
                            self:repaintView()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    })

                    table.insert(sub, {
                        text_func = function()
                            local labels = { ui = _("\"ui\" mode (no flash, may degrade)"), partial = _("\"partial\" mode (sharp, may flash)") }
                            return _("Page-turn refresh with a background") .. ": " .. labels[self:getPageRefreshMode()]
                        end,
                        -- Only has an effect with a background shown and No-flash page turns ON: greyed out otherwise
                        enabled_func = function() return self:_wantsNoFlash() and true or false end,
                        help_text = _(
                            "Refresh used when you turn the page while a background is shown (needs No-flash page turns ON). " ..
                            "It is a trade-off between degradation and flashing:\n\n" ..
                            "\"ui\" mode (no flash, may degrade): the page never flashes, but the text can look softer and ghost more " ..
                            "until the next full refresh.\n" ..
                            "\"partial\" mode (sharp, may flash): KOReader's own page-turn refresh, crisper text, but the screen may flash. " ..
                            "The background is still not treated as image content, and the periodic full refresh keeps working."),
                        sub_item_table = {
                            {
                                text = _("\"ui\" mode: no flash, softer text, ghosting"),
                                checked_func = function() return self:getPageRefreshMode() == "ui" end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    CFG:saveSetting(PAGE_REFRESH_KEY, "ui")
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end,
                            },
                            {
                                text = _("\"partial\" mode: crisper text, may flash"),
                                checked_func = function() return self:getPageRefreshMode() == "partial" end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    CFG:saveSetting(PAGE_REFRESH_KEY, "partial")
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end,
                            },
                        },
                    })

                    table.insert(sub, {
                        text_func = function()
                            local off = CFG:readSetting(SWIPE_ANIM_KEY) == "off"
                            return _("Kindle page-turn animation with a background") .. ": " .. (off and _("Off") or _("Keep"))
                        end,
                        -- Same condition the hook uses (background shown + No-flash page turns ON): greyed out otherwise
                        enabled_func = function() return self:_wantsNoFlash() and true or false end,
                        help_text = _(
                            "Only for Kindles that have the page-turn animation (turned on in KOReader's own settings).\n\n" ..
                            "Keep: KOReader's animation, as it is.\n" ..
                            "Off: no animation while a background is shown (the page changes with a plain refresh). " ..
                            "Use it if the animation looks wrong with a background."),
                        sub_item_table = {
                            {
                                text = _("Keep"),
                                checked_func = function() return CFG:readSetting(SWIPE_ANIM_KEY) ~= "off" end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    CFG:saveSetting(SWIPE_ANIM_KEY, "keep")
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end,
                            },
                            {
                                text = _("Off while a background is shown"),
                                checked_func = function() return CFG:readSetting(SWIPE_ANIM_KEY) == "off" end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    CFG:saveSetting(SWIPE_ANIM_KEY, "off")
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end,
                            },
                        },
                    })

                    -- Diagnostics: shows exactly what the plugin sees, to find why a background does not appear
                    table.insert(sub, {
                        text = _("Diagnostics (why is there no background?)"),
                        keep_menu_open = true,
                        callback = function()
                            local sc = self:getSceneMode()
                            local book_val = self:readBgChoice()
                            local glob = self:getGlobalDefaultBg()
                            local resolved = self:getCurrentDocBg()
                            local imgs = self:getCurrentImageCache()
                            local count = 0
                            for kk in pairs(imgs) do count = count + 1 end
                            local function show(v)
                                if v == nil then return "[nothing]" end
                                if v == "" then return "[empty = no background]" end
                                return tostring(v)
                            end
                            UIManager:show(InfoMessage:new{
                                text = table.concat({
                                    "Mode: " .. sc,
                                    "Background setting (global): " .. show(book_val),
                                    "Global default: " .. show(glob),
                                    "Applied now: " .. show(resolved),
                                    "Image file found: " .. show(resolved and imgs[resolved] or nil),
                                    "Images in list: " .. count,
                                    "Folder: " .. getBackgroundsFolder(),
                                    "Pieces mode setting: " .. tostring(isOverlayMode()),
                                    "Pieces mode now: " .. tostring(self._overlay_info or "(not evaluated)"),
                                    "Screen dithering (sw / hw): " .. tostring(Screen.sw_dithering) .. " / " .. tostring(Screen.hw_dithering)
                                        .. (self._dither_suspended and "  [sw switched off by the plugin]" or ""),
                                    (function()
                                        local d = self.ui.document
                                        local out = { "setBackgroundImage: " .. type(d and d.setBackgroundImage) }
                                        out[#out + 1] = "Rotated by plugin: " .. tostring(d and d._is_rotated_by_plugin)
                                        local src = resolved and imgs[resolved] or nil
                                        if src then
                                            local ok, scaled = pcall(self.getBgScaledPath, self, src)
                                            out[#out + 1] = "Source: " .. tostring(src)
                                            out[#out + 1] = "Scaled: " .. (ok and tostring(scaled) or ("ERROR " .. tostring(scaled)))
                                            if ok and scaled then
                                                local a = lfs.attributes(scaled)
                                                out[#out + 1] = "Scaled size: " .. tostring(a and a.size)
                                            end
                                            local ok2, err = pcall(function()
                                                d:setBackgroundImage(ok and scaled or src)
                                            end)
                                            out[#out + 1] = "Apply: " .. (ok2 and "ok" or ("ERROR " .. tostring(err)))
                                        end
                                        return table.concat(out, "\n")
                                    end)(),
                                }, "\n"),
                            })
                        end,
                    })

                    -- No background
                    table.insert(sub, {
                        text = _("No background"),
                        checked_func = function()
                            local v = self:readBgChoice()
                            return v == nil or v == DOC_BG_NONE
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self:applyBackground(DOC_BG_NONE)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end
                    })

                    -- Follow global default
                    table.insert(sub, {
                        text_func = function()
                            return _("Follow global default background") .. ": " .. (self:getGlobalDefaultBg() or _("random"))
                        end,
                        checked_func = function()
                            return self:readBgChoice() == DOC_BG_GLOBAL
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            -- Toggle: ON = the global background is shown (in every book), OFF = no background
                            local turned_on
                            if self:readBgChoice() == DOC_BG_GLOBAL then
                                self:applyBackground(DOC_BG_NONE)
                                turned_on = false
                            else
                                -- Turn ON exactly like picking an image from the list does (that path is known to draw):
                                -- use the global image, or a random one when none is selected.
                                local g = self:getGlobalDefaultBg()
                                local imgs = self:getCurrentImageCache()
                                if not (g and g ~= "" and imgs[g]) then g = self:getRandomBg() end
                                if g then
                                    self:applyBackground(g)
                                else
                                    self:applyBackground(DOC_BG_GLOBAL)
                                end
                                turned_on = true
                            end
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                            -- Visible feedback so it is clear the toggle was received (and what it resolved to)
                            local shown = self:getCurrentDocBg()
                            local found = shown and self:getCurrentImageCache()[shown]
                            local random_note = (self:getGlobalDefaultBg() == nil) and " (random)" or ""
                            local msg
                            local saved_val = self:readBgChoice()
                            if turned_on and saved_val ~= DOC_BG_GLOBAL then
                                msg = "Background ON but NOT saved (value: " .. tostring(saved_val) .. ")"
                            elseif not turned_on then
                                msg = "Background OFF"
                            elseif found then
                                msg = "Background ON: " .. shown .. random_note
                            else
                                msg = "Background ON but there are no images to show (mode: " .. self:getSceneMode() .. ")"
                            end
                            UIManager:show(InfoMessage:new{ text = msg, timeout = 2 })
                        end
                    })


                    local images = self:getCurrentImageCache()
                    local used_time = self:getAllLastUsed()
                    local bg_names = {}
                    for name in pairs(images) do table.insert(bg_names, name) end
                    self:sortBgNameList(bg_names, scene, used_time)
                    for _, name in ipairs(bg_names) do
                        table.insert(sub, {
                            text_func = function()
                                if self:isNewImage(name) then return name .. " [New]" end
                                return name
                            end,
                            checked_func = function()
                                return self:getGlobalDefaultBg() == name
                            end,
                            keep_menu_open = true,
                            callback = function(touchmenu_instance)
                                self:applyBackground(name)
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            end
                        })
                    end
                    if not next(images) then
                        local tip_text = scene == SCENE_DAY and _("No usable day background images found in the background folder") or _("No usable night background images (filename ending in -night) found in the background folder")
                        table.insert(sub, {text = tip_text, enabled = false})
                    end
                    return sub
                end
            }
        }
    }

    -- File manager (no book open): hide "Ruled lines" and "Custom reading background",
    -- they only make sense inside a book. Only the sleep icon menu is kept.
    if not self.ui.document then
        local sub = menu_items.custombg.sub_item_table
        for i = #sub, 2, -1 do table.remove(sub, i) end
    end
end

return CustomBg
