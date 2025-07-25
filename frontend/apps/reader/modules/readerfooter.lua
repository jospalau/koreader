local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Presets = require("ui/presets")
local ProgressWidget = require("ui/widget/progresswidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local SpinWidget = require("ui/widget/spinwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local datetime = require("datetime")
local logger = require("logger")
local util = require("util")
local T = require("ffi/util").template
local _ = require("gettext")
local C_ = _.pgettext
local Screen = Device.screen
local SQ3 = require("lua-ljsqlite3/init")
local util = require("util")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")


local MODE = {
    off = 0,
    page_progress = 1,
    pages_left_book = 2,
    time = 3,
    pages_left = 4,
    battery = 5,
    percentage = 6,
    book_time_to_read = 7,
    chapter_time_to_read = 8,
    frontlight = 9,
    mem_usage = 10,
    wifi_status = 11,
    book_title = 12,
    book_chapter = 13,
    bookmark_count = 14,
    chapter_progress = 15,
    frontlight_warmth = 16,
    custom_text = 17,
    book_author = 18,
    page_turning_inverted = 19, -- includes both page-turn-button and swipe-and-tap inversion
    dynamic_filler = 20,
}

local symbol_prefix = {
    letters = {
        time = nil,
        pages_left_book = "->",
        pages_left = "=>",
        -- @translators This is the footer letter prefix for battery % remaining.
        battery = C_("FooterLetterPrefix", "B:"),
        -- @translators This is the footer letter prefix for the number of bookmarks (bookmark count).
        bookmark_count = C_("FooterLetterPrefix", "BM:"),
        -- @translators This is the footer letter prefix for percentage read.
        percentage = C_("FooterLetterPrefix", "R:"),
        -- @translators This is the footer letter prefix for book time to read.
        book_time_to_read = C_("FooterLetterPrefix", "TB:"),
        -- @translators This is the footer letter prefix for chapter time to read.
        chapter_time_to_read = C_("FooterLetterPrefix", "TC:"),
        -- @translators This is the footer letter prefix for frontlight level.
        frontlight = C_("FooterLetterPrefix", "L:"),
        -- @translators This is the footer letter prefix for light warmth of the frontlight (redshift).
        frontlight_warmth = C_("FooterLetterPrefix", "LW:"),
        -- @translators This is the footer letter prefix for memory usage.
        mem_usage = C_("FooterLetterPrefix", "M:"),
        -- @translators This is the footer letter prefix for Wi-Fi status.
        wifi_status = C_("FooterLetterPrefix", "W:"),
        -- @translators This is the footer letter prefix for page turning status.
        page_turning_inverted = C_("FooterLetterPrefix", "Pg:"),
    },
    icons = {
        time = "⌚",
        pages_left_book = BD.mirroredUILayout() and "↢" or "↣",
        pages_left = BD.mirroredUILayout() and "⇐" or "⇒",
        battery = "",
        bookmark_count = "\u{F097}", -- "empty bookmark" from nerdfont
        percentage = BD.mirroredUILayout() and "⤟" or "⤠",
        book_time_to_read = "⏳",
        chapter_time_to_read = BD.mirroredUILayout() and "⥖" or "⤻",
        frontlight = "☼",
        frontlight_warmth = "💡",
        mem_usage = "",
        wifi_status = "",
        wifi_status_off = "",
        page_turning_inverted = "⇄",
        page_turning_regular = "⇉",
    },
    compact_items = {
        time = nil,
        pages_left_book = BD.mirroredUILayout() and "‹" or "›",
        pages_left = BD.mirroredUILayout() and "‹" or "›",
        battery = "",
        bookmark_count = "\u{F097}",
        percentage = nil,
        book_time_to_read = nil,
        chapter_time_to_read = BD.mirroredUILayout() and "«" or "»",
        frontlight = "✺",
        frontlight_warmth = "⊛",
        -- @translators This is the footer compact item prefix for memory usage.
        mem_usage = C_("FooterCompactItemsPrefix", "M"),
        wifi_status = "",
        wifi_status_off = "",
        page_turning_inverted = "⇄",
        page_turning_regular = "⇉",
    }
}
if BD.mirroredUILayout() then
    -- We need to RTL-wrap these letters and symbols for proper layout
    for k, v in pairs(symbol_prefix.letters) do
        local colon = v:find(":")
        local wrapped
        if colon then
            local pre = v:sub(1, colon-1)
            local post = v:sub(colon)
            wrapped = BD.wrap(pre) .. BD.wrap(post)
        else
            wrapped = BD.wrap(v)
        end
        symbol_prefix.letters[k] = wrapped
    end
    for k, v in pairs(symbol_prefix.icons) do
        symbol_prefix.icons[k] = BD.wrap(v)
    end
end

-- functions that generates footer text for each mode
local footerTextGeneratorMap
footerTextGeneratorMap = {
    empty = function() return "" end,
    frontlight = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].frontlight
        local powerd = Device:getPowerDevice()
        if powerd:isFrontlightOn() then
            if Device:isCervantes() or Device:isKobo() then
                return (prefix .. " %d%%"):format(powerd:frontlightIntensity())
            else
                return (prefix .. " %d"):format(powerd:frontlightIntensity())
            end
        else
            if footer.settings.all_at_once and footer.settings.hide_empty_generators then
                return ""
            else
                return T(_("%1 Off"), prefix)
            end
        end
    end,
    frontlight_warmth = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].frontlight_warmth
        local powerd = Device:getPowerDevice()
        if powerd:isFrontlightOn() then
            local warmth = powerd:frontlightWarmth()
            if warmth then
                return (prefix .. " %d%%"):format(warmth)
            end
        else
            if footer.settings.all_at_once and footer.settings.hide_empty_generators then
                return ""
            else
                return T(_("%1 Off"), prefix)
            end
        end
    end,
    battery = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].battery
        local powerd = Device:getPowerDevice()
        local batt_lvl = 0
        local is_charging = false

        if Device:hasBattery() then
            local main_batt_lvl = powerd:getCapacity()

            if Device:hasAuxBattery() and powerd:isAuxBatteryConnected() then
                local aux_batt_lvl = powerd:getAuxCapacity()
                is_charging = powerd:isAuxCharging()
                -- Sum both batteries for the actual text
                batt_lvl = main_batt_lvl + aux_batt_lvl
                -- But average 'em to compute the icon...
                if symbol_type == "icons" or symbol_type == "compact_items" then
                    prefix = powerd:getBatterySymbol(powerd:isAuxCharged(), is_charging, batt_lvl / 2)
                end
            else
                is_charging = powerd:isCharging()
                batt_lvl = main_batt_lvl
                if symbol_type == "icons" or symbol_type == "compact_items" then
                   prefix = powerd:getBatterySymbol(powerd:isCharged(), is_charging, main_batt_lvl)
                end
            end
        end

        if footer.settings.all_at_once and batt_lvl > footer.settings.battery_hide_threshold then
            return ""
        end

        -- If we're using icons, use the fancy variable icon from powerd:getBatterySymbol
        if symbol_type == "icons" or symbol_type == "compact_items" then
            if symbol_type == "compact_items" then
                return BD.wrap(prefix)
            else
                return BD.wrap(prefix) .. batt_lvl .. "%"
            end
        else
            return BD.wrap(prefix) .. " " .. (is_charging and "+" or "") .. batt_lvl .. "%"
        end
    end,
    bookmark_count = function(footer)
        local bookmark_count = footer.ui.annotation:getNumberOfAnnotations()
        if footer.settings.all_at_once and footer.settings.hide_empty_generators and bookmark_count == 0 then
            return ""
        end
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].bookmark_count
        return prefix .. " " .. tostring(bookmark_count)
    end,
    time = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].time
        local clock = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
        if not prefix then
            return clock
        else
            return prefix .. " " .. clock
        end
    end,
    page_progress = function(footer)
        if footer.pageno then
            if footer.ui.pagemap and footer.ui.pagemap:wantsPageLabels() then
                -- (Page labels might not be numbers)
                return ("%s de %s"):format(footer.ui.pagemap:getCurrentPageLabel(true),
                                          footer.ui.pagemap:getLastPageLabel(true))
            end
            if footer.ui.document:hasHiddenFlows() then
                -- i.e., if we are hiding non-linear fragments and there's anything to hide,
                local flow = footer.ui.document:getPageFlow(footer.pageno)
                local page = footer.ui.document:getPageNumberInFlow(footer.pageno)
                local pages = footer.ui.document:getTotalPagesInFlow(flow)
                if flow == 0 then
                    return ("%d // %d"):format(page, pages)
                else
                    return ("[%d / %d]%d"):format(page, pages, flow)
                end
            else
                return ("%d de %d"):format(footer.pageno, footer.pages)
            end
        elseif footer.position then
            return ("%d / %d"):format(footer.position, footer.doc_height)
        end
    end,
    pages_left_book = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].pages_left_book
        if footer.pageno then
            if footer.ui.pagemap and footer.ui.pagemap:wantsPageLabels() then
                -- (Page labels might not be numbers)
                local label, idx, count = footer.ui.pagemap:getCurrentPageLabel(false) -- luacheck: no unused
                local remaining = count - idx
                if footer.settings.pages_left_includes_current_page then
                    remaining = remaining + 1
                end
                return ("%s %s / %s"):format(prefix, remaining, footer.ui.pagemap:getLastPageLabel(true))
            end
            if footer.ui.document:hasHiddenFlows() then
                -- i.e., if we are hiding non-linear fragments and there's anything to hide,
                local flow = footer.ui.document:getPageFlow(footer.pageno)
                local page = footer.ui.document:getPageNumberInFlow(footer.pageno)
                local pages = footer.ui.document:getTotalPagesInFlow(flow)
                local remaining = pages - page
                if footer.settings.pages_left_includes_current_page then
                    remaining = remaining + 1
                end
                if flow == 0 then
                    return ("%s %d // %d"):format(prefix, remaining, pages)
                else
                    return ("%s [%d / %d]%d"):format(prefix, remaining, pages, flow)
                end
            else
                local remaining = footer.pages - footer.pageno
                if footer.settings.pages_left_includes_current_page then
                    remaining = remaining + 1
                end
                return ("%s %d / %d"):format(prefix, remaining, footer.pages)
            end
        elseif footer.position then
            return ("%s %d / %d"):format(prefix, footer.doc_height - footer.position, footer.doc_height)
        end
    end,
    pages_left = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].pages_left
        local left = footer.ui.toc:getChapterPagesLeft(footer.pageno) or footer.ui.document:getTotalPagesLeft(footer.pageno)
        if footer.settings.pages_left_includes_current_page then
            left = left + 1
        end
        return prefix .. " " .. ("%d"):format(left)
    end,
    chapter_progress = function(footer)
        return footer:getChapterProgress()
    end,
    percentage = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].percentage
        local digits = footer.settings.progress_pct_format
        local string_percentage = "%." .. digits .. "f%%"
        if footer.ui.document:hasHiddenFlows() then
            local flow = footer.ui.document:getPageFlow(footer.pageno)
            if flow ~= 0 then
                string_percentage = "[" .. string_percentage .. "]"
            end
        end
        if prefix then
            string_percentage = prefix .. " " .. string_percentage
        end
        return string_percentage:format(footer:getBookProgress() * 100)
    end,
    book_time_to_read = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].book_time_to_read
        local left = footer.ui.document:getTotalPagesLeft(footer.pageno)
        return footer:getDataFromStatistics(prefix and (prefix .. " ") or "", left)
    end,
    chapter_time_to_read = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].chapter_time_to_read
        local left = footer.ui.toc:getChapterPagesLeft(footer.pageno) or footer.ui.document:getTotalPagesLeft(footer.pageno)
        return footer:getDataFromStatistics(prefix .. " ", left)
    end,
    mem_usage = function(footer)
        local statm = io.open("/proc/self/statm", "r")
        if statm then
            local symbol_type = footer.settings.item_prefix
            local prefix = symbol_prefix[symbol_type].mem_usage
            local dummy, rss = statm:read("*number", "*number")
            statm:close()
            -- we got the nb of 4Kb-pages used, that we convert to MiB
            rss = math.floor(rss * (4096 / 1024 / 1024))
            return (prefix .. " %d"):format(rss)
        end
        return ""
    end,
    wifi_status = function(footer)
        -- NOTE: This one deviates a bit from the mold because, in icons mode, we simply use two different icons and no text.
        local symbol_type = footer.settings.item_prefix
        local NetworkMgr = require("ui/network/manager")
        if symbol_type == "icons" or symbol_type == "compact_items" then
            if NetworkMgr:isWifiOn() then
                return symbol_prefix.icons.wifi_status
            else
                if footer.settings.all_at_once and footer.settings.hide_empty_generators then
                    return ""
                else
                    return symbol_prefix.icons.wifi_status_off
                end
            end
        else
            local prefix = symbol_prefix[symbol_type].wifi_status
            if NetworkMgr:isWifiOn() then
                return T(_("%1 On"), prefix)
            else
                if footer.settings.all_at_once and footer.settings.hide_empty_generators then
                    return ""
                else
                    return T(_("%1 Off"), prefix)
                end
            end
        end
    end,
    page_turning_inverted = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].page_turning_inverted
        if G_reader_settings:isTrue("input_invert_page_turn_keys") or G_reader_settings:isTrue("input_invert_left_page_turn_keys") or
           G_reader_settings:isTrue("input_invert_right_page_turn_keys") or footer.view.inverse_reading_order then -- inverse_reading_order is set on a per_book basis and/or global one.
            if symbol_type == "icons" or symbol_type == "compact_items" then
                return symbol_prefix.icons.page_turning_inverted
            else
                return T(_("%1 On"), prefix)
            end
        elseif footer.settings.all_at_once and footer.settings.hide_empty_generators then
            return ""
        else
            if symbol_type == "icons" or symbol_type == "compact_items" then
                return symbol_prefix.icons.page_turning_regular
            else
                return T(_("%1 Off"), prefix)
            end
        end
    end,
    book_author = function(footer)
        local text = footer.ui.doc_props.authors
        return footer:getFittedText(text, footer.settings.book_author_max_width_pct)
    end,
    book_title = function(footer)
        local text = footer.ui.doc_props.display_title
        return footer:getFittedText(text, footer.settings.book_title_max_width_pct)
    end,
    book_chapter = function(footer)
        local text = footer.ui.toc:getTocTitleByPage(footer.pageno)
        return footer:getFittedText(text, footer.settings.book_chapter_max_width_pct)
    end,
    custom_text = function(footer)
        -- if custom_text contains only spaces, request to merge it with the text before and after,
        -- in other words, don't add a separator then.
        local merge = footer.custom_text:gsub(" ", ""):len() == 0
        return footer.custom_text:rep(footer.custom_text_repetitions), merge
    end,
    dynamic_filler = function(footer)
        local margin = footer.horizontal_margin
        if not footer.settings.disable_progress_bar then
            if footer.settings.progress_bar_position == "alongside" then
                return
            end
            if footer.settings.align == "center" then
                margin = Screen:scaleBySize(footer.settings.progress_margin_width)
            end
        end
        local max_width = math.floor(footer._saved_screen_width - 2 * margin)
        -- when the filler is between other items, it replaces the separator
        local text, is_filler_inside = footer:genAllFooterText(footerTextGeneratorMap.dynamic_filler)
        local tmp = TextWidget:new{
            text = text,
            face = footer.footer_text_face,
            bold = footer.settings.text_font_bold,
        }
        local text_width = tmp:getSize().w
        tmp:free()
        if footer.separator_width == nil then
            tmp = TextWidget:new{
                text = footer:genSeparator(),
                face = footer.footer_text_face,
                bold = footer.settings.text_font_bold,
            }
            footer.separator_width = tmp:getSize().w
            tmp:free()
        end
        local separator_width = is_filler_inside and footer.separator_width or 0
        local filler_space = " "
        if footer.filler_space_width == nil then
            tmp = TextWidget:new{
                text = filler_space,
                face = footer.footer_text_face,
                bold = footer.settings.text_font_bold,
            }
            footer.filler_space_width = tmp:getSize().w
            tmp:free()
        end
        local filler_nb = math.floor((max_width - text_width + separator_width) / footer.filler_space_width)
        if filler_nb > 0 then
            return filler_space:rep(filler_nb), true
        end
    end,
}

local ReaderFooter = WidgetContainer:extend{
    mode = MODE.page_progress,
    pageno = nil,
    pages = nil,
    footer_text = nil,
    text_font_face = "myfont3",
    height = Screen:scaleBySize(G_defaults:readSetting("DMINIBAR_CONTAINER_HEIGHT")),
    horizontal_margin = Size.span.horizontal_default,
    bottom_padding = Size.padding.tiny,
    settings = nil, -- table
    -- added to expose them to unit tests
    textGeneratorMap = footerTextGeneratorMap,
}

-- NOTE: This is used in a migration script by ui/data/onetime_migration,
--       which is why it's public.
ReaderFooter.default_settings = {
    disable_progress_bar = false, -- enable progress bar by default
    chapter_progress_bar = false, -- the whole book
    disabled = false,
    all_at_once = false,
    reclaim_height = false,
    toc_markers = true,
    page_progress = true,
    pages_left_book = false,
    time = true,
    pages_left = true,
    battery = Device:hasBattery(),
    battery_hide_threshold = Device:hasAuxBattery() and 200 or 100,
    percentage = true,
    book_time_to_read = true,
    chapter_time_to_read = true,
    frontlight = false,
    mem_usage = false,
    wifi_status = false,
    page_turning_inverted = false,
    book_author = false,
    book_title = false,
    book_chapter = false,
    bookmark_count = false,
    chapter_progress = false,
    item_prefix = "icons",
    toc_markers_width = 2, -- unscaled_size_check: ignore
    text_font_size = 14, -- unscaled_size_check: ignore
    text_font_bold = false,
    container_height = G_defaults:readSetting("DMINIBAR_CONTAINER_HEIGHT"),
    container_bottom_padding = 1, -- unscaled_size_check: ignore
    progress_margin_width = Device:isAndroid() and Screen:scaleByDPI(16) or 10, -- android: guidelines for rounded corner margins
    progress_margin = false, -- true if progress bar margins same as book margins
    progress_bar_min_width_pct = 20,
    book_author_max_width_pct = 30,
    book_title_max_width_pct = 30,
    book_chapter_max_width_pct = 30,
    skim_widget_on_hold = false,
    progress_style_thin = false,
    progress_bar_position = "alongside",
    bottom_horizontal_separator = false,
    align = "center",
    auto_refresh_time = false,
    progress_style_thin_height = 3, -- unscaled_size_check: ignore
    progress_style_thick_height = 7, -- unscaled_size_check: ignore
    hide_empty_generators = false,
    lock_tap = false,
    items_separator = "bar",
    progress_pct_format = "0",
    pages_left_includes_current_page = false,
    initial_marker = false,
}

function ReaderFooter:init()
    self.settings = G_reader_settings:readSetting("footer", self.default_settings)

    self.additional_footer_content = {} -- array, where additional header content can be inserted.

    -- Remove items not supported by the current device
    if not Device:hasFastWifiStatusQuery() then
        MODE.wifi_status = nil
    end
    if not Device:hasFrontlight() then
        MODE.frontlight = nil
    end
    if not Device:hasBattery() then
        MODE.battery = nil
    end
    if not Device:hasNaturalLight() then
        MODE.frontlight_warmth = nil
    end

    -- self.mode_index will be an array of MODE names, with an additional element
    -- with key 0 for "off", which feels a bit strange but seems to work...
    -- (The same is true for self.settings.order which is saved in settings.)
    self.mode_index = {}
    self.mode_nb = 0

    local handled_modes = {}
    if self.settings.order then
        -- Start filling self.mode_index from what's been ordered by the user and saved
        for i=0, #self.settings.order do
            local name = self.settings.order[i]
            -- (if name has been removed from our supported MODEs: ignore it)
            if MODE[name] then -- this mode still exists
                self.mode_index[self.mode_nb] = name
                self.mode_nb = self.mode_nb + 1
                handled_modes[name] = true
            end
        end
        -- go on completing it with remaining new modes in MODE
    end
    -- If no previous self.settings.order, fill mode_index with what's in MODE
    -- in the original indices order
    local orig_indexes = {}
    local orig_indexes_to_name = {}
    for name, orig_index in pairs(MODE) do
        if not handled_modes[name] then
            table.insert(orig_indexes, orig_index)
            orig_indexes_to_name[orig_index] = name
        end
    end
    table.sort(orig_indexes)
    for i = 1, #orig_indexes do
        self.mode_index[self.mode_nb] = orig_indexes_to_name[orig_indexes[i]]
        self.mode_nb = self.mode_nb + 1
    end
    -- require("logger").dbg(self.mode_nb, self.mode_index)

    -- Container settings
    self.height = Screen:scaleBySize(self.settings.container_height)
    self.bottom_padding = Screen:scaleBySize(self.settings.container_bottom_padding)

    self.mode_list = {}
    for i = 0, #self.mode_index do
        self.mode_list[self.mode_index[i]] = i
    end
    if self.settings.disabled then
        -- footer feature is completely disabled, stop initialization now
        self:disableFooter()
        return
    end

    self.pageno = self.view.state.page
    self.has_no_mode = true
    self.reclaim_height = self.settings.reclaim_height
    for _, m in ipairs(self.mode_index) do
        if self.settings[m] then
            self.has_no_mode = false
            break
        end
    end

    self.footer_text_face = Font:getFace(self.settings.text_font_face and self.settings.text_font_face or self.text_font_face, self.settings.text_font_size)
    self.footer_text = TextWidget:new{
        text = "",
        face = self.footer_text_face,
        bold = self.settings.text_font_bold,
    }
    -- all width related values will be initialized in self:resetLayout()
    self.text_width = 0
    self.footer_text.height = 0
    self.progress_bar = ProgressWidget:new{
        width = nil,
        height = nil,
        percentage = nil,
        tick_width = Screen:scaleBySize(self.settings.toc_markers_width),
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
        initial_pos_marker = self.settings.initial_marker,
    }

    if self.settings.progress_style_thin then
        self.progress_bar:updateStyle(false, nil)
    end

    self.text_container = RightContainer:new{
        dimen = Geom:new{ w = 0, h = self.height },
        self.footer_text,
        --debug = true,
        --thin = true,
    }

    if self.settings.bar_top then
        self.old_bottom_padding = self.bottom_padding
        self.bottom_padding = 0
    end
    self:updateFooterContainer()
    self.mode = G_reader_settings:readSetting("reader_footer_mode") or self.mode
    if self.has_no_mode and self.settings.disable_progress_bar then
        self.mode = self.mode_list.off
        self.view.footer_visible = false
        self:resetLayout()
        self.footer_text.height = 0
    end
    if self.settings.all_at_once then
        self.view.footer_visible = (self.mode ~= self.mode_list.off)
        self:updateFooterTextGenerator()
        if self.settings.progress_bar_position ~= "alongside" and self.has_no_mode then
            self.footer_text.height = 0
        end
    else
        self:applyFooterMode()
    end

    self.visibility_change = nil

    self.custom_text = G_reader_settings:readSetting("reader_footer_custom_text", "KOReader")
    self.custom_text_repetitions =
        tonumber(G_reader_settings:readSetting("reader_footer_custom_text_repetitions", "1"))

    self.preset_obj = {
        presets = G_reader_settings:readSetting("footer_presets", {}),
        dispatcher_name = "load_footer_preset",
        buildPreset = function() return self:buildPreset() end,
        loadPreset = function(preset) self:loadPreset(preset) end,
    }
    self.progress_bar.zero = (self.settings.progress_style_thin and self.settings.progress_style_thin_height == 0) and true or false
end

function ReaderFooter:set_custom_text(touchmenu_instance)
    local text_dialog
    text_dialog = MultiInputDialog:new{
        title = _("Enter a custom text"),
        fields = {
            {
                text = self.custom_text or "",
                description = _("Custom string:"),
            },
            {
                text = self.custom_text_repetitions,
                description =_("Number of repetitions:"),
                input_type = "number",
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(text_dialog)
                    end,
                },
                {
                    text = _("Set"),
                    callback = function()
                        local inputs = text_dialog:getFields()
                        local new_text, new_repetitions = inputs[1], inputs[2]
                        if new_text == "" then
                            new_text = " "
                        end
                        if self.custom_text ~= new_text then
                            self.custom_text = new_text
                            G_reader_settings:saveSetting("reader_footer_custom_text",
                                self.custom_text)
                        end
                        new_repetitions = tonumber(new_repetitions) or 1
                        if new_repetitions < 1 then
                            new_repetitions = 1
                        end
                        if new_repetitions and self.custom_text_repetitions ~= new_repetitions then
                            self.custom_text_repetitions = new_repetitions
                            G_reader_settings:saveSetting("reader_footer_custom_text_repetitions",
                                self.custom_text_repetitions)
                        end
                        UIManager:close(text_dialog)
                        self:refreshFooter(true, true)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                },
            },
        },
    }
    UIManager:show(text_dialog)
    text_dialog:onShowKeyboard()
end

-- Help text string, or function, to be shown, or executed, on a long press on menu item
local option_help_text = {
    pages_left_book = _("Can be configured to include or exclude the current page."),
    percentage      = _("Progress percentage can be shown with zero, one or two decimal places."),
    mem_usage       = _("Show memory usage in MiB."),
    reclaim_height  = _("When the status bar is hidden, this setting will utilize the entirety of screen real estate (for your book) and will temporarily overlap the text when the status bar is shown."),
    custom_text     = ReaderFooter.set_custom_text,
}

function ReaderFooter:updateFooterContainer()
    local margin_span = HorizontalSpan:new{ width = self.horizontal_margin }
    self.vertical_frame = VerticalGroup:new{}
    if self.settings.bottom_horizontal_separator then
        self.separator_line = LineWidget:new{
            dimen = Geom:new{
                w = 0,
                h = Size.line.medium,
            }
        }
        local vertical_span = VerticalSpan:new{width = Size.span.vertical_default}
        table.insert(self.vertical_frame, self.separator_line)
        table.insert(self.vertical_frame, vertical_span)
    end
    if self.settings.progress_bar_position ~= "alongside" and not self.settings.disable_progress_bar then
        self.horizontal_group = HorizontalGroup:new{
            margin_span,
            self.text_container,
            margin_span,
        }
    else
        self.horizontal_group = HorizontalGroup:new{
            margin_span,
            self.progress_bar,
            self.text_container,
            margin_span,
        }
    end

    if self.settings.align == "left" then
        self.footer_container = LeftContainer:new{
            dimen = Geom:new{ w = 0, h = self.height },
            self.horizontal_group
        }
    elseif self.settings.align == "right" then
        self.footer_container = RightContainer:new{
            dimen = Geom:new{ w = 0, h = self.height },
            self.horizontal_group,
            --debug = true,
        }
    else
        self.footer_container = CenterContainer:new{
            dimen = Geom:new{ w = 0, h = self.height },
            self.horizontal_group
        }
    end
    self.progress_bar.zero = (self.settings.progress_style_thin and self.settings.progress_style_thin_height == 0) and true or false
    local vertical_span = VerticalSpan:new{width = Size.span.vertical_default}

    if self.settings.progress_bar_position == "above" and not self.settings.disable_progress_bar then
        if self.progress_bar.zero then
            table.insert(self.vertical_frame, self.progress_bar)
            table.insert(self.vertical_frame, self.footer_container)
        else
            table.insert(self.vertical_frame, self.progress_bar)
            table.insert(self.vertical_frame, vertical_span)
            table.insert(self.vertical_frame, self.footer_container)
        end
    elseif self.settings.progress_bar_position == "below" and not self.settings.disable_progress_bar then
        if self.progress_bar.zero then
            table.insert(self.vertical_frame, self.footer_container)
            table.insert(self.vertical_frame, self.progress_bar)
        else
            table.insert(self.vertical_frame, self.footer_container)
            table.insert(self.vertical_frame, vertical_span)
            table.insert(self.vertical_frame, self.progress_bar)
        end
    else
        table.insert(self.vertical_frame, self.footer_container)
    end
    -- If we don't use background, it will be transparent
    -- Bear in mind autorefresh won't refresh properly
    -- The self.autoRefreshFooter() function will need a second parameter true:
    -- self:onUpdateFooter(self:shouldBeRepainted(), true)

    -- In any case, the function updateFooterPage() will call always to self:updateFooterText(force_repaint, true) passing true as second parameter
    -- And autorefresh works without problem with a transparent status bar
    self.footer_content = FrameContainer:new{
        self.vertical_frame,
        -- background = Blitbuffer.COLOR_WHITE, -- Make the status bar transparent
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }

    self.footer_positioner = BottomContainer:new{
        dimen = Geom:new(),
        self.footer_content,
    }
    self[1] = self.footer_positioner
end

function ReaderFooter:unscheduleFooterAutoRefresh()
    if not self.autoRefreshFooter then return end -- not yet set up
    -- Slightly different wording than in rescheduleFooterAutoRefreshIfNeeded because it might not actually be scheduled at all
    logger.dbg("ReaderFooter: unschedule autoRefreshFooter")
    UIManager:unschedule(self.autoRefreshFooter)
end

function ReaderFooter:shouldBeRepainted()
    -- Since self.autoRefreshFooter() repaints also the topbar
    -- Repaint also when topbar is active even if footer is not visible
    if not self.view.footer_visible and not self.view.topbar.settings:isTrue("show_top_bar") then
        return false
    end

    local top_wg = UIManager:getTopmostVisibleWidget() or {}
    -- logger.info("ReaderFooter:shouldBeRepainted, top_wg name:", top_wg.name, "src:", debug.getinfo(top_wg.init or top_wg._init or top_wg.free or top_wg.new or top_wg.paintTo or function() end, "S").short_src,  "fs:", top_wg.covers_fullscreen, "ft:", top_wg.covers_footer)
    if top_wg.name == "ReaderUI" then
        -- No overlap possible, it's safe to request a targeted widget repaint
        return true
    elseif top_wg.covers_fullscreen or top_wg.covers_footer then
        -- No repaint necessary at all
        return false
    end

    -- The topmost visible widget might overlap with us, but dimen isn't reliable enough to do a proper bounds check
    -- (as stuff often just sets it to the Screen dimensions),
    -- so request a full ReaderUI repaint to avoid out-of-order repaints.
    return true, true
end

function ReaderFooter:rescheduleFooterAutoRefreshIfNeeded()
    if not self.autoRefreshFooter then
        -- Create this function the first time we're called
        self.autoRefreshFooter = function()
            -- Only actually repaint the footer if nothing's being shown over ReaderUI (#6616)
            -- (We want to avoid the footer to be painted over a widget covering it - we would
            -- be fine refreshing it if the widget is not covering it, but this is hard to
            -- guess from here.)
            local top_wg = UIManager:getTopmostVisibleWidget() or {}
            -- logger.info("ReaderFooter:shouldBeRepainted, top_wg name:", top_wg.name, "src:", debug.getinfo(top_wg.init or top_wg._init or top_wg.free or top_wg.new or top_wg.paintTo or function() end, "S").short_src,  "fs:", top_wg.covers_fullscreen, "ft:", top_wg.covers_footer)
            if top_wg.name == "ReaderUI" then
                if self.ui.statistics and self.ui.view.topbar and self.ui.view.topbar.settings:isTrue("show_top_bar") then
                    if self.ui.statistics:checkNewDay() then
                        self.ui.view.topbar:resetSession()
                    end
                    self.ui.view.topbar:toggleBar()
                end
                --self:onUpdateFooter(self:shouldBeRepainted())
                if self:shouldBeRepainted() then
                    self:refresh()
                end
            end
            self:rescheduleFooterAutoRefreshIfNeeded() -- schedule (or not) next refresh
        end
    end
    local unscheduled = UIManager:unschedule(self.autoRefreshFooter) -- unschedule if already scheduled
    -- Only schedule an update if the footer has items that may change
    -- As self.view.footer_visible may be temporarily toggled off by other modules,
    -- we can't trust it for not scheduling auto refresh
    local schedule = false
    if self.settings.auto_refresh_time then
        if self.settings.all_at_once then
            --if self.settings.time or self.settings.battery or self.settings.wifi_status or self.settings.mem_usage then
            schedule = true
            --end
        else
            --if self.mode == self.mode_list.time or self.mode == self.mode_list.battery
            --        or self.mode == self.mode_list.wifi_status or self.mode == self.mode_list.mem_usage then
            schedule = true
            --end
        end
    end
    if schedule then
        UIManager:scheduleIn(61 - tonumber(os.date("%S")), self.autoRefreshFooter)
        if not unscheduled then
            logger.dbg("ReaderFooter: scheduled autoRefreshFooter")
        else
            logger.dbg("ReaderFooter: rescheduled autoRefreshFooter")
        end
    elseif unscheduled then
        logger.dbg("ReaderFooter: unscheduled autoRefreshFooter")
    end
end

function ReaderFooter:setupTouchZones()
    if not Device:isTouchDevice() then return end
    local DTAP_ZONE_MINIBAR = G_defaults:readSetting("DTAP_ZONE_MINIBAR")
    local footer_screen_zone = {
        ratio_x = DTAP_ZONE_MINIBAR.x, ratio_y = DTAP_ZONE_MINIBAR.y,
        ratio_w = DTAP_ZONE_MINIBAR.w, ratio_h = DTAP_ZONE_MINIBAR.h,
    }
    self.ui:registerTouchZones({
        {
            id = "readerfooter_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = 0, ratio_y = 24/25, ratio_w = 1, ratio_h =25,
            },
            handler = function(ges) return self:TapFooter(ges) end,
            overrides = {
                "readerconfigmenu_ext_tap",
                "readerconfigmenu_tap",
                "tap_forward",
                "tap_backward",
            },
            -- (Low priority: tap on existing highlights
            -- or links have priority)
        },
        {
            id = "readerfooter_double_tap",
            ges = "double_tap",
            screen_zone = {
                ratio_x = 0, ratio_y = 24/25, ratio_w = 1, ratio_h =25,
            },
            handler = function(ges) return self:DoubleTapFooter(ges) end,
            overrides = {
                "pagetextinfo_double_tap",
            },
        },
        {
            id = "readerfooter_hold",
            ges = "hold",
            screen_zone = footer_screen_zone,
            handler = function(ges) return self:onHoldFooter(ges) end,
            overrides = {
                "readerhighlight_hold",
            },
            -- (High priority: it's a fallthrough if we held outside the footer)
        },
    })
end

-- call this method whenever the screen size changes
function ReaderFooter:resetLayout(force_reset)
    local new_screen_width = Screen:getWidth()
    local new_screen_height = Screen:getHeight()
    if new_screen_width == self._saved_screen_width
        and new_screen_height == self._saved_screen_height and not force_reset then return end

    if self.settings.disable_progress_bar then
        self.progress_bar.width = 0
    elseif self.settings.progress_bar_position ~= "alongside" then
        self.progress_bar.width = math.floor(new_screen_width -
            2 * Screen:scaleBySize(self.settings.progress_margin_width))
    else
        self.progress_bar.width = math.floor(new_screen_width -
            2 * Screen:scaleBySize(self.settings.progress_margin_width) - self.text_width)
    end
    if self.separator_line then
        self.separator_line.dimen.w = new_screen_width - 2 * self.horizontal_margin
    end
    if self.settings.disable_progress_bar then
        self.progress_bar.height = 0
    else
        local bar_height
        if self.settings.progress_style_thin then
            bar_height = self.settings.progress_style_thin_height
        else
            bar_height = self.settings.progress_style_thick_height
        end
        self.progress_bar:setHeight(bar_height)
    end

    self.horizontal_group:resetLayout()
    self.footer_positioner.dimen.w = new_screen_width
    self.footer_positioner.dimen.h = new_screen_height
    self.footer_container.dimen.w = new_screen_width
    self.dimen = self.footer_positioner:getSize()

    self._saved_screen_width = new_screen_width
    self._saved_screen_height = new_screen_height
end

function ReaderFooter:getHeight()
    if self.footer_content then
        -- NOTE: self.footer_content is self.vertical_frame + self.bottom_padding,
        --       self.vertical_frame includes self.text_container (which includes self.footer_text)
        return self.footer_content:getSize().h
    else
        return 0
    end
end

function ReaderFooter:disableFooter()
    self.onReaderReady = function() end
    self.resetLayout = function() end
    self.updateFooterPage = function() end
    self.updateFooterPos = function() end
    self.mode = self.mode_list.off
    self.view.footer_visible = false
end

function ReaderFooter:updateFooterTextGenerator()
    local footerTextGenerators = {}
    for i, m in pairs(self.mode_index) do
        if self.settings[m] then
            table.insert(footerTextGenerators,
                         footerTextGeneratorMap[m])
            if not self.settings.all_at_once then
                -- if not show all at once, then one is enough
                self.mode = i
                break
            end
        end
    end
    if #footerTextGenerators == 0 then
        -- all modes are disabled
        self.genFooterText = footerTextGeneratorMap.empty
    elseif #footerTextGenerators == 1 then
        -- there is only one mode enabled, simplify the generator
        -- function to that one
        self.genFooterText = footerTextGenerators[1]
    else
        self.genFooterText = self.genAllFooterText
    end

    -- Even if there's no or a single mode enabled, all_at_once requires this to be set
     self.footerTextGenerators = footerTextGenerators

    -- notify caller that UI needs update
    return true
end

function ReaderFooter:textOptionTitles(option)
    local symbol = self.settings.item_prefix
    local option_titles = {
        all_at_once = _("Show all selected items at once"),
        reclaim_height = _("Overlap status bar"),
        bookmark_count = T(_("Bookmark count (%1)"), symbol_prefix[symbol].bookmark_count),
        page_progress = T(_("Current page (%1)"), "/"),
        pages_left_book = T(_("Pages left in book (%1)"), symbol_prefix[symbol].pages_left_book),
        time = symbol_prefix[symbol].time
            and T(_("Current time (%1)"), symbol_prefix[symbol].time) or _("Current time"),
        chapter_progress = T(_("Current page in chapter (%1)"), " ⁄⁄ "),
        pages_left = T(_("Pages left in chapter (%1)"), symbol_prefix[symbol].pages_left),
        battery = T(_("Battery percentage (%1)"), symbol_prefix[symbol].battery),
        percentage = symbol_prefix[symbol].percentage
            and T(_("Progress percentage (%1)"), symbol_prefix[symbol].percentage) or _("Progress percentage"),
        book_time_to_read = symbol_prefix[symbol].book_time_to_read
            and T(_("Time left to finish book (%1)"),symbol_prefix[symbol].book_time_to_read) or _("Time left to finish book"),
        chapter_time_to_read = T(_("Time left to finish chapter (%1)"), symbol_prefix[symbol].chapter_time_to_read),
        frontlight = T(_("Brightness level (%1)"), symbol_prefix[symbol].frontlight),
        frontlight_warmth = T(_("Warmth level (%1)"), symbol_prefix[symbol].frontlight_warmth),
        mem_usage = T(_("KOReader memory usage (%1)"), symbol_prefix[symbol].mem_usage),
        wifi_status = T(_("Wi-Fi status (%1)"), symbol_prefix[symbol].wifi_status),
        page_turning_inverted = T(_("Page turning inverted (%1)"), symbol_prefix[symbol].page_turning_inverted),
        book_author = _("Book author"),
        book_title = _("Book title"),
        book_chapter = _("Chapter title"),
        custom_text = T(_("Custom text (long-press to edit): \'%1\'%2"), self.custom_text,
            self.custom_text_repetitions > 1 and
            string.format(" × %d", self.custom_text_repetitions) or ""),
        dynamic_filler = _("Dynamic filler"),
    }
    return option_titles[option]
end

function ReaderFooter:addToMainMenu(menu_items)
    local sub_items = {}
    menu_items.status_bar = {
        text = _("Status bar"),
            enabled_func = function()
                return self.ui.view.topbar.status_bar
            end,
        sub_item_table = sub_items,
    }

    -- If using crengine, add Alt status bar items at top
    if self.ui.crelistener then
        table.insert(sub_items, self.ui.crelistener:getAltStatusBarMenu())
    end

    -- menu item to fake footer tapping when touch area is disabled
    local DTAP_ZONE_MINIBAR = G_defaults:readSetting("DTAP_ZONE_MINIBAR")
    if DTAP_ZONE_MINIBAR.h == 0 or DTAP_ZONE_MINIBAR.w == 0 then
        table.insert(sub_items, {
            text = _("Toggle mode"),
            enabled_func = function()
                return not self.view.flipping_visible
            end,
            callback = function() self:onToggleFooterMode() end,
        })
    end

    local getMinibarOption = function(option, callback)
        return {
            text_func = function()
                return self:textOptionTitles(option)
            end,
            help_text = type(option_help_text[option]) == "string"
                and option_help_text[option],
            help_text_func = type(option_help_text[option]) == "function" and
                function(touchmenu_instance)
                    option_help_text[option](self, touchmenu_instance)
                end,
            checked_func = function()
                return self.settings[option] == true
            end,
            callback = function()
                self.settings[option] = not self.settings[option]
                -- We only need to send a SetPageBottomMargin event when we truly affect the margin
                local should_signal = false
                -- only case that we don't need a UI update is enable/disable
                -- non-current mode when all_at_once is disabled.
                local should_update = false
                local first_enabled_mode_num
                local prev_has_no_mode = self.has_no_mode
                local prev_reclaim_height = self.reclaim_height
                self.has_no_mode = true
                for mode_num, m in pairs(self.mode_index) do
                    if self.settings[m] then
                        first_enabled_mode_num = mode_num
                        self.has_no_mode = false
                        break
                    end
                end
                self.reclaim_height = self.settings.reclaim_height
                -- refresh margins position
                if self.has_no_mode then
                    self.footer_text.height = 0
                    should_signal = true
                    self.genFooterText = footerTextGeneratorMap.empty
                    self.mode = self.mode_list.off
                elseif prev_has_no_mode then
                    if self.settings.all_at_once then
                        self.mode = self.mode_list.page_progress
                        self:applyFooterMode()
                        G_reader_settings:saveSetting("reader_footer_mode", self.mode)
                    else
                        G_reader_settings:saveSetting("reader_footer_mode", first_enabled_mode_num)
                    end
                    should_signal = true
                elseif self.reclaim_height ~= prev_reclaim_height then
                    should_signal = true
                    should_update = true
                end
                if callback then
                    should_update = callback(self)
                elseif self.settings.all_at_once then
                    should_update = self:updateFooterTextGenerator()
                elseif (self.mode_list[option] == self.mode and self.settings[option] == false)
                        or (prev_has_no_mode ~= self.has_no_mode) then
                    -- current mode got disabled, redraw footer with other
                    -- enabled modes. if all modes are disabled, then only show
                    -- progress bar
                    if not self.has_no_mode then
                        self.mode = first_enabled_mode_num
                    else
                        -- If we've just disabled our last mode, first_enabled_mode_num is nil
                        -- If the progress bar is enabled,
                        -- fake an innocuous mode so that we switch to showing the progress bar alone, instead of nothing,
                        -- This is exactly what the "Show progress bar" toggle does.
                        self.mode = self.settings.disable_progress_bar and self.mode_list.off or self.mode_list.page_progress
                    end
                    should_update = true
                    self:applyFooterMode()
                    G_reader_settings:saveSetting("reader_footer_mode", self.mode)
                end
                if should_update or should_signal then
                    self:refreshFooter(should_update, should_signal)
                end
                -- The absence or presence of some items may change whether auto-refresh should be ensured
                self:rescheduleFooterAutoRefreshIfNeeded()
            end,
        }
    end

    table.insert(sub_items, {
        text = _("Progress bar"),
        separator = true,
        sub_item_table = {
            {
                text = _("Show progress bar"),
                checked_func = function()
                    return not self.settings.disable_progress_bar
                end,
                callback = function()
                    self.settings.disable_progress_bar = not self.settings.disable_progress_bar
                    if not self.settings.disable_progress_bar then
                        self:setTocMarkers()
                    end
                    -- If the status bar is currently disabled, switch to an innocuous mode to display it
                    if not self.view.footer_visible then
                        self.mode = self.mode_list.page_progress
                        self:applyFooterMode()
                        G_reader_settings:saveSetting("reader_footer_mode", self.mode)
                    end
                    self:refreshFooter(true, true)
                end,
            },
            {
                text = _("Show chapter-progress bar instead"),
                help_text = _("Show progress bar for the current chapter, instead of the whole book."),
                enabled_func = function()
                    return not self.settings.disable_progress_bar
                end,
                checked_func = function()
                    return self.settings.chapter_progress_bar
                end,
                callback = function()
                    self:onToggleChapterProgressBar()
                end,
            },
            {
                text_func = function()
                    return T(_("Position: %1"), self:genProgressBarPositionMenuItems())
                end,
                enabled_func = function()
                    return not self.settings.disable_progress_bar
                end,
                sub_item_table = {
                    self:genProgressBarPositionMenuItems("above"),
                    self:genProgressBarPositionMenuItems("alongside"),
                    self:genProgressBarPositionMenuItems("below"),
                },
                separator = true,
            },
            {
                text_func = function()
                    if self.settings.progress_style_thin then
                        return _("Thickness and height: thin")
                    else
                        return _("Thickness and height: thick")
                    end
                end,
                enabled_func = function()
                    return not self.settings.disable_progress_bar
                end,
                sub_item_table = {
                    {
                        text = _("Thick"),
                        checked_func = function()
                            return not self.settings.progress_style_thin
                        end,
                        callback = function()
                            self.settings.progress_style_thin = nil
                            local bar_height = self.settings.progress_style_thick_height
                            self.progress_bar:updateStyle(true, bar_height)
                            self:setTocMarkers()
                            self:refreshFooter(true, true)
                        end,
                    },
                    {
                        text = _("Thin"),
                        checked_func = function()
                            return self.settings.progress_style_thin
                        end,
                        callback = function()
                            self.settings.progress_style_thin = true
                            local bar_height = self.settings.progress_style_thin_height
                            self.progress_bar:updateStyle(false, bar_height)
                            self:refreshFooter(true, true)
                        end,
                        separator = true,
                    },
                    {
                        text_func = function()
                            local height = self.settings.progress_style_thin
                                and self.settings.progress_style_thin_height or self.settings.progress_style_thick_height
                            return T(_("Height: %1"), height)
                        end,
                        callback = function(touchmenu_instance)
                            local value, value_min, value_max, default_value
                            if self.settings.progress_style_thin then
                                default_value = self.default_settings.progress_style_thin_height
                                value = self.settings.progress_style_thin_height
                                value_min = 0
                                value_max = 12
                            else
                                default_value = self.default_settings.progress_style_thick_height
                                value = self.settings.progress_style_thick_height
                                value_min = 5
                                value_max = 28
                            end
                            local items = SpinWidget:new{
                                value = value,
                                value_min = value_min,
                                value_step = 1,
                                value_hold_step = 2,
                                value_max = value_max,
                                default_value = default_value,
                                title_text = _("Progress bar height"),
                                keep_shown_on_apply = true,
                                callback = function(spin)
                                    if self.settings.progress_style_thin then
                                        self.progress_bar.zero = spin.value == 0 and true or false
                                        self.settings.progress_style_thin_height = spin.value
                                    else
                                        self.settings.progress_style_thick_height = spin.value
                                    end
                                    self:refreshFooter(true, true)
                                    touchmenu_instance:updateItems()
                                end,
                            }
                            UIManager:show(items)
                        end,
                        keep_menu_open = true,
                    },
                },
            },
            {
                text_func = function()
                    local value = self.settings.progress_margin and _("same as book margins") or self.settings.progress_margin_width
                    return T(_("Margins: %1"), value)
                end,
                enabled_func = function()
                    return not self.settings.disable_progress_bar
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local spin_widget
                    spin_widget = SpinWidget:new{
                        title_text = _("Progress bar margins"),
                        value = self.settings.progress_margin_width,
                        value_min = 0,
                        value_max = 140, -- max creoptions h_page_margins
                        value_hold_step = 5,
                        default_value = self.default_settings.progress_margin_width,
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            self.settings.progress_margin_width = spin.value
                            self.settings.progress_margin = false
                            self:refreshFooter(true)
                            touchmenu_instance:updateItems()
                        end,
                        extra_text = not self.ui.document.info.has_pages and _("Same as book margins"),
                        extra_callback = function()
                            local h_margins = self.ui.document.configurable.h_page_margins
                            local value = math.floor((h_margins[1] + h_margins[2])/2)
                            self.settings.progress_margin_width = value
                            self.settings.progress_margin = true
                            self:refreshFooter(true)
                            touchmenu_instance:updateItems()
                            spin_widget.value = value
                            spin_widget.original_value = value
                            spin_widget:update()
                        end,
                    }
                    UIManager:show(spin_widget)
                end,
            },
            {
                text_func = function()
                    return T(_("Minimum progress bar width: %1\xE2\x80\xAF%"), self.settings.progress_bar_min_width_pct) -- U+202F NARROW NO-BREAK SPACE
                end,
                enabled_func = function()
                    return self.settings.progress_bar_position == "alongside" and not self.settings.disable_progress_bar
                        and self.settings.all_at_once
                end,
                callback = function(touchmenu_instance)
                    local items = SpinWidget:new{
                        value = self.settings.progress_bar_min_width_pct,
                        value_min = 5,
                        value_step = 5,
                        value_hold_step = 20,
                        value_max = 50,
                        unit = "%",
                        title_text = _("Minimum progress bar width"),
                        text = _("Minimum percentage of screen width assigned to progress bar"),
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            self.settings.progress_bar_min_width_pct = spin.value
                            self:refreshFooter(true, true)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(items)
                end,
                keep_menu_open = true,
                separator = true,
            },
            {
                text = _("Show initial-position marker"),
                checked_func = function()
                    return self.settings.initial_marker == true
                end,
                enabled_func = function()
                    return not self.settings.disable_progress_bar
                end,
                callback = function()
                    self.settings.initial_marker = not self.settings.initial_marker
                    self.progress_bar.initial_pos_marker = self.settings.initial_marker
                    self:refreshFooter(true)
                end,
            },
            {
                text = _("Show chapter markers"),
                checked_func = function()
                    return self.settings.toc_markers == true and not self.settings.chapter_progress_bar
                end,
                enabled_func = function()
                    return not self.settings.progress_style_thin and not self.settings.chapter_progress_bar
                        and not self.settings.disable_progress_bar
                end,
                callback = function()
                    self.settings.toc_markers = not self.settings.toc_markers
                    self:setTocMarkers()
                    self:refreshFooter(true)
                end,
            },
            {
                text_func = function()
                    return T(_("Chapter marker width: %1"), self:genProgressBarChapterMarkerWidthMenuItems())
                end,
                enabled_func = function()
                    return not self.settings.progress_style_thin and not self.settings.chapter_progress_bar
                        and self.settings.toc_markers and not self.settings.disable_progress_bar
                end,
                sub_item_table = {
                    self:genProgressBarChapterMarkerWidthMenuItems(1),
                    self:genProgressBarChapterMarkerWidthMenuItems(2),
                    self:genProgressBarChapterMarkerWidthMenuItems(3),
                },
            },
        }
    })
    -- footer_items
    local footer_items = {}
    table.insert(sub_items, {
        text = _("Status bar items"),
        sub_item_table = footer_items,
    })
    table.insert(footer_items, getMinibarOption("page_progress"))
    table.insert(footer_items, getMinibarOption("pages_left_book"))
    table.insert(footer_items, getMinibarOption("time"))
    table.insert(footer_items, getMinibarOption("chapter_progress"))
    table.insert(footer_items, getMinibarOption("pages_left"))
    if Device:hasBattery() then
        table.insert(footer_items, getMinibarOption("battery"))
    end
    table.insert(footer_items, getMinibarOption("bookmark_count"))
    table.insert(footer_items, getMinibarOption("percentage"))
    table.insert(footer_items, getMinibarOption("book_time_to_read"))
    table.insert(footer_items, getMinibarOption("chapter_time_to_read"))
    if Device:hasFrontlight() then
        table.insert(footer_items, getMinibarOption("frontlight"))
    end
    if Device:hasNaturalLight() then
        table.insert(footer_items, getMinibarOption("frontlight_warmth"))
    end
    table.insert(footer_items, getMinibarOption("mem_usage"))
    if Device:hasFastWifiStatusQuery() then
        table.insert(footer_items, getMinibarOption("wifi_status"))
    end
    table.insert(footer_items, getMinibarOption("page_turning_inverted"))
    table.insert(footer_items, getMinibarOption("book_author"))
    table.insert(footer_items, getMinibarOption("book_title"))
    table.insert(footer_items, getMinibarOption("book_chapter"))
    table.insert(footer_items, getMinibarOption("custom_text"))
    table.insert(footer_items, getMinibarOption("dynamic_filler"))

    local FontList = require("fontlist")
    local table_fonts = {}

    for _, font_path in ipairs(FontList:getFontList()) do
        if font_path:match("([^/]+%-Regular%.[ot]tf)$") then
            font_path = font_path:match("([^/]+%-Regular%.[ot]tf)$")
            table.insert(table_fonts, {
                text = font_path,
                checked_func = function()
                    return self.settings.text_font_face == font_path
                end,
                callback = function()
                    local face = Font:getFace(font_path, self.settings.text_font_size)
                    self.footer_text_face = face
                    self.settings.text_font_face = font_path
                    self:updateFooterFont()
                    self:refreshFooter(true, true)
                    return true
                end,
            })
        end
    end
    -- configure footer_items
    table.insert(sub_items, {
        text = _("Configure items"),
        separator = true,
        sub_item_table = {
            {
                text = _("Arrange items in status bar"),
                separator = true,
                keep_menu_open = true,
                enabled_func = function()
                    local enabled_count = 0
                    for _, m in ipairs(self.mode_index) do
                        if self.settings[m] then
                            if enabled_count == 1 then
                                return true
                            end
                            enabled_count = enabled_count + 1
                        end
                    end
                    return false
                end,
                callback = function()
                    local item_table = {}
                    for i, item in ipairs(self.mode_index) do
                        item_table[i] = { text = self:textOptionTitles(item), label = item, dim = not self.settings[item] }
                    end
                    local SortWidget = require("ui/widget/sortwidget")
                    UIManager:show(SortWidget:new{
                        title = _("Arrange items"),
                        height = Screen:getHeight() - self:getHeight() - Size.padding.large,
                        item_table = item_table,
                        callback = function()
                            for i, item in ipairs(item_table) do
                                self.mode_index[i] = item.label
                            end
                            self.settings.order = self.mode_index
                            self:updateFooterTextGenerator()
                            self:onUpdateFooter(true)
                            UIManager:setDirty(nil, "ui")
                        end,
                    })
                end,
            },
            getMinibarOption("all_at_once", self.updateFooterTextGenerator),
            {
                text = _("Auto refresh items"),
                help_text = _("This option allows certain items to update without needing user interaction (i.e page refresh). For example, the time item will update every minute regardless of user input."),
                checked_func = function()
                    return self.settings.auto_refresh_time == true
                end,
                callback = function()
                    self.settings.auto_refresh_time = not self.settings.auto_refresh_time
                    self:rescheduleFooterAutoRefreshIfNeeded()
                end,
            },
            {
                text = _("Hide inactive items"),
                help_text = _([[This option will hide inactive items from appearing on the status bar. For example, if the frontlight is 'off' (i.e 0 brightness), no symbols or values will be displayed until the brightness is set to a value >= 1.]]),
                enabled_func = function()
                    return self.settings.all_at_once == true
                end,
                checked_func = function()
                    return self.settings.hide_empty_generators == true
                end,
                callback = function()
                    self.settings.hide_empty_generators = not self.settings.hide_empty_generators
                    self:refreshFooter(true, true)
                end,
            },
            {
                text = _("Include current page in pages left"),
                help_text = _([[
By default, KOReader does not include the current page when calculating pages left. For example, in a book or chapter with n pages the 'pages left' item will range from 'n−1' to 0 (last page).
With this feature enabled, the current page is factored in, resulting in the count going from n to 1 instead.]]),
                enabled_func = function()
                    return self.settings.pages_left or self.settings.pages_left_book
                end,
                checked_func = function()
                    return self.settings.pages_left_includes_current_page == true
                end,
                callback = function()
                    self.settings.pages_left_includes_current_page = not self.settings.pages_left_includes_current_page
                    self:refreshFooter(true)
                end,
            },
            {
                text_func = function()
                    return T(_("Progress percentage format: %1"), self:genProgressPercentageFormatMenuItems())
                end,
                sub_item_table = {
                    self:genProgressPercentageFormatMenuItems("0"),
                    self:genProgressPercentageFormatMenuItems("1"),
                    self:genProgressPercentageFormatMenuItems("2"),
                },
                separator = true,
            },
            {
                text_func = function()
                    local font_weight = ""
                    if self.settings.text_font_bold == true then
                        font_weight = ", " .. _("bold")
                    end
                    return T(_("Item font: %1, %2%3"),
                        (self.settings.text_font_face and self.settings.text_font_face or self.text_font_face),
                        self.settings.text_font_size, font_weight)
                end,
                sub_item_table = {
                    {
                        text_func = function()
                            return T(_("Item font face: %1"), self.settings.text_font_face and self.settings.text_font_face or "Default: " .. self.text_font_face)
                        end,
                        sub_item_table = table_fonts,
                    },
                    {
                        text_func = function()
                            return T(_("Item font size: %1"), self.settings.text_font_size)
                        end,
                        callback = function(touchmenu_instance)
                            local items_font = SpinWidget:new{
                                title_text = _("Item font size"),
                                value = self.settings.text_font_size,
                                value_min = 8,
                                value_max = 36,
                                default_value = self.default_settings.text_font_size,
                                keep_shown_on_apply = true,
                                callback = function(spin)
                                    self.settings.text_font_size = spin.value
                                    self:updateFooterFont()
                                    self:refreshFooter(true, true)
                                    touchmenu_instance:updateItems()
                                end,
                            }
                            UIManager:show(items_font)
                        end,
                        keep_menu_open = true,
                    },
                    {
                        text = _("Items in bold"),
                        checked_func = function()
                            return self.settings.text_font_bold == true
                        end,
                        callback = function()
                            self.settings.text_font_bold = not self.settings.text_font_bold
                            self:updateFooterFont()
                            self:refreshFooter(true, true)
                        end,
                    },
                },
            },
            {
                text_func = function()
                    return T(_("Item symbols: %1"), self:genItemSymbolsMenuItems())
                end,
                sub_item_table = {
                    self:genItemSymbolsMenuItems("icons"),
                    self:genItemSymbolsMenuItems("letters"),
                    self:genItemSymbolsMenuItems("compact_items"),
                },
            },
            {
                text_func = function()
                    return T(_("Item separator: %1"), self:genItemSeparatorMenuItems())
                end,
                sub_item_table = {
                    self:genItemSeparatorMenuItems("bar"),
                    self:genItemSeparatorMenuItems("bullet"),
                    self:genItemSeparatorMenuItems("dot"),
                    self:genItemSeparatorMenuItems("none"),
                },
            },
            {
                text = _("Item max width"),
                sub_item_table = {
                    self:genItemMaxWidthMenuItems(_("Book-author item"),
                        _("Book-author item: %1\xE2\x80\xAF%"), "book_author_max_width_pct"), -- U+202F NARROW NO-BREAK SPACE
                    self:genItemMaxWidthMenuItems(_("Book-title item"),
                        _("Book-title item: %1\xE2\x80\xAF%"), "book_title_max_width_pct"),
                    self:genItemMaxWidthMenuItems(_("Chapter-title item"),
                        _("Chapter-title item: %1\xE2\x80\xAF%"), "book_chapter_max_width_pct"),
                },
            },
            {
                text_func = function()
                    return T(_("Alignment: %1"), self:genAlignmentMenuItems())
                end,
                enabled_func = function()
                    return self.settings.disable_progress_bar or self.settings.progress_bar_position ~= "alongside"
                end,
                sub_item_table = {
                    self:genAlignmentMenuItems("left"),
                    self:genAlignmentMenuItems("center"),
                    self:genAlignmentMenuItems("right"),
                },
            },
            {
                text_func = function()
                    return T(_("Height: %1"), self.settings.container_height)
                end,
                callback = function(touchmenu_instance)
                    local spin_widget = SpinWidget:new{
                        value = self.settings.container_height,
                        value_min = 7,
                        value_max = 98,
                        default_value = self.default_settings.container_height,
                        title_text = _("Items container height"),
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            self.settings.container_height = spin.value
                            self.height = Screen:scaleBySize(self.settings.container_height)
                            self:refreshFooter(true, true)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(spin_widget)
                end,
                keep_menu_open = true,
            },
            {
                text_func = function()
                    return T(_("Bottom margin: %1"), self.settings.container_bottom_padding)
                end,
                callback = function(touchmenu_instance)
                    local spin_widget = SpinWidget:new{
                        value = self.settings.container_bottom_padding,
                        value_min = 0,
                        value_max = 49,
                        default_value = self.default_settings.container_bottom_padding,
                        title_text = _("Container bottom margin"),
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            self.settings.container_bottom_padding = spin.value
                            self.bottom_padding = Screen:scaleBySize(self.settings.container_bottom_padding)
                            self:refreshFooter(true, true)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(spin_widget)
                end,
                keep_menu_open = true,
            },
           {
                text_func = function()
                    return T(_("Adjust margin top: %1"), self.settings.top_padding)
                end,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local top_padding = self.settings.top_padding
                    local items_font = SpinWidget:new{
                        value = top_padding,
                        value_min = 0,
                        value_max = 100,
                        default_value = 5,
                        ok_text = _("Set margin"),
                        title_text = _("Top bar margin"),
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            self.settings.top_padding = spin.value
                            if not self.settings.top_padding then
                                self.top_padding = Screen:scaleBySize(self.settings.top_padding)
                            else
                                self.top_padding = Screen:scaleBySize(5)
                            end
                            self:refreshFooter(true, true)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(items_font)
                end,
                keep_menu_open = true,
            },
        }
    })
    local configure_items_sub_table = sub_items[#sub_items].sub_item_table -- will pick the last item of sub_items
    if Device:hasBattery() then
        table.insert(configure_items_sub_table, 5, {
            text_func = function()
                if self.settings.battery_hide_threshold <= self.default_settings.battery_hide_threshold then
                    return T(_("Hide battery item when higher than: %1\xE2\x80\xAF%"), self.settings.battery_hide_threshold) -- U+202F NARROW NO-BREAK SPACE
                else
                    return _("Hide battery item at custom threshold")
                end
            end,
            checked_func = function()
                return self.settings.battery_hide_threshold <= self.default_settings.battery_hide_threshold
            end,
            enabled_func = function()
                return self.settings.all_at_once == true
            end,
            callback = function(touchmenu_instance)
                local max_pct = self.default_settings.battery_hide_threshold
                local battery_threshold = SpinWidget:new{
                    value = math.min(self.settings.battery_hide_threshold, max_pct),
                    value_min = 0,
                    value_max = max_pct,
                    default_value = max_pct,
                    unit = "%",
                    value_hold_step = 10,
                    title_text = _("Minimum threshold to hide battery item"),
                    callback = function(spin)
                        self.settings.battery_hide_threshold = spin.value
                        self:refreshFooter(true, true)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                    extra_text = _("Disable"),
                    extra_callback = function()
                        self.settings.battery_hide_threshold = max_pct + 1
                        self:refreshFooter(true, true)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                    ok_always_enabled = true,
                }
                UIManager:show(battery_threshold)
            end,
            keep_menu_open = true,
            separator = true,
        })
    end
    table.insert(sub_items, {
        text = _("Status bar presets"),
        separator = true,
        sub_item_table_func = function()
            return Presets.genPresetMenuItemTable(self.preset_obj, nil, nil)
        end,
    })
    table.insert(sub_items, {
        text = _("Show status bar separator"),
        checked_func = function()
            return self.settings.bottom_horizontal_separator == true
        end,
        callback = function()
            self.settings.bottom_horizontal_separator = not self.settings.bottom_horizontal_separator
            self:refreshFooter(true, true)
        end,
    })
    if Device:isTouchDevice() then
        table.insert(sub_items, getMinibarOption("reclaim_height"))
        table.insert(sub_items, {
            text = _("Lock status bar"),
            checked_func = function()
                return self.settings.lock_tap == true
            end,
            callback = function()
                self.settings.lock_tap = not self.settings.lock_tap
            end,
        })
        table.insert(sub_items, {
            text = _("Long-press on status bar to skim"),
            checked_func = function()
                return self.settings.skim_widget_on_hold == true
            end,
            callback = function()
                self.settings.skim_widget_on_hold = not self.settings.skim_widget_on_hold
            end,
        })
    end
end

-- settings menu item generators

function ReaderFooter:genProgressBarPositionMenuItems(value)
    local strings = {
        above     = _("Above items"),
        alongside = _("Alongside items"),
        below     = _("Below items"),
    }
    if value == nil then
        return strings[self.settings.progress_bar_position]:lower()
    end
    return {
        text = strings[value],
        checked_func = function()
            return self.settings.progress_bar_position == value
        end,
        callback = function()
            if value == "alongside" then
                -- Text alignment is disabled in this mode
                self.settings.align = "center"
            end
            self.settings.progress_bar_position = value
            self:refreshFooter(true, true)
        end,
    }
end

function ReaderFooter:genProgressBarChapterMarkerWidthMenuItems(value)
    local strings = {
        _("Thin"),
        _("Medium"),
        _("Thick"),
    }
    if value == nil then
        return strings[self.settings.toc_markers_width]:lower()
    end
    return {
        text = strings[value],
        checked_func = function()
            return self.settings.toc_markers_width == value
        end,
        callback = function()
            self.settings.toc_markers_width = value -- unscaled_size_check: ignore
            self:setTocMarkers()
            self:refreshFooter(true)
        end,
    }
end

function ReaderFooter:genProgressPercentageFormatMenuItems(value)
    local strings = {
        ["0"] = _("No decimal places (%1)"),
        ["1"] = _("1 decimal place (%1)"),
        ["2"] = _("2 decimal places (%1)"),
    }
    local progressPercentage = function(digits)
        local symbol_type = self.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].percentage
        local string_percentage = "%." .. digits .. "f%%"
        if prefix then
            string_percentage = prefix .. " " .. string_percentage
        end
        return string_percentage:format(self:getBookProgress() * 100)
    end
    if value == nil then
        return progressPercentage(self.settings.progress_pct_format)
    end
    return {
        text_func = function()
            return T(strings[value], progressPercentage(value))
        end,
        checked_func = function()
            return self.settings.progress_pct_format == value
        end,
        callback = function()
            self.settings.progress_pct_format = value
            self:refreshFooter(true)
        end,
    }
end

function ReaderFooter:genItemSymbolsMenuItems(value)
    local strings = {
        icons         = C_("Status bar", "Icons"),
        letters       = C_("Status bar", "Letters"),
        compact_items = C_("Status bar", "Compact"),
    }
    if value == nil then
        return strings[self.settings.item_prefix]:lower()
    end
    return {
        text_func = function()
            local sym_tbl = {}
            for _, letter in pairs(symbol_prefix[value]) do
                table.insert(sym_tbl, letter)
            end
            return T("%1 (%2)", strings[value], table.concat(sym_tbl, " "))
        end,
        checked_func = function()
            return self.settings.item_prefix == value
        end,
        callback = function()
            self.settings.item_prefix = value
            if self.settings.items_separator == "none" then
                self.separator_width = nil
            end
            self:refreshFooter(true)
        end,
    }
end

function ReaderFooter:genItemSeparatorMenuItems(value)
    local strings = {
        bar    = _("Vertical bar (|)"),
        bullet = _("Bullet (•)"),
        dot    = _("Dot (·)"),
        none   = _("No separator"),
    }
    if value == nil then
        return strings[self.settings.items_separator]:lower()
    end
    return {
        text = strings[value],
        checked_func = function()
            return self.settings.items_separator == value
        end,
        callback = function()
            self.settings.items_separator = value
            self.separator_width = nil
            self:refreshFooter(true)
        end,
    }
end

function ReaderFooter:genItemMaxWidthMenuItems(title_text, item_text, setting)
    return {
        text_func = function()
            return T(item_text, self.settings[setting])
        end,
        callback = function(touchmenu_instance)
            local spin_widget = SpinWidget:new{
                title_text = title_text,
                info_text = _("Maximum percentage of screen width used for the item"),
                value = self.settings[setting],
                value_min = 10,
                value_max = 100,
                value_step = 5,
                value_hold_step = 20,
                unit = "%",
                default_value = self.default_settings[setting],
                keep_shown_on_apply = true,
                callback = function(spin)
                    self.settings[setting] = spin.value
                    self:refreshFooter(true, true)
                    touchmenu_instance:updateItems()
                end
            }
            UIManager:show(spin_widget)
        end,
        keep_menu_open = true,
    }
end

function ReaderFooter:genAlignmentMenuItems(value)
    local strings = {
        left   = _("Left"),
        center = _("Center"),
        right  = _("Right"),
    }
    if value == nil then
        return strings[self.settings.align]:lower()
    end
    return {
        text = strings[value],
        checked_func = function()
            return self.settings.align == value
        end,
        callback = function()
            self.settings.align = value
            self:refreshFooter(true)
        end,
    }
end

function ReaderFooter:buildPreset()
    return {
        footer = util.tableDeepCopy(self.settings),
        reader_footer_mode = self.mode,
        reader_footer_custom_text = self.custom_text,
        reader_footer_custom_text_repetitions = self.custom_text_repetitions,
    }
end

function ReaderFooter:loadPreset(preset)
    local old_text_font_size = self.settings.text_font_size
    local old_text_font_bold = self.settings.text_font_bold
    G_reader_settings:saveSetting("footer", util.tableDeepCopy(preset.footer))
    G_reader_settings:saveSetting("reader_footer_mode", preset.reader_footer_mode)
    G_reader_settings:saveSetting("reader_footer_custom_text", preset.reader_footer_custom_text)
    G_reader_settings:saveSetting("reader_footer_custom_text_repetitions", preset.reader_footer_custom_text_repetitions)
    self.settings = G_reader_settings:readSetting("footer")
    self.mode_index = self.settings.order or self.mode_index
    self.custom_text = preset.reader_footer_custom_text
    self.custom_text_repetitions = tonumber(preset.reader_footer_custom_text_repetitions)
    self:applyFooterMode(preset.reader_footer_mode)
    self:updateFooterTextGenerator()
    if old_text_font_size ~= self.settings.text_font_size or old_text_font_bold ~= self.settings.text_font_bold then
        self:updateFooterFont()
    else
        self.separator_width = nil
        self.filler_space_width = nil
    end
    self:setTocMarkers()
    self:refreshFooter(true, true)
end

function ReaderFooter:onLoadFooterPreset(preset_name)
    return Presets.onLoadPreset(self.preset_obj, preset_name, true)
end

function ReaderFooter.getPresets() -- for Dispatcher
    local footer_config = {
        presets = G_reader_settings:readSetting("footer_presets", {})
    }
    return Presets.getPresets(footer_config)
end

function ReaderFooter:addAdditionalFooterContent(content_func)
    table.insert(self.additional_footer_content, content_func)
end

function ReaderFooter:removeAdditionalFooterContent(content_func)
    for i, v in ipairs(self.additional_footer_content) do
        if v == content_func then
            table.remove(self.additional_footer_content, i)
            return true
        end
    end
end

-- this method will be updated at runtime based on user setting
function ReaderFooter:genFooterText() end

function ReaderFooter:getFittedText(text, max_width_pct)
    if text == nil or text == "" then
        return ""
    end
    local text_widget = TextWidget:new{
        text = text:gsub(" ", "\u{00A0}"), -- no-break-space
        max_width = self._saved_screen_width * max_width_pct * (1/100),
        face = self.footer_text_face,
        bold = self.settings.text_font_bold,
    }
    local fitted_text, add_ellipsis = text_widget:getFittedText()
    text_widget:free()
    if add_ellipsis then
        fitted_text = fitted_text .. "…"
    end
    return BD.auto(fitted_text)
end

function ReaderFooter:genSeparator()
    local strings = {
        bar    = " | ",
        bullet = " • ",
        dot    = " · ",
    }
    return strings[self.settings.items_separator]
        or (self.settings.item_prefix == "compact_items" and " " or "  ")
end

function ReaderFooter:genAllFooterText(gen_to_skip)
    local info = {}
    -- We need to BD.wrap() all items and separators, so we're
    -- sure they are laid out in our order (reversed in RTL),
    -- without ordering by the RTL Bidi algorithm.
    local count = 0 -- total number of visible items
    local skipped_idx, prev_had_merge
    for _, gen in ipairs(self.footerTextGenerators) do
        if gen == gen_to_skip then
            count = count + 1
            skipped_idx = count
            goto continue
        end
        -- Skip empty generators, so they don't generate bogus separators
        local text, merge = gen(self)
        if text and text ~= "" then
            count = count + 1
            if self.settings.item_prefix == "compact_items" and gen ~= footerTextGeneratorMap.dynamic_filler then
                -- remove whitespace from footer items if symbol_type is compact_items
                -- use a hair-space to avoid issues with RTL display
                text = text:gsub("%s", "\u{200A}")
            end
            -- if generator request a merge of this item, add it directly,
            -- i.e. no separator before and after the text then.
            if merge then
                local merge_pos = #info == 0 and 1 or #info
                info[merge_pos] = (info[merge_pos] or "") .. text
                prev_had_merge = true
            elseif prev_had_merge then
                info[#info] = info[#info] .. text
                prev_had_merge = false
            else
                table.insert(info, BD.wrap(text))
            end
        end
        ::continue::
    end
    return table.concat(info, BD.wrap(self:genSeparator())), skipped_idx ~= 1 and skipped_idx ~= count
end

function ReaderFooter:setTocMarkers(reset)
    if self.settings.disable_progress_bar or self.settings.progress_style_thin then return end
    if reset then
        self.progress_bar.ticks = nil
        self.pages = self.ui.document:getPageCount()
    end
    if self.settings.toc_markers and not self.settings.chapter_progress_bar then
        self.progress_bar.tick_width = Screen:scaleBySize(self.settings.toc_markers_width)
        if self.progress_bar.ticks ~= nil then -- already computed
            return
        end
        if self.ui.document:hasHiddenFlows() and self.pageno then
            local flow = self.ui.document:getPageFlow(self.pageno)
            self.progress_bar.ticks = {}
            if self.ui.toc then
                -- filter the ticks to show only those in the current flow
                for n, pageno in ipairs(self.ui.toc:getTocTicksFlattened()) do
                    if self.ui.document:getPageFlow(pageno) == flow then
                        table.insert(self.progress_bar.ticks, self.ui.document:getPageNumberInFlow(pageno))
                    end
                end
            end
            self.progress_bar.last = self.ui.document:getTotalPagesInFlow(flow)
        else
            if self.ui.toc then
                self.progress_bar.ticks = self.ui.toc:getTocTicksFlattened()
            end
            if self.view.view_mode == "page" then
                self.progress_bar.last = self.pages or self.ui.document:getPageCount()
            else
                -- in scroll mode, convert pages to positions
                if self.ui.toc then
                    self.progress_bar.ticks = {}
                    for n, pageno in ipairs(self.ui.toc:getTocTicksFlattened()) do
                        local idx = self.ui.toc:getTocIndexByPage(pageno)
                        local pos = self.ui.document:getPosFromXPointer(self.ui.toc.toc[idx].xpointer)
                        table.insert(self.progress_bar.ticks, pos)
                    end
                end
                self.progress_bar.last = self.doc_height or self.ui.document.info.doc_height
            end
        end
    else
        self.progress_bar.ticks = nil
    end
    -- notify caller that UI needs update
    return true
end

-- This is implemented by the Statistics plugin
function ReaderFooter:getAvgTimePerPage() end

function ReaderFooter:getDataFromStatistics(title, pages)
    local sec = _("N/A")
    local average_time_per_page = self:getAvgTimePerPage()
    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
    if average_time_per_page then
        sec = datetime.secondsToClockDuration(user_duration_format, pages * average_time_per_page, true)
    end
    return title .. sec
end

function ReaderFooter:onUpdateFooter(force_repaint, full_repaint)
    if self.pageno then
        self:updateFooterPage(force_repaint, full_repaint)
    else
        self:updateFooterPos(force_repaint, full_repaint)
    end
end

function ReaderFooter:updateFooterPage(force_repaint, full_repaint)
    if type(self.pageno) ~= "number" then return end
    if self.settings.chapter_progress_bar then
        if self.progress_bar.initial_pos_marker then
            if self.ui.toc:getNextChapter(self.pageno) == self.ui.toc:getNextChapter(self.initial_pageno) then
                self.progress_bar.initial_percentage = self:getChapterProgress(true, self.initial_pageno)
            else -- initial position is not in the current chapter
                self.progress_bar.initial_percentage = -1 -- do not draw initial position marker
            end
        end
        self.progress_bar:setPercentage(self:getChapterProgress(true))
    else
        self.progress_bar:setPercentage(self:getBookProgress())
    end

    -- If the footer is on top we want to repaint it always, otherwise it will be double-painted
    -- in certain circumstances like when changing bright or selecting a new typography configuration
    --if self.settings.bar_top then
    --    self:updateFooterText(true, true)
    --else
    --    self:updateFooterText(force_repaint, full_repaint)
    --end

    -- Full repaint always, otherwise, the status bar always covers the topbar side text which
    -- was made visible recently
    self:updateFooterText(force_repaint, true)
end

function ReaderFooter:updateFooterPos(force_repaint, full_repaint)
    if type(self.position) ~= "number" then return end
    if self.settings.chapter_progress_bar then
        if self.progress_bar.initial_pos_marker then
            if self.pageno and (self.ui.toc:getNextChapter(self.pageno) == self.ui.toc:getNextChapter(self.initial_pageno)) then
                self.progress_bar.initial_percentage = self:getChapterProgress(true, self.initial_pageno)
            else
                self.progress_bar.initial_percentage = -1
            end
        end
        self.progress_bar:setPercentage(self:getChapterProgress(true))
    else
        self.progress_bar:setPercentage(self.position / self.doc_height)
    end
    self:updateFooterText(force_repaint, full_repaint)
end

function ReaderFooter:updateFooterFont()
    self.separator_width = nil
    self.filler_space_width = nil
    self.footer_text_face = Font:getFace(self.settings.text_font_face and self.settings.text_font_face or self.text_font_face, self.settings.text_font_size)
    self.footer_text:free()
    self.footer_text = TextWidget:new{
        text = self.footer_text.text,
        face = self.footer_text_face,
        bold = self.settings.text_font_bold,
    }
    self.text_container[1] = self.footer_text
end

-- updateFooterText will start as a noop. After onReaderReady event is
-- received, it will initialized as _updateFooterText below
function ReaderFooter:updateFooterText(force_repaint, full_repaint)
end

-- only call this function after document is fully loaded
function ReaderFooter:_updateFooterText(force_repaint, full_repaint)
    -- footer is invisible, we need neither a repaint nor a recompute, go away.
    if not self.view.footer_visible and not force_repaint and not full_repaint then
        return
    end

    local text = self:genFooterText() or ""
    for _, v in ipairs(self.additional_footer_content) do
        local value = v()
        if value and value ~= "" then
            text = text == "" and value or value .. self:genSeparator() .. text
        end
    end
    self.footer_text:setText(text)

    if self.settings.disable_progress_bar then
        if self.has_no_mode or text == "" then
            self.text_width = 0
            self.footer_text.height = 0
        else
            -- No progress bar, we're only constrained to fit inside self.footer_container
            self.footer_text:setMaxWidth(math.floor(self._saved_screen_width - 2 * self.horizontal_margin))
            self.text_width = self.footer_text:getSize().w
            self.footer_text.height = self.footer_text:getSize().h
        end
        self.progress_bar.height = 0
        self.progress_bar.width = 0
    elseif self.settings.progress_bar_position ~= "alongside" then
        local margins_width = 2 * Screen:scaleBySize(self.settings.progress_margin_width)
        if self.has_no_mode or text == "" then
            self.text_width = 0
            self.footer_text.height = 0
        else
            -- With a progress bar above or below us, we want to align ourselves to the bar's margins... iff text is centered.
            if self.settings.align == "center" then
                self.footer_text:setMaxWidth(math.floor(self._saved_screen_width - margins_width))
            else
                -- Otherwise, we have to constrain ourselves to the container, or weird shit happens.
                self.footer_text:setMaxWidth(math.floor(self._saved_screen_width - 2 * self.horizontal_margin))
            end
            self.text_width = self.footer_text:getSize().w
            self.footer_text.height = self.footer_text:getSize().h
        end
        self.progress_bar.width = math.floor(self._saved_screen_width - margins_width)
    else
        local margins_width = 2 * Screen:scaleBySize(self.settings.progress_margin_width)
        if self.has_no_mode or text == "" then
            self.text_width = 0
            self.footer_text.height = 0
        else
            -- Alongside a progress bar, it's the bar's width plus whatever's left.
            local text_max_available_ratio = (100 - self.settings.progress_bar_min_width_pct) * (1/100)
            self.footer_text:setMaxWidth(math.floor(text_max_available_ratio * self._saved_screen_width - margins_width - self.horizontal_margin))
            -- Add some spacing between the text and the bar
            self.text_width = self.footer_text:getSize().w + self.horizontal_margin
            self.footer_text.height = self.footer_text:getSize().h
        end
        self.progress_bar.width = math.floor(self._saved_screen_width - margins_width - self.text_width)
    end

    if self.separator_line then
        self.separator_line.dimen.w = self._saved_screen_width - 2 * self.horizontal_margin
    end
    self.text_container.dimen.w = self.text_width
    self.horizontal_group:resetLayout()
    -- NOTE: This is essentially preventing us from truly using "fast" for panning,
    --       since it'll get coalesced in the "fast" panning update, upgrading it to "ui".
    -- NOTE: That's assuming using "fast" for pans was a good idea, which, it turned out, not so much ;).
    -- NOTE: We skip repaints on page turns/pos update, as that's redundant (and slow).
    if force_repaint then
        -- If there was a visibility change, notify ReaderView
        if self.visibility_change then
            self.visibility_change = nil
            self.ui:handleEvent(Event:new("ReaderFooterVisibilityChange"))
        end

        -- NOTE: Getting the dimensions of the widget is impossible without having drawn it first,
        --       so, we'll fudge it if need be...
        --       i.e., when it's no longer visible, because there's nothing to draw ;).
        local refresh_dim = self.footer_content.dimen
        -- No more content...
        if not self.view.footer_visible and not refresh_dim then
            -- So, instead, rely on self:getHeight to compute self.footer_content's height early...
            refresh_dim = self.dimen
            refresh_dim.h = self:getHeight()
            refresh_dim.y = self._saved_screen_height - refresh_dim.h
        end
        -- If we're making the footer visible (or it already is), we don't need to repaint ReaderUI behind it
        if self.view.footer_visible and not full_repaint then
            -- Unfortunately, it's not a modal (we never show() it), so it's not in the window stack,
            -- instead, it's baked inside ReaderUI, so it gets slightly trickier...
            -- NOTE: self.view.footer -> self ;).

            -- c.f., ReaderView:paintTo()
            UIManager:widgetRepaint(self.view.footer, 0, 0)
            -- We've painted it first to ensure self.footer_content.dimen is sane
            UIManager:setDirty(nil, function()
                return self.view.currently_scrolling and "fast" or "ui", self.footer_content.dimen
            end)
        else
            -- If the footer is invisible or might be hidden behind another widget, we need to repaint the full ReaderUI stack.
            UIManager:setDirty(self.view.dialog, function()
                return self.view.currently_scrolling and "fast" or "ui", refresh_dim
            end)
        end
    end
end

-- Note: no need for :onDocumentRerendered(), ReaderToc will catch "DocumentRerendered"
-- and will then emit a "TocReset" after the new ToC is made.
function ReaderFooter:onTocReset()
    self:setTocMarkers(true)
    if self.view.view_mode == "page" then
        self:updateFooterPage()
    else
        self:updateFooterPos()
    end
end

function ReaderFooter:onPageUpdate(pageno)
    local toc_markers_update = false
    if self.ui.document:hasHiddenFlows() then
        local flow = self.pageno and self.ui.document:getPageFlow(self.pageno)
        local new_flow = pageno and self.ui.document:getPageFlow(pageno)
        if pageno and new_flow ~= flow then
            toc_markers_update = true
        end
    end
    self.pageno = pageno
    if not self.initial_pageno then
        self.initial_pageno = pageno
    end
    self.pages = self.ui.document:getPageCount()
    if toc_markers_update then
        self:setTocMarkers(true)
    end
    self.ui.doc_settings:saveSetting("doc_pages", self.pages) -- for Book information
    -- This is called now in the onPageUpdate() event handler function of the statistic plugins main.lua source
    -- The reader footer does not show statistics anymore so we update it here
    self:updateFooterPage()
end

function ReaderFooter:onPosUpdate(pos, pageno)
    self.position = pos
    self.doc_height = self.ui.document.info.doc_height
    if pageno then
        self.pageno = pageno
        if not self.initial_pageno then
            self.initial_pageno = pageno
        end
        self.pages = self.ui.document:getPageCount()
        self.ui.doc_settings:saveSetting("doc_pages", self.pages) -- for Book information
    end
    self:updateFooterPos()
end

function ReaderFooter:onReaderReady()
    self.ui.menu:registerToMainMenu(self)
    self:setupTouchZones()
    if self.settings.progress_margin then -- progress bar margins same as book margins
        if self.ui.paging then -- enforce default static margins
            self.settings.progress_margin_width = self.default_settings.progress_margin_width
        else -- current book margins
            local h_margins = self.ui.document.configurable.h_page_margins
            self.settings.progress_margin_width = math.floor((h_margins[1] + h_margins[2])/2)
        end
        self:updateFooterContainer()
    end
    self:resetLayout(self.settings.progress_margin) -- set widget dimen
    self:setTocMarkers()
    self.updateFooterText = self._updateFooterText
    self:onUpdateFooter()
    self:rescheduleFooterAutoRefreshIfNeeded()
end

function ReaderFooter:applyFooterMode(mode)
    if mode ~= nil then self.mode = mode end
    local prev_visible_state = self.view.footer_visible
    self.view.footer_visible = (self.mode ~= self.mode_list.off)

    -- NOTE: _updateFooterText won't actually run the text generator(s) when hidden ;).

    -- We're hidden, disable text generation entirely
    if not self.view.footer_visible then
        self.genFooterText = footerTextGeneratorMap.empty
    else
        if self.settings.all_at_once then
            -- If all-at-once is enabled, we only have toggle from empty to All.
            self.genFooterText = self.genAllFooterText
        else
            -- Otherwise, switch to the right text generator for the new mode
            local mode_name = self.mode_index[self.mode]
            if not self.settings[mode_name] or self.has_no_mode then
                -- all modes disabled, only show progress bar
                mode_name = "empty"
            end
            self.genFooterText = footerTextGeneratorMap[mode_name]
        end
    end

    -- If we changed visibility state at runtime (as opposed to during init), better make sure the layout has been reset...
    if prev_visible_state ~= nil and self.view.footer_visible ~= prev_visible_state then
        self:updateFooterContainer()
        -- NOTE: _updateFooterText does a resetLayout, but not a forced one!
        self:resetLayout(true)
        -- Flag _updateFooterText to notify ReaderView to recalculate the visible_area!
        self.visibility_change = true
    end
end

function ReaderFooter:onEnterFlippingMode()
    self.orig_mode = self.mode
    self:applyFooterMode(self.mode_list.page_progress)
    self:rescheduleFooterAutoRefreshIfNeeded()
end

function ReaderFooter:onExitFlippingMode()
    self:applyFooterMode(self.orig_mode)
    self:rescheduleFooterAutoRefreshIfNeeded()
end

function ReaderFooter:TapFooter(ges)
    if self.ui.gestures.ignore_hold_corners and self.ui.pagetextinfo and self.ui.pagetextinfo.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") then
        return self:DoubleTapFooter(ges)
    end
    if self.view.flipping_visible and ges then
        local pos = ges.pos
        local dimen = self.progress_bar.dimen
        -- if reader footer is not drawn before the dimen value should be nil
        if dimen then
            local percentage = (pos.x - dimen.x)/dimen.w
            self.ui:handleEvent(Event:new("GotoPercentage", percentage))
        end
        self:onUpdateFooter(true)
        return true
    end
    if self.settings.lock_tap then return end
    local text = not self.ui.gestures.ignore_hold_corners and "Hold and double tap lock" or "Hold and double tap unlock"
    UIManager:show(Notification:new{
        text = _(tostring(text)),
    })

    self.ui.gestures:onIgnoreHoldCorners(not self.ui.gestures.ignore_hold_corners)
    self.ui.disable_double_tap = self.ui.gestures.ignore_hold_corners

    -- This is not needed because it will work when the notification widget is closed
    -- but I leave it in case I decide to remove the notification
    Device.input.disable_double_tap = self.ui.disable_double_tap

    -- No need for this, we are not stopping the double tap:
    -- -- When double tapping the footer, the double tap will also be locked and the vocabulary builder words will be highlighted
    -- -- and we won't be able to double tap the footer and won't be able then to deactivated the vocabulary builder words highlighting automaticaly
    -- -- We do it here when tapping. When tapping after double tapping, the double tap will be unlocked and the vocabulary builder words unhighlighted
    -- -- if self.ui.pagetextinfo and self.ui.pagetextinfo.settings:isTrue("highlight_all_words_vocabulary") then
    -- --     self.ui.pagetextinfo.settings:saveSetting("highlight_all_words_vocabulary", false)
    -- -- end

    -- Instead:
    -- When ignore_hold_corners we are disabling double tap as well but just for the gestures plugin
    -- In the main.lua source of the gestures plugin, there is an event handler function gestureAction() in which this has been changed:
    --  ((ges.ges == "hold" or ges.ges == "double_tap") and self.ignore_hold_corners) then

    -- That means, we can still double tap the footer to toggle it

    self.ui.view.topbar:toggleBar()
    UIManager:setDirty(self.view.dialog, function()
        return self.view.currently_scrolling and "fast" or "ui"
    end)
    -- UIManager:setDirty("all", "full")
    -- return self:onToggleFooterMode()
    return true
end

function ReaderFooter:DoubleTapFooter(ges)
    if self.view.flipping_visible and ges then
        local pos = ges.pos
        local dimen = self.progress_bar.dimen
        -- if reader footer is not drawn before the dimen value should be nil
        if dimen then
            local percentage = (pos.x - dimen.x)/dimen.w
            self.ui:handleEvent(Event:new("GotoPercentage", percentage))
        end
        self:onUpdateFooter(true)
        return true
    end
    if self.settings.lock_tap then return end
    local text = not self.ui.gestures.ignore_hold_corners and "Hold and double tap lock" or "Hold and double tap unlock"
    UIManager:show(Notification:new{
        text = _(tostring(text)),
    })

    self.ui.gestures:onIgnoreHoldCorners(not self.ui.gestures.ignore_hold_corners)
    -- Do not disable double tap when double tapping the footer because we want to double tap words
    -- self.ui.disable_double_tap = self.ui.gestures.ignore_hold_corners
    if self.view.view_modules["pagetextinfo"] then
        self.ui.pagetextinfo:toggleHighlightAllWordsVocabulary(self.ui.gestures.ignore_hold_corners)
    end

    self.ui.view.topbar:toggleBar()
    UIManager:setDirty(self.view.dialog, function()
        return self.view.currently_scrolling and "fast" or "ui"
    end)

    return true
end

function ReaderFooter:getHeight2()
    local bar_height = 0
    if not self.settings.disable_progress_bar then
        if self.settings.progress_style_thin then
            bar_height = self.settings.progress_style_thin_height
        else
            bar_height = self.settings.progress_style_thick_height
        end
    end
    --local h_footer = Screen:scaleBySize(
    --    self.settings.container_bottom_padding
    --    + bar_height
    --    + self.settings.container_height
    --    + self.settings.text_font_size
    --)
    -- self:resetLayout(true) --Not needed, nothing changed
    -- The text is vertically centered inside a fixed-height container.
    -- When the text overflows, it may extend both above and below the container.
    -- To ensure the total visual height is accurate, we add:
    --   - the actual text height (measured)
    --   - the progress bar height (in real pixels)
    --   - the bottom padding (already scaled)
    --   - plus half the container height to compensate for the
    --     vertical centering and potential overlap.
    -- This provides a robust estimate, even in overflow scenarios.
    local h_footer = self.footer_text:getSize().h --measured
    + bar_height -- not scaled
    + (self.bottom_padding or 0) -- already scale
    + math.floor(Screen:scaleBySize(self.settings.container_height) / 2)
    -- Calculate actual refresh alignment
    --local block = 16
    --local screen_h = Screen:getHeight()
    --local y_requested = screen_h - h_footer
    --local y_aligned = y_requested - (y_requested % block)
    --local h_aligned = screen_h - y_aligned
    --local y_end = y_aligned + h_aligned

    --UIManager:show(Notification:new{
    --    text = string.format(
    --        "Footer: y=%d height=%d → refresco real y=%d h=%d hasta=%d",
    --        y_requested, h_footer, y_aligned, h_aligned, y_end
    --    ),
    --})

    -- NOTE: Although we return h_footer, in some devices (e.g. MTK with alignment_constraint = 16)
    -- or when dithering is enabled (dither_alignment_constraint = 8), the actual refresh region
    -- may be adjusted to start higher and cover more height to match hardware alignment blocks.
    -- That adjustment is handled later by getBoundedRect() and fb:refresh().
    return h_footer
    --return h_aligned
end

function ReaderFooter:onToggleFooterMode()
    if self.has_no_mode and self.settings.disable_progress_bar then return end
    if util.getFileNameSuffix(self.ui.document.file) == "epub"
        and (self.settings.all_at_once or self.has_no_mode) then
       if self.mode >= 1 then
            --self.ui.view[4]:showTopBar()
            self.ui.view.topbar.status_bar = false
            self.mode = self.mode_list.off
        else
            --self.ui.view[4]:hideTopBar()
            self.ui.view.topbar.status_bar = true
            self.mode = self.mode_list.page_progress
        end
        self.ui.view.topbar:toggleBar()
    else
        self.mode = (self.mode + 1) % self.mode_nb
        for i, m in ipairs(self.mode_index) do
            if self.mode == self.mode_list.off then break end
            if self.mode == i then
                if self.settings[m] then
                    break
                else
                    self.mode = (self.mode + 1) % self.mode_nb
                end
            end
        end
    end

    -- It is important to pass the second parameter as true, so the function updatePos() in source readerrolling.lua will be executed performing a partial refresh
    -- And that's why it works
    -- self:refreshFooter(true, true)

    self:applyFooterMode()
    G_reader_settings:saveSetting("reader_footer_mode", self.mode)

    -- local text = self:genFooterText() or ""
    -- for _, v in ipairs(self.additional_footer_content) do
    --     local value = v()
    --     if value and value ~= "" then
    --         text = text == "" and value or value .. self:genSeparator() .. text
    --     end
    -- end
    -- self.footer_text:setText(text)
    -- local margins_width = 2 * Screen:scaleBySize(self.settings.progress_margin_width)
    -- self.footer_text:setMaxWidth(math.floor(self._saved_screen_width - margins_width))
    -- UIManager:setDirty(nil, function()
    --     return self.view.currently_scrolling and "fast" or "ui", self.footer_content.dimen
    -- end)

    --UIManager:setDirty(self.view.dialog, function()
    --     return self.view.currently_scrolling and "fast" or "ui"
    --end)

    return self:refresh()
end

function ReaderFooter:refresh()
    -- With the following two calls we will have fast or ui (depending if we are scrolling or not) refreshes when toggling the footer mode
    -- We can do the refreshes manually like in the previous commented block but the problem is that if we hide the footer toggling it, turn a page and show it toggling it
    -- it won't be properly formatted. We need to reconfigure the footer configuration manually like we are partially doing in the commented block code calling to self.footer_text:setText(text)
    -- There is a function updateFooterText() which will be doing it as a result of calling self:onUpdateFooter(true)
    -- This function will perform afterwards the other refresh needed
    self:onUpdateFooter(false)
    UIManager:setDirty(self.view.dialog, function()
        return self.view.currently_scrolling and "fast" or "ui",
        Geom:new{ w = Screen:getWidth(), h = self.ui.view.topbar:getHeight(), y = 0}
    end)
    local footer_height = self:getHeight2()
    local bottom_height = self.ui.view.topbar:getBottomHeight() > footer_height
    and self.ui.view.topbar:getBottomHeight()
    or footer_height
    UIManager:setDirty(self.view.dialog, function()
       return self.view.currently_scrolling and "fast" or "ui",
        Geom:new{ w = Screen:getWidth(),
        h = bottom_height,
        y = Screen:getHeight() - bottom_height}
        end)
    self:rescheduleFooterAutoRefreshIfNeeded()
    return true
end

function ReaderFooter:onToggleChapterProgressBar()
    self.settings.chapter_progress_bar = not self.settings.chapter_progress_bar
    self:setTocMarkers()
    if self.progress_bar.initial_pos_marker and not self.settings.chapter_progress_bar then
        self.progress_bar.initial_percentage = self.initial_pageno / self.pages
    end
    self:refreshFooter(true)
end

function ReaderFooter:getBookProgress()
    if self.ui.document:hasHiddenFlows() then
        local flow = self.ui.document:getPageFlow(self.pageno)
        local page = self.ui.document:getPageNumberInFlow(self.pageno)
        local pages = self.ui.document:getTotalPagesInFlow(flow)
        return page / pages
    end
    return self.pageno / self.pages
end

function ReaderFooter:getChapterProgress(get_percentage, pageno)
    pageno = pageno or self.pageno
    local current = self.ui.toc:getChapterPagesDone(pageno)
    -- We want a page number, not a page read count
    if current then
        current = current + 1
    else
        current = pageno
        if self.ui.document:hasHiddenFlows() then
            current = self.ui.document:getPageNumberInFlow(pageno)
        end
    end
    local total = self.ui.toc:getChapterPageCount(pageno) or self.pages
    if get_percentage then
        return current / total
    end
    return ("%d"):format(current) .. " de " .. ("%d"):format(total)
end

function ReaderFooter:onHoldFooter(ges)
    -- We're higher priority than readerhighlight_hold, so, make sure we fall through properly...
    if not self.settings.skim_widget_on_hold then
        return
    end
    if not self.view.footer_visible then
        return
    end
    if not self.footer_content.dimen or not self.footer_content.dimen:contains(ges.pos) then
        -- We held outside the footer: meep!
        return
    end

    -- We're good, make sure we stop the event from going to readerhighlight_hold
    self.ui:handleEvent(Event:new("ShowSkimtoDialog"))
    return true
end

function ReaderFooter:refreshFooter(refresh, signal)
    self:updateFooterContainer()
    self:resetLayout(true)
    -- If we signal, the event we send will trigger a full repaint anyway, so we should be able to skip this one.
    -- We *do* need to ensure we at least re-compute the footer layout, though, especially when going from visible to invisible...
    self:onUpdateFooter(refresh and not signal, refresh and signal)
    if signal then
        if self.ui.document.provider == "crengine" then
            -- This will ultimately trigger an UpdatePos, hence a ReaderUI repaint.
            self.ui:handleEvent(Event:new("SetPageBottomMargin", self.ui.document.configurable.b_page_margin))
        else
            -- No fancy chain of events outside of CRe, just ask for a ReaderUI repaint ourselves ;).
            UIManager:setDirty(self.view.dialog, "partial")
        end
    end
end

function ReaderFooter:onResume()
    -- Reset the initial marker, if any
    if self.progress_bar.initial_pos_marker then
        self.initial_pageno = self.pageno
        self.progress_bar.initial_percentage = self.progress_bar.percentage
    end

    -- Don't repaint the footer until OutOfScreenSaver if screensaver_delay is enabled...
    local screensaver_delay = G_reader_settings:readSetting("screensaver_delay")
    if screensaver_delay and screensaver_delay ~= "disable" then
        self._delayed_screensaver = true
        return
    end

    -- Maybe perform a footer repaint on resume if it was visible.
    self:maybeUpdateFooter()
    self:rescheduleFooterAutoRefreshIfNeeded()
end

function ReaderFooter:onOutOfScreenSaver()
    if not self._delayed_screensaver then
        return
    end

    self._delayed_screensaver = nil
    -- Maybe perform a footer repaint on resume if it was visible.
    self:maybeUpdateFooter()
    self:rescheduleFooterAutoRefreshIfNeeded()
end

function ReaderFooter:onSuspend()
    self:unscheduleFooterAutoRefresh()
end

function ReaderFooter:onCloseDocument()
    self:unscheduleFooterAutoRefresh()
end

-- Used by event handlers that can trip without direct UI interaction...
function ReaderFooter:maybeUpdateFooter()
    -- ...so we need to avoid stomping over unsuspecting widgets (usually, ScreenSaver).
    self:onUpdateFooter(self:shouldBeRepainted())
end

function ReaderFooter:onFrontlightStateChanged()
    self:maybeUpdateFooter()
end
ReaderFooter.onCharging    = ReaderFooter.onFrontlightStateChanged
ReaderFooter.onNotCharging = ReaderFooter.onFrontlightStateChanged

function ReaderFooter:onNetworkConnected()
    if self.settings.wifi_status then
        self:maybeUpdateFooter()
    end
end
ReaderFooter.onNetworkDisconnected = ReaderFooter.onNetworkConnected

function ReaderFooter:onSwapPageTurnButtons()
    if self.settings.page_turning_inverted then
        -- We may receive the event *before* DeviceListener, so delay this to make sure it had a chance to actually swap the settings.
        -- Also delay it further to avoid screwing with TouchMenu highlights...
        UIManager:scheduleIn(0.5, self.maybeUpdateFooter, self)
    end
end
ReaderFooter.onToggleReadingOrder = ReaderFooter.onSwapPageTurnButtons

function ReaderFooter:onSetDimensions()
    self:updateFooterContainer()
    self:resetLayout(true)
end
ReaderFooter.onScreenResize = ReaderFooter.onSetDimensions

function ReaderFooter:onSetPageHorizMargins(h_margins)
    if self.settings.progress_margin then
        self.settings.progress_margin_width = math.floor((h_margins[1] + h_margins[2])/2)
        self:refreshFooter(true)
    end
end

function ReaderFooter:onTimeFormatChanged()
    self:refreshFooter(true, true)
end

function ReaderFooter:onBookMetadataChanged(prop_updated)
    if prop_updated and (prop_updated.metadata_key_updated == "title" or prop_updated.metadata_key_updated == "authors") then
        self:maybeUpdateFooter()
    end
end

function ReaderFooter:onRefreshAdditionalContent()
    if #self.additional_footer_content > 0 then
        -- Can be sent an any time, so we need to be careful about the repaint/refresh
        self:maybeUpdateFooter()
    end
end

function ReaderFooter:onCloseWidget()
    self:free()
end

function ReaderFooter:onSwitchStatusBarText()
    local text = ""
    self._show_just_toptextcontainer = not self._show_just_toptextcontainer
    if self.settings.disable_progress_bar and self.mode == 0 then
        -- text = "Status bar not on"
        -- UIManager:show(Notification:new{
        --     text = _(text),
        -- })
        -- return true
        self.view.footer_visible = true
    end

    -- if self._show_just_toptextcontainer then
    --     text = "Show just top text container. Toggle again to restore"
    --     -- self.height = Screen:scaleBySize(0) -- It was needed previously since we we were adding the text container instead of the footer container in updateFooterContainer()
    -- else
    --     text = "Status bar restored"
    --     self.height = Screen:scaleBySize(self.settings.container_height)
    -- end
    -- UIManager:show(Notification:new{
    --     text = _(text),
    --     my_height = Screen:scaleBySize(20),
    --     -- align = "left",
    --     -- timeout = 0.3,
    -- })
    UIManager:setDirty(self.dialog, "ui")
    self:refreshFooter(true, false) -- This uses _show_just_toptextcontainer
    self:onUpdateFooter(true, true) -- Importante pasar el segundo parámetro a true
    return true
end

function ReaderFooter:onMoveStatusBar()
    local text = ""
    if self.settings.bar_top then
        self.bottom_padding = self.old_bottom_padding
        --self.settings.container_bottom_padding = self.old_bottom_padding
        text = "status bar set to bottom"
        self.settings.progress_bar_position = "below"
    else
        self.old_bottom_padding = self.bottom_padding
        self.bottom_padding = 0
        --self.settings.container_bottom_padding = 0
        text = "status bar set to top"
        self.settings.progress_bar_position = "above"
    end

    self.settings.bar_top = not self.settings.bar_top

    -- It is important to pass the second parameter as true, so the function updatePos() in source readerrolling.lua will be executed performing a partial refresh
    -- And that's why it works
    -- self:refreshFooter(true, true)

    self:updateFooterContainer()
    self:resetLayout(true)
    UIManager:setDirty(nil, function()
        return self.view.currently_scrolling and "fast" or "ui", self.footer_content.dimen
    end)

    UIManager:setDirty(self.view.dialog, function()
        return self.view.currently_scrolling and "fast" or "ui"
    end)

    self:rescheduleFooterAutoRefreshIfNeeded()
    if self.settings.bar_top then
        UIManager:show(Notification:new{
            text = _(text),
            -- my_height = Screen:scaleBySize(30),
            -- align = "left",
            timeout = 0.3,
        })
    else
        UIManager:show(Notification:new{
            text = _(text),
        })
    end
    return true
end

return ReaderFooter
