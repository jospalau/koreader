local AlphaContainer = require("ui/widget/container/alphacontainer")
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FileChooser = require("ui/widget/filechooser")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local ImageWidget = require("ui/widget/imagewidget")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local userpatch = require("userpatch")

local Screen = Device.screen

-- local logger = require("logger")

local orig_FileChooser_getList = FileChooser.getList
local cached_list = {}

function FileChooser:getList(path, collate)
    local key = tostring(path) .. tostring(collate) .. tostring(self.show_filter.status)
    cached_list[key] = cached_list[key] or { orig_FileChooser_getList(self, path, collate) }
    return table.unpack(cached_list[key])
end

local function capitalize(sentence)
    local words = {}
    for word in sentence:gmatch("%S+") do
        table.insert(words, word:sub(1, 1):upper() .. word:sub(2):lower())
    end
    return table.concat(words, " ")
end

local function getAlphaFrame(border_size, alpha, widget)
    return FrameContainer:new {
        padding = 0,
        bordersize = border_size,
        AlphaContainer:new { alpha = alpha, widget },
    }
end

local function patchCoverBrowser(plugin)
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    local BookInfoManager = userpatch.getUpValue(MosaicMenuItem.update, "BookInfoManager")
    local original_update = MosaicMenuItem.update

    function MosaicMenuItem:update(...)
        original_update(self, ...)
        if self._foldercover_processed or self.menu.no_refresh_covers or not self.do_cover_image then
            return
        end

        if self.entry.is_file or self.entry.file then return end -- it's a file
        local dir_path = self.entry and self.entry.path
        if not dir_path then return end

        self.menu._dummy = true
        local entries = self.menu:genItemTableFromPath(dir_path) -- sorted
        self.menu._dummy = false
        if not entries then return end

        for _, entry in ipairs(entries) do
            if entry.is_file or entry.file then
                local bookinfo = BookInfoManager:getBookInfo(entry.path, true)
                local widget = self:_getFolderCover(bookinfo)
                if widget then
                    if self._underline_container[1] then self._underline_container[1]:free(true) end
                    self._underline_container[1] = widget
                    self._foldercover_processed = true
                end
                break
            end
        end
    end

    function MosaicMenuItem:_getFolderCover(bookinfo)
        if
            bookinfo
            and bookinfo.cover_bb
            and bookinfo.has_cover
            and bookinfo.cover_fetched
            and not bookinfo.ignore_cover
            and not BookInfoManager.isCachedCoverInvalid(bookinfo, self.menu.cover_specs)
        then
            local border_size = Size.border.thick
            local alpha = 0.75
            book_thick = Screen:scaleBySize(2.5)
            book_margin = Size.line.medium
            local top_h = 2 * (book_thick + book_margin)

            local _, _, scale_factor = BookInfoManager.getCachedCoverSize(
                bookinfo.cover_w,
                bookinfo.cover_h,
                self.width - 2 * border_size,
                self.height - 2 * border_size - top_h
            )
            local image = ImageWidget:new { image = bookinfo.cover_bb, scale_factor = scale_factor }
            image:_render()
            local img_size = image:getSize()
            local dimen = { w = img_size.w + 2 * border_size, h = img_size.h + 2 * border_size }
            local directory, nbitems = self:_getTextBoxes { w = img_size.w, h = img_size.h }

            return VerticalGroup:new {
                LineWidget:new {
                    background = Blitbuffer.COLOR_GRAY_6,
                    dimen = { w = img_size.w * 0.95, h = book_thick },
                },
                VerticalSpan:new { width = book_margin },
                LineWidget:new {
                    background = Blitbuffer.COLOR_GRAY_6,
                    dimen = { w = img_size.w * 0.975, h = book_thick },
                },
                VerticalSpan:new { width = book_margin },
                OverlapGroup:new {
                    dimen = { w = self.width, h = self.height - top_h },
                    FrameContainer:new {
                        padding = 0,
                        bordersize = border_size,
                        image,
                        overlap_align = "center",
                    },
                    CenterContainer:new {
                        dimen = dimen,
                        getAlphaFrame(border_size, alpha, directory),
                        overlap_align = "center",
                    },
                    BottomContainer:new {
                        dimen = dimen,
                        getAlphaFrame(border_size, alpha, nbitems),
                        overlap_align = "center",
                    },
                },
            }
        end
    end

    function MosaicMenuItem:_getTextBoxes(dimen)
        local nbitems = TextBoxWidget:new {
            text = self.mandatory,
            face = Font:getFace("cfont", 17),
            width = dimen.w,
            alignment = "center",
        }

        local text = self.text
        if text:match("/$") then text = text:sub(1, -2) end -- remove "/"
        text = BD.directory(capitalize(text))
        local available_height = dimen.h - 2 * nbitems:getSize().h
        local dir_font_size = 25
        local directory

        while true do
            if directory then directory:free(true) end
            directory = TextBoxWidget:new {
                text = text,
                face = Font:getFace("cfont", dir_font_size),
                width = dimen.w,
                alignment = "center",
                bold = true,
            }
            if directory:getSize().h <= available_height then break end
            dir_font_size = dir_font_size - 1
            if dir_font_size < 10 then -- don't go too low
                directory:free()
                directory.height = available_height
                directory.height_adjust = true
                directory.height_overflow_show_ellipsis = true
                directory:init()
                break
            end
        end

        return directory, nbitems
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverBrowser)
