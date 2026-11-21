-- Fonts menu: paged grid of font families, with long-press font info.
--
-- Lives next to main.lua. Load it from main.lua, after PageTextInfo is defined:
--     require("font_selection_menu")(PageTextInfo)
--
-- It adds these methods to PageTextInfo:
--     closeFontsMenu, applyFontAndReopen, showFontInfo, onShowFonts
--
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FontList = require("fontlist")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

-- Seconds after a change before the menu is refreshed for the last time (the page
-- refresh that comes first can leave it grey) and starts accepting taps again (the ones
-- made while the book was being laid out are delivered right before and dropped).
-- Lower = the menu settles sooner; too low and the two refreshes collide (flashes on
-- the Paperwhite) or a queued tap starts a second change.
local SETTLE_DELAY = 0.2

-- Input inhibition while a font is being applied.
-- ReaderRolling:onUpdatePos (run by SetFont) calls Input:inhibitInput(true) before the
-- re-layout and Input:inhibitInputUntil(0.2) after it, which drops all input for the
-- whole re-layout, so a tap outside the menu made in that window never reaches it.
-- The menu already protects itself with `busy`, so while it is applying a font those
-- requests are ignored. It only acts while the menu is on screen and busy.
-- Set to false to go back to KOReader's behaviour.
local ALLOW_INPUT_DURING_FONT_CHANGE = true
local active_dialog   -- the fonts dialog on screen, if any
if ALLOW_INPUT_DURING_FONT_CHANGE then
    pcall(function()
        local input = Device.input
        if input and not input._pti_inhibit_wrapped then
            local orig = input.inhibitInput
            input.inhibitInput = function(self_, toggle, ...)
                if toggle and active_dialog and active_dialog.busy then
                    return
                end
                return orig(self_, toggle, ...)
            end
            input._pti_inhibit_wrapped = true
        end
    end)
end

return function(PageTextInfo)

-- One pass over the font list. Returns two maps:
--   face name -> font file path (prefers the regular style)
--   face name -> set of styles available ("Regular", "Bold", ...)
local function buildFaceMaps()
    local regular, any, styles = {}, {}, {}
    local list = FontList:getFontList() or {}
    for __, path in ipairs(list) do
        local info = FontList.fontinfo and FontList.fontinfo[path]
        if info then
            for __, f in ipairs(info) do
                if f.name then
                    local st = (f.bold and f.italic) and "Bold Italic"
                        or f.bold and "Bold"
                        or f.italic and "Italic"
                        or "Regular"
                    styles[f.name] = styles[f.name] or {}
                    styles[f.name][st] = true
                    -- Ties go to the smallest path (the same rule as resolveFace in
                    -- settings_menu.lua), so the result never depends on list order
                    if not f.bold and not f.italic then
                        if not regular[f.name] or path < regular[f.name] then
                            regular[f.name] = path
                        end
                    end
                    if not any[f.name] or path < any[f.name] then
                        any[f.name] = path
                    end
                end
            end
        end
    end
    for name, path in pairs(any) do
        regular[name] = regular[name] or path
    end
    return regular, styles
end

-- Font:getFace keeps every face it loads in Font.faces for good, and a face is a
-- whole font file mapped in memory. The menu draws each name in its own font (and
-- the info window loads one at 100 px), so browsing the list piled up hundreds of
-- them until the device crawled. This takes the fonts of the list out of that
-- cache: widgets still showing one keep it alive, the rest is freed by the
-- collection forced at the end (the Lua GC alone does not see that memory).
-- Resident memory of the process in MB (nil where /proc is not available)
local function residentMb()
    local fh = io.open("/proc/self/status", "r")
    if not fh then return nil end
    local mb
    for line in fh:lines() do
        local kb = line:match("^VmRSS:%s+(%d+)")
        if kb then mb = math.floor(tonumber(kb) / 1024 + 0.5); break end
    end
    fh:close()
    return mb
end

local malloc_trim_declared   -- the C declaration is made once

local function purgeFontFaces(self)
    local faces = require("ui/font").faces
    if type(faces) ~= "table" or not self.font_paths then return end
    local paths = {}
    for __, path in pairs(self.font_paths) do
        if type(path) == "string" then paths[path] = true end
    end
    local drop = {}
    for key, face in pairs(faces) do
        local realname = type(face) == "table" and face.realname
        local match = realname and paths[realname]
        if not match and type(key) == "string" then
            for path in pairs(paths) do
                if key:sub(1, #path) == path then match = true; break end
            end
        end
        if match then drop[#drop + 1] = key end
    end
    local rss_before = residentMb()
    for __, key in ipairs(drop) do faces[key] = nil end
    collectgarbage()
    local rss_gc = residentMb()
    -- glibc keeps the memory it was given even when it is free again, so the
    -- resident size creeps up with every font loaded and freed: hand it back
    pcall(function()
        local ffi = require("ffi")
        if not malloc_trim_declared then
            -- It may already be declared elsewhere: that error must not skip the trim
            pcall(ffi.cdef, "int malloc_trim(size_t pad);")
            malloc_trim_declared = true
        end
        ffi.C.malloc_trim(0)
    end)
    pcall(function()
        require("logger").dbg("[PTI] purgeFontFaces: dropped", #drop, "faces; RSS MB:",
            tostring(rss_before), "-> after GC", tostring(rss_gc),
            "-> after malloc_trim", tostring(residentMb()))
    end)
end

-- Freeing the faces forces a full garbage collection and a malloc_trim, which can
-- take a good part of a second. It runs two ticks later, after the change of menu
-- has been painted, so the screen never waits for it.
-- Later still, and only once: every change of font (and closing the menu) asks for
-- it; they are joined into a single one that runs 2 s after the last request, so it
-- does not get in the way of the next thing the user does.
local purge_fn
local function purgeFontFacesLater(self)
    if purge_fn then UIManager:unschedule(purge_fn); purge_fn = nil end
    -- Not while the menu is open: on slower devices (Paperwhite) the collection
    -- blocks the loop for long enough to swallow the taps the user makes to close
    -- the menu. closeFontsMenu asks for it again once the menu is gone.
    if self.fonts_dialog then return end
    purge_fn = function()
        purge_fn = nil
        -- The menu was opened again in the meantime: wait for it to be closed
        if self.fonts_dialog then return end
        -- The settings menu is on screen (the fonts menu was opened from it): the
        -- collection would swallow its taps. Ask again, which checks every 2 s until
        -- that menu is gone.
        if self.settings_dialog then purgeFontFacesLater(self); return end
        -- A failure here must never take KOReader down: log it and go on
        local ok, err = pcall(purgeFontFaces, self)
        if not ok then require("logger").warn("[PTI] purgeFontFaces failed:", err) end
    end
    UIManager:scheduleIn(2, purge_fn)
end

-- Close the fonts menu and repaint the page underneath
function PageTextInfo:closeFontsMenu()
    local d = self.fonts_dialog
    self.fonts_dialog = nil
    if d == active_dialog then active_dialog = nil end
    self.fonts_stats = nil
    local changed = self.fonts_changed
    self.fonts_changed = nil
    if d then
        if changed then
            -- A font was applied: the whole page was laid out again while the menu
            -- covered part of it, so the text around and under the menu has been
            -- refreshed in different modes at different moments (ghosting, bits of
            -- the old layout). Closing with only the menu's rectangle in "ui" mode
            -- left those behind. One non-flashing "partial" refresh of the whole
            -- page leaves it consistent.
            local s = Screen:getSize()
            UIManager:close(d, "partial", Geom:new{ x = 0, y = 0, w = s.w, h = s.h })
        else
            UIManager:close(d, "ui", d.frame_rect)
        end
    end
    purgeFontFacesLater(self)

    -- Opened from the settings menu: go back to it (flag set in settings_menu.lua)
    if self.fonts_from_settings then
        self.fonts_from_settings = nil
        if self.onShowSettingsMenu then
            UIManager:nextTick(function()
                self:onShowSettingsMenu()
                -- NOTE: toggleBar() must act as a REFRESH of the top bar here.
                -- If it is a real on/off switch, it flips every time.
                if self.view and self.view.topbar then
                    self.view.topbar:toggleBar()
                end
            end)
        end
    end
end

-- Apply the font directly on the reader (synchronously). Sizes are in pt only: the
-- size stays as it is and the book is laid out again with the new face (KOReader's
-- own behaviour). Returns the timing function `lap`.
function PageTextInfo:applyFont(face)
    local Event = require("ui/event")
    -- Timing of every phase (wall clock, ms), always logged: grep "[PTI] timing"
    local time = require("ui/time")
    local t0 = time.now()
    local function lap(name)
        require("logger").dbg("[PTI] timing: font change,", name, time.to_ms(time.since(t0)), "ms")
    end

    self.ui:handleEvent(Event:new("SetFont", face))
    lap("SetFont")
    return lap
end

-- Apply the font, then show the menu again (kept for callers that need a new menu)
function PageTextInfo:applyFontAndReopen(face)
    local page = self.fonts_page
    local lap = self:applyFont(face)
    UIManager:nextTick(function()
        -- The menu was closed while the font was being applied: don't reopen it
        if self.fonts_dialog then self:onShowFonts(page) end
        purgeFontFacesLater(self)
        lap("fonts menu shown")
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

    -- Styles available for this family (computed once, with the path map)
    local has = self.font_styles and self.font_styles[face] or {}
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

    -- x-height: the value stored in the font (one read, no rendering)
    local metrics_lines = {}
    local xi = self.getFontXHeightInfo and self:getFontXHeightInfo(face)
    table.insert(metrics_lines, xi
        and string.format("x-height: %s%.2fmm%s (%dpx) at %gpt; design %.1f%% of em",
            xi.estimated and "~" or "", xi.mm, xi.rem and " (rem)" or "", xi.px, xi.pt, xi.ratio * 100)
        or "x-height: n/a")
    if xi and xi.rem then
        table.insert(metrics_lines, string.format(
            "Book text is set in rem: x%.2f of the chosen size (%.2fmm without it)", xi.rem, xi.mm_nominal))
    end

    -- Readability from readability_table.lua, with the reason the script gives
    local rating, why
    if self.getFontReadability then rating, why = self:getFontReadability(face, path) end
    table.insert(metrics_lines, "Readability: " .. (rating
        and (why and (rating .. " (" .. why .. ")") or rating) or "n/a"))

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
        -- Double tap off while this window is on top. KOReader works it out again
        -- every time a widget is closed (UIManager:close) from the topmost widget that
        -- states it, and this one stated nothing: the reader below (with double tap
        -- on) won, so after the window was reopened (show new, close old) taps were
        -- delayed and a second quick tap came as "double_tap", which nobody handled.
        disable_double_tap = true,
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
        if not ok then require("logger").warn("[PTI] getFontStats failed:", err) end
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

    -- 1) Fonts from the database, most-read first
    for __, pinned in ipairs(stats.order) do
        local i = index[norm(pinned)]
        if i and not used[i] then add(i, true) end
    end
    -- 2) Everything else, keeping the original (alphabetical) order
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
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local VerticalSpan = require("ui/widget/verticalspan")
    local LineWidget = require("ui/widget/linewidget")
    local LeftContainer = require("ui/widget/container/leftcontainer")

    -- Grid settings
    local COLUMNS = 2
    local ROWS_PER_PAGE = 5
    local FONT_SIZE = 14
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
    local current = ui.font.font_face
    if not self.font_paths then
        self.font_paths, self.font_styles = buildFaceMaps()
    end

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
    local frame_w = math.floor(screen.w * 0.8)
    local outer_pad = Screen:scaleBySize(5)
    -- Inner width available for the grid (window width minus padding and border)
    local dialog_w = frame_w - 2 * (outer_pad + Size.border.window)
    local gap = Screen:scaleBySize(3)   -- space between cells and between rows
    local thin = Screen:scaleBySize(1)
    local cell_w = math.floor((dialog_w - gap * (COLUMNS - 1)) / COLUMNS)
    -- The last column takes the rounding remainder so rows span exactly dialog_w
    local last_cell_w = dialog_w - gap * (COLUMNS - 1) - cell_w * (COLUMNS - 1)
    local label_h = math.floor(Screen:scaleBySize(11) * 1.4)
    local font_px = Screen:scaleBySize(FONT_SIZE)
    local cell_h = math.floor(font_px * 2.0)
    local text_h = math.floor(font_px * 1.6)
    local baseline = math.floor(font_px * 1.15)
    local cells = {}   -- font cells: { frame, face, label }
    local btn_prev, btn_next   -- declared here so dialog:onHold can see them

    local dialog = InputContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = screen.w, h = screen.h },
        -- Double tap off while this window is on top. KOReader works it out again
        -- every time a widget is closed (UIManager:close) from the topmost widget that
        -- states it, and this one stated nothing: the reader below (with double tap
        -- on) won, so after the window was reopened (show new, close old) taps were
        -- delayed and a second quick tap came as "double_tap", which nobody handled.
        disable_double_tap = true,
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
        -- A swipe that starts outside the window does nothing (it does not close it)
        -- and is consumed so it doesn't reach the reader underneath
        -- (frame_rect is a local declared further down, so it is read from the dialog)
        if not (ges and ges.pos and self.frame_rect and ges.pos:intersectWith(self.frame_rect)) then
            return true
        end
        if self.busy then return true end   -- a font is being applied
        -- Diagonal swipes ("northwest", "southeast"...) count too: only the
        -- horizontal part matters
        local dir = ges.direction or ""
        local target
        if dir:find("west") then
            target = has_next and page + 1 or 1              -- last -> first
        elseif dir:find("east") then
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
        if self:closeIfOutside(ges) then return true end
        if self.busy then return true end   -- a font is being applied
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

    -- Fonts installed / fonts already used (the ones with reading time in the stats)
    local used_count = 0
    for __, face in ipairs(fonts) do
        if self.fonts_stats.secs[(face:gsub("%s+", ""):lower())] then
            used_count = used_count + 1
        end
    end

    -- Caption: fonts installed / used, and the x-height of the current font at the
    -- size now set. It is built again when the font changes.
    local function buildCaption(cur)
        local text = string.format("Fonts: %d  |  Used: %d", #fonts, used_count)
        local xi = cur and self.getFontXHeightInfo and self:getFontXHeightInfo(cur)
        text = text .. (xi and string.format("  |  x-height: %s%.2fmm%s", xi.estimated and "~" or "", xi.mm,
            xi.rem and " (rem)" or "")
            or "  |  x-height: n/a")
        -- How good the font is: HIGH / MEDIUM / LOW from readability_table.lua
        local rating = cur and self.getFontReadability
            and self:getFontReadability(cur, self.font_paths and self.font_paths[cur])
        return text .. "  |  " .. (rating or "n/a")
    end
    local caption = buildCaption(current)

    local grid = VerticalGroup:new{ align = "center" }

    -- Small caption with a thin separator below it (same look as the settings
    -- menu). Kept in cap_widget to change its text in place.
    local cap_widget = TextWidget:new{
        text = caption,
        face = Font:getFace("cfont", 11),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = dialog_w - 2 * gap,
    }
    table.insert(grid, LeftContainer:new{
        dimen = Geom:new{ w = dialog_w, h = label_h },
        HorizontalGroup:new{
            HorizontalSpan:new{ width = gap },
            cap_widget,
        },
    })
    table.insert(grid, LineWidget:new{
        dimen = Geom:new{ w = dialog_w, h = thin },
        background = Blitbuffer.COLOR_DARK_GRAY,
    })
    table.insert(grid, VerticalSpan:new{ width = gap })

    local row = HorizontalGroup:new{}
    local col = 0   -- cells in the current row (spacers don't count)

    local function addCell(face, label)
        local w = (col == COLUMNS - 1) and last_cell_w or cell_w
        local is_current = face ~= nil and face == current
        -- The active cell is inverted (white text on black)
        local fg = is_current and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        local text_widget
        local path = face and self.font_paths[face]
        if path then
            local ok, font_face = pcall(Font.getFace, Font, path, FONT_SIZE)
            if ok and font_face then
                text_widget = TextWidget:new{
                    text = label,
                    face = font_face,
                    fgcolor = fg,
                    forced_height = text_h,
                    forced_baseline = baseline,
                    max_width = w - 2 * Size.padding.small,
                }
            end
        end
        -- Fallback to the UI font
        if not text_widget then
            text_widget = TextWidget:new{
                text = label,
                face = Font:getFace("cfont", FONT_SIZE),
                fgcolor = fg,
                forced_height = text_h,
                forced_baseline = baseline,
                max_width = w - 2 * Size.padding.small,
            }
        end

        -- Rounded cell; the empty padding cells have no visible border
        local cell_frame = FrameContainer:new{
            bordersize = thin,
            color = is_current and Blitbuffer.COLOR_BLACK
                or (face and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_WHITE),
            background = is_current and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
            radius = Size.radius.button,
            margin = 0,
            padding = 0,
            CenterContainer:new{
                dimen = Geom:new{
                    w = w - 2 * thin,
                    h = cell_h - 2 * thin,
                },
                text_widget,
            },
        }
        if col > 0 then table.insert(row, HorizontalSpan:new{ width = gap }) end
        table.insert(row, cell_frame)
        col = col + 1
        if face then
            table.insert(cells, { frame = cell_frame, face = face, label = label,
                text = text_widget, current = is_current })
        end
    end

    local function flushRow()
        table.insert(grid, row)
        table.insert(grid, VerticalSpan:new{ width = gap })
        row = HorizontalGroup:new{}
        col = 0
    end

    for i = first, last do
        local face = fonts[i]
        addCell(face, (names and names[i]) or face)
        if col == COLUMNS then flushRow() end
    end
    -- Pad the last row with empty cells
    if col > 0 then
        while col < COLUMNS do
            addCell(nil, "")
        end
        flushRow()
    end

    -- Navigation row
    local nav_w = math.floor((dialog_w - 2 * gap) / 3)
    local nav_last_w = dialog_w - 2 * gap - 2 * nav_w
    local nav_h = math.floor(font_px * 2)
    -- Arrows and counter share the same baseline (a plain centered text box
    -- would put the "‹" "›" glyphs higher than the digits). The baseline is
    -- placed so the middle of the arrow glyph sits in the middle of the button.
    local nav_baseline = math.floor(nav_h / 2 + Screen:scaleBySize(24) * 0.25)

    -- boxed: rounded outline (arrows); the page counter has none
    local function navCell(text, enabled, boxed, size, w)
        local bs = boxed and thin or 0
        return FrameContainer:new{
            bordersize = bs,
            color = enabled and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_LIGHT_GRAY,
            radius = Size.radius.button,
            padding = 0,
            margin = 0,
            CenterContainer:new{
                dimen = Geom:new{ w = w - 2 * bs, h = nav_h - 2 * bs },
                TextWidget:new{
                    text = text,
                    face = Font:getFace("cfont", size),
                    forced_height = nav_h - 2 * bs,
                    forced_baseline = nav_baseline - bs,
                    fgcolor = enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY,
                },
            },
        }
    end

    btn_prev = navCell("‹", has_prev, true, 24, nav_w)
    local btn_info = navCell(string.format("%d / %d", page, total_pages), true, false, 18, nav_w)
    btn_next = navCell("›", has_next, true, 24, nav_last_w)
    table.insert(grid, HorizontalGroup:new{
        btn_prev,
        HorizontalSpan:new{ width = gap },
        btn_info,
        HorizontalSpan:new{ width = gap },
        btn_next,
    })

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius = Size.radius.window,
        padding = outer_pad,
        margin = 0,
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

    -- A gesture that starts outside the window closes the menu (a tap with a bit of
    -- movement comes as a swipe or a hold, and used to be swallowed)
    function dialog:closeIfOutside(ges)
        if not (ges and ges.pos) or ges.pos:intersectWith(frame_rect) then return false end
        self:requestClose()
        return true
    end

    -- The font changed: update the caption in place
    function dialog:updateCaptions(face)
        cap_widget:setText(buildCaption(face))
    end

    -- Invert the chosen cell (and restore the one that was active): done right after
    -- the font has been applied. Returns the area to refresh.
    local function markCurrent(cell)
        local region
        for __, c in ipairs(cells) do
            if c == cell or c.current then
                local on = (c == cell)
                c.frame.background = on and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
                c.frame.color = on and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY
                c.text.fgcolor = on and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
                c.current = on
                if c.frame.dimen then
                    region = region and region:combine(c.frame.dimen) or c.frame.dimen:copy()
                end
            end
        end
        return region
    end

    -- Applies a font cell: lays the book out again with the new face, marks the cell and
    -- refreshes the menu. Used by a tap and by a tap that was remembered (see below).
    function dialog:applyCell(cell)
        -- Same face already applied: skip the extra SetFont and reflow
        if cell.face == current then return end
        local plugin, face = self.plugin, cell.face
        -- The cell is NOT highlighted yet: it is only marked as the current
        -- font once the font has been applied and the book laid out again
        -- (see markCurrent, called from the timer below)
        self.busy = true
        -- Like KOReader's own config panel (ConfigDialog:onConfigChoose): the
        -- change is applied two ticks after the tap, not inside the tap
        -- handler, so the gesture is completely handled before the re-layout
        -- blocks and inhibits the input
        UIManager:tickAfterNext(function()
            if plugin.fonts_dialog ~= self then self.busy = nil; return end
            local ok, err = pcall(plugin.applyFont, plugin, face)
            if ok then
                current = face
                plugin.fonts_changed = true   -- closeFontsMenu cleans the page up
                -- SetFont is synchronous: the book has been laid out again by
                -- now (ReaderRolling:onUpdatePos), so mark the cell right away.
                -- It is painted in the same pass as the new page, instead of
                -- waiting for the timer below.
                local okm, region = pcall(markCurrent, cell)
                UIManager:setDirty(self, "ui", okm and region or nil)
                -- The caption (x-height, rating) can be measured now: SetFont has
                -- already laid the book out (see above), so the engine reports the
                -- new font. It is refreshed together with the cell and the page.
                pcall(self.updateCaptions, self, face)
                UIManager:setDirty(self, "ui", self.frame_rect)
                -- The book is laid out again a couple of ticks from now and the
                -- whole page is refreshed with the "partial" mode, which can
                -- leave the menu on top of it grey or ghosted. Once that is done
                -- (the timer is due after the layout, which blocks the loop) the
                -- menu is refreshed once more on its own, with the "ui" mode.
                local dlg = self
                local function settle()
                    if plugin.fonts_dialog ~= dlg then dlg.busy = nil; return end
                    -- The caption is already up to date: this is only the clean
                    -- "ui" refresh after the page refresh
                    UIManager:setDirty(dlg, "ui", dlg.frame_rect)
                    -- Everything is done in this step (layout, correction, caches).
                    -- Taps made while the loop was blocked have already reached the
                    -- dialog and were dealt with while it was locked: it is selectable
                    -- again from here.
                    purgeFontFacesLater(plugin)
                    dlg.busy = nil
                    if dlg.close_after then
                        -- A tap outside came meanwhile: close now that the refreshes are done
                        plugin:closeFontsMenu()
                    else
                        -- Otherwise do what was tapped last meanwhile, if anything
                        dlg:runPending()
                    end
                end
                -- SETTLE_DELAY is counted from AFTER the first repaint of the change
                -- (two ticks on), not from now: a timer started here could fall due
                -- right behind that repaint, and the menu's final refresh would
                -- collide with the page refresh still in flight.
                UIManager:tickAfterNext(function()
                    UIManager:scheduleIn(SETTLE_DELAY, settle)
                end)
            else
                require("logger").warn("[PTI] applyFont failed:", err)
                self.busy = nil
                if self.close_after then
                    plugin:closeFontsMenu()
                else
                    plugin:onShowFonts(plugin.fonts_page)   -- draw the real state again
                end
            end
        end)
    end

    -- On a slow device (Kindle) the book is laid out and the screen refreshed for a second
    -- or two after a tap, and the taps made meanwhile reach the menu only afterwards, while
    -- it is still locked: they used to be lost. Now the LAST font cell or page arrow tapped
    -- meanwhile is remembered (self.pending) and done as soon as the menu is free.
    function dialog:runPending()
        local pending = self.pending
        self.pending = nil
        if not pending or self.busy or self.plugin.fonts_dialog ~= self then return end
        require("logger").dbg("[PTI] fonts menu: doing the tap remembered meanwhile")
        if pending.cell then
            self:applyCell(pending.cell)
        elseif pending.page then
            local plugin, target = self.plugin, pending.page
            UIManager:nextTick(function() plugin:onShowFonts(target) end)
        end
    end

    -- Tap handling
    function dialog:onTap(arg, ges)
        -- Font cells
        for __, cell in ipairs(cells) do
            if cell.frame.dimen and ges.pos:intersectWith(cell.frame.dimen) then
                -- A font is being applied: no second selection until the book has been
                -- laid out again and the menu refreshed. The last one tapped meanwhile is
                -- remembered and applied then (a tap outside still closes the menu)
                if self.busy then
                    if not self.close_after then
                        self.pending = { cell = cell }
                        require("logger").dbg("[PTI] fonts menu: tap remembered:", cell.face)
                    end
                    return true
                end
                self:applyCell(cell)
                return true
            end
        end

        if ges.pos:intersectWith(frame_rect) then
            -- Navigation buttons: use the real on-screen area of each one
            local dir
            if btn_prev.dimen and ges.pos:intersectWith(btn_prev.dimen) then
                dir = -1
            elseif btn_next.dimen and ges.pos:intersectWith(btn_next.dimen) then
                dir = 1
            end
            if self.busy then   -- a font is being applied: remember the page, go there after
                if dir and not self.close_after then
                    local target = ((self.pending and self.pending.page) or page) + dir
                    if target >= 1 and target <= total_pages then
                        self.pending = { page = target }
                        require("logger").dbg("[PTI] fonts menu: page tap remembered:", target)
                    end
                end
                return true
            end
            if dir == -1 and has_prev then
                UIManager:nextTick(function() self.plugin:onShowFonts(page - 1) end)
            elseif dir == 1 and has_next then
                UIManager:nextTick(function() self.plugin:onShowFonts(page + 1) end)
            end
            return true
        end

        -- Tap outside the window: close
        self:requestClose()
        return true
    end

    -- Close the menu. While a font is being applied the close waits for the end of
    -- the change (see the timer in onTap): closing in the middle of the page refresh
    -- and of the menu's own final refresh makes the two collide and leaves glitches.
    function dialog:requestClose()
        if self.busy then
            self.close_after = true
        else
            self.plugin:closeFontsMenu()
        end
    end

    -- Back key: like a tap outside, it waits for a font being applied to finish
    function dialog:onClose()
        self:requestClose()
        return true
    end
    dialog.plugin = self
    dialog.frame_rect = frame_rect

    -- Report the area the menu really covers as its dimen, not the whole screen.
    -- The dialog needs a full-screen dimen to be built, but Bookends' flipping halo
    -- (the page-coloured circle it draws behind KOReader's top-left "re-rendering"
    -- icon) skips itself when the topmost widget's dimen covers that corner. With
    -- a full-screen dimen it was always skipped, so on every font change the
    -- re-render icon was drawn straight over Bookends' top-left text, and its
    -- "fast" refresh left that corner glitchy. The menu is centred and never
    -- reaches the corner, so the halo must be allowed to paint.
    -- WidgetContainer:paintTo rewrites dimen.x / dimen.y on every paint, so the
    -- real rectangle is put back after each one (the halo toast paints later in
    -- the same pass, so it always sees the right value).
    function dialog:paintTo(bb, x, y)
        InputContainer.paintTo(self, bb, x, y)
        self.dimen = frame_rect:copy()
    end

    self.fonts_dialog = dialog
    active_dialog = dialog

    local region = frame_rect
    if old_region then region = region:combine(old_region) end

    UIManager:show(dialog, "ui", region)
    if old_dialog then
        UIManager:close(old_dialog, "ui", region)
    end
    return true
end

end -- return function(PageTextInfo)
