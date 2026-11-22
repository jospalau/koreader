-- Custom dogear patch
--
-- 1) Replaces the stock dogear icon with your own image (dogear-custom.png / .svg), drawn SCALE times bigger.
-- 2) Makes sure the dogear is painted ON TOP of everything else the ReaderView draws (Bookends, other view modules),
--    without editing readerview.lua and without an extra overlay widget.
--
-- Stock KOReader paints the dogear in ReaderView:paintTo() BEFORE the view modules, so a module such as Bookends can
-- cover it. Here ReaderView:paintTo() is wrapped: the early stock paint is skipped, the original runs, and the dogear is
-- painted last. The original runs under pcall, so even if a view module raises an error halfway the dogear is still
-- painted and then the error is re-thrown unchanged (nothing is hidden).
--
-- Because nothing is changed in readerview.lua any more, you can undo your edit of that file.
--
-- Where to put the icon (first match wins):
--   <koreader>/resources/icons/dogear-custom.png   (or .svg)
--   <koreader>/icons/dogear-custom.png             (or .svg)
-- If no icon is found the stock one is used.

local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local Device = require("device")
local ImageWidget = require("ui/widget/imagewidget")
local ReaderDogear = require("apps/reader/modules/readerdogear")
local ReaderView = require("apps/reader/modules/readerview")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Screen = Device.screen

-- Size relative to the stock dogear (stock = 1/32 of the short screen side, reduced to fit the page margins)
local SCALE = 4
local ICON_NAMES = { "dogear-custom.png", "dogear-custom.svg" }

-- Size in percent, set from the Page text info menu ("Dogear size"). 100 = SCALE times the stock dogear.
local function getSizePct()
    local ok, pct = pcall(function() return G_reader_settings:readSetting("custom_dogear_size_pct") end)
    if ok and type(pct) == "number" then
        return math.max(10, math.min(400, pct))
    end
    return 100
end

-- The icon can be picked from the Page text info menu ("Dogear icon"): its file name is stored in the global setting
-- "custom_dogear_icon". "@stock" = use KOReader's own dogear. Nothing stored / file missing = dogear-custom.png.
local function findIcon()
    local ok, selected = pcall(function() return G_reader_settings:readSetting("custom_dogear_icon") end)
    if ok and selected == "@stock" then
        return nil
    end
    local names = {}
    if ok and type(selected) == "string" and selected ~= "" then
        names[#names + 1] = selected
    end
    for _, name in ipairs(ICON_NAMES) do names[#names + 1] = name end

    local base = DataStorage:getDataDir()
    for _, name in ipairs(names) do
        for _, dir in ipairs({ base .. "/resources/icons/", base .. "/icons/" }) do
            local path = dir .. name
            if lfs.attributes(path, "mode") == "file" then
                return path
            end
        end
    end
end

-- ===== Custom icon =====
if not ReaderDogear._custom_dogear_patched then
    ReaderDogear._custom_dogear_patched = true

    local orig_setupDogear = ReaderDogear.setupDogear
    ReaderDogear.setupDogear = function(self, new_dogear_size)
        local base_size = new_dogear_size or self.dogear_max_size
        -- Already built for this stock size: nothing to do.
        -- (Without this, every margin / layout event rebuilt the icon from scratch.)
        if self._custom_base_size == base_size and self._custom_icon_active then
            return
        end
        self._custom_base_size, self._custom_icon_active = nil, nil

        orig_setupDogear(self, new_dogear_size)

        local icon_path = findIcon()
        if not icon_path or not self.icon or not self.vgroup then
            return   -- stock icon stays
        end

        local scaled_size = math.max(8, math.ceil(base_size * SCALE * getSizePct() / 100))
        local ok, err = pcall(function()
            -- Build the new widget first: if it fails, the stock icon is left untouched
            local new_icon = ImageWidget:new{
                file = icon_path,
                width = scaled_size,
                height = scaled_size,
                alpha = true,
                is_icon = true,
                rotation_angle = BD.mirroredUILayout() and 90 or 0,   -- same mirroring as the stock icon
            }
            self.icon:free()
            self.icon = new_icon
            self.dogear_size = scaled_size
            self.vgroup[2] = new_icon
            self.vgroup:resetLayout()
            if self[1] and self[1].dimen then
                self[1].dimen.w = Screen:getWidth()
                self[1].dimen.h = (self.dogear_y_offset or 0) + scaled_size
            end
        end)
        if ok then
            self._custom_base_size = base_size
            self._custom_icon_active = true
        else
            logger.warn("custom dogear: could not load", icon_path, err)
        end
    end
end

-- Rebuild the dogear with the currently selected icon (called by the Page text info menu after a new icon is picked).
function ReaderDogear:reloadCustomIcon()
    local base = self._custom_base_size or self.dogear_size or self.dogear_max_size
    self._custom_base_size, self._custom_icon_active = nil, nil
    self.dogear_size = nil                  -- makes the original setupDogear rebuild the widgets
    self:setupDogear(base)
end

-- ===== Safety net =====
-- KOReader asks the dogear for its refresh region when a bookmark is toggled (ReaderBookmark:onToggleBookmark ->
-- ReaderDogear:getRefreshRegion), and the stock code simply does `return self.icon.dimen`: if `icon` is ever nil that
-- takes the whole reader down ("attempt to index field 'icon' (a nil value)"). Instead of crashing, rebuild the icon
-- (and log it) and, if even that fails, fall back to the container's own area.
if not ReaderDogear._custom_dogear_region_patched then
    ReaderDogear._custom_dogear_region_patched = true

    local orig_getRefreshRegion = ReaderDogear.getRefreshRegion
    ReaderDogear.getRefreshRegion = function(self)
        if self.icon then
            return orig_getRefreshRegion(self)
        end
        logger.warn("custom dogear: icon was nil in getRefreshRegion, rebuilding it")
        self._custom_base_size, self._custom_icon_active = nil, nil
        self.dogear_size = nil                       -- forces setupDogear to rebuild
        pcall(self.setupDogear, self)
        if self.icon then
            return self.icon.dimen
        end
        return self[1] and self[1].dimen
    end
end

-- ===== Always on top =====
if not ReaderView._custom_dogear_top_patched then
    ReaderView._custom_dogear_top_patched = true

    local orig_paintTo = ReaderView.paintTo
    ReaderView.paintTo = function(self, bb, x, y)
        local visible = self.dogear_visible
        if not visible or not self.dogear then
            return orig_paintTo(self, bb, x, y)
        end
        -- Skip the early stock paint WITHOUT touching dogear_visible: other view modules (e.g. the top bar moves its
        -- corner mark to the bottom-right while a bookmark dogear is showing) read that flag while they paint.
        -- So the dogear widget's own paintTo is muted for the duration of the original paint instead.
        local dogear = self.dogear
        local real_paintTo = dogear.paintTo
        local own_paintTo = rawget(dogear, "paintTo")
        dogear.paintTo = function() end
        local ok, err = pcall(orig_paintTo, self, bb, x, y)
        dogear.paintTo = own_paintTo         -- nil removes the override again
        pcall(real_paintTo, dogear, bb, x, y)   -- on top of everything
        if not ok then
            error(err, 0)                    -- keep the original behaviour for real errors
        end
    end
end
