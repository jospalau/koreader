-- Fonts menu: paged grid of font families, with long-press font info and
-- x-height preservation when the font is changed.
--
-- Lives next to main.lua. Load it from main.lua, after PageTextInfo is defined:
--     require("font_selection_menu")(PageTextInfo)
--
-- It adds these methods to PageTextInfo:
--     closeFontsMenu, applyFontAndReopen, showFontInfo, onShowFonts
--
-- applyFontAndReopen needs the methods added by settings_menu.lua
-- (getXHeightMm, ptForXHeight, applyFontSizePt, getActivePreset, applyPreset),
-- so load that module too.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FontList = require("fontlist")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

return function(PageTextInfo)

-- Build a map: face name -> font file path (prefers the regular style)
local function buildFacePathMap()
    local regular, any = {}, {}
    local list = FontList:getFontList() or {}
    for __, path in ipairs(list) do
        local info = FontList.fontinfo and FontList.fontinfo[path]
        if info then
            for __, f in ipairs(info) do
                if f.name then
                    if not f.bold and not f.italic then
                        regular[f.name] = regular[f.name] or path
                    end
                    any[f.name] = any[f.name] or path
                end
            end
        end
    end
    for name, path in pairs(any) do
        regular[name] = regular[name] or path
    end
    return regular
end

-- Close the fonts menu and repaint the page underneath
function PageTextInfo:closeFontsMenu()
    local d = self.fonts_dialog
    self.fonts_dialog = nil
    self.fonts_stats = nil
    if d then
        UIManager:close(d, "ui", d.frame_rect)
    end
end

-- Close the menu, apply the font directly on the reader, then reopen.
-- The x-height the reader had BEFORE the change is preserved by adjusting
-- the pt size for the new face.
function PageTextInfo:applyFontAndReopen(face)
    local Event = require("ui/event")
    local logger = require("logger")
    local page = self.fonts_page

    local scale = PageTextInfo:isScaleByXHeight()
    -- Active font preset (small / normal / big) before the face changes, so it
    -- stays selected on the new face
    local preset = scale and self:getActivePreset() or nil

    local function debugFont(stage)
        logger.dbg(string.format(
            "[FontChange] %s | face=%s | size=%s pt | x-height=%s mm",
            stage,
            tostring(self.ui.document._document:getFontFace()),
            tostring(self.ui.font.configurable.font_size),
            scale and tostring(self:getXHeightMm()) or "n/a"
        ))
    end

    local target_mm
    if scale then
        target_mm = self:getXHeightMm()
        logger.dbg("[FontChange] target x-height:", target_mm)
    end

    debugFont("BEFORE")

    -- Don't close the dialog: the new one replaces it
    self.ui:handleEvent(Event:new("SetFont", face))

    debugFont("AFTER SetFont")

    -- Keep the same x-height with the new face (skipped if scaling is disabled or it can't be measured)
    if preset then
        -- A preset was active: apply the same preset (same target mm) on the new face
        self:applyPreset(preset)
        debugFont("AFTER applyPreset")
    elseif target_mm then
        local pt = self:ptForXHeight(target_mm)
        logger.dbg("[FontChange] calculated size:", pt)
        if pt then
            self:applyFontSizePt(pt)
            debugFont("AFTER applyFontSizePt")
        end
    end

    UIManager:nextTick(function()
        debugFont("NEXT TICK")
        self:onShowFonts(page)
    end)
end

-- Info window for a font (opened with a long press)
function PageTextInfo:showFontInfo(face, label)
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local lfs = require("libs/libkoreader-lfs")

    local path = self.font_paths and self.font_paths[face]

    -- Styles available for this family
    local has = {}
    if FontList.fontinfo then
        for __, info in pairs(FontList.fontinfo) do
            for __, f in ipairs(info) do
                if f.name == face then
                    local s = (f.bold and f.italic) and "Bold Italic"
                        or f.bold and "Bold"
                        or f.italic and "Italic"
                        or "Regular"
                    has[s] = true
                end
            end
        end
    end
    local styles = {}
    for __, s in ipairs({ "Regular", "Bold", "Italic", "Bold Italic" }) do
        if has[s] then table.insert(styles, s) end
    end

    -- File data
    local filename = path and path:match("[^/]+$") or "?"
    local dir = path and path:match("^(.*)/[^/]+$") or "?"
    local size_txt = "?"
    if path then
        local size = lfs.attributes(path, "size")
        if size then
            size_txt = size >= 1048576
                and string.format("%.1f MB", size / 1048576)
                or string.format("%d KB", math.floor(size / 1024 + 0.5))
        end
    end

    -- Metrics measured from rendered glyphs (big size for precision)
    local metrics_lines = {}
    if path then
        local RenderText = require("ui/rendertext")
        local ok_face, mface = pcall(Font.getFace, Font, path, 100)
        if ok_face and mface then
            local em = mface.size or Screen:scaleBySize(100)

            -- returns (px above baseline, px below baseline) of a glyph
            local function extent(code)
                local ok, g = pcall(RenderText.getGlyph, RenderText, mface, code)
                if not ok or not g or not g.bb then return nil end
                local top = g.t or g.top
                if not top then return nil end
                return top, g.bb:getHeight() - top
            end

            local x_h = extent(120)            -- x
            local cap_h = extent(72)           -- H
            local asc_h = extent(100)          -- d
            local __, desc_h = extent(112)     -- p

            local function pct(v)
                return string.format("%.0f%%", v / em * 100)
            end

            if x_h then
                table.insert(metrics_lines, "x-height: " .. pct(x_h))
            end
            if cap_h then
                table.insert(metrics_lines, "Cap height: " .. pct(cap_h))
            end
            if x_h and cap_h and cap_h > 0 then
                table.insert(metrics_lines,
                    string.format("x/Cap ratio: %.2f", x_h / cap_h))
            end
            if asc_h then
                table.insert(metrics_lines, "Ascender: " .. pct(asc_h))
            end
            if desc_h then
                table.insert(metrics_lines, "Descender: " .. pct(desc_h))
            end
        end
    end

    local lines = {
        "File: " .. filename,
        "Folder: " .. dir,
        "Size: " .. size_txt,
        "Styles: " .. (#styles > 0 and table.concat(styles, ", ") or "?"),
    }
    for __, l in ipairs(metrics_lines) do
        table.insert(lines, l)
    end
    local info_text = table.concat(lines, "\n")
    local screen = Screen:getSize()
    local pad = Size.padding.large
    local width = math.floor(screen.w * 0.8)
    local inner_w = width - 2 * pad - 2 * Size.border.window

    local sample_face
    if path then
        local ok, f = pcall(Font.getFace, Font, path, 20)
        if ok then sample_face = f end
    end
    sample_face = sample_face or Font:getFace("cfont", 20)

    local content = VerticalGroup:new{ align = "left" }
    table.insert(content, TextBoxWidget:new{
        text = label or face,
        face = sample_face,
        width = inner_w,
        alignment = "center",
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.large })
    table.insert(content, TextBoxWidget:new{
        text = info_text,
        face = Font:getFace("cfont", 16),
        width = inner_w,
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.large })
    for __, line in ipairs({
        "The quick brown fox jumps over the lazy dog",
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        "abcdefghijklmnopqrstuvwxyz",
        "0123456789 áéíóúñ çü ¡¿ ?!",
    }) do
        table.insert(content, TextBoxWidget:new{
            text = line,
            face = sample_face,
            width = inner_w,
        })
    end

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius = Size.radius.window,
        padding = pad,
        content,
    }

    local info_dialog = InputContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h },
        ges_events = {
            Tap = { GestureRange:new{
                ges = "tap",
                range = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h },
            } },
        },
        key_events = Device:hasKeys() and { Close = { { Device.input.group.Back } } } or {},
    }
    info_dialog[1] = CenterContainer:new{
        dimen = Geom:new{ w = screen.w, h = screen.h },
        frame,
    }
    function info_dialog:onTap()
        UIManager:close(self)
        return true
    end
    function info_dialog:onClose()
        UIManager:close(self)
        return true
    end

    UIManager:show(info_dialog)
    return true
end

-- Fonts shown first in the fonts menu, in this order.
-- Matching ignores case and spaces ("Chare Ink 7SP" == "chareink7sp").
-- local PINNED_FONTS = {
--     "Alegreya",
--     "AmasisMTW1G",
--     "AndadaPro",
--     "Average",
--     "BitterPro",
--     "Bookerly",
--     "PMNCaeciliaLT",
--     "CanelaText",
--     "Capita",
--     "ChareInk7SP",
--     "Constantia",
--     "CrimsonPro",
--     "EBGaramond",
--     "GentiumBookPlus",
--     "Georgia",
--     "GoudyOldStyle",
--     "IBMPlexSerif",
--     "IowanOldStBT",
--     "LexiaDaMa",
--     "LiberationSerif",
--     "LibreBaskerville",
--     "Literata7pt",
--     "Luciole",
--     "Merriweather",
--     "Palatino",
--     "Souvenir",
--     "Spectral",
--     "Vollkorn",
-- }

local PINNED_FONTS = {
}

-- Reading time per font, most-read first (same query as "Time per Font").
-- Returns { order = {names...}, secs = {normalized_name = seconds} }.
-- Empty if the DB or the table/column doesn't exist.
local function getFontStats()
    local stats = { order = {}, secs = {} }
    pcall(function()
        local SQ3 = require("lua-ljsqlite3/init")
        local DataStorage = require("datastorage")
        local lfs = require("libs/libkoreader-lfs")

        local db_path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
        if not lfs.attributes(db_path, "mode") then return end

        local conn = SQ3.open(db_path)
        -- Close the connection even if the query fails
        local ok, err = pcall(function()
            local stmt = conn:prepare([[
                SELECT COALESCE(font_name, 'Unknown'), SUM(duration) as total_duration
                FROM wpm_stat_data
                GROUP BY font_name
                ORDER BY total_duration DESC
            ]])
            for row in stmt:rows() do
                local name = row[1]
                if name and name ~= "" and name ~= "Unknown" then
                    local key = (name:gsub("%s+", ""):lower())
                    stats.order[#stats.order + 1] = name
                    -- sum in case two DB names normalize to the same key
                    stats.secs[key] = (stats.secs[key] or 0) + (tonumber(row[2]) or 0)
                end
            end
            stmt:close()
        end)
        conn:close()
        if not ok then require("logger").warn("getFontStats failed:", err) end
    end)
    return stats
end

-- 25 min  /  12.5 h  /  2 d 5 h (days from 24 h up)
local function formatReadTime(secs)
    if not secs or secs <= 0 then return nil end
    if secs < 3600 then
        return string.format("%d min", math.max(1, math.floor(secs / 60 + 0.5)))
    elseif secs < 86400 then
        return string.format("%.1f h", secs / 3600)
    end
    local d = math.floor(secs / 86400)
    local h = math.floor((secs % 86400) / 3600)
    return string.format("%d d %d h", d, h)
end

-- Marker shown before pinned fonts. "*" exists in every font; "★" usually
-- renders through KOReader's fallback fonts, but "📌" often won't on e-ink.
local PIN_MARK = "★ "

local function pinFonts(fonts, names, stats)
    local function norm(s) return (s:gsub("%s+", ""):lower()) end
    stats = stats or { order = {}, secs = {} }

    local index = {}
    for i, face in ipairs(fonts) do index[norm(face)] = i end

    local used, new_fonts, new_names = {}, {}, {}
    local function add(i, pinned)
        used[i] = true
        local label = (names and names[i]) or fonts[i]
        local t = formatReadTime(stats.secs[norm(fonts[i])])
        if t then label = label .. " (" .. t .. ")" end
        new_fonts[#new_fonts + 1] = fonts[i]
        new_names[#new_names + 1] = pinned and (PIN_MARK .. label) or label
    end

    -- 1) Fixed pinned list, in the configured order (skip those not installed)
    for __, pinned in ipairs(PINNED_FONTS) do
        local i = index[norm(pinned)]
        if i and not used[i] then add(i, true) end
    end
    -- 2) Fonts from the database, most-read first
    for __, pinned in ipairs(stats.order) do
        local i = index[norm(pinned)]
        if i and not used[i] then add(i, true) end
    end
    -- 3) Everything else, keeping the original (alphabetical) order
    for i = 1, #fonts do
        if not used[i] then add(i, false) end
    end
    return new_fonts, new_names
end

function PageTextInfo:onShowFonts(page)
    local TextWidget = require("ui/widget/textwidget")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local VerticalGroup = require("ui/widget/verticalgroup")

    -- Grid settings
    local COLUMNS = 2
    local ROWS_PER_PAGE = 5
    local FONT_SIZE = 16
    local PER_PAGE = COLUMNS * ROWS_PER_PAGE

    local ui = self.ui
    -- Only reflowable documents
    if not ui or not ui.document or ui.paging or not ui.font then
        return true
    end

    -- Remember the previous dialog; it is closed after the new one is shown
    local old_dialog = self.fonts_dialog
    local old_region = old_dialog and old_dialog.frame_rect
        and old_dialog.frame_rect:copy()
    self.fonts_dialog = nil

    local fonts, names = FontList.getFontArgFunc()
    self.fonts_stats = self.fonts_stats or getFontStats()
    fonts, names = pinFonts(fonts, names, self.fonts_stats)
    local current = ui.document._document:getFontFace()
    self.font_paths = self.font_paths or buildFacePathMap()

    -- Page to show: if none requested, jump to the page of the current font
    local total_pages = math.max(1, math.ceil(#fonts / PER_PAGE))
    if not page then
        page = 1
        for i, face in ipairs(fonts) do
            if face == current then
                page = math.ceil(i / PER_PAGE)
                break
            end
        end
    end
    page = math.min(math.max(page, 1), total_pages)
    self.fonts_page = page

    local has_prev = page > 1
    local has_next = page < total_pages

    local first = (page - 1) * PER_PAGE + 1
    local last = math.min(first + PER_PAGE - 1, #fonts)

    -- Sizes
    local screen = Screen:getSize()
    local dialog_w = math.floor(screen.w * 0.7)
    local cell_w = math.floor(dialog_w / COLUMNS)
    local font_px = Screen:scaleBySize(FONT_SIZE)
    local cell_h = math.floor(font_px * 2.2)
    local text_h = math.floor(font_px * 1.6)
    local baseline = math.floor(font_px * 1.15)
    local cells = {}   -- font cells: { frame, face, label }
    local btn_prev, btn_next   -- declared here so dialog:onHold can see them

    local dialog = InputContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h },
        ges_events = {
            Tap = { GestureRange:new{
                ges = "tap",
                range = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h },
            } },
            Swipe = { GestureRange:new{
                ges = "swipe",
                range = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h },
            } },
            Hold = { GestureRange:new{
                ges = "hold",
                range = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h },
            } },
        },
        key_events = Device:hasKeys() and { Close = { { Device.input.group.Back } } } or {},
    }
    -- Swipe left/right: next / previous page (wraps around)
    function dialog:onSwipe(arg, ges)
        local dir = ges.direction
        local target
        if dir == "west" then
            target = has_next and page + 1 or 1              -- last -> first
        elseif dir == "east" then
            target = has_prev and page - 1 or total_pages    -- first -> last
        end
        if target and target ~= page then
            UIManager:nextTick(function() self.plugin:onShowFonts(target) end)
        end
        -- Always consume the gesture so it doesn't reach the reader underneath
        return true
    end

    -- Long press: on a font cell shows its info; on the arrows jumps to the
    -- first / last page
    function dialog:onHold(arg, ges)
        -- Font cells
        for __, cell in ipairs(cells) do
            if cell.frame.dimen and ges.pos:intersectWith(cell.frame.dimen) then
                self.plugin:showFontInfo(cell.face, cell.label)
                return true
            end
        end

        -- Arrows: use the real on-screen area of each button
        local target
        if btn_prev.dimen and ges.pos:intersectWith(btn_prev.dimen) then
            target = 1                -- first page
        elseif btn_next.dimen and ges.pos:intersectWith(btn_next.dimen) then
            target = total_pages      -- last page
        end
        if target and target ~= page then
            UIManager:nextTick(function() self.plugin:onShowFonts(target) end)
        end
        return true
    end

    local grid = VerticalGroup:new{ align = "center" }
    local row = HorizontalGroup:new{}

    local function addCell(face, label)
        local text_widget
        local path = face and self.font_paths[face]
        if path then
            local ok, font_face = pcall(Font.getFace, Font, path, FONT_SIZE)
            if ok and font_face then
                text_widget = TextWidget:new{
                    text = label,
                    face = font_face,
                    forced_height = text_h,
                    forced_baseline = baseline,
                    max_width = cell_w - 2 * Size.padding.small,
                }
            end
        end
        -- Fallback to the UI font
        if not text_widget then
            text_widget = TextWidget:new{
                text = label,
                face = Font:getFace("cfont", FONT_SIZE),
                forced_height = text_h,
                forced_baseline = baseline,
                max_width = cell_w - 2 * Size.padding.small,
            }
        end
        local is_current = face ~= nil and face == current
        local thin  = Screen:scaleBySize(1)   -- original grid line
        local thick = Screen:scaleBySize(3)   -- total border of the active cell

        local cell_frame = FrameContainer:new{
            -- Outer frame: thin black line, identical on every cell
            bordersize = thin,
            color = Blitbuffer.COLOR_BLACK,
            margin = 0,
            padding = 0,
            FrameContainer:new{
                -- Inner frame: grows the border inward, black only on the active cell
                bordersize = thick - thin,
                color = is_current and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
                background = Blitbuffer.COLOR_WHITE,
                margin = 0,
                padding = 0,
                CenterContainer:new{
                    dimen = Geom:new{
                        w = cell_w - 2 * thick,
                        h = cell_h - 2 * thick,
                    },
                    text_widget,
                },
            },
        }
        table.insert(row, cell_frame)
        if face then
            table.insert(cells, { frame = cell_frame, face = face, label = label })
        end
    end

    for i = first, last do
        local face = fonts[i]
        addCell(face, (names and names[i]) or face)
        if #row == COLUMNS then
            table.insert(grid, row)
            row = HorizontalGroup:new{}
        end
    end
    -- Pad the last row with empty cells
    if #row > 0 then
        while #row < COLUMNS do
            addCell(nil, "")
        end
        table.insert(grid, row)
    end

    -- Navigation row
    local nav_w = math.floor(dialog_w / 3)
    local nav_h = math.floor(font_px * 1.8)

    local function navCell(text, enabled)
        return FrameContainer:new{
            bordersize = 0,
            padding = 0,
            margin = 0,
            CenterContainer:new{
                dimen = Geom:new{ w = nav_w, h = nav_h },
                TextWidget:new{
                    text = text,
                    face = Font:getFace("cfont", 26),
                    fgcolor = enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY,
                },
            },
        }
    end

    btn_prev = navCell("‹", has_prev)
    local btn_info = navCell(string.format("%d / %d", page, total_pages), true)
    btn_next = navCell("›", has_next)
    table.insert(grid, HorizontalGroup:new{ btn_prev, btn_info, btn_next })

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius = Size.radius.window,
        padding = Size.padding.small,
        grid,
    }
    dialog[1] = CenterContainer:new{
        dimen = Geom:new{ w = screen.w, h = screen.h },
        frame,
    }

    local fsize = frame:getSize()
    local frame_rect = Geom:new{
        x = math.floor((screen.w - fsize.w) / 2),
        y = math.floor((screen.h - fsize.h) / 2),
        w = fsize.w,
        h = fsize.h,
    }

    -- Tap handling
    function dialog:onTap(arg, ges)
        -- Font cells
        for __, cell in ipairs(cells) do
            if cell.frame.dimen and ges.pos:intersectWith(cell.frame.dimen) then
                -- Same face already applied: skip the extra SetFont and reflow
                if cell.face ~= current then
                    self.plugin:applyFontAndReopen(cell.face)
                end
                return true
            end
        end

        if ges.pos:intersectWith(frame_rect) then
            -- Navigation row
            local nav_top = frame_rect.y + frame_rect.h
                            - Size.border.window - Size.padding.small - nav_h
            if ges.pos.y >= nav_top then
                local third = frame_rect.w / 3
                local rel_x = ges.pos.x - frame_rect.x
                if rel_x < third then
                    if has_prev then
                        UIManager:nextTick(function() self.plugin:onShowFonts(page - 1) end)
                    end
                elseif rel_x > 2 * third then
                    if has_next then
                        UIManager:nextTick(function() self.plugin:onShowFonts(page + 1) end)
                    end
                end
            end
            return true
        end

        -- Tap outside the window: close
        self.plugin:closeFontsMenu()
        return true
    end

    function dialog:onClose()
        self.plugin:closeFontsMenu()
        return true
    end

    dialog.plugin = self
    dialog.frame_ref = frame
    dialog.frame_rect = frame_rect
    self.fonts_dialog = dialog

    local region = frame_rect
    if old_region then region = region:combine(old_region) end

    UIManager:show(dialog, "ui", region)
    if old_dialog then
        UIManager:close(old_dialog, "ui", region)
    end
    return true
end

end -- return function(PageTextInfo)
