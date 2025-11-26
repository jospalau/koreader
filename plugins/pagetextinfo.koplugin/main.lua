-- if true then
--     return { disabled = true, }
-- end

local BD = require("ui/bidi")
local CenterContainer = require("ui/widget/container/centercontainer")
local Dispatcher = require("dispatcher")  -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local InputContainer = require("ui/widget/container/inputcontainer")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local OverlapGroup = require("ui/widget/overlapgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local LineWidget = require("ui/widget/linewidget")
local Blitbuffer = require("ffi/blitbuffer")
local left_container = require("ui/widget/container/leftcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local TextViewer = require("ui/widget/textviewer")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local Screen = require("device").screen
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local Event = require("ui/event")
local ffiUtil = require("ffi/util")
local datetime = require("datetime")
local Device = require("device")
local ConfirmBox = require("ui/widget/confirmbox")
local logger = require("logger")
local util = require("util")
local SQ3 = require("lua-ljsqlite3/init")
local _ = require("gettext")
local T = require("ffi/util").template



local FileManager = require("apps/filemanager/filemanager")
local TitleBar = require("titlebar")
local FileChooser = require("ui/widget/filechooser")
local DocumentRegistry = require("document/documentregistry")
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local _FileManager_setupLayout_orig = FileManager.setupLayout
local _FileManager_updateTitleBarPath_orig = FileManager.updateTitleBarPath
local C_ = _.pgettext
local DocSettings = require("docsettings")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local FileManagerConverter = require("apps/filemanager/filemanagerconverter")
local ButtonDialog = require("ui/widget/buttondialog")
local BookList = require("ui/widget/booklist")

local PageTextInfo = InputContainer:extend{
    is_enabled = nil,
    name = "pagetextinfo",
    is_doc_only = false,
}

PageTextInfo.readability_table = dofile("plugins/pagetextinfo.koplugin/readability_table.lua")
PageTextInfo.genres_table = dofile("plugins/pagetextinfo.koplugin/genres_table.lua")

local function onFolderUp()
    if not (G_reader_settings:isTrue("lock_home_folder") and
        FileManager.instance.file_chooser.path == G_reader_settings:readSetting("home_dir")) then
            FileManager.instance.file_chooser:changeToPath(string.format("%s/..", FileManager.instance.file_chooser.path), FileManager.instance.file_chooser.path)
    end
end

function PageTextInfo:updateTitleBarPath(path)
    -- We dont need the original function
    -- We dont use that title bar and we dont use the subtitle
end

-- Same as in filemanager.lua but using the custom title bar widget
function PageTextInfo:setupLayout()
    self.show_parent = self.show_parent or self
    self.title_bar = TitleBar:new{
        show_parent = self.show_parent,
        fullscreen = "true",
        align = "center",
        title = "",
        title_top_padding = Screen:scaleBySize(6),
        subtitle = "",
        subtitle_truncate_left = true,
        subtitle_fullwidth = true,
        button_padding = Screen:scaleBySize(5),
        -- home
        left_icon = "home2",
        left_icon_size_ratio = 1,
        left_icon_tap_callback = function() self:onHome() end,
        left_icon_hold_callback = function() self:onShowFolderMenu() end,
        -- favorites
        left2_icon = "favorites",
        left2_icon_size_ratio = 1,
        left2_icon_tap_callback = function() FileManager.instance.collections:onShowCollList() end,
        left2_icon_hold_callback = function() FileManager.instance.folder_shortcuts:onShowFolderShortcutsDialog() end,
        -- history
        left3_icon = "history",
        left3_icon_size_ratio = 1,
        left3_icon_tap_callback = function() FileManager.instance.history:onShowHist() end,
        left3_icon_hold_callback = false,
        -- plus menu
        right_icon = self.selected_files and "check2" or "plus2",
        right_icon_size_ratio = 1,
        right_icon_tap_callback = function() self:onShowPlusMenu() end,
        right_icon_hold_callback = false, -- propagate long-press to dispatcher
        -- up folder
        right2_icon = "go_up",
        right2_icon_size_ratio = 1,
        right2_icon_tap_callback = function() onFolderUp() end,
        right2_icon_hold_callback = false,
        -- open last file
        right3_icon = "last_document",
        right3_icon_size_ratio = 1,
        right3_icon_tap_callback = function() FileManager.instance.menu:onOpenLastDoc() end,
        right3_icon_hold_callback = false,
        -- centered logo
        center_icon = "hero",
        center_icon_size_ratio = 1.25, -- larger "hero" size compared to rest of titlebar icons
        center_icon_tap_callback = false,
        center_icon_hold_callback = function()
            UIManager:show(InfoMessage:new{
                text = T(_("KOReader %1\nhttps://koreader.rocks\n\nProject Title v0.01\nhttps://projtitle.github.io\n\nLicensed under Affero GPL v3.\nAll dependencies are free software."), BD.ltr(Version:getShortVersion())),
                show_icon = false,
                alignment = "center",
            })
        end,
    }

    local file_chooser = FileChooser:new{
        name = "filemanager",
        path = self.root_path,
        focused_path = self.focused_file,
        show_parent = self.show_parent,
        file_filter = function(filename) return DocumentRegistry:hasProvider(filename) end,
        close_callback = function() return self:onClose() end,
        -- allow left bottom tap gesture, otherwise it is eaten by hidden return button
        return_arrow_propagation = true,
        -- allow Menu widget to delegate handling of some gestures to GestureManager
        ui = self,
        -- Tell FileChooser (i.e., Menu) to use our own title bar instead of Menu's default one
        custom_title_bar = self.title_bar,
    }
    self.file_chooser = file_chooser
    self.focused_file = nil -- use it only once

    local file_manager = self

    function file_chooser:onFileSelect(item)
        if file_manager.selected_files then -- toggle selection
            item.dim = not item.dim and true or nil
            file_manager.selected_files[item.path] = item.dim
            self:updateItems()
        else
            file_manager:openFile(item.path)
        end
        return true
    end

    function file_chooser:onFileHold(item)
        if file_manager.selected_files then
            file_manager:tapPlus()
        else
            self:showFileDialog(item)
        end
    end

    function file_chooser:showFileDialog(item)
        local file = item.path
        local is_file = item.is_file
        local is_not_parent_folder = not item.is_go_up

        local function close_dialog_callback()
            UIManager:close(self.file_dialog)
        end
        local function refresh_callback()
            self:refreshPath()
        end
        local function close_dialog_refresh_callback()
            UIManager:close(self.file_dialog)
            self:refreshPath()
        end

        local buttons = {
            {
                {
                    text = C_("File", "Copy"),
                    enabled = is_not_parent_folder,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:copyFile(file)
                    end,
                },
                {
                    text = C_("File", "Paste"),
                    enabled = file_manager.clipboard and true or false,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:pasteFileFromClipboard(file)
                    end,
                },
                {
                    text = _("Select"),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:onToggleSelectMode()
                        if is_file then
                            file_manager.selected_files[file] = true
                            item.dim = true
                            self:updateItems()
                        end
                    end,
                },
            },
            {
                {
                    text = _("Cut"),
                    enabled = is_not_parent_folder,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:cutFile(file)
                    end,
                },
                {
                    text = _("Delete"),
                    enabled = is_not_parent_folder,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:showDeleteFileDialog(file, refresh_callback)
                    end,
                },
                {
                    text = _("Rename"),
                    enabled = is_not_parent_folder,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:showRenameFileDialog(file, is_file)
                    end,
                }
            },
            {}, -- separator
        }

        local book_props
        if is_file then
            local has_provider = DocumentRegistry:hasProvider(file)
            local been_opened = BookList.hasBookBeenOpened(file)
            local doc_settings_or_file = file
            if has_provider or been_opened then
                book_props = file_manager.coverbrowser and file_manager.coverbrowser:getBookInfo(file)
                if been_opened then
                    doc_settings_or_file = BookList.getDocSettings(file)
                    if not book_props then
                        local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
                        local props = doc_settings_or_file:readSetting("doc_props")
                        book_props = FileManagerBookInfo.extendProps(props, file)
                        book_props.has_cover = true -- to enable "Book cover" button, we do not know if cover exists
                    end
                end
                table.insert(buttons, filemanagerutil.genStatusButtonsRow(doc_settings_or_file, close_dialog_refresh_callback))
                table.insert(buttons, {}) -- separator
                table.insert(buttons, {
                    filemanagerutil.genResetSettingsButton(doc_settings_or_file, close_dialog_refresh_callback),
                    file_manager.collections:genAddToCollectionButton(file, close_dialog_callback, refresh_callback),
                })
            end
            if Device:canExecuteScript(file) then
                table.insert(buttons, {
                    filemanagerutil.genExecuteScriptButton(file, close_dialog_callback),
                })
            end
            if FileManagerConverter:isSupported(file) then
                table.insert(buttons, {
                    FileManagerConverter:genConvertButton(file, close_dialog_callback, refresh_callback)
                })
            end
            table.insert(buttons, {
                {
                    text = _("Open with…"),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:showOpenWithDialog(file)
                    end,
                },
                filemanagerutil.genBookInformationButton(doc_settings_or_file, book_props, close_dialog_callback),
            })
            if has_provider then
                table.insert(buttons, {
                    filemanagerutil.genBookCoverButton(file, book_props, close_dialog_callback),
                    filemanagerutil.genBookDescriptionButton(file, book_props, close_dialog_callback),
                })
            end
        else -- folder
            local folder = ffiUtil.realpath(file)
            table.insert(buttons, {
                {
                    text = _("Set as HOME folder"),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:setHome(folder)
                    end
                },
            })
            table.insert(buttons, {
                file_manager.folder_shortcuts:genAddRemoveShortcutButton(folder, close_dialog_callback, refresh_callback)
            })
        end

        if file_manager.file_dialog_added_buttons ~= nil then
            for _, row_func in ipairs(file_manager.file_dialog_added_buttons) do
                local row = row_func(file, is_file, book_props)
                if row ~= nil then
                    table.insert(buttons, row)
                end
            end
        end

        local title = ""
        if is_file then
            title = BD.filename(file:match("([^/]+)$"))

            local extension = string.lower(string.match(title, ".+%.([^.]+)") or "")
            if extension == "epub" then
                title = title:gsub(".epub","")
            end
            if self.calibre_data[item.text] and self.calibre_data[item.text]["pubdate"]
                and self.calibre_data[item.text]["words"]
                and self.calibre_data[item.text]["grrating"]
                and self.calibre_data[item.text]["grvotes"] then
                    title = title .. ", " ..  self.calibre_data[item.text]["pubdate"]:sub(1, 4) ..
                    " - " .. self.calibre_data[item.text]["grrating"] .. "★ ("  ..
                    self.calibre_data[item.text]["grvotes"] .. ") - " ..
                    tostring(math.floor(self.calibre_data[item.text]["words"]/1000)) .."kw"
            end
        else
            title = BD.directory(file:match("([^/]+)$"))
        end

        self.file_dialog = ButtonDialog:new{
            title = title,
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(self.file_dialog)
        return true
    end

    local fm_ui = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        file_chooser,
    }

    self[1] = fm_ui

    self.menu = FileManagerMenu:new{
        ui = self
    }



    -- No need to reinvent the wheel, use FileChooser's layout
    self.layout = file_chooser.layout

    self:registerKeyEvents()
end

-- Since the real function setupLayout() is called in the file manager init() function before initializing plugins it won't work on start
-- With the emulator works because the environment variables EMULATE_READER_W and EMULATE_READER_H used when launching kodev trigger a resize in the window
-- To make it work, we have to call it again after initializing the plugins. We do it in the filemanager.lua source
-- Another option is to call self.ui:setupLayout() in the refreshFileManagerInstance() function of the main.lua source of the cover browser plugin
local settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/pagetextinfo.lua")
if settings:isTrue("enable_change_bar_menu") then
    FileManager.setupLayout = PageTextInfo.setupLayout
    FileManager.updateTitleBarPath = PageTextInfo.updateTitleBarPath
    FileManager.hooked_fmSetupLayout = true
end

function PageTextInfo:onDispatcherRegisterActions()
    Dispatcher:registerAction("pagetextinfo_action", {category="none", event="PageTextInfo", title=_("Page text info widget"), general=true,})

    -- open_random_favorite = {category="none", event="OpenRandomFav", title=_("Open random book MBR"), general=true},
    Dispatcher:registerAction("series", {category="none", event="ShowSeriesList", title=_("Series"), general=true,})
    Dispatcher:registerAction("generate_favorites", {category="none", event="GenerateFavorites", title=_("Generate favorites"), general=true,})
    Dispatcher:registerAction("filemanager_scripts", {category="none", event="Scripts", title=_("File browser scripts"), general=true, separator=true,})
    Dispatcher:registerAction("filemanager", {category="none", event="Home", title=_("File browser"), general=true,})
    Dispatcher:registerAction("notebook_file", {category="none", event="ShowNotebookFile", title=_("Notebook file"), general=true, separator=true,})
    Dispatcher:registerAction("text_properties", {category="none", event="ShowTextProperties", title=_("Show text properties"), general=true, separator=true,})
    Dispatcher:registerAction("random_profile", {category="none", event="RandomProfile", title=_("Random profile"), general=true, separator=true,})
    Dispatcher:registerAction("get_styles", {category="none", event="GetStyles", title=_("Get styles"), general=true, separator=true,})
    Dispatcher:registerAction("synchronize_code", {category="none", event="SynchronizeCode", title=_("Synchronize code"), general=true, separator=true,})
    Dispatcher:registerAction("synchronize_code_phone", {category="none", event="SynchronizeCodePhone", title=_("Synchronize code phone"), general=true, separator=true,})
    Dispatcher:registerAction("install_last_version", {category="none", event="InstallLastVersion", title=_("Install last KOReader version"), general=true, separator=true,})
    Dispatcher:registerAction("synchronize_statistics", {category="none", event="SynchronizeStatistics", title=_("Synchronize statistics script"), general=true, separator=true,})
    Dispatcher:registerAction("toggle_ssh", {category="none", event="ToggleSSH", title=_("Toggle SSH server"), general=true, separator=true,})
    Dispatcher:registerAction("get_tbr", {category="none", event="GetTBR", title=_("Get TBR"), general=true, separator=true,})
    Dispatcher:registerAction("sync_books", {category="none", event="SyncBooks", title=_("Synchronize Books"), general=true, separator=true,})
    Dispatcher:registerAction("get_text_page", {category="none", event="GetTextPage", title=_("Get text page"), general=true, separator=true,})
    Dispatcher:registerAction("pull_config", {category="none", event="PullConfig", title=_("Pull configuration"), general=true, separator=true,})
    Dispatcher:registerAction("push_config", {category="none", event="PushConfig", title=_("Push configuration"), general=true, separator=true,})
    Dispatcher:registerAction("get_last_pushing_config", {category="none", event="GetLastPushingConfig", title=_("Who pushed last config"), general=true, separator=true,})
    Dispatcher:registerAction("pull_sidecar_files", {category="none", event="PullSidecarFiles", title=_("Pull sidecar files"), general=true, separator=true,})
    Dispatcher:registerAction("push_sidecar_files", {category="none", event="PushSidecarFiles", title=_("Push sidecar files"), general=true, separator=true,})
    Dispatcher:registerAction("get_last_pushing_sidecars", {category="none", event="GetLastPushingSidecars", title=_("Who pushed last sidecars"), general=true, separator=true,})
    Dispatcher:registerAction("wifi_on_kindle", {category="none", event="TurnOnWifiKindle", title=_("Turn on Wi-Fi Kindle"), general=true, separator=true,})
    Dispatcher:registerAction("print_chapter_left_fbink", {category="none", event="PrintChapterLeftFbink", title=_("Print chapter left Fbink"), general=true, separator=true,})
    Dispatcher:registerAction("print_session_duration_fbink", {category="none", event="PrintSessionDurationFbink", title=_("Print session duration Fbink"), general=true, separator=true,})
    Dispatcher:registerAction("print_progress_book_fbink", {category="none", event="PrintProgressBookFbink", title=_("Print progress book Fbink"), general=true, separator=true,})
    Dispatcher:registerAction("print_clock_fbink", {category="none", event="PrintClockFbink", title=_("Print clock Fbink"), general=true, separator=true,})
    Dispatcher:registerAction("print_duration_chapter_fbink", {category="none", event="PrintDurationChapterFbink", title=_("Print duration chapter Fbink"), general=true, separator=true,})
    Dispatcher:registerAction("print_duration_next_chapter_fbink", {category="none", event="PrintDurationNextChapterFbink", title=_("Print duration next chapter Fbink"), general=true, separator=true,})
    Dispatcher:registerAction("toggle_rsyncd", {category="none", event="ToggleRsyncdService", title=_("Toggle Rsyncd service"), general=true, separator=true,})
    Dispatcher:registerAction("print_wpm_session_fbink", {category="none", event="PrintWpmSessionFbink", title=_("Print wpm session Fbink"), general=true, separator=true,})
    Dispatcher:registerAction("show_db_stats", {category="none", event="ShowDbStats", title=_("Show db stats"), general=true, separator=true,})
    Dispatcher:registerAction("move_status_bar", {category="none", event="MoveStatusBar", title=_("Move status bar"), general=true, separator=true,})
    Dispatcher:registerAction("switch_status_bar_text", {category="none", event="SwitchStatusBarText", title=_("Switch status bar text"), general=true, separator=true,})
    Dispatcher:registerAction("switch_top_bar", {category="none", event="SwitchTopBar", title=_("Switch top bar"), general=true, separator=true,})
    Dispatcher:registerAction("test", {category="none", event="Test", title=_("Test"), general=true, separator=true,})
    Dispatcher:registerAction("toggle_horizontal_vertical", {category="none", event="ToggleHorizontalVertical", title=_("Toggle screen layout"), general=true, separator=true,})
    Dispatcher:registerAction("search_dictionary", {category="none", event="SearchDictionary", title=_("Search dictionary"), general=true, separator=true,})
    Dispatcher:registerAction("show_heatmap", {category="none", event="ShowHeatmapView", title=_("Show heatmap"), general=true, separator=true,})
    Dispatcher:registerAction("show_general_stats", {category="none", event="ShowGeneralStats", title=_("Show general stats"), general=true, separator=true,})
    Dispatcher:registerAction("adjust_margins_topbar", {category="none", event="AdjustMarginsTopbar", title=_("Adjust margins topbar"), general=true, separator=true,})
    Dispatcher:registerAction("show_notes_footer", {category="none", event="ShowNotesFooter", title=_("Show notes on footer"), general=true, separator=true,})
    Dispatcher:registerAction("file_search", {category="none", event="ShowFileSearch", title=_("File search"), filemanager=true, separator=true,})
    Dispatcher:registerAction("file_search_all", {category="none", event="ShowFileSearchLists", title=_("File search all"), filemanager=true, separator=true,})
    Dispatcher:registerAction("file_search_all_recent", {category="none", event="ShowFileSearchLists", arg={recent = true}, title=_("File search all recent"), filemanager=true, separator=true,})
    Dispatcher:registerAction("file_search_all_completed", {category="none", event="ShowFileSearchAllCompleted", title=_("File search all recent"), filemanager=true, separator=true,})
    Dispatcher:registerAction("mbr", {category="none", event="ShowHistMBR", title=_("MBR"), general=true,})
    Dispatcher:registerAction("tbr", {category="none", event="ShowHistTBR", title=_("TBR"), general=true,})
    Dispatcher:registerAction("toggle_status_bar", {category="none", event="ToggleFooterMode", title=_("Toggle status bar cycle"), reader=true,})
    Dispatcher:registerAction("toggle_status_bar_back", {category="none", event="ToggleFooterModeBack", title=_("Toggle status bar cycle back"), reader=true,})
    Dispatcher:registerAction("toggle_status_bar_onoff", {category="none", event="ToggleStatusBarOnOff", title=_("Toggle status bar on/off"), reader=true,})
    Dispatcher:registerAction("status_bar_just_progress_bar", {category="none", event="StatusBarJustProgressBar", title=_("Status bar just progress bar"), reader=true, separator=true,})
    Dispatcher:registerAction("toggle_reclaim_height", {category="none", event="ToggleReclaimHeight", title=_("Toggle reclaim height"), reader=true,})
    Dispatcher:registerAction("toggle_hyphenation", {category="none", event="ToggleHyphenation", title=_("Toggle hyphenation"), reader=true, separator=true,})
    Dispatcher:registerAction("increase_weight", {category="none", event="IncreaseWeightSize", title=_("Increase weight size"), rolling=true,})
    Dispatcher:registerAction("decrease_weight", {category="none", event="DecreaseWeightSize", title=_("Decrease weight size"), rolling=true,})
    Dispatcher:registerAction("toggle_sort_by_mode", {category="none", event="ToggleSortByMode", title=_("Toggle sort by mode"), general=true,})
    Dispatcher:registerAction("toggle_double_bar", {category="none", event="ToggleDoubleBar", title=_("Toggle double bar"), reader=true, separator=true,})
    Dispatcher:registerAction("notebook_file_render", {category="none", event="ShowNotebookFileRender", title=_("Notebook file render"), general=true,})
end

function PageTextInfo:onPageTextInfo()
    self.is_enabled = not self.is_enabled
    self.settings:saveSetting("is_enabled", self.is_enabled)
    self.settings:flush()
    if self.is_enabled then
        local Screen = require("device").screen
        self:paintTo(Screen.bb, 0, 0)
    end
    UIManager:setDirty("all", "ui")
    -- local popup = InfoMessage:new{
    --     text = _("Test"),
    -- }
    -- UIManager:show(popup)
end

function PageTextInfo:initGesListener()
    if not Device:isTouchDevice() then return end
    self.ui:registerTouchZones({
        {
            id = "pagetextinfo_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            overrides = {
                "readerconfigmenu_tap",
                "readerhighlight_tap_select_mode",
            },
            handler = function(ges) return self:onTap(nil, ges) end,
        },
        {
            id = "pagetextinfo_double_tap",
            ges = "double_tap",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onDoubleTap(nil, ges) end,
        },
        {
            id = "pagetextinfo_swipe",
            ges = "swipe",
            overrides = {
                "rolling_swipe",
                "paging_swipe",
            },
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onSwipe(nil, ges) end,
        },
    })
end

function PageTextInfo:toggleHighlightAllWordsVocabulary(toggle)
    self.settings:saveSetting("highlight_all_words_vocabulary_builder_and_notes", toggle)
    self.settings:flush()
    if toggle then
        self:updateWordsVocabulary()
        self:updateNotes()
    end
    self.view.topbar:toggleBar()
    self.view.doublebar:toggleBar()
    UIManager:setDirty(self.view.dialog, "ui")
    return true
end

local RulerOverlay = InputContainer:extend{
    name = "RulerOverlay",
}

function RulerOverlay:init()
    local GestureRange = require("ui/gesturerange")
    local ImageWidget = require("ui/widget/imagewidget")
    local widget_settings = {
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        x = 1000,
        y = 1000,
        alpha = 0 -- transparency (0.0 = fully transparent, 1.0 = opaque)
    }

    self.ges_events = {
        TapRuler = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
        SwipeRuler = {
            GestureRange:new{
                ges = "swipe",
                range = self.dimen,
            },
        },
    }
    -- widget_settings.image_disposable = true
    if Device.model == "Kobo_spaBW" or Device.model == "Kobo_goldfinch" or Device.model == "Kobo_spaColour" then
        widget_settings.file = "resources/rulerKoboClaraBW.png" -- 1072x1448
    else
        widget_settings.file = "resources/rulerEmulator.png" -- 1040x1190
    end


    -- widget_settings.file_do_cache = false
    widget_settings.alpha = true


    self.ruler_widget = ImageWidget:new(widget_settings)
    self.pos_x = 0
    self.pos_y = 0
    self.last_pos_x = -1
end

function RulerOverlay:onTapRuler(arg, ges_ev)
    -- UIManager:close(self.ruler_widget)
    -- UIManager:close(self)
    -- local ruler_overlay = RulerOverlay:new()
    -- UIManager:show(ruler_overlay.ruler_widget)
    if self.tapped == nil or self.tapped == false then
        local ruler = self.ruler_widget
        UIManager:setDirty(require("apps/reader/readerui").instance.view.dialog, "ui")
        -- UIManager:show(ruler_overlay)
        self.tapped = true
        self.pos_x = ges_ev.pos.x
        self.pos_y = ges_ev.pos.y
        UIManager:scheduleIn(0.5, function()
            ruler:paintTo(Screen.bb, ges_ev.pos.x - Screen:getWidth() / 2, ges_ev.pos.y)
            UIManager:setDirty(nil, "ui")
            self.tapped = false
        end)
    end

    return true -- event handled
end

function RulerOverlay:onSwipeRuler(arg, ges_ev)
    UIManager:close(self.ruler_widget)
    UIManager:close(self)
    return true -- event handled
end

function RulerOverlay:onSuspend()
    --UIManager:close(self.ruler_widget)
    --UIManager:close(self)
    return true
end

function RulerOverlay:onResume()
    UIManager:scheduleIn(1, function()
        if self.pos_x > 0 and self.pos_x ~= self.last_pos_x then self.pos_x = self.pos_x - Screen:getWidth() / 2 end
        self.last_pos_x = self.pos_x
        self.ruler_widget:paintTo(Screen.bb, self.pos_x, self.pos_y)
        UIManager:setDirty(nil, "ui")
    end)
    return true
end

function PageTextInfo:onSwipe(_, ges)
    if not self.initialized then return end
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if direction == "west" then
        self.ui.gestures:onIgnoreHoldCorners(true)
        if self.settings:readSetting("highlight_all_words_vocabulary_builder_and_notes") then
            Device.input.disable_double_tap = false
            self.ui.gestures:onIgnoreHoldCorners(false)
            self.view.topbar:toggleBar()
            self.view.doublebar:toggleBar()
            UIManager:setDirty(self.view.dialog, "ui")
            return self:toggleHighlightAllWordsVocabulary(not self.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes"))
        elseif not self.ui.disable_double_tap then
            self.ui.disable_double_tap = true
            -- We need also to change this, otherwise the toggle does not work just with self.ui.disable_double_tap
            Device.input.disable_double_tap = self.ui.disable_double_tap
            self.settings:saveSetting("highlight_all_words_vocabulary_builder_and_notes", false)
            self.view.topbar:toggleBar()
            self.view.doublebar:toggleBar()
            UIManager:setDirty(self.view.dialog, "ui")
        elseif self.ui.disable_double_tap then
            self.ui.disable_double_tap = false
            -- We need also to change this, otherwise the toggle does not work just with self.ui.disable_double_tap
            Device.input.disable_double_tap = self.ui.disable_double_tap
            return self:toggleHighlightAllWordsVocabulary(not self.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes"))
        else
            self.settings:saveSetting("highlight_all_words_vocabulary_builder_and_notes", false)
            self.ui.disable_double_tap = true
            self.view.topbar:toggleBar()
            self.view.doublebar:toggleBar()
            UIManager:setDirty(self.view.dialog, "ui")
        end
    elseif direction == "north" then
        if self.view.topbar.is_enabled == nil or self.view.topbar.is_enabled == false then
            self.view.topbar:quickToggleOnOff(true)
        else
            self.view.topbar:quickToggleOnOff(false)
        end
    elseif direction == "south" then

        if self.settings:isTrue("enable_ruler") and
            (Device:isEmulator() or Device.model == "Kobo_spaBW" or Device.model == "Kobo_goldfinch" or Device.model == "Kobo_spaColour") then
            local ruler_overlay = RulerOverlay:new()
            -- UIManager:show(ruler_overlay.ruler_widget)
            ruler_overlay.ruler_widget:paintTo(Screen.bb, 0, 0)
            UIManager:show(ruler_overlay)
        end
    elseif direction == "east" then
        -- local doc_settings = DocSettings:open(doc_path)
        local reference_page = self.ui.doc_settings:readSetting("reference_page_xpointer")
        if not reference_page then
            local xp = self.ui.document:getXPointer()
            self.ui.doc_settings:saveSetting("reference_page_xpointer", xp)
            self.ui.doc_settings:flush()
        else
            local pageno = self.ui.document:getPageFromXPointer(reference_page)
            local pageno_label = self.ui.pagemap:getXPointerPageLabel(reference_page)
            local toc_title = self.ui.toc:getTocTitleByPage(pageno)
            local _ = require("gettext")
            local MultiConfirmBox = require("ui/widget/multiconfirmbox")
            UIManager:show(MultiConfirmBox:new{
                text = _("Already set inside chapter " .. toc_title .. ", do you want to reset it to this page?"),
                choice1_text = _("Yes"),
                choice1_callback = function()
                    local xp = self.ui.document:getXPointer()
                    self.ui.doc_settings:saveSetting("reference_page_xpointer", xp)
                    self.ui.doc_settings:flush()
                    return true
                end,
                choice2_text = _("Take me"),
                choice2_callback = function()
                    self.ui.pagemap.ui.link:addCurrentLocationToStack()
                    self.ui.rolling:onGotoXPointer(reference_page)
                    return true
                end,
            })
        end
        return
    end
    return false
end

-- In order for double tap events to arrive we need to configure the gestures plugin:
-- Menu gear icon - Taps and gestures - Gesture manager - Double tap and we set Left side and Right side to Pass through clearing the default actions

-- Originally, the OnDoubleTap() event handler function was readerrolling but it was not working because I was using a dispatcher action (defined now in this plugin)
-- configured for the left and right side double taps events of the gesture plugin

-- Original comment:
-- This won't work but I leave it as it is because I set the double tap gesture ready in this source in case we want to do something else with this or other gestures in the future
-- Instead, we are using a SearchDictionary event defined in the source dispatcher.lua with a corresponding action named Search dictionary
-- This Search dictionary action is assigned to double tap in both Left side and Right side in the Taps and gestures configuration instead of Turn pages with a value of 10 which is the default
-- The event is captured in the source readerui.lua and it is exactly the same as this, we turn 10 or -10 pages if we double tap on the right or left sides, or we call the dictionary if we double tap any other place
-- If we want to use this handler for the gesture, we have to set Pass through for both Left side and Right side in the Taps and gestures configuration
-- For the hold action press modification, I modified the readerhighlight.lua source which is capturing the hold event
function PageTextInfo:onDoubleTap(_, ges)
    if not self.initialized then return end
    if util.getFileNameSuffix(self.ui.document.file) ~= "epub"  then return end
    local res = self.ui.document._document:getTextFromPositions(ges.pos.x, ges.pos.y,
                ges.pos.x, ges.pos.y, false, false)
    if ges.pos.x < Screen:scaleBySize(40) and not G_reader_settings:isTrue("ignore_hold_corners") then
        self.ui.rolling:onGotoViewRel(-10)
    elseif ges.pos.x > Screen:getWidth() - Screen:scaleBySize(40) and not G_reader_settings:isTrue("ignore_hold_corners") then
        self.ui.rolling:onGotoViewRel(10)
    else
        if res and res.text then
            local words = util.splitToWords2(res.text)
            if #words == 1 then
                local boxes = self.ui.document:getScreenBoxesFromPositions(res.pos0, res.pos1, true)
                if boxes ~= nil then
                    self.ui.dictionary:onLookupWord(util.cleanupSelectedText(res.text), false, boxes, nil, nil, function()
                        if self.settings:isTrue("enable_extra_refreshes") then
                            UIManager:setDirty(nil, "full")
                        end
                    end)
                    -- self:handleEvent(Event:new("LookupWord", util.cleanupSelectedText(res.text)))
                end

            end
        end
    end
end

local function inside_box(pos, box)
    if pos then
        local x, y = pos.x, pos.y
        if box.x <= x and box.y <= y
            and box.x + box.w >= x
            and box.y + box.h >= y then
            return true
        end
    end
end


-- If no argument, the call is coming from a new entry Notes added in the readerhighlight.lua source
-- to show possible notes associate to a word
function PageTextInfo:showNote(text_note)
    if text_note then
        -- local text = ""
        -- local annotations = self.ui.annotation.annotations
        -- for i, item in ipairs(annotations) do
        --     if item.note and item.text:upper() == text_note:upper() then
        --         text = text .. '<p style="display:block;font-size:1.25em;">' .. item.note .. "</p>"
        --     end
        -- end
        -- local FootnoteWidget = require("ui/widget/footnotewidget")
        -- local popup
        -- popup = FootnoteWidget:new{
        --     html = text,
        --     doc_font_name = self.ui.font.font_face,
        --     doc_font_size = Screen:scaleBySize(self.document.configurable.font_size),
        --     doc_margins = self.document:getPageMargins(),
        --     follow_callback = function() -- follow the link on swipe west
        --         UIManager:close(popup)
        --     end,
        --     dialog = self.dialog,
        -- }
        -- UIManager:show(popup)
        -- return true

        local annotations = self.ui.annotation.annotations
        for i, item in ipairs(annotations) do
            if item.note and item.text:upper() == text_note:upper() then
                local bookmark_note = item.note
                local index = i
                local textviewer
                textviewer = TextViewer:new{
                    title = _("Note"),
                    show_menu = false,
                    text = bookmark_note,
                    width = math.floor(math.min(self.ui.highlight.screen_w, self.ui.highlight.screen_h) * 0.8),
                    height = math.floor(math.max(self.ui.highlight.screen_w, self.ui.highlight.screen_h) * 0.4),
                    anchor = function()
                        return self.ui.highlight:_getDialogAnchor(textviewer, index)
                    end,
                    buttons_table = {
                        {
                            {
                                text = _("Delete note"),
                                callback = function()
                                    UIManager:close(textviewer)
                                    local annotation = self.ui.annotation.annotations[index]
                                    annotation.note = nil
                                    self.ui:handleEvent(Event:new("AnnotationsModified",
                                            { annotation, nb_highlights_added = 1, nb_notes_added = -1 }))
                                            self.ui.highlight:writePdfAnnotation("content", annotation, nil)
                                    if self.view.highlight.note_mark then -- refresh note marker
                                        UIManager:setDirty(self.dialog, "ui")
                                    end
                                    if self.settings:isTrue("highlight_all_notes_and_allow_to_edit_them_on_tap") or self.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") then
                                        self:updateNotes()
                                        UIManager:setDirty("all", "full")
                                    end
                                end,
                            },
                            {
                                text = _("Edit note"),
                                callback = function()
                                    UIManager:close(textviewer)
                                    self.ui.highlight:editNote(index)
                                end,
                            },
                        },
                        {
                            {
                                text = _("Delete highlight"),
                                callback = function()
                                    UIManager:close(textviewer)
                                    self.ui.highlight:deleteHighlight(index)
                                end,
                            },
                            {
                                text = _("Highlight menu"),
                                callback = function()
                                    UIManager:close(textviewer)
                                    self.ui.highlight:showHighlightDialog(index)
                                end,
                            },
                        },
                    },
                }
                UIManager:show(textviewer)
                return true
            end
        end
    end

    local text = nil
    local annotations = self.ui.annotation.annotations
    for i, item in ipairs(annotations) do
        if item.text == self.ui.highlight.selected_text.text then
            text = item.note
        end
    end
    if self.ui.highlight.highlight_dialog then
        UIManager:close(self.ui.highlight.highlight_dialog)
    end
    local FootnoteWidget = require("ui/widget/footnotewidget")
    local popup = nil
    if text then
        text = '<p style="display:block;font-size:1.25em;">' .. text .. "</p>"
        --if true then
            --UIManager:show( require("ui/widget/textviewer"):new{text = text})
        --end
        popup = FootnoteWidget:new{
            html = text,
            doc_font_name = self.ui.font.font_face,
            doc_font_size = Screen:scaleBySize(self.document.configurable.font_size),
            doc_margins = self.document:getPageMargins(),
            follow_callback = function() -- follow the link on swipe west
                UIManager:close(popup)
            end,
            dialog = self.dialog,
        }
    else
        popup = FootnoteWidget:new{
            html = "No notes",
            doc_font_name = self.ui.font.font_face,
            doc_font_size = Screen:scaleBySize(self.document.configurable.font_size),
            doc_margins = self.document:getPageMargins(),
            follow_callback = function() -- follow the link on swipe west
                UIManager:close(popup)
            end,
            dialog = self.dialog,
        }
        -- local UIManager = require("ui/uimanager")
        -- local Notification = require("ui/widget/notification")
        -- UIManager:show(Notification:new{
        --     text = _("No note"),
        -- })
    end
    UIManager:show(popup)
    self.ui.highlight:clear()
    return false
end


-- If highlight all notes is not activated
-- or there is not any annotation associated to the word
-- The event will be passed returning false

-- To be able to perform just our tap action when tapping a word with annotation
-- avoiding the tap action of the highlight modules to be fired
-- we need to set readerhighlight_tap_select_mode
-- in the overrides property of the tap touch zone definition
-- but, we still can invoke the highlight tap event returning false

-- In any case, when highlight all notes is activated
-- this plugin will manage what to do when tapping a notes
-- which basically is to show all the notes associated to a word having one or more note
function PageTextInfo:onTap(_, ges)
    if not self.initialized then return end
    if util.getFileNameSuffix(self.ui.document.file) ~= "epub"  then return false end
    local res = self.ui.document._document:getTextFromPositions(ges.pos.x, ges.pos.y,
                ges.pos.x, ges.pos.y, false, false)
    if self.settings:isTrue("highlight_all_notes_and_allow_to_edit_them_on_tap") then
        if ges and ges.pos then
            local pos = self.view:screenToPageTransform(ges.pos)
            if self.pages_notes[self.view.state.page] then
                for _, item in ipairs(self.pages_notes[self.view.state.page]) do
                    local boxes = self.ui.document:getScreenBoxesFromPositions(item.start, item["end"], true)
                    if boxes then
                        for _, box in ipairs(boxes) do
                            if inside_box(pos, box) then
                                -- local UIManager = require("ui/uimanager")
                                -- local Notification = require("ui/widget/notification")
                                -- UIManager:show(Notification:new{
                                -- text =("searching"),
                                -- })
                                -- local dump = require("dump")
                                -- print(dump(item))
                                local word = self.document:getWordFromPosition(box, true)
                                return self:showNote(word.word)
                            end
                        end
                    end
                end
            end
        end
    end
    return false -- Pass the event
end

function PageTextInfo:init()
    -- UIManager:scheduleIn(2, function()
    --     FileManager.instance:setupLayout()
    -- end)
    if not self.settings then self:readSettingsFile() end
    self.is_enabled = self.settings:isTrue("is_enabled")
    self.translations = {}
    -- if PageTextInfo.preserved_hightlight_all_notes then
    --     self.settings:saveSetting("highlight_all_notes", PageTextInfo.preserved_hightlight_all_notes)
    --     PageTextInfo.preserved_hightlight_all_notes = nil
    --     self.settings:flush()
    -- end

    -- if PageTextInfo.preserved_highlight_all_words_vocabulary then
    --     self.settings:saveSetting("highlight_all_words_vocabulary",  PageTextInfo.preserved_highlight_all_words_vocabulary)
    --     PageTextInfo.preserved_highlight_all_words_vocabulary = nil
    --     self.settings:flush()
    -- end




    -- if not self.is_enabled then
    --     return
    -- end
    self:onDispatcherRegisterActions()
    self:initGesListener()

    -- We call the function registerToMainMenu() here if we want the menu entry to be shown both for the fm and the reader top menus
    -- If we want the menu entry to be shown just for the reader like in this plugin, better to call it in the onReaderReady() event handler function
    -- In both cases we need to define the function PageTextInfo:addToMainMenu() with the custom menu items
    -- and configure them in a proper menu section adding the name given to the menu items (menu_items.pagetextinfo)
    -- in the filemanager_menu_order.lua source for the fm or in the reader_menu_order.lua source for the reader
    self.ui.menu:registerToMainMenu(self)

    -- Not needed since it is automatically available
    -- self.ui.pagetextinfo = self

    self.width = 400
    self.height = 20

    self.vg1 = VerticalGroup:new{
        left_container:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            TextWidget:new{
                text =  "",
                face = Font:getFace("myfont4"),
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        },
        VerticalSpan:new{width = self.height},
        left_container:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            TextWidget:new{
                text =  "",
                face = Font:getFace("myfont4"),
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        },
        VerticalSpan:new{width = self.height},
        left_container:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            TextWidget:new{
                text =  "",
                face = Font:getFace("myfont4"),
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        },
    }

    self.f1 = FrameContainer:new{
        self.vg1,
        background = Blitbuffer.COLOR_WHITE,
        padding = self.height,
        bordersize = 0,
    }

    self.vg2 = VerticalGroup:new{
        left_container:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            TextWidget:new{
                text =  "",
                face = Font:getFace("myfont4"),
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        },
        VerticalSpan:new{width = self.height},
        left_container:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            TextWidget:new{
                text =  "",
                face = Font:getFace("myfont4"),
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        },
        VerticalSpan:new{width = self.height},
        left_container:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            TextWidget:new{
                text =  "",
                face = Font:getFace("myfont4"),
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        }
    }

    self.f2 = FrameContainer:new{
        self.vg2,
        background = Blitbuffer.COLOR_WHITE,
        padding = self.height,
        bordersize = 0,
    }
    -- self.f1 = FrameContainer:new{
    --     left_container:new{
    --         dimen = Geom:new{ w = 80, h = 80 },
    --         self.test,
    --     },
    --     background = Blitbuffer.COLOR_WHITE,
    --     bordersize = 0,
    --     padding = 0,
    --     padding_bottom = self.bottom_padding,
    -- }
    -- self.f2 = FrameContainer:new{
    --     left_container:new{
    --         dimen = Geom:new{ w = 80, h = 80 },
    --         self.test,
    --     },
    --     background = Blitbuffer.COLOR_WHITE,
    --     bordersize = 0,
    --     padding = 0,
    --     padding_bottom = self.bottom_padding,
    -- }


    -- self.f1 = FrameContainer:new{
    --     left_container:new{
    --         dimen = Geom:new{ w = 80, h = 80 },
    --         self.test,
    --     },
    --     background = Blitbuffer.COLOR_WHITE,
    --     bordersize = 0,
    --     padding = 0,
    --     padding_bottom = self.bottom_padding,
    -- }
    -- self.f2 = FrameContainer:new{
    --     left_container:new{
    --         dimen = Geom:new{ w = 80, h = 80 },
    --         self.test,
    --     },
    --     background = Blitbuffer.COLOR_WHITE,
    --     bordersize = 0,
    --     padding = 0,
    --     padding_bottom = self.bottom_padding,
    -- }

    -- self.vertical_frame = VerticalGroup:new{
    --     FrameContainer:new{
    --         left_container:new{
    --             dimen = Geom:new{ w = 80, h = 80 },
    --             self.test,
    --         },
    --         left_container:new{
    --             dimen = Geom:new{ w = 80, h = 80 },
    --             self.test2,
    --         },
    --         background = Blitbuffer.COLOR_WHITE,
    --         bordersize = 0,
    --         padding = 0,
    --         padding_bottom = self.bottom_padding,
    --     },
    -- }
    self.vertical_frame = VerticalGroup:new{}
    table.insert(self.vertical_frame, self.f1)
    table.insert(self.vertical_frame, self.f2)
    -- local vertical_span = VerticalSpan:new{width = Size.span.vertical_default}
    -- table.insert(self.vertical_frame, self.separator_line)
    -- table.insert(self.vertical_frame, vertical_span)
    self.pages_notes = {}
    self.initialized = false
    -- self.ui:registerPostInitCallback(function()
    --     self:_postInit()
    -- end)
    self.server = self.settings:readSetting("server", "192.168.50.252")
    self.port = self.settings:readSetting("server_port","5000")
    if self.ui.highlight then
        self.ui.highlight._highlight_buttons["14_get_mood"] = function(this)
            return {
                text = _("Get mood"),
                enabled = this.hold_pos ~= nil and this.selected_text ~= nil and this.selected_text.text ~= "",
                is_quickmenu_button = true, -- To make it flash
                callback = function()
                    UIManager:scheduleIn(0, function()
                        self.ui.pagetextinfo:sendHighlightToServerForMood()
                    end)
                end,
            }
        end
        self.ui.highlight._highlight_buttons["15_get_heatmap"] = function(this)
            return {
                text = _("Get heatmap"),
                enabled = this.hold_pos ~= nil and this.selected_text ~= nil and this.selected_text.text ~= "",
                is_quickmenu_button = true, -- To make it flash
                callback = function()
                    UIManager:scheduleIn(0, function()
                        self.ui.pagetextinfo:sendHighlightToServerForHeatmap()
                    end)
                end,
            }
        end
    end
end

-- function PageTextInfo:_postInit()
--     self.initialized = true
-- end

function PageTextInfo:readSettingsFile()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/pagetextinfo.lua")
end

function PageTextInfo:onReaderReady()
    -- self.ui.menu:registerToMainMenu(self)
    self.view:registerViewModule("pagetextinfo", self)
    self.initialized = true


    -- This is just for Android devices, at least the Boox Palma
    -- We have self.ui.gestures.ignore_hold_corners == true
    -- We exit from KOReader and for some reason KOReader is stopped or we stop it
    -- When we come back to KOReader and we open a document, the top bar lock icon is on
    -- because self.ui.gestures.ignore_hold_corners is still true so we set it always to be false when opening the document
    if Device:isAndroid() then
        self.ui.gestures:onIgnoreHoldCorners(false)
    end
    -- self.insertSession = function()
    --     if self.ui.statistics then
    --         if self.ui.statistics:insertSession() and self.view.topbar.is_enabled then
    --             self.view.topbar:resetSession()
    --             self.view.topbar:toggleBar()
    --             UIManager:setDirty(self.view.dialog, "ui")
    --         end
    --     end
    --     UIManager:scheduleIn(600, self.insertSession)
    -- end
    -- UIManager:unschedule(self.insertSession)
    -- UIManager:scheduleIn(600, self.insertSession)
end


function PageTextInfo:onPageUpdate(pageno)
    -- Avoid double execution when loading document
    if not self.initialized then return end

    if self.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") and not self.ui.searching and util.getFileNameSuffix(self.ui.document.file) == "epub" then
        self:updateWordsVocabulary()
    end
    if (self.settings:isTrue("highlight_all_notes_and_allow_to_edit_them_on_tap") or self.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes")) and not self.ui.searching and util.getFileNameSuffix(self.ui.document.file) == "epub" then
        self:updateNotes()
    end
end


-- function PageTextInfo:addToMainMenu(menu_items)
--     menu_items.hello_world = {
--         text = _("Hello World"),
--         -- in which menu this should be appended
--         sorting_hint = "more_tools",
--         -- a callback when tapping
--         callback = function()
--             UIManager:show(InfoMessage:new{
--                 text = _("Hello, plugin world"),
--             })
--         end,
--     }
-- end
local function getIfosInDir(path)
    -- Get all the .ifo under directory path.
    -- Don't walk into "res/" subdirectories, as per Stardict specs, they
    -- may contain possibly many resource files (image, audio files...)
    -- that could slow down our walk here.
    local ifos = {}
    local ok, iter, dir_obj = pcall(lfs.dir, path)
    if ok then
        for name in iter, dir_obj do
            if name ~= "." and name ~= ".." and name ~= "res" then
                local fullpath = path.."/"..name
                local attributes = lfs.attributes(fullpath)
                if attributes ~= nil then
                    if attributes.mode == "directory" then
                        local dirifos = getIfosInDir(fullpath) -- recurse
                        for _, ifo in pairs(dirifos) do
                            table.insert(ifos, ifo)
                        end
                    elseif fullpath:match("%.ifo$") then
                        table.insert(ifos, fullpath)
                    end
                end
            end
        end
    end
    return ifos
end

function PageTextInfo:addToMainMenu(menu_items)
    -- If we don't want this being called for the filemanager, better to call self.ui.menu:registerToMainMenu(self) in the onReaderReady() event handler function
    -- Although we can set in the init() function and skip it like this:
    local FileManager = require("apps/filemanager/filemanager")
    if FileManager.instance then
        menu_items.pagetextinfo = {
            text = _("Page text info"),
            sub_item_table ={
                {
                    text = _("Change bar menu"),
                    checked_func = function() return self.settings:isTrue("enable_change_bar_menu") end,
                    callback = function(touchmenu_instance)
                        local enable_change_bar_menu = not self.settings:isTrue("enable_change_bar_menu")
                        self.settings:saveSetting("enable_change_bar_menu", enable_change_bar_menu)
                        FileManager.hooked_fmSetupLayout = enable_change_bar_menu
                        FileManager.setupLayout = PageTextInfo.setupLayout
                        FileManager.updateTitleBarPath = PageTextInfo.updateTitleBarPath
                        if enable_change_bar_menu then
                            FileManager.setupLayout = FileManager.setupLayout
                            FileManager.updateTitleBarPath = FileManager.updateTitleBarPath
                        else
                            FileManager.setupLayout = _FileManager_setupLayout_orig
                            FileManager.updateTitleBarPath = _FileManager_updateTitleBarPath_orig
                        end
                        -- local ok, err = pcall(dofile, "plugins/pagetextinfo.koplugin/patch.lua")
                        --FileManager.instance:setupLayout()
                        --FileManager.instance:updateTitleBarTitle(true)
                        self.settings:flush()
                        --FileManager:onClose() -- No need to close. The instance will be closed whe calling the showFiles() function
                        local path = FileManager.instance.file_chooser.path
                        touchmenu_instance:closeMenu()
                        --self.ui.menu:onCloseFileManagerMenu()
                        local cur_page = FileManager.instance.file_chooser.page
                        FileManager:showFiles(path)
                        FileManager.instance.file_chooser:onGotoPage(cur_page)
                        --self.ui.menu:exitOrRestart(nil, true)
                        --UIManager:restartKOReader()
                        --FileManager:onRefresh()
                        return true
                    end,
                },
                {
                    text = _("Enable devices flashes tweaks"),
                    checked_func = function() return self.settings:isTrue("enable_devices_flashes_tweaks") end,
                    help_text = _([[Some tweaks to fix the different issues for the different devices when flashing elements in the UI.

This is to be active only if the option flash buttons and menu items or the option allow to flash some elements are checked.]]),
                    callback = function()
                        local enable_devices_flashes_tweaks = not self.settings:isTrue("enable_devices_flashes_tweaks")
                        self.settings:saveSetting("enable_devices_flashes_tweaks", enable_devices_flashes_tweaks)
                        self.settings:flush()
                        return true
                    end,
                },
                {
                    text = _("Enable extra refreshes"),
                    checked_func = function() return self.settings:isTrue("enable_extra_refreshes") end,
                    help_text = _([[Allow extra refreshes which will work as an alternative or in addition to the option avoid mandatory black flashes in UI if it is enabled.]]),
                    callback = function()
                        local enable_extra_refreshes = not self.settings:isTrue("enable_extra_refreshes")
                        self.settings:saveSetting("enable_extra_refreshes", enable_extra_refreshes)
                        self.settings:flush()
                        return true
                    end,
                },
                {
                    text = _("Enable minimum flashes"),
                    checked_func = function() return self.settings:isTrue("enable_minimum_flashes") end,
                    help_text = _([[Allow to flash some elements like quick menu buttons even though the option flash buttons and menu items is not checked.]]),
                    callback = function()
                        local enable_minimum_flashes = not self.settings:isTrue("enable_minimum_flashes")
                        self.settings:saveSetting("enable_minimum_flashes", enable_minimum_flashes)
                        self.settings:flush()
                        return true
                    end,
                },
                {
                    text = _("Enable extra tweaks"),
                    checked_func = function() return self.settings:isTrue("enable_extra_tweaks") end,
                    help_text = _([[Extra tweaks to have them all gathered under a setting.]]),
                    callback = function(touchmenu_instance)
                        local enable_extra_tweaks = not self.settings:isTrue("enable_extra_tweaks")
                        self.settings:saveSetting("enable_extra_tweaks", enable_extra_tweaks)
                        self.settings:flush()

                        local path = FileManager.instance.file_chooser.path
                        if path:match("✪ Collections") then
                            path = G_reader_settings:readSetting("home_dir")
                        end
                        touchmenu_instance:closeMenu()
                        --self.ui.menu:onCloseFileManagerMenu()
                        local cur_page = FileManager.instance.file_chooser.page
                        FileManager:showFiles(path)
                        FileManager.instance.file_chooser:onGotoPage(cur_page)
                        return true
                    end,
                },
                {
                    text = _("Enable extra tweaks mosaic view"),
                    checked_func = function() return self.settings:isTrue("enable_extra_tweaks_mosaic_view") end,
                    help_text = _([[Extra tweaks mosaic view.]]),
                    callback = function()
                        local enable_extra_tweaks_mosaic_view = not self.settings:isTrue("enable_extra_tweaks_mosaic_view")
                        self.settings:saveSetting("enable_extra_tweaks_mosaic_view", enable_extra_tweaks_mosaic_view)
                        self.settings:flush()

                        local FileManager = require("apps/filemanager/filemanager").instance
                        if FileManager then
                            --FileManager:onRefresh()
                            local path = FileManager.instance.file_chooser.path
                            --FileManager:setupLayout()
                            FileManager.instance.file_chooser:changeToPath(path)
                        end
                        return true
                    end,
                },
                {
                    text = _("Enable rounded corners mosaic view"),
                    checked_func = function() return self.settings:isTrue("enable_rounded_corners") end,
                    help_text = _([[Rounded corners in mosaic view.]]),
                    callback = function()
                        local enable_rounded_corners = not self.settings:isTrue("enable_rounded_corners")
                        self.settings:saveSetting("enable_rounded_corners", enable_rounded_corners)
                        self.settings:flush()

                        local FileManager = require("apps/filemanager/filemanager").instance
                        if FileManager then
                            --FileManager:onRefresh()
                            local path = FileManager.instance.file_chooser.path
                            --FileManager:setupLayout()
                            FileManager.instance.file_chooser:changeToPath(path)
                        end
                        return true
                    end,
                },
                {
                    text = _("Covers in folders"),
                    checked_func = function() return self.settings:isTrue("covers_in_folders") end,
                    help_text = _([[Covers in folders.]]),
                    callback = function()
                        local covers_in_folders = not self.settings:isTrue("covers_in_folders")
                        self.settings:saveSetting("covers_in_folders", covers_in_folders)
                        self.settings:flush()

                        local FileManager = require("apps/filemanager/filemanager").instance
                        if FileManager then
                            --FileManager:onRefresh()
                            local path = FileManager.instance.file_chooser.path
                            --FileManager:setupLayout()
                            FileManager.instance.file_chooser:changeToPath(path)
                        end
                        return true
                    end,
                },
                {
                    text = _("Covers in grid mode"),
                    checked_func = function() return self.settings:isTrue("covers_grid_mode") end,
                    help_text = _([[Covers in grid mode.]]),
                    callback = function()
                        local covers_grid_mode = not self.settings:isTrue("covers_grid_mode")
                        self.settings:saveSetting("covers_grid_mode", covers_grid_mode)
                        self.settings:flush()

                        local FileManager = require("apps/filemanager/filemanager").instance
                        if FileManager then
                            --FileManager:onRefresh()
                            local path = FileManager.instance.file_chooser.path
                            --FileManager:setupLayout()
                            FileManager.instance.file_chooser:changeToPath(path)
                        end
                        return true
                    end,
                },
            },
        }
    else
        self.data_dir = G_defaults:readSetting("STARDICT_DATA_DIR") or
            os.getenv("STARDICT_DATA_DIR") or
            DataStorage:getDataDir() .. "/data/dict"
        local ifo_files = getIfosInDir(self.data_dir)
        local table_dictionaries = {}
        for _, ifo_file in pairs(ifo_files) do
            local f = io.open(ifo_file, "r")
            if f then
                local content = f:read("*all")
                f:close()
                local dictname = content:match("\nbookname=(.-)\r?\n")
                table.insert(table_dictionaries, {
                    text = dictname,
                    checked_func = function() return self.settings:readSetting("dictionary") == dictname end,
                    callback = function()
                        self.settings:saveSetting("dictionary", dictname)
                        self.settings:flush()
                        if self.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") and not self.ui.searching and util.getFileNameSuffix(self.ui.document.file) == "epub" then
                            self.translations = {}
                            self:updateWordsVocabulary()
                            UIManager:setDirty("all", "full")
                        end
                        if (self.settings:isTrue("highlight_all_notes_and_allow_to_edit_them_on_tap") or self.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes")) and not self.ui.searching and util.getFileNameSuffix(self.ui.document.file) == "epub" then
                            self.translations = {}
                            self:updateNotes()
                            UIManager:setDirty("all", "full")
                        end
                        return true
                    end,
                })
            end
        end
        menu_items.pagetextinfo = {
            text = _("Page text info"),
            sub_item_table ={
                {
                    text = _("Enable"),
                    checked_func = function() return self.is_enabled end,
                    callback = function()
                        self.is_enabled = not self.is_enabled
                        self.settings:saveSetting("is_enabled", self.is_enabled)
                        self.settings:flush()
                        UIManager:setDirty("all", "ui")
                        return true
                    end,
                },
                {
                    text = _("Enable show footer separator"),
                    checked_func = function()
                        return self.settings:isTrue("show_footer_separator")
                    end,
                    callback = function()
                        local show_footer_separator = not self.settings:isTrue("show_footer_separator")
                        self.settings:saveSetting("show_footer_separator", show_footer_separator)
                        self.settings:flush()
                        UIManager:setDirty("all", "ui")
                        return true
                    end,
                },
                {
                    text = _("Enable devices flashes tweaks"),
                    checked_func = function() return self.settings:isTrue("enable_devices_flashes_tweaks") end,
                    help_text = _([[Some tweaks to fix the different issues for the different devices when flashing elements in the UI.

This is to be active only if the option flash buttons and menu items or the option allow to flash some elements are checked.]]),
                    callback = function()
                        local enable_devices_flashes_tweaks = not self.settings:isTrue("enable_devices_flashes_tweaks")
                        self.settings:saveSetting("enable_devices_flashes_tweaks", enable_devices_flashes_tweaks)
                        self.settings:flush()
                        return true
                    end,
                },
                {
                    text = _("Enable extra refreshes"),
                    checked_func = function() return self.settings:isTrue("enable_extra_refreshes") end,
                    help_text = _([[Allow extra refreshes which will work as an alternative or in addition to the option avoid mandatory black flashes in UI if it is enabled.]]),
                    callback = function()
                        local enable_extra_refreshes = not self.settings:isTrue("enable_extra_refreshes")
                        self.settings:saveSetting("enable_extra_refreshes", enable_extra_refreshes)
                        self.settings:flush()
                        return true
                    end,
                },
                {
                    text = _("Enable minimum flashes"),
                    checked_func = function() return self.settings:isTrue("enable_minimum_flashes") end,
                    help_text = _([[Allow to flash some elements like quick menu buttons even though the option flash buttons and menu items is not checked.]]),
                    callback = function()
                        local enable_minimum_flashes = not self.settings:isTrue("enable_minimum_flashes")
                        self.settings:saveSetting("enable_minimum_flashes", enable_minimum_flashes)
                        self.settings:flush()
                        return true
                    end,
                },
                {
                    text = _("Enable extra tweaks"),
                    checked_func = function() return self.settings:isTrue("enable_extra_tweaks") end,
                    help_text = _([[Extra tweaks to have them all gathered under a setting.]]),
                    callback = function()
                        local enable_extra_tweaks = not self.settings:isTrue("enable_extra_tweaks")
                        self.settings:saveSetting("enable_extra_tweaks", enable_extra_tweaks)
                        self.settings:flush()
                        return true
                    end,
                },
                {
                    text = _("Enable ruler"),
                    checked_func = function() return self.settings:isTrue("enable_ruler") end,
                    help_text = _([[Enable measuring ruler to be shown when a north to south swipe is performed. Just for emulator and some devices.]]),
                    callback = function()
                        local enable_ruler = not self.settings:isTrue("enable_ruler")
                        self.settings:saveSetting("enable_ruler", enable_ruler)
                        self.settings:flush()

                        return true
                    end,
                },
                {
                    text = _("Python server configuration"),
                    sub_item_table = {
                        {
                            text_func = function()
                                return T(_("Server: %1"), self.server)
                            end,
                            keep_menu_open = true,
                            callback = function(touchmenu_instance)
                                local InputDialog = require("ui/widget/inputdialog")
                                local server_dialog
                                server_dialog = InputDialog:new{
                                    title = _("Set server"),
                                    input = self.server,
                                    input_type = "string",
                                    input_hint = _("Server (default is 192.168.50.252)"),
                                    buttons =  {
                                        {
                                            {
                                                text = _("Cancel"),
                                                id = "close",
                                                callback = function()
                                                    UIManager:close(server_dialog)
                                                end,
                                            },
                                            {
                                                text = _("OK"),
                                                -- keep_menu_open = true,
                                                callback = function()
                                                    local server = server_dialog:getInputValue()
                                                    if server == "" then
                                                        server = "192.168.50.252"
                                                    end
                                                    self.server = server
                                                    self.settings:saveSetting("server", server)

                                                    UIManager:close(server_dialog)
                                                    touchmenu_instance:updateItems()
                                                end,
                                            },
                                        },
                                    },
                                }
                                UIManager:show(server_dialog)
                                server_dialog:onShowKeyboard()
                            end,
                        },
                        {
                            text_func = function()
                                return T(_("Port: %1"), self.port)
                            end,
                            keep_menu_open = true,
                            callback = function(touchmenu_instance)
                                local InputDialog = require("ui/widget/inputdialog")
                                local port_dialog
                                port_dialog = InputDialog:new{
                                    title = _("Set custom port"),
                                    input = self.port,
                                    input_type = "number",
                                    input_hint = _("Port number (default is 5000)"),
                                    buttons =  {
                                        {
                                            {
                                                text = _("Cancel"),
                                                id = "close",
                                                callback = function()
                                                    UIManager:close(port_dialog)
                                                end,
                                            },
                                            {
                                                text = _("OK"),
                                                -- keep_menu_open = true,
                                                callback = function()
                                                    local port = port_dialog:getInputValue()
                                                    logger.warn("port", port)
                                                    if port and port >= 1 and port <= 65535 then
                                                        port = port
                                                    end
                                                    if not port then
                                                        port = "5000"
                                                    end
                                                    self.port = port
                                                    self.settings:saveSetting("server_port", port)
                                                    UIManager:close(port_dialog)
                                                    touchmenu_instance:updateItems()
                                                end,
                                            },
                                        },
                                    },
                                }
                                UIManager:show(port_dialog)
                                port_dialog:onShowKeyboard()
                            end,
                        }
                    },
                },
                {
                    text = _("Highlight"),
                    sub_item_table ={
                        {
                            text = _("Highlight all notes and allow to edit them on tap"),
                            checked_func = function() return self.settings:isTrue("highlight_all_notes_and_allow_to_edit_them_on_tap") end,
                            callback = function()
                                local highlight_all_notes_and_allow_to_edit_them_on_tap = self.settings:isTrue("highlight_all_notes_and_allow_to_edit_them_on_tap")
                                self.settings:saveSetting("highlight_all_notes_and_allow_to_edit_them_on_tap", not highlight_all_notes_and_allow_to_edit_them_on_tap)
                                -- self.ui:reloadDocument(nil, true) -- seamless reload (no infomsg, no flash)
                                self:updateNotes()
                                UIManager:setDirty("all", "full")
                                self.settings:flush()
                                return true
                            end,
                        },
                        {
                            text = _("Highlight all words vocabulary builder and notes"),
                            checked_func = function() return self.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") end,
                            -- enabled_func = function()
                            --     return false
                            -- end,
                            callback = function()
                                local highlight_all_words_vocabulary_builder_and_notes = self.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes")
                                self.settings:saveSetting("highlight_all_words_vocabulary_builder_and_notes", not highlight_all_words_vocabulary_builder_and_notes)
                                -- self.ui:reloadDocument(nil, true) -- seamless reload (no infomsg, no flash)

                                self:updateWordsVocabulary()
                                self.ui.gestures:onIgnoreHoldCorners(not highlight_all_words_vocabulary_builder_and_notes)
                                if self.ui.view.topbar then
                                    self.ui.view.topbar:toggleBar()
                                end
                                UIManager:setDirty("all", "full")
                                self.settings:flush()
                                return true
                            end,
                        },
                        {
                            text = _("Show definitions"),
                            checked_func = function() return self.settings:isTrue("show_definitions") end,
                            -- enabled_func = function()
                            --     return false
                            -- end,
                            callback = function()
                                local show_definitions = self.settings:isTrue("show_definitions")
                                self.settings:saveSetting("show_definitions", not show_definitions)
                                -- self.ui:reloadDocument(nil, true) -- seamless reload (no infomsg, no flash)
                                self:updateWordsVocabulary()
                                UIManager:setDirty("all", "full")
                                self.settings:flush()
                                return true
                            end,
                        },
                        {
                            text = _("Dictionaries"),
                            sub_item_table = table_dictionaries,
                        },
                    },
                }
            },
        }
    end
end

-- function PageTextInfo:updateNotes()
--     -- self.search:fullTextSearch("Citra")
--     self.pages_notes = {}
--     self.notes = {}
--     local annotations = self.ui.annotation.annotations
--     for i, item in ipairs(annotations) do
--         if item.note and not item.text:find("%s+") then
--             item.words = self.document:findAllText(item.text, true, 5, 5000, 0, false)
--             table.insert(self.notes, item)
--             for i, word in ipairs(item.words) do
--                 word.note = item.note
--                 local page = self.document:getPageFromXPointer(word.start)
--                 if not self.pages_notes[page] then
--                     self.pages_notes[page]={}
--                 end
--                 table.insert(self.pages_notes[page], word)
--                 local page2 = self.document:getPageFromXPointer(word["end"])
--                 if not self.pages_notes[page2] then
--                     self.pages_notes[page2]={}
--                 end
--                 table.insert(self.pages_notes[page2], word)
--             end
--         end
--     end

--     --self.words = self.document:findAllText("Citra", true, 5, 5000, 0, false)
--     --local dump = require("dump")
--     --print(dump(self.notes))
-- end


function PageTextInfo:onCloseDocument()
    -- UIManager:unschedule(self.insertSession)
    self.ui.gestures:onIgnoreHoldCorners(false)
    self.ui.disable_double_tap = false
    self.settings:saveSetting("highlight_all_notes_and_allow_to_edit_them_on_tap", false)
    self.settings:saveSetting("highlight_all_words_vocabulary_builder_and_notes", false)
    self.settings:flush()
end

-- function PageTextInfo:onPreserveCurrentSession()
--     PageTextInfo.preserved_hightlight_all_notes = self.settings:readSetting("highlight_all_notes")
--     PageTextInfo.preserved_highlight_all_words_vocabulary = self.settings:readSetting("highlight_all_words_vocabulary")
-- end

local function tailAfterFirstHyphen(str)
    local pos = str:find("-")
    return pos and str:sub(pos + 1) or str
end

local function nestedTail(str, depth)
    local segment = tailAfterFirstHyphen(str)
    for _ = 2, depth do
        segment = tailAfterFirstHyphen(segment)
    end
    return segment
end

local function findBestHyphenatedMatch(doc, hyphenatedWord)
    local attempts = {
        tailAfterFirstHyphen(hyphenatedWord),       -- nivel 1
        nestedTail(hyphenatedWord, 2),              -- nivel 2
        nestedTail(hyphenatedWord, 3),              -- nivel 3
        nestedTail(hyphenatedWord, 4),              -- nivel 4
        nestedTail(hyphenatedWord, 5),              -- nivel 5
        hyphenatedWord:gsub("-", "")                -- sin guiones
    }

    for _, suggestion in ipairs(attempts) do
        local found = doc:findText(suggestion, 1, false, true, -1, false, 1)
        if found then return found end
    end

    return nil
end

function PageTextInfo:updateNotes()
    -- self.search:fullTextSearch("Citra")
    self.pages_notes = {}
    self.notes = {}
    local annotations = self.ui.annotation.annotations
    local res = self.document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(), false)
    if res and res.text then
        local t = util.splitToWords2(res.text) -- contar palabras
        local words_page = {}
        for i=1, #t do
            words_page[t[i]] = "";
        end
        if words_page and annotations then
            for i, item in ipairs(annotations) do
                local words = nil
                local hyphenated = false
                if words_page[item.text] then
                    if t[1] == item.text then -- If first word is hyphenated
                        local cre = require("libs/libkoreader-cre")
                        local hyphenation = cre.getHyphenationForWord(item.text)

                        if hyphenation:find("-") then
                            hyphenated = true
                            words = findBestHyphenatedMatch(self.document, hyphenation)
                        else
                            words = self.document:findText(item.text, 1, false, true, -1, false, 1)
                        end
                    else
                        words = self.document:findText(item.text, 1, false, true, -1, false, 60)
                    end
                    -- words = self.document:findText(item.text, 1, false, true, -1, false, 30)
                    if words then
                        if item.note and not item.text:find("%s+") then
                            table.insert(self.notes, item)
                            for i, word in ipairs(words) do
                                word.note = item.note
                                word.text = item.text
                                if hyphenated then
                                    word.hyphenated = true
                                else

                                end
                                local page = self.document:getPageFromXPointer(word.start)
                                if not self.pages_notes[page] then
                                    self.pages_notes[page]={}
                                end
                                table.insert(self.pages_notes[page], word)
                                local page2 = self.document:getPageFromXPointer(word["end"])
                                if not self.pages_notes[page2] then
                                    self.pages_notes[page2]={}
                                end
                                table.insert(self.pages_notes[page2], word)
                            end
                        end
                    end
                end
            end
        end
    end
    self.ui.document:clearSelection()
end

local function removeDupes(tab)
    local seen = {}
    local result = {}
    for _, val in ipairs(tab) do
        if not seen[val] then
            seen[val] = true
            table.insert(result, val)
        end
    end
    return result
end

function PageTextInfo:updateWordsVocabulary()
    if not ffiUtil.realpath(DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3") then return end
    local db_location = DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3"
    sql_stmt = "SELECT distinct(word) FROM vocabulary"
    local conn = require("lua-ljsqlite3/init").open(db_location)
    stmt = conn:prepare(sql_stmt)

    self.words = {}
    self.all_words = {}
    while true do
        local row = {}
        if not stmt:step(row) then break end
        local word = row[1]
        if not word:find("%s+") then
            self.all_words[word] = ""
        end
    end

    -- Using regular expressions to get full words is very slow and then we have to remove the characters used in them
    -- Searching text without regular expressions we won't get words, we will get the position in the dom (start and end)
    -- for each of the places the text if found wether the full word or the text inside a word and we want full words to highlight them
    -- When painting in the source readerview.lua, we get the boxes from the positions and using the boxes we can get the fulls words to highlight them
    if self.all_words then
        local res = self.document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(), false)
        if res and res.text then
            -- print(res.pos0)
            -- print(res.pos1)
            local words_page = removeDupes(util.splitToWords2(res.text))
            if words_page and self.all_words then
                for i = 1, #words_page do
                    local word_page = words_page[i] --:gsub("[^%w%s]+", "")
                    local words = nil
                    local hyphenated = false
                    if i == 1 and self.all_words[word_page] then
                        local cre = require("libs/libkoreader-cre")
                        local hyphenation = cre.getHyphenationForWord(word_page)

                        if hyphenation:find("-") then
                            hyphenated = true
                            words = findBestHyphenatedMatch(self.document, hyphenation)
                        else
                            words = self.document:findText(word_page, 1, false, true, -1, false, 1)
                        end
                    elseif self.all_words[word_page] then
                        words = self.document:findText(word_page, 1, false, true, -1, false, 30)
                    end
                    if words then
                        for j = 1, #words do
                            local wordi = words[j]
                            wordi.text = word_page
                            -- First result of the first word of the page in case is hyphenated
                            -- In this case we want always
                            if hyphenated then
                                wordi.hyphenated = true
                            end

                            local word = self.document:getTextFromXPointers(wordi.start, wordi["end"])
                            -- Not using regular expressions
                            -- print(word)
                            -- print(wordi.start)
                            -- if word:sub(word:len()) == " " then
                            --     local pos = tonumber(wordi["end"]:sub(wordi["end"]:find("%.") + 1, wordi["end"]:len()))
                            --     pos = pos - 1
                            --     wordi["end"] = wordi["end"]:sub(1, wordi["end"]:find("%.") - 1) .. "." .. pos
                            --     word = self.document:getTextFromXPointers(wordi.start, wordi["end"])
                            -- end
                            -- if word:sub(word:len()) == "." or
                            --     word:sub(word:len()) == "," or
                            --     word:sub(word:len()) == "!" or
                            --     word:sub(word:len()) == "?" then
                            --     local pos = tonumber(wordi["end"]:sub(wordi["end"]:find("%.") + 1, wordi["end"]:len()))
                            --     pos = pos - 1
                            --     wordi["end"] = wordi["end"]:sub(1, wordi["end"]:find("%.") - 1) .. "." .. pos
                            -- end
                            local page = self.document:getPageFromXPointer(wordi.start)
                            if not self.words[page] then
                                self.words[page] = {}
                            end
                            table.insert(self.words[page], wordi)
                            local page2 = self.document:getPageFromXPointer(wordi["end"])
                            if not self.words[page2] then
                                self.words[page2] = {}
                            end
                            table.insert(self.words[page2], wordi)
                        end
                    end
                end
            end
        end
    end

    -- if all_words then
    --     all_words = all_words:sub(1, all_words:len() - 1)
    --     local words = self.document:findAllText(all_words, true, 5, 300000, 0, false)
    --     if words then
    --         for i, wordi in ipairs(words) do
    --             local page = self.document:getPageFromXPointer(wordi.start)
    --             if not self.words[page] then
    --                 self.words[page]={}
    --             end
    --             table.insert(self.words[page], wordi)
    --             local page2 = self.document:getPageFromXPointer(wordi["end"])
    --             if not self.words[page2] then
    --                 self.words[page2]={}
    --             end
    --             table.insert(self.words[page2], wordi)
    --         end
    --     end
    -- end

    -- if self.all_words then
    --     self.all_words = self.all_words:sub(1, self.all_words:len() - 1)
    --     local words = self.document:findText(self.all_words, 1, false, true, -1, true, 100) -- Page not used, set -1
    --     if words then
    --         for i, wordi in ipairs(words) do
    --             local page = self.document:getPageFromXPointer(wordi.start)
    --             if not self.words[page] then
    --                 self.words[page]={}
    --             end
    --             table.insert(self.words[page], wordi)
    --             local page2 = self.document:getPageFromXPointer(wordi["end"])
    --             if not self.words[page2] then
    --                 self.words[page2]={}
    --             end
    --             table.insert(self.words[page2], wordi)
    --         end
    --     end
    -- end
    -- In the cre.cpp source findText() function, there is a call to doc->text_view->selectWords( words ); when looking for words
    -- But when it finishes doesn't called doc->text_view->clearSelection(); like thefindAllText() function does
    -- The result is that the words are highlighted by the CREngine
    -- But only happens here when loading the document. It does not happen when turning pages
    -- It should be done in the cre.cpp source but I do it here since I haven't found any other issue
    self.ui.document:clearSelection()
end
function PageTextInfo:paintTo(bb, x, y)

    if util.getFileNameSuffix(self.ui.document.file) ~= "epub" then return end
    if self.settings:isTrue("highlight_all_notes_and_allow_to_edit_them_on_tap") or self.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") then
        self:drawXPointerSavedHighlightNotes(bb, x, y)
    end

    if self.words and self.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") then
        self:drawXPointerVocabulary(bb, x, y)
    end

    local total_words = 0
    if self.settings:isTrue("show_footer_separator") then
        LineWidget = require("ui/widget/linewidget")
        local footer_height = self.ui.view.footer:getHeight2()
        local separator_line = LineWidget:new{
            dimen = Geom:new{
                w = Screen:getWidth(),
                h = Size.line.thick,
            }
        }
        if self.ui.view.footer.settings.bar_top then
            separator_line:paintTo(bb, x, y + footer_height)
        else
            separator_line:paintTo(bb, x, y + Screen:getHeight() - footer_height)
        end
    end
    if self.is_enabled and self.vertical_frame then
        local res = self.document:getTextFromPositions({x = 0, y = 0},
        {x = Screen:getWidth(), y = Screen:getHeight()}, true) -- do not highlight
        if res and res.pos0 and res.pos1 then
            local boxes = self.ui.document:getScreenBoxesFromPositions(res.pos0, res.pos1, true)
            if boxes then
                -- local last_word = ""
                for _, box in ipairs(boxes) do
                    if box.h ~= 0 then
                        -- local t = TextWidget:new{
                        --     text =  "New line",
                        --     face = Font:getFace("myfont4", 6),
                        --     fgcolor = Blitbuffer.COLOR_BLACK,
                        -- }
                        -- t:paintTo(bb, x, box.y)
                            local text_line = self.ui.document._document:getTextFromPositions(box.x, box.y, Screen:getWidth(), box.y, false, false).text
                            -- text_line = text_line:gsub("’", ""):gsub("‘", ""):gsub("–", ""):gsub("— ", ""):gsub(" ", ""):gsub("”", ""):gsub("“", ""):gsub("”", "…")
                            local words_nb = 0
                            for word in util.gsplit(text_line, "[%s%p]+", false) do
                                if util.hasCJKChar(word) then
                                    for char in util.gsplit(word, "[\192-\255][\128-\191]+", true) do
                                        words_nb = words_nb + 1
                                    end
                                else
                                    words_nb = words_nb + 1
                                end
                            end
                            -- for i = #wordst, 1, -1 do
                            --     if wordst[i] == "’" or wordst[i] == "–" or wordst[i] == " " or wordst[i] == "”" or wordst[i] == "…" or wordst[i] == "…’" then
                            --       table.remove(wordst, i)
                            --     end
                            -- end
                            local words = words_nb
                            -- local dump = require("dump")
                            -- print(dump(wordst))
                            -- Hyphenated words are counted twice since getTextFromPositions returns the whole word for the line.
                            -- They can be removed but it is fine to count them twice
                            -- if last_word:find(util.splitToWords2(text_line)[1]) then
                            -- if util.splitToWords2(text_line)[1] == last_word then
                            --     words = words - 1
                            -- end
                            -- last_word = util.splitToWords2(text_line)[#util.splitToWords2(text_line)]
                            -- print(text_line:sub(1, 10))
                            -- print(text_line:sub(#text_line-10, #text_line))
                            -- if text_line:sub(#text_line, #text_line) == "-" then
                            --     words = words - 1
                            -- end
                            total_words = total_words + words
                            local t = TextWidget:new{
                                text =  words,
                                face = Font:getFace("myfont4", self.ui.document.configurable.font_size),
                                fgcolor = Blitbuffer.COLOR_BLACK,
                            }
                            t:paintTo(bb, x, box.y)
                            local t2 = TextWidget:new{
                                text =  total_words,
                                face = Font:getFace("myfont4", self.ui.document.configurable.font_size),
                                fgcolor = Blitbuffer.COLOR_BLACK,
                            }
                            t2:paintTo(bb, x + Screen:getWidth() - t2:getSize().w, box.y)
                    end
                    self.view:drawHighlightRect(bb, x, y, box, "underscore", nil, false)
                end
            end
        end
        -- logger.warn(res.text)
        local nblines, nbwords = self.ui.view:getCurrentPageLineWordCounts()
        local res = self.ui.document._document:getTextFromPositions(0, 0, Screen:getWidth(), 1, false, true)
        local chars_first_line = 0
        if res and res.text then
            local words = res.text
            chars_first_line = #words
        end

        self.vg1[1][1]:setText("Lines      " .. nblines)
        self.vg1[3][1]:setText("Words      " .. nbwords)
        self.vg1[5][1]:setText("CFL        " .. chars_first_line)

        if self.ui.statistics then
            local duration_raw =  math.floor(((os.time() - self.ui.statistics.start_current_period)/60)* 100) / 100
            local wpm = 0
            if self.ui.statistics._total_words > 0 then
                wpm = math.floor(self.ui.statistics._total_words/duration_raw)
            end
            self.vg2[1][1]:setText("Total words session " .. self.ui.statistics._total_words)
            self.vg2[3][1]:setText("Total pages session " .. self.ui.statistics._total_pages)
            self.vg2[5][1]:setText("Wpm session         " .. wpm)
        else
            self.vg2[1][1]:setText("Statistics plugin not enabled")
        end

        self.vertical_frame:paintTo(bb, x + Screen:getWidth() - self.vertical_frame[1][1]:getSize().w - self.vertical_frame[1].padding, y)
        -- -- This is painted before some other stuff like for instance the dogear widget. This is the way to paint it just after all in the next UI tick.
        -- -- But we leave it commented since sometimes it is painted even over the application menus
        -- UIManager:scheduleIn(0, function()
        --     self.vertical_frame:paintTo(bb, x + Screen:getWidth() -  self.vertical_frame[1][1]:getSize().w - self.vertical_frame[1].padding, y)
        --     local Screen = require("device").screen
        --     -- self:paintTo(Screen.bb, 0, 0)
        --     UIManager:setDirty(self, "ui")
        -- end)

        -- local times_text = TextWidget:new{
        --     text =  "",
        --     face = Font:getFace("myfont3", 12),
        --     fgcolor = Blitbuffer.COLOR_BLACK,
        --     invert = true,
        -- }

        -- local Device = require("device")
        -- local datetime = require("datetime")
        -- local powerd = Device:getPowerDevice()
        -- local batt_lvl = tostring(powerd:getCapacity())



        -- local time = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))

        -- local last_file = "None"
        -- if G_reader_settings:readSetting("lastfile") ~= nil then
        --     last_file = G_reader_settings:readSetting("lastfile")
        -- end


        -- -- local time_battery_text_text = time .. "|" .. batt_lvl .. "%|" ..  last_file

        -- -- times_text:setText(time_battery_text_text:reverse())
        -- -- times_text:paintTo(bb, x - times_text:getSize().w - TopBar.MARGIN_BOTTOM - Screen:scaleBySize(12), y)

        -- local Screen = Device.screen

        -- local books_information = FrameContainer:new{
        --     left_container:new{
        --         dimen = Geom:new{ w = Screen:getWidth(), h = 12 },
        --         TextWidget:new{
        --             text =  "",
        --             face = Font:getFace("myfont3", 12),
        --             fgcolor = Blitbuffer.COLOR_BLACK,
        --         },
        --     },
        --     background = Blitbuffer.COLOR_WHITE,
        --     bordersize = 0,
        --     padding = 0,
        --     padding_left = Screen:scaleBySize(10),
        --     padding_bottom = Screen:scaleBySize(6),
        -- }

        -- -- local FileManagerFileSearcher = require("apps/filemanager/filemanagerfilesearcher")
        -- -- local _, files = self:getList("*.epub")
        -- -- books_information[1][1]:setText("TF: " .. tostring(#files))

        -- local ffiutil = require("ffi/util")
        -- local topbar = self.ui.view[4]
        -- if G_reader_settings:readSetting("home_dir") and ffiutil.realpath(G_reader_settings:readSetting("home_dir") .. "/stats.lua") then
        --     local ok, stats = pcall(dofile, G_reader_settings:readSetting("home_dir") .. "/stats.lua")
        --     local last_days = ""
        --     for k, v in pairs(stats["stats_last_days"]) do
        --         last_days = v > 0 and last_days .. " ● " or last_days .. " ○ "
        --     end
        --     -- local execute = io.popen("find " .. G_reader_settings:readSetting("home_dir") .. " -iname '*.epub' | wc -l" )
        --     -- local execute2 = io.popen("find " .. G_reader_settings:readSetting("home_dir") .. " -iname '*.epub.lua' -exec ls {} + | wc -l")
        --     -- books_information[1][1]:setText("TB: " .. execute:read('*a') .. "TBC: " .. execute2:read('*a'))

        --     local stat_years = 0
        --     if topbar then
        --         stats_year = topbar:getReadThisYearSoFar()
        --     end
        --     if stats_year > 0 then
        --         stats_year = "+" .. stats_year
        --     end
        --     books_information[1][1]:setText("B: " .. stats["total_books"]
        --     .. ", BF: " .. stats["total_books_finished"]
        --     .. ", BFTM: " .. stats["total_books_finished_this_month"]
        --     .. ", BFTY: " .. stats["total_books_finished_this_year"]
        --     .. ", BFLY: " .. stats["total_books_finished_last_year"]
        --     .. ", BMBR: " .. stats["total_books_mbr"]
        --     .. ", BTBR: " .. stats["total_books_tbr"]
        --     .. ", LD: " .. last_days
        --     .. " " .. stats_year)
        -- else
        --     books_information[1][1]:setText("No stats.lua file in home dir")
        -- end

        -- -- books_information:paintTo(bb, x + topbar.MARGIN_SIDES, Screen:getHeight() - topbar.MARGIN_BOTTOM)


        -- local times = FrameContainer:new{
        --     left_container:new{
        --         dimen = Geom:new{ w = Screen:getWidth(), h = 12 },
        --         TextWidget:new{
        --             text =  "",
        --             face = Font:getFace("myfont3", 12),
        --             fgcolor = Blitbuffer.COLOR_BLACK,
        --         },
        --     },
        --     background = Blitbuffer.COLOR_WHITE,
        --     bordersize = 0,
        --     padding = 0,
        --     padding_left = Screen:scaleBySize(10),
        --     padding_bottom = Screen:scaleBySize(11),
        --     padding_top = Screen:scaleBySize(6),
        -- }


        -- -- times[1][1]:setText(time .. "|" .. batt_lvl .. "%")


        -- -- local space = FrameContainer:new{
        -- --     left_container:new{
        -- --         dimen = Geom:new{ w = Screen:getWidth(), h = 12 },
        -- --         VerticalSpan:new{width = 29, background = Blitbuffer.COLOR_WHITE},
        -- --     },
        -- --     background = Blitbuffer.COLOR_WHITE,
        -- --     bordersize = 0,
        -- --     padding = 0,
        -- -- }

        -- local total_read = ""
        -- local total_books = ""
        -- if topbar then
        --     total_read = topbar:getTotalRead()
        --     total_books = topbar:getBooksOpened()
        -- end
        -- self.vertical_frame2 = VerticalGroup:new{}
        -- table.insert(self.vertical_frame2, times)
        -- -- table.insert(self.vertical_frame2, VerticalSpan:new{width = 8}) -- We set the vertical space using padding for both of the elements that make up the vertical frame
        -- table.insert(self.vertical_frame2, books_information)

        -- -- times[1].dimen.w = self.vertical_frame2:getSize().w
        -- times[1].dimen.wh = self.vertical_frame2:getSize().h
        -- times[1][1]:setText("BDB: " .. total_books .. ", TR: " .. total_read .. "d")
        -- self.vertical_frame2:paintTo(bb, x, Screen:getHeight() - self.vertical_frame2:getSize().h )
    end
end

function PageTextInfo:drawXPointerSavedHighlightNotes(bb, x, y)
    -- Getting screen boxes is done for each tap on screen (changing pages,
    -- showing menu...). We might want to cache these boxes per page (and
    -- clear that cache when page layout change or highlights are added
    -- or removed).
    -- Even in page mode, it's safer to use pos and ui.dimen.h
    -- than pages' xpointers pos, even if ui.dimen.h is a bit
    -- larger than pages' heights
    local cur_view_top = self.document:getCurrentPos()
    local cur_view_bottom
    if self.view_mode == "page" and self.document:getVisiblePageCount() > 1 then
        cur_view_bottom = cur_view_top + 2 * self.ui.dimen.h
    else
        cur_view_bottom = cur_view_top + self.ui.dimen.h
    end
    local colorful
--    if true then
--        local dump = require("dump")
--        UIManager:show( require("ui/widget/textviewer"):new{text = dump(self.ui.notes)})
--    end
--
    if self.pages_notes[self.ui.view.state.page] then
        for _, item in ipairs(self.pages_notes[self.ui.view.state.page]) do
            -- document:getScreenBoxesFromPositions() is expensive, so we
            -- first check if this item is on current page
            local start_pos = self.document:getPosFromXPointer(item.start)
            --if start_pos > cur_view_bottom then return colorful end -- this and all next highlights are after the current page
            local end_pos = self.document:getPosFromXPointer(item["end"])
            if end_pos >= cur_view_top then
                local boxes = self.document:getScreenBoxesFromPositions(item.start, item["end"], true) -- get_segments=true
                if boxes then
                    local word = self.ui.document._document:getTextFromPositions(boxes[1].x, boxes[1].y, boxes[1].x, boxes[1].y, false, false)
                    word.text = word.text:match("[A-Za-zÁÉÍÓÚÜÑáéíóúüñ']+$") or word.text
                    if (item.hyphenated and word.text:upper() == item.text:upper()) or word.text:upper() == item.text:upper() then
                        if item.hyphenated and word.text:upper() == item.text:upper() then
                            boxes = self.document:getScreenBoxesFromPositions(word.pos0, word.pos1, true)
                        else
                            boxes = self.document:getScreenBoxesFromPositions(item.start, word.pos1, true)
                        end
                        if boxes then
                            for _, box in ipairs(boxes) do
                                if box.h ~= 0 then
                                    local mark = FrameContainer:new{
                                        left_container:new{
                                            dimen = Geom:new(),
                                            TextWidget:new{
                                                text =  "\u{EB4D}",
                                                face = Font:getFace("symbols", 12),
                                                fgcolor = Blitbuffer.COLOR_BLACK,
                                            },
                                        },
                                        -- background = Blitbuffer.COLOR_WHITE,
                                        bordersize = 0,
                                        padding = 0,
                                        padding_bottom = self.bottom_padding,
                                    }
                                    -- self.ui.view:drawHighlightRect(bb, x, y, box, "underscore", nil, false)
                                    mark:paintTo(bb, box.x, box.y)
                                end
                            end
                        end
                        if item.hyphenated then
                            if boxes then
                                for _, box in ipairs(boxes) do
                                    if box.h ~= 0 then
                                        local mark = FrameContainer:new{
                                            left_container:new{
                                                dimen = Geom:new(),
                                                TextWidget:new{
                                                    text =  "\u{EB4D}",
                                                    face = Font:getFace("symbols", 12),
                                                    fgcolor = Blitbuffer.COLOR_BLACK,
                                                },
                                            },
                                            -- background = Blitbuffer.COLOR_WHITE,
                                            bordersize = 0,
                                            padding = 0,
                                            padding_bottom = self.bottom_padding,
                                        }
                                        -- self.ui.view:drawHighlightRect(bb, x, y, box, "underscore", nil, false)
                                        mark:paintTo(bb, box.x, box.y)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return colorful
end

function extractDefinition(def)
    if not def or def == "" then return "" end

    -- Limpia etiquetas HTML y normaliza saltos de línea
    def = def:gsub("%b<>", ""):gsub("[\r\n]+", "\n")

    local lines = {}
    for line in def:gmatch("[^\n]+") do
        local clean = line:match("^%s*(.-)%s*$")
        if clean and clean ~= "" then
            table.insert(lines, clean)
        end
    end

    -- Busca línea que parezca traducción (letras con acento, coma o punto y coma)
    for _, line in ipairs(lines) do
        -- Evita encabezados tipo "1. ", "adj.", etc.
        local stripped = line:gsub("^%d+%.%s*", ""):gsub("^%a+%.%s*", "")
        if #stripped > 2 and #stripped < 80 and
           (stripped:match("[áéíóúñÑ]") or stripped:match("[a-zA-Z],") or stripped:match(";")) then
            return stripped
        end
    end

    -- Si nada encaja, intenta devolver la primera línea que no sea encabezado
    for _, line in ipairs(lines) do
        local stripped = line:gsub("^%d+%.%s*", ""):gsub("^%a+%.%s*", "")
        if #stripped > 2 and #stripped < 80 and stripped:match("%a") then
            return stripped
        end
    end

    -- Último recurso: la última línea o la definición entera
    return lines[#lines] or def
end

function getTranslation(self, word)
    if self.translations[word] then
        return self.translations[word]
    end

    local dictionaries = {}

    table.insert(dictionaries, "WordReference_EN_ES")
    table.insert(dictionaries, "Babylon English-Spanish")

    local results = self.ui.dictionary:startSdcv(word, dictionaries, true, true)
    local translation = ""

    if results and results[1] and results[1].definition then
        local dict_name = results[1].dictionary
        local def = results[1].definition
        translation = extractDefinition(def)
    end

    self.translations[word] = translation
    return translation
end

function PageTextInfo:drawXPointerVocabulary(bb, x, y)
    -- Getting screen boxes is done for each tap on screen (changing pages,
    -- showing menu...). We might want to cache these boxes per page (and
    -- clear that cache when page layout change or highlights are added
    -- or removed).
    -- Even in page mode, it's safer to use pos and ui.dimen.h
    -- than pages' xpointers pos, even if ui.dimen.h is a bit
    -- larger than pages' heights
    local cur_view_top = self.document:getCurrentPos()
    local cur_view_bottom
    if self.view_mode == "page" and self.document:getVisiblePageCount() > 1 then
        cur_view_bottom = cur_view_top + 2 * self.ui.dimen.h
    else
        cur_view_bottom = cur_view_top + self.ui.dimen.h
    end
    local colorful
--    if true then
--        local dump = require("dump")
--        UIManager:show( require("ui/widget/textviewer"):new{text = dump(self.ui.notes)})
--    end
--
    if self.words[self.ui.view.state.page] then
        for _, item in ipairs(self.words[self.ui.view.state.page]) do
            -- local more_than_one_word = false
            -- document:getScreenBoxesFromPositions() is expensive, so we
            -- first check if this item is on current page
            local start_pos = self.document:getPosFromXPointer(item.start)
            --if start_pos > cur_view_bottom then return colorful end -- this and all next highlights are after the current page
            local end_pos = self.document:getPosFromXPointer(item["end"])
            if end_pos >= cur_view_top then
                -- If the word to search starts after a i or em (also an a) tag
                -- ...it had actually <i class="calibre4">grown</i> from the tree;...</p>
                -- Removing the </p> or putting the space inside i fixes it
                -- sometimes it gets also the previous word. It happens depending on the typography options applied
                -- It is not common in any case
                -- Passing false to getWordFromPosition() does not work
                -- In these cases, we detect if there is more than word coming, compare the last word with the item one
                -- and if it is the same, set set more_than_one_word and it will be highlighted propertly
                -- (the boxes retrieved are correct)

                -- For some of these cases there are more than one box, we pick up the second one and it works
                -- But for some other cases still does not work
                -- The box retrieved is valid always
                -- Finally we use getTextFromPositions()
                -- If a case is missed, we can pass boxes[1].x + 1 as first argument

                -- We want to ensure the visible text matches the target word exactly
                -- This avoids false positives where the word is merely contained within a larger one (e.g., "a" in "action").
                local boxes = self.document:getScreenBoxesFromPositions(item.start, item["end"], true)
                if boxes then
                    local Device = require("device")
                    local display_dpi = Device:getDeviceScreenDPI() or Screen:getDPI()
                    local font_size_px = (display_dpi * self.ui.document.configurable.font_size) / 72
                    local current_font = self.ui.document:getFontFace():gsub(" ","")
                    local face = Font:getFace(current_font .. "-Regular", font_size_px)
                    -- local factor = (current_font:find(".*Garamond.*") or current_font:find(".*APHont.*") or current_font:find(".*Spectral.*")) and 0.40 or 0.25
                    -- local line_spacing_pct = self.ui.font.configurable.line_spacing * (1/100)
                    -- VSPACE = math.ceil(font_size_px * factor * line_spacing_pct)
                    -- local dump = require("dump")
                    -- print(dump(boxes))
                    local word = self.ui.document._document:getTextFromPositions(boxes[1].x, boxes[1].y, boxes[1].x, boxes[1].y, false, false)

                    -- Sometimes the bounding boxes returned for the text are not precise
                    -- This usually happens when the word is wrapped in tags like <em>, <b>, etc.
                    -- In such cases, getTextFromPositions() may return surrounding text as well
                    -- Here, we discard the extra text and rely on item.start to retrieve accurate boxes
                    -- Example: boxes = self.document:getScreenBoxesFromPositions(item.start, word.pos1, true)
                    -- print(word.text)
                    -- Extract only the final word, ignoring any leading punctuation or quote characters.
                    word.text = word.text:match("[A-Za-zÁÉÍÓÚÜÑáéíóúüñ']+$") or word.text
                    --word.text = word.text:match(".*[%p%s](%w+)%s*$") or word.text
                    -- if #boxes >1 then
                    --     word = self.document:getWordFromPosition(boxes[2], true)
                    -- else
                    --     word = self.document:getWordFromPosition(boxes[1], true)
                    -- end
                    -- if word.word:find(" ") then
                    --     -- print("paso   " .. item.text ..  "-" .. word.word)
                    --     local word = word.word:sub(word.word:find(" ") + 1, word.word:len())
                    --     if item.text:upper() == word:upper() then
                    --         more_than_one_word = true
                    --     end
                    -- end
                    if (item.hyphenated and word.text:upper() == item.text:upper()) or word.text:upper() == item.text:upper() then
                        if item.hyphenated and word.text:upper() == item.text:upper() then
                            boxes = self.document:getScreenBoxesFromPositions(word.pos0, word.pos1, true)
                        else
                            boxes = self.document:getScreenBoxesFromPositions(item.start, word.pos1, true)
                        end
                        if boxes then
                            for _, box in ipairs(boxes) do
                                if box.h ~= 0 then
                                    if self.settings:isTrue("show_definitions") then
                                        local dictionaries = {}
                                        if self.settings:readSetting("dictionary") then
                                            table.insert(dictionaries, self.settings:readSetting("dictionary"))
                                        else
                                            table.insert(dictionaries, "Babylon English-Spanish")
                                        end
                                        local translation = getTranslation(self, word.text)
                                        local translation_font_size = self.ui.document.configurable.font_size * 0.60
                                        local test = FrameContainer:new{
                                            left_container:new{
                                                dimen = Geom:new(),
                                                TextWidget:new{
                                                    text =  translation,
                                                    -- face = Font:getFace(self.ui.document:getFontFace():gsub(" ",""), self.ui.document:getFontSize() * 0.75),
                                                    -- face = Font:getFace("myfont4"),
                                                    face = Font:getFace(self.ui.document:getFontFace():gsub(" ","") .. "-Regular", translation_font_size, 0, true), -- Same font reduced 40%
                                                    -- fgcolor = Blitbuffer.COLOR_GRAY,
                                                },
                                            },
                                            -- background = Blitbuffer.COLOR_WHITE,
                                            bordersize = 0,
                                            padding = 0,
                                            padding_bottom = self.bottom_padding,
                                        }
                                        if box.x < Screen:getWidth()/4 then
                                            test:paintTo(bb, box.x , box.y + translation_font_size/2)
                                        elseif box.x > Screen:getWidth() - Screen:getWidth()/4 then
                                            test:paintTo(bb, box.x + box.w - test[1][1]:getSize().w , box.y + translation_font_size/2)
                                        else
                                            test:paintTo(bb, box.x + box.w/2 - test[1][1]:getSize().w/2 , box.y + translation_font_size/2)
                                        end
                                    end
                                    -- local RenderText = require("ui/rendertext")
                                    -- local glyph = RenderText:getGlyph(face, 120)
                                    -- print("paso " ..  glyph.xheight)
                                    -- print("paso " ..  glyph.h)
                                    -- print("paso " ..  face.ftsize:getCapHeight())
                                    -- print("  ")
                                    -- local xrect = box:copy()
                                    -- if self.ui.document:getFontFace():gsub(" ",""):find(".*Garamond.*")
                                    -- or self.ui.document:getFontFace():gsub(" ",""):find(".*APHont.*")
                                    -- or self.ui.document:getFontFace():gsub(" ",""):find(".*Vollkorn.*") then
                                    --     bb:paintRect(xrect.x, xrect.y + math.floor(xrect.h/2) + 1 + face.ftsize:getCapHeight()/2, xrect.w, Size.line.thick, nil)
                                    -- else
                                    --     local face_height, face_ascender = face.ftsize:getHeightAndAscender()
                                    --     local line_spacing_pct = self.ui.font.configurable.line_spacing * (1/100)
                                    --     VSPACE = math.ceil(font_size_px * (face_ascender/100) * line_spacing_pct)
                                    --     local xrect = box:copy()
                                    --     xrect.y = xrect.y - VSPACE
                                    --     self.ui.view:drawHighlightRect(bb, x, y, xrect, "underscore", nil, false)
                                    --     -- self.ui.view:drawHighlightRect(bb, x, y, xrect, "lighten", Blitbuffer.COLOR_LIGHT_GRAY, false)
                                    -- end
                                    -- local face_height, face_ascender = face.ftsize:getHeightAndAscender()
                                    local xrect = box:copy()
                                    -- xrect.y = xrect.y - VSPACE
                                    -- self.ui.view:drawHighlightRect(bb, x, y, xrect, "underscore", nil, false)
                                    -- self.ui.view:drawHighlightRect(bb, x, y, xrect, "lighten", Blitbuffer.COLOR_LIGHT_GRAY, false)
                                    -- bb:paintRect(xrect.x, xrect.y + xrect.h - 1, xrect.w, Size.line.thick, nil)
                                    local line_h = xrect.h  -- Total height of the text line rectangle

                                    -- Estimate typographic metrics as proportions of the line height. In most Latin-script fonts:
                                    -- The visible tops of tall letters (l, h, b) typically reach ~70–75% of the line height,
                                    -- while the font's ascender metric (which defines the top of the line box) is usually 80–90%.
                                    -- The descender (bottom of g, y, p) accounts for ~20–30%
                                    -- The baseline (where most letters sit) is between those two zones
                                    local ascender  = line_h * 0.80     -- Height from top of line to baseline
                                    local x_height  = line_h * 0.48     -- Height from baseline to top of lowercase letters (e.g. "x")
                                    local descender = line_h * 0.26     -- Depth below the baseline for letters like "g", "p", "y"

                                    if current_font:find(".*UglyQua.*") or current_font:find(".*Literata.*")
                                        or current_font:find(".*BitterPro.*") or current_font:find(".*ChartereBook.*") then
                                        ascender  = line_h * 0.90       -- baseline slightly higher
                                    elseif current_font:find(".*Chare.*") then
                                        ascender  = line_h * 0.72       -- baseline slightly lower
                                    elseif current_font:find(".*Vollkorn.*") or current_font:find(".*Garamond.*")
                                        or current_font:find(".*APHont.*") or current_font:find(".*Thesis.*") then
                                        ascender  = line_h * 0.68       -- baseline slightly more lower
                                    end
                                    -- Compute y-coordinates of typographic reference lines
                                    local y_baseline = xrect.y + ascender          -- Baseline position relative to line top
                                    local y_xheight  = y_baseline - x_height       -- x-height line above baseline
                                    local y_desc     = y_baseline + descender      -- Bottom of descenders below baseline

                                    -- bb:paintRect(xrect.x, y_xheight, xrect.w, Size.line.thick, nil)    -- x-height
                                    bb:paintRect(xrect.x, y_baseline, xrect.w, Size.line.thick, nil)   -- baseline
                                    -- bb:paintRect(xrect.x, y_desc, xrect.w, Size.line.thick, nil)       -- descender
                                end
                            end
                        end
                    elseif item.hyphenated then -- or more_than_one_word then
                        if boxes then
                            for _, box in ipairs(boxes) do
                                if box.h ~= 0 then
                                    local xrect = box:copy()
                                    -- xrect.y = xrect.y - VSPACE
                                    -- self.ui.view:drawHighlightRect(bb, x, y, xrect, "underscore", nil, false)
                                    -- xrect.y = xrect.y - VSPACE
                                    -- self.ui.view:drawHighlightRect(bb, x, y, xrect, "underscore", nil, false)
                                    local line_h = xrect.h
                                    local ascender  = line_h * 0.80
                                    local y_baseline = xrect.y + ascender
                                    if current_font:find(".*UglyQua.*") or current_font:find(".*Literata.*")
                                        or current_font:find(".*BitterPro.*") or current_font:find(".*ChartereBook.*") then
                                        ascender  = line_h * 0.90       -- baseline slightly higher
                                    elseif current_font:find(".*Chare.*") then
                                        ascender  = line_h * 0.72       -- baseline slightly lower
                                    elseif current_font:find(".*Vollkorn.*") or current_font:find(".*Garamond.*")
                                        or current_font:find(".*APHont.*") or current_font:find(".*Thesis.*") then
                                        ascender  = line_h * 0.68       -- baseline slightly more lower
                                    end
                                    bb:paintRect(xrect.x, y_baseline, xrect.w, Size.line.thick, nil)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return colorful
end

-- Moved from readerui.lua. It won't be used since I handle double taps events in this plugin
-- function ReaderUI:onSearchDictionary()
--     if util.getFileNameSuffix(self.document.file) ~= "epub"  then return end
--     if self.lastevent  then
--         local res = self.document._document:getTextFromPositions(self.lastevent.gesture.pos.x, self.lastevent.gesture.pos.y,
--                     self.lastevent.gesture.pos.x, self.lastevent.gesture.pos.y, false, false)

--         if self.lastevent.gesture.pos.x < math.max(Screen:scaleBySize(40), Screen:scaleBySize(self.document.configurable.h_page_margins[1])) then
--             if not G_reader_settings:isTrue("ignore_hold_corners") then
--                 self.rolling:onGotoViewRel(-10)
--             end
--         elseif self.lastevent.gesture.pos.x > Screen:getWidth() - math.max(Screen:scaleBySize(40), Screen:scaleBySize(self.document.configurable.h_page_margins[1])) then
--             if not G_reader_settings:isTrue("ignore_hold_corners") then
--                 self.rolling:onGotoViewRel(10)
--             end
--         else
--             if res and res.text then
--                 local words = util.splitToWords2(res.text)
--                 if #words == 1 then
--                     local boxes = self.document:getScreenBoxesFromPositions(res.pos0, res.pos1, true)
--                     local word_boxes
--                     if boxes ~= nil then
--                         word_boxes = {}
--                         for i, box in ipairs(boxes) do
--                             word_boxes[i] = self.view:pageToScreenTransform(res.pos0.page, box)
--                         end
--                     end
--                     self.dictionary:onLookupWord(util.cleanupSelectedText(res.text), false, boxes)
--                     -- self:handleEvent(Event:new("LookupWord", util.cleanupSelectedText(res.text)))
--                 end
--             end
--         end
--     end
-- end

-- function ReaderUI:onOpenRandomFav()
--     self:switchDocument(self.menu:getRandomFav())
-- end

function PageTextInfo:onPrintChapterLeftFbink()
    if util.getFileNameSuffix(self.ui.document.file) ~= "epub" then return end
    local clock ="⌚ " ..  datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
    local left_chapter = self.ui.toc:getChapterPagesLeft(self.view.state.page) or self.ui.document:getTotalPagesLeft(self.view.state.page)
    if self.settings.pages_left_includes_current_page then
        left_chapter = left_chapter + 1
    end

    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() and not Device:isEmulator() then
        UIManager:scheduleIn(0.5, function()
            UIManager:setDirty("all", "full")
        end)
        local execute = nil
        if Device:isKobo() then
            execute = io.popen("/mnt/onboard/.adds/koreader/fbink -f -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. left_chapter .. "\"")
        elseif Device:isKindle() then
            execute = io.popen("/mnt/us/koreader/fbink -f -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. left_chapter .. "\"")
        else --PocketBook
            execute = io.popen("/mnt/ext1/applications/koreader/fbink -f -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. left_chapter .. "\"")
        end
        output = execute:read('*a')
        execute:close()
        -- if Device:isKobo() then
        --     execute = io.popen("/mnt/onboard/.adds/koreader/fbink -t regular=/mnt/onboard/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1150,right=50,format " .. duration)
        -- else --Kindle
        --     execute = io.popen("/mnt/us/koreader/fbink -t regular=/mnt/us/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1100,right=50,format " .. duration)
        -- end
        -- output = execute:read('*a')
        -- UIManager:show(InfoMessage:new{
        --     text = T(_(output)),
        --     face = Font:getFace("myfont"),
        -- })
    else
        local text = left_chapter
        UIManager:show(Notification:new{
            text = _(tostring(text)),
        })
    end
end

function PageTextInfo:onPrintSessionDurationFbink()
    if util.getFileNameSuffix(self.ui.document.file) ~= "epub" then return end
    local percentage_session, pages_read_session, duration = getSessionStats(self.ui.view.footer)


    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() and not Device:isEmulator() then
        UIManager:scheduleIn(0.5, function()
            UIManager:setDirty("all", "full")
        end)
        local execute = nil
        if Device:isKobo() then
            execute = io.popen("/mnt/onboard/.adds/koreader/fbink -f -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. duration .. "\"")
        elseif Device:isKindle() then
            execute = io.popen("/mnt/us/koreader/fbink -f -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format  \"" .. duration .. "\"")
        else --PocketBook
            execute = io.popen("/mnt/ext1/applications/koreader/fbink -f -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. duration .. "\"")
        end
        output = execute:read('*a')
        execute:close()
        -- if Device:isKobo() then
        --     execute = io.popen("/mnt/onboard/.adds/koreader/fbink -t regular=/mnt/onboard/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1150,right=50,format " .. duration)
        -- else --Kindle
        --     execute = io.popen("/mnt/us/koreader/fbink -t regular=/mnt/us/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1100,right=50,format " .. duration)
        -- end
        -- output = execute:read('*a')
        -- UIManager:show(InfoMessage:new{
        --     text = T(_(output)),
        --     face = Font:getFace("myfont"),
        -- })
    else
        local text = duration
        UIManager:show(Notification:new{
            text = _(text),
        })
    end
end

function PageTextInfo:onPrintProgressBookFbink()
    if util.getFileNameSuffix(self.ui.document.file) ~= "epub" then return end
    local string_percentage  = "%0.f%%"
    local percentage = string_percentage:format(self.view.footer.progress_bar.percentage * 100)

    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() and not Device:isEmulator() then
        UIManager:scheduleIn(0.5, function()
            UIManager:setDirty("all", "full")
        end)
        local execute = nil
        if Device:isKobo() then
            execute = io.popen("/mnt/onboard/.adds/koreader/fbink -f -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. percentage .. "\"")
        elseif Device:isKindle() then
            execute = io.popen("/mnt/us/koreader/fbink -f -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. percentage .. "\"")
        else --PocketBook
            execute = io.popen("/mnt/ext1/applications/koreader/fbink -f -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. percentage .. "\"")
        end
        output = execute:read('*a')
        execute:close()
        -- if Device:isKobo() then
        --     execute = io.popen("/mnt/onboard/.adds/koreader/fbink -t regular=/mnt/onboard/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1150,right=50,format " .. duration)
        -- else --Kindle
        --     execute = io.popen("/mnt/us/koreader/fbink -t regular=/mnt/us/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1100,right=50,format " .. duration)
        -- end
        -- output = execute:read('*a')
        -- UIManager:show(InfoMessage:new{
        --     text = T(_(output)),
        --     face = Font:getFace("myfont"),
        -- })
    else
        local text = percentage
        UIManager:show(Notification:new{
            text = _(text),
        })
    end
end

function PageTextInfo:onPrintClockFbink()
    if util.getFileNameSuffix(self.ui.document.file) ~= "epub" then return end
    local clock =  datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))

    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() and not Device:isEmulator() then
        UIManager:scheduleIn(0.5, function()
            UIManager:setDirty("all", "full")
        end)
        local execute = nil
        if Device:isKobo() then
            execute = io.popen("/mnt/onboard/.adds/koreader/fbink -f -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. clock .. "\"")
        elseif Device:isKindle() then
            execute = io.popen("/mnt/us/koreader/fbink -f -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \""  .. clock .. "\"")
        else --PocketBook
            execute = io.popen("/mnt/ext1/applications/koreader/fbink -f -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. clock .. "\"")
        end

        output = execute:read('*a')
        execute:close()
        -- if Device:isKobo() then
        --     execute = io.popen("/mnt/onboard/.adds/koreader/fbink -t regular=/mnt/onboard/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1150,right=50,format " .. duration)
        -- else --Kindle
        --     execute = io.popen("/mnt/us/koreader/fbink -t regular=/mnt/us/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1100,right=50,format " .. duration)
        -- end
        -- output = execute:read('*a')
        -- UIManager:show(InfoMessage:new{
        --     text = T(_(output)),
        --     face = Font:getFace("myfont"),
        -- })
    else
        local text = clock
        UIManager:show(Notification:new{
            text = _(text),
        })
    end
end

function PageTextInfo:onPrintDurationChapterFbink()
    if util.getFileNameSuffix(self.ui.document.file) ~= "epub" then return end
    if not self.ui.toc then
        return "n/a"
    end

    local left = self.ui.toc:getChapterPagesLeft(self.view.state.page) or self.ui.document:getTotalPagesLeft(self.view.state.page)
    left = (self.ui.statistics and "Cur: " .. self.ui.statistics:getTimeForPages(left) or _("N/A"))

    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() and not Device:isEmulator() then
        UIManager:scheduleIn(0.5, function()
            UIManager:setDirty("all", "full")
        end)

        local execute = nil
        if Device:isKobo() then
            execute = io.popen("/mnt/onboard/.adds/koreader/fbink -f -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. left .. "\"")
        elseif Device:isKindle() then
            execute = io.popen("/mnt/us/koreader/fbink -f -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. left .. "\"")
        else --PocketBook
            execute = io.popen("/mnt/ext1/applications/koreader/fbink -f -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. left .. "\"")
        end


        output = execute:read('*a')
        execute:close()
        -- if Device:isKobo() then
        --     execute = io.popen("/mnt/onboard/.adds/koreader/fbink -t regular=/mnt/onboard/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1150,right=50,format " .. duration)
        -- else --Kindle
        --     execute = io.popen("/mnt/us/koreader/fbink -t regular=/mnt/us/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1100,right=50,format " .. duration)
        -- end
        -- output = execute:read('*a')
        -- UIManager:show(InfoMessage:new{
        --     text = T(_(output)),
        --     face = Font:getFace("myfont"),
        -- })
    else
        local text = left
        UIManager:show(Notification:new{
            text = _(text),
        })
    end
end

function PageTextInfo:onPrintDurationNextChapterFbink()
    if util.getFileNameSuffix(self.ui.document.file) ~= "epub" then return end
    if not self.ui.toc then
        return "n/a"
    end

    local sigcap = self.ui.toc:getNextChapter(self.view.state.page, self.toc_level)
    if sigcap == nil then
    return "n/a"
    end
    local sigcap2 = self.ui.toc:getNextChapter(sigcap + 1, self.toc_level)
    if sigcap2 == nil then
        return "n/a"
    end
    sigcap2 = (self.ui.statistics and "Sig: " .. self.ui.statistics:getTimeForPages(sigcap2 - sigcap) or _("N/A"))
    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() and not Device:isEmulator() then
        UIManager:scheduleIn(0.5, function()
            UIManager:setDirty("all", "full")
        end)
        local execute = nil
        if Device:isKobo() then
            execute = io.popen("/mnt/onboard/.adds/koreader/fbink -f -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. sigcap2 .. "\"")
        elseif Device:isKindle() then
            execute = io.popen("/mnt/us/koreader/fbink -f -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. sigcap2 .. "\"")
        else --PocketBook
            execute = io.popen("/mnt/ext1/applications/koreader/fbink -f -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. sigcap2 .. "\"")
        end

        output = execute:read('*a')
        execute:close()
        -- if Device:isKobo() then
        --     execute = io.popen("/mnt/onboard/.adds/koreader/fbink -t regular=/mnt/onboard/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1150,right=50,format " .. duration)
        -- else --Kindle
        --     execute = io.popen("/mnt/us/koreader/fbink -t regular=/mnt/us/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1100,right=50,format " .. duration)
        -- end
        -- output = execute:read('*a')
        -- UIManager:show(InfoMessage:new{
        --     text = T(_(output)),
        --     face = Font:getFace("myfont"),
        -- })
    else
        local text = sigcap2
        UIManager:show(Notification:new{
            text = _(text),
        })
    end
end

function PageTextInfo:onPrintWpmSessionFbink()
    if util.getFileNameSuffix(self.ui.document.file) ~= "epub" then return end
    local duration_raw =  math.floor(((os.time() - self.ui.statistics.start_current_period)/60)* 100) / 100
    local wpm_session,_words_session = duration_raw
    if duration_raw == 0 then
        wpm_session = 0
        words_session = 0
    else
        wpm_session = math.floor(self.ui.statistics._total_words/duration_raw)
        words_session = self.ui.statistics._total_words
    end

    wpm_session  = wpm_session .. "wpm"
    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() and not Device:isEmulator() then
        UIManager:scheduleIn(0.5, function()
            UIManager:setDirty("all", "full")
        end)
        local execute = nil
        if Device:isKobo() then
            execute = io.popen("/mnt/onboard/.adds/koreader/fbink -f -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. wpm_session .. "\"")
        elseif Device:isKindle() then
            execute = io.popen("/mnt/us/koreader/fbink -f -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. wpm_session .. "\"")
        else --PocketBook
            execute = io.popen("/mnt/ext1/applications/koreader/fbink -f -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. wpm_session .. "\"")
        end
        output = execute:read('*a')
        execute:close()
    else
        local text = wpm_session
        UIManager:show(Notification:new{
            text = _(text),
        })
    end
end

function PageTextInfo:onGetStyles()
    if util.getFileNameSuffix(self.ui.document.file) ~= "epub" then return end
    local css_text = self.ui.document:getDocumentFileContent("OPS/styles/stylesheet.css")
    if css_text == nil then
        css_text = self.ui.document:getDocumentFileContent("stylesheet.css")
    end

    -- Special case for resources/arthur-conan-doyle_the-hound-of-the-baskervilles.epub but no important, since div and p tags don't use classes in this document
    if css_text == nil then
        css_text = self.ui.document:getDocumentFileContent("epub/css/core.css")
    end


    local first_text = self.ui.document._document:getTextFromPositions(0, 0, 10, Screen:getHeight(), false, false)
    local html, css_files, css_selectors_offsets =
    self.ui.document._document:getHTMLFromXPointers(first_text.pos0, first_text.pos1, 0xE830, true)
    if html == nil then
        local text =  "Could not retrieve styles"
        UIManager:show(InfoMessage:new{
            text = T(_(text)),
            no_refresh_on_close = false,
            face = Font:getFace("myfont3"),
            width = math.floor(Screen:getWidth() * 0.85),
        })
        return true
    end
    local htmlw=""

    -- No puedo hacerlo con gmatch, iré línea a línea que además viene bien para extraer las clases
    -- for w in string.gmatch(html, "(<%w* class=\"%w*\">)") do
    -- for w in string.gmatch(html,"(<%w* class=\"(.-)\">)") do
    --    htmlw = htmlw .. "," .. w
    -- end
    local classes = ""
    for line in html:gmatch("[^\n]+") do
        if (line:find("^.*<body") ~= nil or line:find("^.*<p") ~= nil or line:find("^.*<div") ~= nil) and line:find("class=") ~= nil then
            htmlw = htmlw .. "," .. string.match(line, " %b<>")
            classes = classes .. "," .. string.match(line, "class=\"(.-)\"")
            if line:find("^.*<span") ~= nil and string.match(line, "<span.*>$"):match("%b<>"):find("class") ~= nil then
                htmlw = htmlw .. "," .. string.match(line, "<span.*>$"):match("%b<>")
                classes = classes .. "," .. string.match(line, "<span.*>$"):match("%b<>"):match("class=\"(.-)\"")
            end
        end
    end
    -- Algunas clases contienen el caracter -. Tenemos que escaparlo
    classes = classes:sub(2,classes:len()):gsub("%-", "%%-")
    local csss = ""
    local csss_classes = ""
    for line in classes:gmatch("[^,]+") do
        if string.find(line, " ") then
            for line2 in classes:gmatch("[^ ]+") do
                local css_class = string.match(css_text, "%." .. line2 .. " %b{}")
                if css_class ~= nil and csss:match("%." .. line2 .. " {") == nil then
                    csss = csss .. css_class .. "\n"
                    csss_classes = csss_classes .. line2 .. ","
                end
            end
        else
            -- The regex was not matching properly thr classes, matching for instance fmtx when tx
            -- We match first the initial class dot scaping it in the regex
            local css_class = string.match(css_text, "%." .. line .. " %b{}")
            if css_class ~= nil and csss:match("%." .. line .. " {") == nil then
                csss = csss .. css_class .. "\n"
                csss_classes = csss_classes .. line .. ","
            end
        end
    end
    csss_classes = csss_classes:sub(1,csss_classes:len() - 1):gsub("%%", "")
    htmlw = htmlw:sub(2,htmlw:len())

    local text =  string.char(10) .. htmlw
    .. string.char(10) .. csss_classes
    .. string.char(10) .. csss
    UIManager:show(TextViewer:new{
        title = "Book styles",
        title_multilines = true,
        text = text,
        text_type = "file_content",
    })
    return true
end


-- The desktop publishing point (DTP point) or PostScript point is defined as 1/72 or 0.0138 of the international inch
-- In the United States and Great Britain, the point is approximately one-seventy-second of an inch (.351 mm), or one-twelfth of a pica and is called a pica point
-- In Europe, the point is a little bigger (.376 mm) and is called a Didot point
--  1pt = 0.93575 Didot point

-- The official size is 1 Didot point = 0.3759mm.
-- Convierte a  mm y multiplica por 0.3759mm (1000/2660) para pasar a Didot points

local function convertSizeTo(px, format)
    local format_factor = 1 -- we are defaulting on mm
    -- If we remove (2660 / 1000) the result are in mm
    if format == "pt" then
        format_factor =  format_factor * (2660 / 1000) -- see https://www.wikiwand.com/en/Metric_typographic_units
    elseif format == "in" then
        format_factor = 1 / 25.4
    end

    --  Screen:scaleBySize(px) returns real pixels from the number used in KOReader after scalating it taking into account device resolution and software dpi if set
    local display_dpi = Device:getDeviceScreenDPI() or Screen:getDPI() -- use device hardcoded dpi if available
    return Screen:scaleBySize(px) / display_dpi * 25.4 * format_factor

end

function PageTextInfo:onGetTextPage()
    if util.getFileNameSuffix(self.ui.document.file) ~= "epub" then return end
    local cur_page = self.ui.document:getCurrentPage()
    local res = self.ui.document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(), false, false)
    -- local name, name2, height, unitheight, height2, unitheight2, indent, unitindent, indent2, unitindent2, margin, unitmargin, margin2, unitmargin2 = "","","","","","","","","","","","","",""
    local text_properties=""

    -- print(require("dump")(res))

    -- We look first in the last element in page to retrieve styles and if we don't get information we check then the first element
    if res and res.pos1 ~= ".0" then
        name, name2, height, unitheight, height2, unitheight2, indent, unitindent, indent2, unitindent2, margin, unitmargin, margin2, unitmargin2, alignment, alignment2, fontsize, unitfontsize, fontsize2, unitfontsize2 = self.ui.document:getHeight(res.pos1)

        if name == "" and res.pos0 ~= ".0"  then
            name, name2, height, unitheight, height2, unitheight2, indent, unitindent, indent2, unitindent2, margin, unitmargin, margin2, unitmargin2, alignment, alignment2, fontsize, unitfontsize, fontsize2, unitfontsize2 = self.ui.document:getHeight(res.pos0)
        end


        -- If there is not css property line-height in any style, the CREngine return a value of -2
        -- And line-height is calculated using the font metrics
        -- I explicit calculated the value in cre.cpp
        -- lua_pushnumber(L, (float) sourceNodeParent->getFont()->getHeight()/sourceNodeParent->getFont()->getSize());

        -- The tweak does not seem to work and we won't to know which em value it is being applied considering the value of the line-height
        -- coming with the font metrics
        -- and that's why the following
        -- uniheight == "Font" means no line-height.
        -- if unitheight == "Font" and self.ui.tweaks:find("Spacing between lines %(1.2em%)") then

        -- I will leaving but, the tweak for line-height works since I modified to affect div tagas as well
        if unitheight == "Font" then
            height = height * self.ui.document.configurable.line_spacing/100
            height2 = height2 * self.ui.document.configurable.line_spacing/100
        end

        if self.ui.tweaks:find("Spacing between lines %(1.2em%)") then
            unitheight = unitheight .. "*"
            unitheight2 = unitheight2 .. "*"
        end

        if self.ui.tweaks:find("Indentation on first paragraph line") then
            unitindent = unitindent .. "*"
            unitindent2 = unitindent2 .. "*"
        end

        if self.ui.tweaks:find("Ignore publisher page margins") then
            unitmargin = unitmargin .. "*"
            unitmargin2 = unitmargin2 .. "*"
        end

        if self.ui.tweaks:find("Left align most text") or self.ui.tweaks:find("Justify most text") then
            alignment = alignment .. "*"
            alignment2 = alignment2 .. "*"
        end

        if self.ui.tweaks:find("Ignore publisher font sizes") then
            unitfontsize = unitfontsize .. "*"
            unitfontsize2 = unitfontsize2 .. "*"
        end

        if name ~= "" then
            local Math = require("optmath")
            -- If p doesnt have a class with line-height and body or the container tag does,
            -- it inherits the value
            height = Math.round(height*100)/100 .. unitheight
            height2 = Math.round(height2*100)/100 .. unitheight2
            indent = Math.round(indent*100)/100 .. unitindent
            indent2 = Math.round(indent2*100)/100 .. unitindent2
            margin =  Math.round(margin*100)/100 .. unitmargin
            margin2 = Math.round(margin2*100)/100 .. unitmargin2
            -- fontsize3 = string.format("%.2fp", convertSizeTo(fontsize, "pt"))
            -- This comes always in pxs, we convert it back to pt
            -- See readerfont function onSetFontSize()
            -- local display_dpi = Device:getDeviceScreenDPI() or Screen:getDPI()
            -- fontsize3 = Math.round((72 * fontsize / display_dpi)* 10)/10 .. "pt"
            -- fontsize4 = Math.round((72 * fontsize2 / display_dpi)* 10)/10 .. "pt"
            -- fontsize =  fontsize .. unitfontsize
            -- fontsize2 = fontsize2 .. unitfontsize2
            text_properties = string.format("%-15s%-10s%-5s","Tag",name2,name) .. string.char(10)
            text_properties = text_properties .. string.format("%-15s%-10s%-5s", "Line height", height2, height) .. string.char(10)
            text_properties = text_properties .. string.format("%-15s%-10s%-5s", "Text indent", indent2, indent) .. string.char(10)
            text_properties = text_properties .. string.format("%-15s%-10s%-5s", "Margin", margin2, margin) .. string.char(10)
            text_properties = text_properties .. string.format("%-15s%-10s%-5s", "Text align", alignment, alignment2) .. string.char(10)
            -- text_properties = text_properties .. string.format("%-15s%-15s%-5s", "Font size", fontsize .. ", " .. fontsize3, fontsize2 .. ", " .. fontsize4)
        else
            text_properties = "Can't find positions to retrieve styles:" .. string.char(10)
            text_properties = text_properties .. "Pos 0: " ..  res.pos0 .. string.char(10)
            text_properties = text_properties .. "Pos 1: " .. res.pos1
        end
    end


    local font_size = self.ui.document._document:getFontSize()
    local font_face = self.ui.document._document:getFontFace()


    local display_dpi = Device:getDeviceScreenDPI() or Screen:getDPI()


    -- local font_size_pt = math.floor((font_size * 72 / display_dpi) * 100) / 100
    -- local font_size_mm = math.floor((font_size * 25.4 / display_dpi)  * 100) / 100

    -- We have now points in the font size
    local font_size_pt =  self.ui.document.configurable.font_size
    local font_size_mm =  self.ui.document.configurable.font_size * 0.35

    -- Calculates the visual angle in arcminutes from size (mm) and distance (mm)
    function arcminutes_from_mm(size_mm, distance_mm)
        -- Visual angle in radians: 2 * atan(size / (2 * distance))
        local angle_rad = 2 * math.atan(size_mm / (2 * distance_mm))
        -- Convert to degrees
        local angle_deg = math.deg(angle_rad)
        -- Convert to arcminutes (1 degree = 60 arcminutes)
        local angle_arcmin = angle_deg * 60
        return angle_arcmin
    end
    local RenderText = require("ui/rendertext")
    local Math = require("optmath")
    local current_face = font_face:gsub("%s+", "") .. "-Regular"
    local display_dpi = Device:getDeviceScreenDPI() or Screen:getDPI()
    local size_px = (display_dpi * self.ui.document.configurable.font_size)/72

    local face_base = Font:getFace(current_face, size_px, 0, false);
    local x_height = 0
    local x_height_mm = 0
    local arcminutes_40cm = 0
    local font_weight = 0
    if face_base == nil then
        x_height = "N/A"
        x_height_mm = "N/A"
        arcminutes_40cm = "N/A"
        font_weight = "N/A"
    else
        local glyph = RenderText:getGlyph(face_base, 120)

        -- The parameter sxHeight in the OS/2 table does not exist for all the fonts and it is not accurate for some of them (Crimson Text)
        -- The xheight property created for glyphs in the source freetype.lua as tonumber(glyph.metrics.horiBearingY / 64) neither it is
        -- if face_base.ftsize:getSxHeight() > 0 then
        --     local ratio = face_base.ftsize:getSxHeight() / face_base.ftsize:getUnitsPerEM()
        --     x_height = Math.round(ratio * size_px * 100) / 100
        -- else
        --     x_height = glyph.xheight
        -- end

        -- We use this getXHeight() which computed the correct value
        x_height = Math.round(face_base.ftsize:getXHeight() * size_px)
        x_height_mm = Math.round((x_height * (25.4 / display_dpi) * 100)) / 100
        arcminutes_40cm = arcminutes_from_mm(x_height_mm, 400)
        x_height = x_height .."px"
        x_height_mm = x_height_mm .."mm"
        arcminutes_40cm = string.format("%.1f′ @40cm", arcminutes_40cm)
        font_weight = 400 + self.ui.document.configurable.font_base_weight * 100
    end

    local readability = self.readability_table[current_face] and self.readability_table[current_face] or "N/A"
    -- The desktop publishing point (DTP point) or PostScript point is defined as 1/72 or 0.0138 of the international inch
    -- We have now points in the font size, converting to didot points is simple, 1 points = 0.93575007368111 didot points
    -- local font_size_pt_koreader = string.format(" (%.2fp)", convertSizeTo(self.ui.document.configurable.font_size, "pt"))
    local font_size_pt_koreader = string.format(" (%.2fp)", self.ui.document.configurable.font_size * 0.94)
    -- if Device:isKobo() or Device:isPocketBook() or Device.model == "boox" then
    --     font_size_pt = math.floor((font_size * 72 / 300) * 100) / 100
    --     font_size_mm = math.floor((font_size * 25.4 / 300)  * 100) / 100
    -- elseif Device:isAndroid() then
    --     font_size_pt = math.floor((font_size * 72 / 446) * 100) / 100
    --     font_size_mm = math.floor((font_size * 25.4 / 446)  * 100) / 100
    -- else
    --     font_size_pt = math.floor((font_size * 72 / 160) * 100) / 100
    --     font_size_mm = math.floor((font_size * 25.4 / 160)  * 100) / 100
    -- end


    local sessions, avg_wpm, avg_last_seven_days, avg_last_thirty_days, avg_last_sixty_days, avg_last_ninety_days, avg_last_hundred_and_eighty_days = getSessionsInfo(self.ui.view.footer)
    avg_wpm = math.floor(avg_wpm) .. "wpm" .. ", " .. math.floor(avg_wpm*60) .. "wph"

    local text = "Font: " .. font_face .. " (" .. readability .. ")" .. string.char(10) ..
    "Font size: " .. font_size .. "px, " .. font_size_pt .. "pt" .. font_size_pt_koreader .. ", " .. font_size_mm .. "mm" .. string.char(10) ..
    "Font weight: " .. font_weight .. string.char(10) ..
    "Device resolution: " .. Screen:getWidth() .. "x" .. Screen:getHeight() .. ", " .. display_dpi .. "ppi" .. string.char(10) ..
    "Font x-height: " .. x_height .. ", " .. x_height_mm .. " (" .. arcminutes_40cm .. ")" .. string.char(10) ..
    " • ~20′ is ideal for effortless reading" .. string.char(10) ..
    " • <15′ may strain the eyes without good contrast" .. string.char(10) ..
    " • >25′ feels oversized and slows reading" .. string.char(10) ..
    "At ~40cm, forearm length (from elbow to knuckles):" .. string.char(10) ..
    " • 2.1–2.6 mm (18–22′) optimal · effortless reading" .. string.char(10) ..
    " • 1.7–1.85 mm (14.6–15.9′) compact yet comfortable · preferred aesthetic range" .. string.char(10) ..
    " • <1.7 mm (<14.6′) low/demanding · needs good contrast & sharp rendering" .. string.char(10) ..
    " • >2.6 mm (>22.3′) too large · disrupts flow and density" .. string.char(10) .. string.char(10) ..
    "Applied tweaks: " .. self.ui.tweaks_no .. string.char(10) ..
    self.ui.tweaks .. string.char(10) ..
    text_properties
    UIManager:show(InfoMessage:new{
        text = T(_(text)),
        face = Font:getFace("myfont3"),
        width = math.floor(Screen:getWidth() * 0.7),
    })
    return true
end

local WPP = 240

getSessionsInfo = function(footer)
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    if not footer.ui.statistics then
        return "n/a"
    end
    local session_started = footer.ui.statistics.start_current_period
    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
    -- best to e it to letters, to get '2m' ?
    user_duration_format = "letters"

    -- No necesitamos el id del libro para poder traer las páginas en la sesión actual
    local id_book = footer.ui.statistics.id_curr_book
    if id_book == nil then
        id_book = 0
    end

    local conn = SQ3.open(db_location)
    local sql_stmt ="SELECT count(id_book) AS sessions FROM wpm_stat_data"
    local sessions = conn:rowexec(sql_stmt)
    local sql_stmt ="SELECT avg(wpm) FROM wpm_stat_data where wpm > 0"
    local avg_wpm = conn:rowexec(sql_stmt)

    sql_stmt = [[SELECT SUM(sum_duration)
        FROM   (
                    SELECT sum(duration)    AS sum_duration
                    FROM   wpm_stat_data
                WHERE DATE(start_time,'unixepoch','localtime') > DATE(DATE('now', '-7 day','localtime'),'localtime')
                GROUP BY DATE(start_time,'unixepoch','localtime'));"
                );
    ]]
    local avg_last_seven_days = conn:rowexec(sql_stmt)

    sql_stmt = [[SELECT SUM(sum_duration)
    FROM   (
                SELECT sum(duration)    AS sum_duration
                FROM   wpm_stat_data
            WHERE DATE(start_time,'unixepoch','localtime') > DATE(DATE('now', '-30 day','localtime'),'localtime')
            GROUP BY DATE(start_time,'unixepoch','localtime'));"
            );
    ]]
    local avg_last_thirty_days = conn:rowexec(sql_stmt)


    sql_stmt = [[SELECT SUM(sum_duration)
    FROM   (
                SELECT sum(duration)    AS sum_duration
                FROM   wpm_stat_data
            WHERE DATE(start_time,'unixepoch','localtime') > DATE(DATE('now', '-60 day','localtime'),'localtime')
            GROUP BY DATE(start_time,'unixepoch','localtime'));"
            );
    ]]
    local avg_last_sixty_days = conn:rowexec(sql_stmt)

    sql_stmt = [[SELECT SUM(sum_duration)
    FROM   (
                SELECT sum(duration)    AS sum_duration
                FROM   wpm_stat_data
            WHERE DATE(start_time,'unixepoch','localtime') > DATE(DATE('now', '-90 day','localtime'),'localtime')
            GROUP BY DATE(start_time,'unixepoch','localtime'));"
            );
    ]]
    local avg_last_ninety_days = conn:rowexec(sql_stmt)

    sql_stmt = [[SELECT SUM(sum_duration)
    FROM   (
                SELECT sum(duration)    AS sum_duration
                FROM   wpm_stat_data
            WHERE DATE(start_time,'unixepoch','localtime') > DATE(DATE('now', '-180 day','localtime'),'localtime')
            GROUP BY DATE(start_time,'unixepoch','localtime'));"
            );
    ]]
    local avg_last_hundred_and_eighty_days = conn:rowexec(sql_stmt)

    conn:close()
    if sessions == nil then
        sessions = 0
    end
    sessions = tonumber(sessions)

    if avg_wpm == nil then
        avg_wpm = 0
    end

    avg_wpm = tonumber(avg_wpm)
    if avg_last_seven_days == nil then
        avg_last_seven_days = 0
    end

    if avg_last_thirty_days == nil then
        avg_last_thirty_days = 0
    end

    if avg_last_sixty_days == nil then
        avg_last_sixty_days = 0
    end

    if avg_last_ninety_days == nil then
        avg_last_ninety_days = 0
    end

    if avg_last_hundred_and_eighty_days == nil then
        avg_last_hundred_and_eighty_days = 0
    end

    avg_last_seven_days = math.floor(tonumber(avg_last_seven_days)/7/60/60 * 100)/100
    avg_last_thirty_days = math.floor(tonumber(avg_last_thirty_days)/30/60/60 * 100)/100
    avg_last_sixty_days = math.floor(tonumber(avg_last_sixty_days)/60/60/60 * 100)/100
    avg_last_ninety_days = math.floor(tonumber(avg_last_ninety_days)/90/60/60 * 100)/100
    avg_last_hundred_and_eighty_days = math.floor(tonumber(avg_last_hundred_and_eighty_days)/180/60/60 * 100)/100

    return sessions, avg_wpm, avg_last_seven_days, avg_last_thirty_days, avg_last_sixty_days, avg_last_ninety_days, avg_last_hundred_and_eighty_days
end

getSessionStats = function(footer)
        local DataStorage = require("datastorage")
        local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
        if not footer.ui.statistics then
            return "n/a"
        end



        local session_started = footer.ui.statistics.start_current_period
        local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
        -- best to e it to letters, to get '2m' ?
        -- user_duration_format = "letters"

        -- No necesitamos el id del libro para poder traer las páginas en la sesión actual
        local id_book = footer.ui.statistics.id_curr_book
        if id_book == nil then
            id_book = 0
        end

        local conn = SQ3.open(db_location)
        local sql_stmt = [[
            SELECT count(*)
            FROM   (
                        SELECT sum(duration)    AS sum_duration
                        FROM   page_stat
                        WHERE  start_time >= %d
                        GROUP  BY id_book, page
                   );
        ]]
        local pages_read_session = conn:rowexec(string.format(sql_stmt, session_started))


        local sql_stmt = [[
                SELECT pages
                FROM   book
                WHERE  id = %d;
        ]]


        local total_pages = conn:rowexec(string.format(sql_stmt, id_book))


        local sql_stmt = [[
            SELECT sum(sum_duration)
            FROM    (
                         SELECT sum(duration)    AS sum_duration
                         FROM   page_stat
                         WHERE  start_time >= %d
                         GROUP  BY id_book, page
                    );
        ]]

        local now_stamp = os.time()
        local now_t = os.date("*t")
        local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
        local start_today_time = now_stamp - from_begin_day

        local read_today = conn:rowexec(string.format(sql_stmt,start_today_time))

        local flow = footer.ui.document:getPageFlow(footer.pageno)

        conn:close()
        if pages_read_session == nil then
            pages_read_session = 0
        end
        pages_read_session = tonumber(pages_read_session)

        if total_pages == nil then
            total_pages = 0
        end
        total_pages = tonumber(total_pages)
        --local percentage_session = footer.pageno/total_pages

        if read_today == nil then
            read_today = 0
        end
        read_today = tonumber(read_today)

        local percentage_session = pages_read_session/total_pages
        local wpm_session = 0

        -- local title_pages = footer.ui.document._document:getDocumentProps().title
        -- local title_words = 0
        -- if (title_pages:find("([0-9,]+w)") ~= nil) then
        --     title_words = title_pages:match("([0-9,]+w)"):gsub("w",""):gsub(",","")
        -- end
        -- -- Just to calculate the sesssion wpm I will assume the WPP to be calculated with the books number of words/syntetic pages for the configuration
        -- -- Not accurate since pages we turn quick are counted when they should not
        -- WPP_SESSION = math.floor((title_words/footer.pages * 100) / 100)
        if pages_read_session > 0 then
            wpm_session = math.floor(((pages_read_session * WPP)/((os.time() - session_started)/60))* 100) / 100
        end

        local words_session = pages_read_session * WPP
        -- logger.warn(pages_read_session)
        -- logger.warn(percentage_session)

        percentage_session = math.floor(percentage_session*1000)/10
        local duration = datetime.secondsToClockDuration(user_duration_format, os.time() - session_started, false)


        local duration_raw =  math.floor(((os.time() - session_started)/60)* 100) / 100
        if duration_raw == nil then
            duration_raw = 0
        end
        return percentage_session, pages_read_session, duration, wpm_session, words_session, duration_raw, read_today
    end

getTodayBookStats = function()
    local now_stamp = os.time()
    local now_t = os.date("*t")
    local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
    local start_today_time = now_stamp - from_begin_day
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT sum(duration), SUM(total_pages)
        FROM   wpm_stat_data
        WHERE  start_time >= %d
    ]]
    local today_duration, today_pages =  conn:rowexec(string.format(sql_stmt, start_today_time))
    conn:close()
    if today_pages == nil then
        today_pages = 0
    end
    if today_duration == nil then
        today_duration = 0
    end
    today_duration = tonumber(today_duration)
    today_pages = tonumber(today_pages)
    local wpm_today = 0
    if today_pages > 0 then
        wpm_today = math.floor(((today_pages * WPP)/((today_duration)/60))* 100) / 100
    end

    local words_today = today_pages * WPP
    return today_duration, today_pages, wpm_today, words_today
end

getThisWeekBookStats = function()
    local now_stamp = os.time()
    local now_t = os.date("*t")
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
    local start_today_time = now_stamp - from_begin_day
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT sum(duration), SUM(total_pages)
        FROM   wpm_stat_data
        WHERE  start_time >= strftime('%s', DATE('now', 'weekday 0','-6 day'))
    ]]
   local week_duration, week_pages = conn:rowexec(sql_stmt)
    conn:close()
    if week_pages == nil then
        week_pages = 0
    end
    if week_duration == nil then
        week_duration = 0
    end
    week_duration = tonumber(week_duration)
    week_pages = tonumber(week_pages)

    local wpm_week = 0
    if week_pages > 0 then
        wpm_week = math.floor(((week_pages * WPP)/((week_duration)/60))* 100) / 100
    end

    local words_week = week_pages * WPP

    return week_duration, week_pages, wpm_week, words_week
end

getThisMonthBookStats = function()
    local now_stamp = os.time()
    local now_t = os.date("*t")
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
    local start_today_time = now_stamp - from_begin_day
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT sum(duration), SUM(total_pages)
        FROM   wpm_stat_data
        WHERE DATE(start_time, 'unixepoch', 'localtime') >= DATE('now', 'localtime', 'start of month')
    ]]
   local month_duration, month_pages = conn:rowexec(sql_stmt)
    conn:close()
    if month_pages == nil then
        month_pages = 0
    end
    if month_duration == nil then
        month_duration = 0
    end
    month_duration = tonumber(month_duration)
    month_pages = tonumber(month_pages)

    local wpm_month = 0
    if month_pages > 0 then
        wpm_month = math.floor(((month_pages * WPP)/((month_duration)/60))* 100) / 100
    end

    local words_week = month_pages * WPP

    return month_duration, month_pages, wpm_month, words_week
end

getReadThisBook = function(footer)
    local now_stamp = os.time()
    local now_t = os.date("*t")
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
    local start_today_time = now_stamp - from_begin_day
    local conn = SQ3.open(db_location)
    local title = footer.ui.document._document:getDocumentProps().title
    if title:match("'") then title = title:gsub("'", "''") end
    local sql_stmt = "SELECT id FROM book where title like 'titles' order by id desc LIMIT 1;"
    local id_book = conn:rowexec(sql_stmt:gsub("titles", title))

    if id_book == nil then
        id_book = 0
    end
    id_book = tonumber(id_book)

    sql_stmt ="SELECT SUM(duration) FROM wpm_stat_data where id_book = ibp"


    local total_time_book = conn:rowexec(sql_stmt:gsub("ibp", id_book))

    if total_time_book == nil then
        total_time_book = 0
    end

    conn:close()

    return total_time_book

end

function PageTextInfo:getGenreBook()
    if not self.ui then return end
    local file_type = string.lower(string.match(self.ui.document.file, ".+%.([^.]+)") or "")
    if file_type == "epub" then
        local css_text = self.ui.document:getDocumentFileContent("OPS/styles/stylesheet.css")
        if css_text == nil then
            css_text = self.ui.document:getDocumentFileContent("stylesheet.css")
        end
        if css_text == nil then
            css_text = self.ui.document:getDocumentFileContent("OEBPS/css/style.css")
        end

        -- $ bsdtar tf arthur-conan-doyle_the-hound-of-the-baskervilles.epub | grep -i css
        -- epub/css/
        -- epub/css/core.css
        -- epub/css/se.css
        -- epub/css/local.css
        if css_text == nil then
            css_text = self.ui.document:getDocumentFileContent("epub/css/core.css")
        end

        local opf_text = self.ui.document:getDocumentFileContent("OPS/Miscellaneous/content.opf")
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("content.opf")
        end

        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("OPS/volume.opf")
        end
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("volume.opf")
        end

        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("OEBPS/volume.opf")
        end

        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("OEBPS/Miscellaneous/content.opf")
        end
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("OEBPS/content.opf")
        end
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("content.opf")
        end

        -- $ bsdtar tf arthur-conan-doyle_the-hound-of-the-baskervilles.epub | grep -i content
        -- epub/content.opf
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("epub/content.opf")
        end

        local origin = string.match(opf_text, "<opf:meta property=\"calibre:user_metadata\">(.-)</opf:meta>")
        if origin ~= nil then
            origin = string.match(origin, "\"#genre\": {(.-)}")
            if origin ~= nil then
                origin = string.match(origin, " \"#value#\": \".-\"")
                if origin ~= nil then
                    origin = string.match(origin, ": .*")
                    origin = origin:sub(4,origin:len() - 1)
                end
            end
        end
        return origin
    end
end

function PageTextInfo:onShowTextProperties()
    if util.getFileNameSuffix(self.ui.document.file) ~= "epub" then return end
    if not self.ui.rolling then
        return "n/a"
    end
    if not self.ui.toc then
        return "n/a"
    end

    local nblines, nbwords = self.ui.view:getCurrentPageLineWordCounts()

    res = self.ui.document._document:getTextFromPositions(0, 0, Screen:getWidth(), 1, false, true)
    local characters_first_line = 0
    if res and res.text then
        characters_first_line = #res.text
    end
    local font_size = self.ui.document._document:getFontSize()
    local font_face = self.ui.document._document:getFontFace()
    local title_pages = self.ui.document._document:getDocumentProps().title
    local author = self.ui.document._document:getDocumentProps().authors

    if author == "" then
        author = "No metadata"
    end
    if not self.ui.statistics.data.pages then
        return "n/a"
    end
    self.ui.statistics:insertDB()
    local avg_words = 0
    local avg_chars = 0
    local avg_chars_per_word = 0
    if self.ui.statistics._pages_turned > 0 then
        avg_words = math.floor(self.ui.statistics._total_words/self.ui.statistics._pages_turned)
        avg_chars = math.floor(self.ui.statistics._total_chars/self.ui.statistics._pages_turned)
        avg_chars_per_word =  math.floor((avg_chars/avg_words) * 100) / 100
    end
    local pages = self.ui.statistics.data.pages
    --  title_pages = string.match(title_pages, "%((%w+)")
    -- local title_pages_ex = string.match(title_pages, "%b()")


    -- if (title_pages_ex) then
    --     local title_words = title_pages:match("([0-9,]+w)"):gsub("w",""):gsub(",","")
    --     title_pages_ex = title_pages_ex:sub(2, title_pages_ex:len() - 1)
    -- else
    --     title_pages_ex = 0
    -- end

    local font_size_pt = nil
    local font_size_mm = nil
    if Device:isKobo() or Device:isPocketBook() or Device.model == "boox" then
        font_size_pt = math.floor((font_size * 72 / 300) * 100) / 100
        font_size_mm = math.floor((font_size * 25.4 / 300)  * 100) / 100
    elseif Device:isAndroid() then
        font_size_pt = math.floor((font_size * 72 / 446) * 100) / 100
        font_size_mm = math.floor((font_size * 25.4 / 446)  * 100) / 100
    else
        font_size_pt = math.floor((font_size * 72 / 160) * 100) / 100
        font_size_mm = math.floor((font_size * 25.4 / 160)  * 100) / 100
    end
    local chapter = self.ui.toc:getTocTitleByPage(self.view.state.page)
    local powerd = Device:getPowerDevice()
    local frontlight = ""
    local frontlightwarm = ""
    if powerd:isFrontlightOn() then
        local warmth = powerd:frontlightWarmth()
        if warmth then
            frontlightwarm = (" %d%%"):format(warmth)
        end
        frontlight = ("L: %d%%"):format(powerd:frontlightIntensity())
    end

  -- local css_text_body = string.match(css_text, "body %b{}")
    -- if css_text_body == nil then
    --     css_text_body = "No body style"
    -- end

    -- local css_text_calibre = string.match(css_text, "calibre %b{}")
    -- if css_text_calibre == nil then
    --     css_text_calibre = "No calibre style"
    -- end

    -- local css_text_calibre1 = string.match(css_text, "calibre1 %b{}")
    -- if css_text_calibre1 == nil then
    --     css_text_calibre1 = "No calibre1 style"
    -- end

    -- Mirar el fichero container.xml para verlo
    -- <rootfiles>
    --     <rootfile full-path="OEBPS/content.opf"
    --         media-type="application/oebps-package+xml" />
    -- </rootfiles>

    local opf_genre = ""
    local file_type = string.lower(string.match(self.ui.document.file, ".+%.([^.]+)") or "")
    if file_type == "epub" then
        local css_text = self.ui.document:getDocumentFileContent("OPS/styles/stylesheet.css")
        if css_text == nil then
            css_text = self.ui.document:getDocumentFileContent("stylesheet.css")
        end
        if css_text == nil then
            css_text = self.ui.document:getDocumentFileContent("OEBPS/css/style.css")
        end

        -- $ bsdtar tf arthur-conan-doyle_the-hound-of-the-baskervilles.epub | grep -i css
        -- epub/css/
        -- epub/css/core.css
        -- epub/css/se.css
        -- epub/css/local.css
        if css_text == nil then
            css_text = self.ui.document:getDocumentFileContent("epub/css/core.css")
        end

        local opf_text = self.ui.document:getDocumentFileContent("OPS/Miscellaneous/content.opf")
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("content.opf")
        end

        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("OPS/volume.opf")
        end
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("volume.opf")
        end

        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("OEBPS/Miscellaneous/content.opf")
        end
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("OEBPS/content.opf")
        end
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("content.opf")
        end

        -- $ bsdtar tf arthur-conan-doyle_the-hound-of-the-baskervilles.epub | grep -i content
        -- epub/content.opf
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("epub/content.opf")
        end

        if opf_text == nil then
            opf_genre = "No opf found"
        else
            for w in string.gmatch(opf_text, "<dc:subject>(.-)</dc:subject>") do
                opf_genre = opf_genre .. ", " .. w
            end
            opf_genre = opf_genre:sub(3,string.len(opf_genre))

            if opf_genre == "" then
                opf_genre = "No metadata"
            end
            -- local opf_calibre = string.match(opf_text, "<opf:meta property=\"calibre:user_metadata\">(.-)</opf:meta>")
            -- if opf_calibre == nil then
            --     opf_calibre = "No property"
            -- else

            --     opf_calibre = string.match(opf_calibre, "\"#genre\": {(.-)}")
            --     opf_calibre = string.match(opf_calibre, " \"#value#\": \".-\"")
            --     opf_calibre = string.match(opf_calibre, ": .*")
            --     opf_calibre = opf_calibre:sub(4,opf_calibre:len() - 1)
            -- end
        end
    end

    local spp = math.floor(self.ui.statistics.avg_time)
    local pages_read = self.ui.statistics.book_read_pages
    local time_read = self.ui.statistics.book_read_time
    -- local wpm = 0
    -- local wph = 0
    -- local wpm_test = 0
    -- if pages_read > 0 and time_read > 0 then
    --     local title_words = self.ui.document._document:getDocumentProps().title
    --     local title_words_ex = string.match(title_words, "%b()")
    --     title_words_ex = title_words_ex:sub(2, title_words_ex:len() - 1)
    --     title_words_ex = string.match(title_words_ex, "%- .*")
    --     title_words_ex = title_words_ex:sub(2,title_words_ex:len() - 1):gsub(",","")
    --     local percentage = self.progress_bar.percentage * 100
    --     wpm_test =  math.floor((title_words_ex * self.progress_bar.percentage/(time_read/60)))

    --     wpm = math.floor((pages_read * WPP)/(time_read/60))
    --     wph = math.floor((pages_read * WPP)/(time_read/60/60))
    -- end

    -- -- Extraigo la información más fácil así
    -- title_pages = self.ui.document._document:getDocumentProps().title

    -- local title_words, avg_words_cal, avg_chars_cal, avg_chars_per_word_cal = 0, 0, 0 ,0
    -- if (title_pages:find("([0-9,]+w)") ~= nil) then
    --     title_words = title_pages:match("([0-9,]+w)")
    --     avg_words_cal = math.floor(title_words:sub(1,title_words:len() - 1):gsub(",","")/pages)
    --     -- Estimated 5.7 chars per words
    --     avg_chars_cal = math.floor(avg_words_cal * 5.7)
    --     avg_chars_per_word_cal = math.floor((avg_chars_cal/avg_words_cal) * 100) / 100
    -- end
    local user_duration_format = "letters"

    local duration_raw =  math.floor(((os.time() - self.ui.statistics.start_current_period)/60)* 100) / 100
    local wpm_session, words_session = duration_raw, duration_raw
    if duration_raw == 0 then
        wpm_session = 0
        words_session = 0
    else
        wpm_session = math.floor(self.ui.statistics._total_words/duration_raw)
        words_session = self.ui.statistics._total_words
    end

    local wph_session = wpm_session * 60

    local percentage_session, pages_read_session, duration, wpm_session, words_session, duration_raw = getSessionStats(self.ui.view.footer)
    local progress_book = ("%d de %d"):format(self.view.state.page, self.ui.document:getPageCount())
    local string_percentage  = "%0.f%%"
    local percentage = string_percentage:format(self.view.footer.progress_bar.percentage * 100)
    local today_duration, today_pages, wpm_today, words_today = getTodayBookStats()
    local today_duration = today_duration + (self.view.topbar and (os.time() - self.view.topbar.start_session_time) or 0)
    local today_duration_number = math.floor((today_duration / 60) * 10) / 10
    today_duration = datetime.secondsToClockDuration(user_duration_format, today_duration, true)

    today_pages = today_pages + (self.ui.statistics and self.ui.statistics._total_pages or 0)
    local icon_goal_time = "⚐"
    local icon_goal_pages = "⚐"
    local goal_time = self.view.topbar and self.view.topbar.daily_time_goal or 120
    local goal_pages = self.view.topbar and self.view.topbar.daily_pages_goal or 120

    if today_duration_number >= goal_time then
        icon_goal_time = "⚑"
    end

    if today_pages >= goal_pages then
        icon_goal_pages = "⚑"
    end

    local this_week_duration, this_week_pages, wpm_week, words_week = getThisWeekBookStats()
    local this_month_duration, this_month_pages, wpm_month, words_month = getThisMonthBookStats()

    local time_reading_current_book = getReadThisBook(self.ui.view.footer)
    time_reading_current_book = time_reading_current_book + (self.view.topbar and (os.time() - self.view.topbar.start_session_time) or 0)
    time_reading_current_book = datetime.secondsToClockDuration(user_duration_format, time_reading_current_book, true)

    local this_week_duration = datetime.secondsToClockDuration(user_duration_format,this_week_duration, true)
    local this_month_duration = datetime.secondsToClockDuration(user_duration_format,this_month_duration, true)

    local left_chapter = self.ui.toc:getChapterPagesLeft(self.view.state.page) or self.ui.document:getTotalPagesLeft(self.view.state.page)
    if self.settings.pages_left_includes_current_page then
        left_chapter = left_chapter + 1
    end
    local clock ="⌚ " ..  datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))

    if duration_raw == 0 then
        wpm_session = 0
        words_session = 0
    else
        wpm_session = math.floor(self.ui.statistics._total_words/duration_raw)
        words_session = self.ui.statistics._total_words
    end
    percentage_session = pages_read_session/self.ui.document:getPageCount()
    percentage_session = math.floor(percentage_session*1000)/10
    pages_read_session =  self.ui.statistics._total_pages

    -- local sessions, avg_wpm, avg_last_seven_days, avg_last_thirty_days = getSessionsInfo(self)
    -- avg_wpm = math.floor(avg_wpm) .. "wpm" .. ", " .. math.floor(avg_wpm*60) .. "wph"

    local line = "\n────────────────────────────────\n"
    local point = "‣"
    local important = " \u{261C}"

    local title_pages = self.ui.document._document:getDocumentProps().title

    -- local title_words = 0
    -- if (title_pages:find("([0-9,]+w)") ~= nil) then
    --     title_words = title_pages:match("([0-9,]+w)"):gsub("w",""):gsub(",","")
    -- end


    local total_characters = 0
    -- if not Device:isPocketBook() then
    total_characters, total_words = self.ui.document:getBookCharactersCount()
    -- total_words = math.ceil(total_characters/5.7)
    -- total_pages = math.ceil(total_characters/1767)
    -- end

    local sessions, avg_wpm, avg_last_seven_days, avg_last_thirty_days, avg_last_sixty_days, avg_last_ninety_days, avg_last_hundred_and_eighty_days = getSessionsInfo(self.ui.view.footer)
    avg_wpm = math.floor(avg_wpm) .. "wpm" .. ", " .. math.floor(avg_wpm*60) .. "wph"

    local text = clock .. " " .. title_pages .. string.char(10) .. string.char(10)
    .. point .. " Progress book: " .. progress_book .. " (" .. percentage .. ")" ..  string.char(10)
    .. point .. " Left chapter " .. chapter .. ": " .. left_chapter  .. important
    .. line
    .. point .. " Author: " ..  author .. string.char(10)
    .. point .. " Genres: " .. opf_genre .. string.char(10)
    -- .. opf_calibre .. string.char(10)
    local genre = self:getGenreBook():match("^%w+%.(.+)$") or self:getGenreBook()
    if genre == nil or genre == "Unknown" then
        genre = "N/A"
    end
    text = text .. point .. " Main Genre: " .. genre .. string.char(10)
    if genre ~= nil and genre ~= "N/A" then
        local genre_profile = self.genres_table[genre] and self.genres_table[genre] or "N/A"
        if genre_profile.fonts ~= nil then
            text = text .. point .. " Ideal fonts to use: " .. string.char(10) .. " " .. genre_profile.description .. string.char(10)
            text = text .. point .. " Suggested fonts: " .. string.char(10)
            for font in string.gmatch(genre_profile.fonts, '([^,]+)') do
                local trimmed_font = font:match("^%s*(.-)%s*$")
                text = text .. " " .. trimmed_font.. string.char(10)
            end
            text = text .. "» Tap to apply a random profile"
        else
            text = text .. "No profile for this genre was found"
        end
    end
    text = text .. line
    text = text .. "Total pages (screens): " .. self.ui.document:getPageCount() .. string.char(10) ..
    "Total pages (1767cpp): " .. self.ui.pagemap:getLastPageLabel(true) .. string.char(10) ..

    --"Total pages assuming 1767 cpp: " .. tostring(total_pages) .. string.char(10) ..
    "Total characters: " .. tostring(total_characters) .. string.char(10) ..
    "Total words: " .. tostring(total_words) .. string.char(10) ..
    -- Dividing characters between 5.7
    "Total words (total chars/5.7): " .. tostring(math.ceil(total_characters/5.7)) .. string.char(10) -- Dividing characters between 5.7
    --"Words per screen page: " .. tostring(math.floor((total_words/self.pages * 100) / 100)) .. string.char(10)
    -- end

    --text = text .. "Total words Calibre: " .. title_words .. string.char(10) ..
    --"Words per page Calibre: " .. tostring(math.floor((title_words/self.pages * 100) / 100)) .. string.char(10) .. string.char(10) ..
    text = text .. "Total sessions in db: " .. tostring(sessions) .. string.char(10) ..
    "Average time read last 7 days: " .. avg_last_seven_days .. "h" .. string.char(10) ..
    "Average time read last 30 days: " .. avg_last_thirty_days .. "h" .. string.char(10) ..
    "Average time read last 60 days: " .. avg_last_sixty_days .. "h" .. string.char(10) ..
    "Average time read last 90 days: " .. avg_last_ninety_days .. "h" .. string.char(10) ..
    "Average time read last 180 days: " .. avg_last_hundred_and_eighty_days .. "h" .. string.char(10) ..
    "Avg wpm and wph: " .. avg_wpm .. string.char(10) .. string.char(10)

    -- .. "Avg wpm and wph in all sessions: " .. avg_wpm .. string.char(10)
    -- .. "Average time read last 7 days: " .. avg_last_seven_days .. "h" .. string.char(10)
    -- .. "Average time read last 30 days: " .. avg_last_thirty_days .. "h" .. string.char(10) .. string.char(10)
    text = text .. point .. " RTRP out of " .. goal_pages .. ": " .. (goal_pages - today_pages) .. "p " .. icon_goal_pages .. string.char(10)
    .. point .. " RTRT out of " .. goal_time .. ": " .. (goal_time - today_duration_number) .. "m " .. icon_goal_time  .. string.char(10)
    .. point .. " This book: " .. time_reading_current_book .. string.char(10)
    .. point .. " This session: " .. duration .. "(" .. percentage_session .. "%, " .. words_session .. "w)"  .. "(" .. pages_read_session.. "p) " .. wpm_session .. "wpm" .. important .. string.char(10)
    .. point .. " Today: " .. today_duration  .. "(" .. today_pages .. "p, ".. words_today .. "w) " .. wpm_today .. "wpm" .. string.char(10)
    .. point .. " Week: " .. this_week_duration  .. "(" .. this_week_pages .. "p, ".. words_week .. "w) " .. wpm_week .. "wpm" .. string.char(10)
    .. point .. " Month: " .. this_month_duration  .. "(" .. this_month_pages .. "p, ".. words_month .. "w) " .. wpm_month .. "wpm" .. string.char(10)
    -- .. point .. " Stats: wpm: " .. wpm_session .. ", wph: " .. wph_session .. string.char(10)
    -- .. point .. " Stats: wpm: " .. wpm .. ", wph: " .. wph .. ", spp: " .. spp .. ", wpmp: " .. wpm_test .. important .. string.char(10)
    -- .. point .. " Static info (from Calibre info): wpp: " .. avg_words_cal .. ", cpp: " .. avg_chars_cal .. ", cpw: " .. avg_chars_per_word_cal .. important .. string.char(10)
    -- .. point .. " Dynamic info: p: " .. self.ui.statistics._pages_turned .. ", wpp: " .. avg_words .. ", cpp: " .. avg_chars .. ", cpw: " .. avg_chars_per_word .. string.char(10) -- Not used   .. line .. string.char(10) .. string.char(10)
    -- .. pages .. "p_" .. title_pages_ex .. string.char(10) ..  font_face .. "-" ..  "S: "
    -- .. point .. " Font parameters: " .. font_face .. ", " .. font_size .. "px, " .. font_size_pt .. "pt, " .. font_size_mm .. "mm" .. important ..  string.char(10)
    .. point .. " L: " ..  nblines .. " - W: " .. nbwords .. " (CFL: " .. characters_first_line .. ")" .. important .. line
    if frontlight ~= "" or frontlightwarm ~= "" then
        text = text .. point .. " Light: " .. frontlight .. " - " .. frontlightwarm .. string.char(10)
    else
        text = text .. point .. " Light off"
    end

    -- .. string.char(10) .. html:sub(100,250)


    -- self.ui.statistics._total_chars=self.ui.statistics._total_char + nbcharacters
    -- local avg_character_pages =  self.ui.statistics._total_chars/ self.ui.statistics._pages_turned
    local TextViewer = require("ui/widget/textviewer")
    local textviewer = TextViewer:new{
        title = "Book information and stats",
        title_multilines = true,
        text = text,
        text_type = "file_content",
    }
    -- local original_onTapClose = textviewer.onTapClose
    textviewer.onTapClose = function(textviewer)
        local genre = self:getGenreBook():match("^%w+%.(.+)$") or self:getGenreBook()

        local genre_profile = self.genres_table[genre] and self.genres_table[genre] or nil
        if genre_profile == nil or genre_profile == "Unknown" then
            UIManager:show(Notification:new{
                text = _("No genre found for this book"),
            })
            -- textviewer.onTapClose = original_onTapClose
        else
            local selected_profile = genre_profile.presets[math.random(1, #genre_profile.presets)]
            local font_profile = selected_profile.font
            local weight_profile = selected_profile.weight
            local font_weight = 400 + (weight_profile * 100)
            local line_spacing_percent_profile = selected_profile.line_spacing_percent
            local line_spacing_em_profile = selected_profile.line_spacing_em
            UIManager:close(textviewer)

            UIManager:nextTick(function()
                UIManager:broadcastEvent(Event:new("SetFont", font_profile))
                UIManager:broadcastEvent(Event:new("SetFontBaseWeight", weight_profile))
                UIManager:broadcastEvent(Event:new("SetLineSpace", line_spacing_percent_profile))
                UIManager:show(Notification:new{
                    text = _(font_profile .. ", " .. font_weight .. ", " .. line_spacing_em_profile),
                })
            end)
        end
    end
    UIManager:show(textviewer)
    return true
end

function PageTextInfo:onShowNotesFooter()
    if util.getFileNameSuffix(self.ui.document.file) ~= "epub" then return end
    local texto = ""
    local res = self.ui.document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(), false, true)
    if res and res.text then
        local annotations = self.ui.annotation.annotations
        for i, item in ipairs(annotations) do
            if item.note and res.text:find(item.text) then
                texto = texto .. '<b><p style="display:block;font-size:small;">' .. item.text .. ": </b>" ..  item.note .. "<br>"
            end
        end

        if texto ~= "" then
            -- texto = "<ol>" .. texto .. "</ol>"
            texto = '<b><p style="display:block;font-size:large;">Notes found in current page: </b><br>' .. texto
            local FootnoteWidget = require("ui/widget/footnotewidget")
            local popup
            popup = FootnoteWidget:new{
                html = texto,
                doc_font_name = self.ui.font.font_face,
                doc_font_size = Screen:scaleBySize(self.ui.document.configurable.font_size),
                doc_margins = self.ui.document:getPageMargins(),
                follow_callback = function() -- follow the link on swipe west
                    UIManager:close(popup)
                end,
                dialog = self.ui.dialog,
            }
            UIManager:show(popup)
        else
            local UIManager = require("ui/uimanager")
            local Notification = require("ui/widget/notification")
            UIManager:show(Notification:new{
                text =("No notes in current page"),
            })
        end
    end
end

function PageTextInfo:onTest()
    local ConfirmBox = require("ui/widget/confirmbox")
    local multi_box= ConfirmBox:new{
        text = "Do you want to reload the document?",
        ok_text = "Yes",
        ok_callback = function()
            local ReaderUI = require("apps/reader/readerui")
            local ui = ReaderUI.instance
            ui:reloadDocument(nil, true) -- seamless reload (no infomsg, no flash)
            return true
        end,
    }

    UIManager:show(multi_box)
    -- -- Screen:clear()
    -- -- Screen:refreshFull(0, 0, Screen:getWidth(), Screen:getHeight())

    -- local util = require("ffi/util")
    -- -- util.usleep(20000000)


    -- local ScreenSaverWidget = require("ui/widget/screensaverwidget")
    -- local OverlapGroup = require("ui/widget/overlapgroup")
    -- local ImageWidget = require("ui/widget/imagewidget")
    -- local BookStatusWidget = require("ui/widget/bookstatuswidget")
    -- local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
    -- local widget_settings = {
    --     width = Screen:getWidth(),
    --     height = Screen:getHeight(),
    --     scale_factor = G_reader_settings:isFalse("screensaver_stretch_images") and 0 or nil,
    --     stretch_limit_percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage"),
    -- }
    -- local ReaderUI = require("apps/reader/readerui")
    -- local ui = ReaderUI.instance
    -- local lastfile = G_reader_settings:readSetting("screensaver_document_cover")
    -- local image = FileManagerBookInfo:getCoverImage(ui and ui.document, lastfile)
    -- widget_settings.image = image
    -- widget_settings.image_disposable = true


    -- -- if Device:isKobo() then
    -- --     widget_settings.file = "/mnt/onboard/.adds/colores.png"
    -- -- elseif Device:isPocketBook() then
    -- --     widget_settings.file = "/mnt/ext1/colores.png"
    -- -- end


    -- widget_settings.file_do_cache = false
    -- widget_settings.alpha = true


    -- local widget = ImageWidget:new(widget_settings)

    -- -- local doc = ui.document
    -- -- local doc_settings = ui.doc_settings
    -- -- widget = BookStatusWidget:new{
    -- --     thumbnail = FileManagerBookInfo:getCoverImage(doc),
    -- --     props = ui.doc_props,
    -- --     document = doc,
    -- --     settings = doc_settings,
    -- --     ui = ui,
    -- --     readonly = true,
    -- -- }

    -- local widget = OverlapGroup:new{
    --     dimen = {
    --         w = Screen:getWidth(),
    --         h = Screen:getHeight(),
    --     },
    --     widget,
    --     nil,
    -- }
    -- local screensaver_widget = ScreenSaverWidget:new{
    --     widget = widget,
    --     background = Blitbuffer.COLOR_WHITE,
    --     covers_fullscreen = true,
    -- }
    -- screensaver_widget.modal = true
    -- screensaver_widget.dithered = true

    -- UIManager:show(screensaver_widget, "full")


    -- UIManager:scheduleIn(2, function()
    --     -- Screen:refreshFullImp(0, 0, Screen:getWidth(), Screen:getHeight()) --
    --     -- UIManager:setDirty("all", "full")
    --     UIManager:close(screensaver_widget)
    -- end)
end

function PageTextInfo:onShowReadingMotive()
    -- Screen:clear()
    -- Screen:refreshFull(0, 0, Screen:getWidth(), Screen:getHeight())

    local util = require("ffi/util")
    -- util.usleep(20000000)


    local ScreenSaverWidget = require("ui/widget/screensaverwidget")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local ImageWidget = require("ui/widget/imagewidget")
    local BookStatusWidget = require("ui/widget/bookstatuswidget")
    local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
    local widget_settings = {
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        scale_factor = G_reader_settings:isFalse("screensaver_stretch_images") and 0 or nil,
        stretch_limit_percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage"),
    }

    widget_settings.image_disposable = true
    -- widget_settings.file = "resources/screenSaverKeepCalm.jpg"
    -- widget_settings.file = "resources/oneMoreChapter.jpg"
    widget_settings.file = "resources/books.jpg"
    -- if Device:isKobo() then
    --     widget_settings.file = "/mnt/onboard/.adds/colores.png"
    -- elseif Device:isPocketBook() then
    --     widget_settings.file = "/mnt/ext1/colores.png"
    -- end


    widget_settings.file_do_cache = false
    widget_settings.alpha = true


    local widget = ImageWidget:new(widget_settings)

    -- local doc = ui.document
    -- local doc_settings = ui.doc_settings
    -- widget = BookStatusWidget:new{
    --     thumbnail = FileManagerBookInfo:getCoverImage(doc),
    --     props = ui.doc_props,
    --     document = doc,
    --     settings = doc_settings,
    --     ui = ui,
    --     readonly = true,
    -- }

    local widget = OverlapGroup:new{
        dimen = {
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        },
        widget,
        nil,
    }
    local screensaver_widget = ScreenSaverWidget:new{
        widget = widget,
        background = Blitbuffer.COLOR_WHITE,
        covers_fullscreen = true,
    }
    screensaver_widget.modal = true
    screensaver_widget.dithered = true

    UIManager:show(screensaver_widget, "full")


    UIManager:scheduleIn(0.25, function()
        -- Screen:refreshFullImp(0, 0, Screen:getWidth(), Screen:getHeight()) --
        -- UIManager:setDirty("all", "full")
        UIManager:close(screensaver_widget)
    end)
end

function PageTextInfo:onPushConfig()
    local InfoMessage = require("ui/widget/infomessage")
    local server = G_reader_settings:readSetting("rsync_server") or "192.168.50.252"
    local port = G_reader_settings:readSetting("rsync_port") or ""
    local rv
    local output = ""
    if not Device:isAndroid() then
        local NetworkMgr = require("ui/network/manager")
        if not NetworkMgr:isWifiOn() then
            NetworkMgr:turnOnWifiAndWaitForConnection()
        end
        local execute = nil
        if Device:isKobo() then
            execute = io.popen(string.format("(cd /mnt/onboard/.adds/scripts && /mnt/onboard/.adds/scripts/pushConfig.sh %s %s)", server, port))
        elseif Device:isKindle() then
            execute = io.popen(string.format("/mnt/us/scripts/pushConfig.sh %s %s && echo $? || echo $?", server, port))
        else -- PocketBook
            execute = io.popen(string.format("/mnt/ext1/scripts/pushConfig.sh %s %s && echo $? || echo $?", server, port))
        end
        output = execute:read('*a')
        execute:close()
        UIManager:show(InfoMessage:new{
            text = T(_(output)),
            face = Font:getFace("myfont"),
        })

    end
end

function PageTextInfo:onPullConfig()
    local InfoMessage = require("ui/widget/infomessage")
    local server = G_reader_settings:readSetting("rsync_server") or "192.168.50.252"
    local port = G_reader_settings:readSetting("rsync_port") or ""
    local rv
    local output = ""
    if not Device:isAndroid() then
        local NetworkMgr = require("ui/network/manager")
        if not NetworkMgr:isWifiOn() then
            NetworkMgr:turnOnWifiAndWaitForConnection()
        end
        local execute = nil
        if Device:isKobo() then
            execute = io.popen(string.format("(cd /mnt/onboard/.adds/scripts && /mnt/onboard/.adds/scripts/pullConfig.sh %s %s)", server, port))
        elseif Device:isKindle() then
            execute = io.popen(string.format("/mnt/us/scripts/pullConfig.sh %s %s && echo $? || echo $?", server, port))
        else -- PocketBook
            execute = io.popen(string.format("/mnt/ext1/scripts/pullConfig.sh %s %s && echo $? || echo $?", server, port))
        end
        output = execute:read('*a')
        execute:close()
        local save_text = _("Quit")
        if Device:canRestart() then
            save_text = _("Restart")
        end

        if not string.match(output, "Problem") and not string.match(output, "not connected") then
            local Size = require("ui/size")
            UIManager:show(ConfirmBox:new{
                dismissable = false,
                text = _("KOReader needs to be restarted."),
                ok_text = save_text,
                margin = Size.margin.tiny,
                padding = Size.padding.tiny,
                flash_yes = true,
                ok_callback = function()
                    local execute = nil
                    if Device:isKobo() then
                        execute = io.popen("/mnt/onboard/.adds/koreader/fbink -mM -f -c -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14 Restarting...")
                    elseif Device:isKindle() then
                        execute = io.popen("/mnt/us/koreader/fbink -mM -f -c -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14 Restarting...")
                    else --PocketBook
                        execute = io.popen("/mnt/ext1/applications/koreader/fbink -mM -f -c -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf Restarting...")
                    end
                    local output = execute:read('*a')
                    execute:close()
                    if Device:canRestart() then
                        UIManager:restartKOReader()
                        -- The new Clara BW is so quick closing that when presing on Restart it doesn't flash
                        -- Set a little delay for all devices
                        local util = require("ffi/util")
                        util.usleep(100000)
                    else
                        UIManager:quit()
                    end
                end,
                cancel_text = _("No need to restart"),
                cancel_callback = function()
                    logger.info("discard defaults")
                end,
            })
            UIManager:show(InfoMessage:new{
                text = T(_(output)),
                face = Font:getFace("myfont"),
            })
        else
            UIManager:show(InfoMessage:new{
                text = T(_("Problem synching")),
                face = Font:getFace("myfont"),
            })
        end
    end
    if G_reader_settings:isTrue("top_manager_infmandhistory") then
        local util = require("util")
        util.generateStats()
    end
end

function PageTextInfo:onGetLastPushingConfig()
    local InfoMessage = require("ui/widget/infomessage")
    local server = G_reader_settings:readSetting("rsync_server") or "192.168.50.252"
    local port = G_reader_settings:readSetting("rsync_port") or ""
    local rv
    local output = ""
    if not Device:isAndroid() then
        local NetworkMgr = require("ui/network/manager")
        if not NetworkMgr:isWifiOn() then
            NetworkMgr:turnOnWifiAndWaitForConnection()
        end
        local execute = nil
        if Device:isKobo() then
            execute = io.popen(string.format("(cd /mnt/onboard/.adds/scripts %s %s && /mnt/onboard/.adds/scripts/getLastPushing.sh)", server, port))
        elseif Device:isKindle() then
            execute = io.popen(string.format("/mnt/us/scripts/getLastPushing.sh %s %s && echo $? || echo $?", server, port))
        else -- PocketBook
            execute = io.popen(string.format("/mnt/ext1/scripts/getLastPushing.sh %s %s && echo $? || echo $?", server, port))
        end
        output = execute:read('*a')
        execute:close()
        UIManager:show(InfoMessage:new{
            text = T(_(output)),
            face = Font:getFace("myfont"),
        })

    end
end

function PageTextInfo:onSynchronizeCode()
    local InfoMessage = require("ui/widget/infomessage")

    local server = G_reader_settings:readSetting("rsync_server") or "192.168.50.252"
    local port = G_reader_settings:readSetting("rsync_port") or ""
    local rv
    local output = ""
    if not Device:isAndroid() then
        local NetworkMgr = require("ui/network/manager")
        if not NetworkMgr:isWifiOn() then
            NetworkMgr:turnOnWifiAndWaitForConnection()
        end
        local execute = nil
        if Device:isKobo() then
            execute = io.popen(string.format("/mnt/onboard/.adds/scripts/syncKOReaderCode.sh %s %s && echo $? || echo $?", server, port))
        elseif Device:isKindle() then
            execute = io.popen(string.format("/mnt/us/scripts/syncKOReaderCode.sh %s %s && echo $? || echo $?", server, port))
        else -- PocketBook
            execute = io.popen(string.format("/mnt/ext1/scripts/syncKOReaderCode.sh %s %s && echo $? || echo $?", server, port))
        end
        output = execute:read('*a')
        execute:close()
        local save_text = _("Quit")
        if Device:canRestart() then
            save_text = _("Restart")
        end
        if not string.match(output, "Problem") and not string.match(output, "not connected") then
            local Size = require("ui/size")
            UIManager:show(ConfirmBox:new{
                dismissable = false,
                text = _("KOReader needs to be restarted."),
                ok_text = save_text,
                margin = Size.margin.tiny,
                padding = Size.padding.tiny,
                flash_yes = true,
                ok_callback = function()
                    local execute = nil
                    if Device:isKobo() then
                        execute = io.popen("/mnt/onboard/.adds/koreader/fbink -mM -f -c -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14 Restarting...")
                    elseif Device:isKindle() then
                        execute = io.popen("/mnt/us/koreader/fbink -mM -f -c -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14 Restarting...")
                    else --PocketBook
                        execute = io.popen("/mnt/ext1/applications/koreader/fbink -mM -f -c -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf Restarting...")
                    end
                    local output = execute:read('*a')
                    execute:close()
                    if Device:canRestart() then
                        UIManager:restartKOReader()
                        -- The new Clara BW is so quick closing that when presing on Restart it doesn't flash
                        -- Set a little delay for all devices
                        local util = require("ffi/util")
                        util.usleep(100000)
                    else
                        UIManager:quit()
                    end
                end,
                cancel_text = _("No need to restart"),
                cancel_callback = function()
                    logger.info("discard defaults")
                end,
            })
            UIManager:show(InfoMessage:new{
                text = T(_(output)),
                face = Font:getFace("myfont"),
            })
        else
            UIManager:show(InfoMessage:new{
                text = T(_("Problem synching")),
                face = Font:getFace("myfont"),
            })
        end
    end
end

function PageTextInfo:onInstallLastVersion()
    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() then
        local NetworkMgr = require("ui/network/manager")
        if not NetworkMgr:isWifiOn() then
            NetworkMgr:turnOnWifiAndWaitForConnection()
        end
        local execute = io.popen("/mnt/onboard/.adds/scripts/getKOReaderNewVersion.sh && echo $? || echo $?" )
        output = execute:read('*a')
        execute:close()
        UIManager:show(InfoMessage:new{
            text = T(_(output)),
            face = Font:getFace("myfont"),
        })

    end
end

function PageTextInfo:onToggleSSH()
    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() then
        local NetworkMgr = require("ui/network/manager")
        if not NetworkMgr:isWifiOn() then
            NetworkMgr:turnOnWifiAndWaitForConnection()
        end
        local execute = nil
        if not util.pathExists("/tmp/dropbear_koreader.pid") then
            text = "Starting SSH Server"
        else
            text = "Stopping SSH Server"
        end
        if Device:isKobo() then
            execute = "/mnt/onboard/.adds/scripts/launchDropbear.sh && echo $? || echo $?"
        else --Kindle
            execute = "/mnt/us/scripts/launchDropbear.sh && echo $? || echo $?"
        end

        if os.execute(execute) ~= 0 then
            if not util.pathExists("/tmp/dropbear_koreader.pid") then
                UIManager:show(InfoMessage:new{
                    text = "Error starting SSH Server",
                })
            else
                UIManager:show(InfoMessage:new{
                    text = "Error stopping SSH Server",
                })
            end
        end
        UIManager:show(InfoMessage:new{
            text = T(_(text)),
            face = Font:getFace("myfont"),
        })
    end
end

function PageTextInfo:onToggleRsyncdService()
    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() then
        local NetworkMgr = require("ui/network/manager")
        if not NetworkMgr:isWifiOn() then
            NetworkMgr:turnOnWifiAndWaitForConnection()
        end
        local execute = nil
        if Device:isKobo() then
            execute = io.popen("/mnt/onboard/.adds/scripts/launchRsyncd.sh && echo $? || echo $?" )
        elseif Device:isKindle() then
            execute = io.popen("/mnt/us/scripts/launchRsyncd.sh && echo $? || echo $?" )
        else -- PocketBook
            execute = io.popen("/mnt/ext1/scripts/launchRsyncd.sh && echo $? || echo $?" )
        end
        output = execute:read('*a')
        execute:close()
        UIManager:show(InfoMessage:new{
            text = T(_(output)),
            face = Font:getFace("myfont"),
        })

    end
end

function PageTextInfo:onShowDbStats()
    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() then
        local execute = nil
        if Device:isKobo() then
            execute = io.popen("(cd /mnt/onboard/.adds/scripts/statsKOReaderDB && /mnt/onboard/.adds/scripts/statsKOReaderDB/stats.sh)")
        elseif Device:isKindle() then
            execute = io.popen("(cd /mnt/us/scripts/statsKOReaderDB && /mnt/us/scripts/statsKOReaderDB/stats.sh)")
        else -- PocketBook
            execute = io.popen("(cd /mnt/ext1/scripts/statsKOReaderDB && /mnt/ext1/scripts/statsKOReaderDB/stats.sh)")
        end
        output = execute:read('*a')
        execute:close()
        UIManager:show(InfoMessage:new{
            text = T(_(output)),
            face = Font:getFace("myfont"),
        })

    end
end

function PageTextInfo:onSyncBooks()
    local InfoMessage = require("ui/widget/infomessage")
    local server = G_reader_settings:readSetting("rsync_server") or "192.168.50.252"
    local port = G_reader_settings:readSetting("rsync_port") or ""
    local rv
    local output = ""
    if not Device:isAndroid() then
        local NetworkMgr = require("ui/network/manager")
        if not NetworkMgr:isWifiOn() then
            NetworkMgr:turnOnWifiAndWaitForConnection()
        end
        local execute = nil
        if Device:isKobo() then
            execute = io.popen(string.format("/mnt/onboard/.adds/scripts/syncBooks.sh %s %s && echo $? || echo $?", server, port))
        elseif Device:isKindle() then
            execute = io.popen(string.format("/mnt/us/scripts/syncBooks.sh %s %s && echo $? || echo $?", server, port))
        else -- PocketBook
            execute = io.popen(string.format("/mnt/ext1/scripts/syncBooks.sh %s %s && echo $? || echo $?", server, port))
        end
        output = execute:read('*a')
        execute:close()
        local save_text = _("Quit")
        if Device:canRestart() then
            save_text = _("Restart")
        end
        if not string.match(output, "Problem syncing") and not string.match(output, "not connected") then
            local Size = require("ui/size")
            UIManager:show(ConfirmBox:new{
                dismissable = false,
                text = _("KOReader needs to be restarted."),
                ok_text = save_text,
                margin = Size.margin.tiny,
                padding = Size.padding.tiny,
                flash_yes = true,
                flash_no = true,
                ok_callback = function()
                    local execute = nil
                    if Device:isKobo() then
                        execute = io.popen("/mnt/onboard/.adds/koreader/fbink -mM -f -c -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14 Restarting...")
                    elseif Device:isKindle() then
                        execute = io.popen("/mnt/us/koreader/fbink -mM -f -c -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14 Restarting...")
                    else --PocketBook
                        execute = io.popen("/mnt/ext1/applications/koreader/fbink -mM -f -c -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf Restarting...")
                    end
                    local output = execute:read('*a')
                    execute:close()
                    if Device:canRestart() then
                        UIManager:restartKOReader()
                        -- The new Clara BW is so quick closing that when presing on Restart it doesn't flash
                        -- Set a little delay for all devices
                        local util = require("ffi/util")
                        util.usleep(100000)
                    else
                        UIManager:quit()
                    end
                end,
                cancel_text = _("No need to restart"),
                cancel_callback = function()
                    if G_reader_settings:isTrue("top_manager_infmandhistory") then
                        local execute = nil
                        if Device:isKobo() then
                            execute = io.popen("/mnt/onboard/.adds/koreader/fbink -mM -f -c -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14 Updating...")
                        elseif Device:isKindle() then
                            execute = io.popen("/mnt/us/koreader/fbink -mM -f -c -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14 Updating...")
                        else --PocketBook
                            execute = io.popen("/mnt/ext1/applications/koreader/fbink -mM -f -c -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf Updating...")
                        end
                        local output = execute:read('*a')
                        execute:close()
                        _G.all_files = util.getListAll()
                        local util = require("util")
                        -- We need to read the history file
                        -- because we can have books in the history
                        -- that are not physically in the device
                        require("readhistory"):reload(true)
                        util.generateStats()
                        require("apps/filemanager/filemanager").instance.file_chooser:refreshPath()
                    end
                end,
            })
            UIManager:show(InfoMessage:new{
                text = T(_(output)),
                face = Font:getFace("myfont"),
            })
        else
            UIManager:show(InfoMessage:new{
                text = T(_("Problem synching")),
                face = Font:getFace("myfont"),
            })
        end
    end
end

function PageTextInfo:onTurnOnWifiKindle()
    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    local NetworkMgr = require("ui/network/manager")
    local execute = io.popen("/mnt/us/scripts/connectNetwork.sh && echo $? || echo $?" )
    output = execute:read('*a')
    execute:close()
    UIManager:show(InfoMessage:new{
        text = T(_(output)),
        face = Font:getFace("myfont"),
    })
end

function PageTextInfo:sendJsonToServer(endpoint, payload, callback)
    local JSON = require("json")
    local logger = require("logger")
    local UIManager = require("ui/uimanager")
    local NetworkMgr = require("ui/network/manager")

    local ok, json_payload = pcall(JSON.encode, payload)
    if not ok then
        logger.err("sendJsonToServer: Failed to encode payload")
        UIManager:show(InfoMessage:new{
            title = _("Encoding error"),
            text = _("Could not prepare request."),
            timeout = 4,
        })
        return
    end

    if not NetworkMgr:isConnected() then
        logger.info("sendJsonToServer: No network connection.")
        NetworkMgr:promptWifiOn(function()
            self:sendJsonToServer(endpoint, payload, callback)
        end, _("Connect to Wi-Fi to send data?"))
        return
    end

    local server_urls = {
        "http://192.168.50.250:5000" .. endpoint,
        "http://" .. (self and self.server or "192.168.43.1") .. ":" .. (self and self.port or "5000") .. endpoint,
    }

    local tmpfile = "/tmp/koreader_generic_response.json"
    local curl_ok = false
    local selected_url = nil
    local curl_path = "curl"
    if Device and Device:isKobo() then
        curl_path = "/mnt/onboard/.niluje/usbnet/bin/curl"
    end

    for _, url in ipairs(server_urls) do
        local cmd = string.format(
            curl_path .. [[ --connect-timeout 2 -s -X POST %s -H "Content-Type: application/json" -d '%s' -o %s]],
            url,
            json_payload:gsub("'", "'\\''"),
            tmpfile
        )
        logger.info("sendJsonToServer: Trying server: " .. url)
        local result = os.execute(cmd)
        if result == 0 then
            curl_ok = true
            selected_url = url
            break
        else
            logger.warn("sendJsonToServer: Failed to contact " .. url)
        end
    end

    if not curl_ok then
        logger.err("sendJsonToServer: All server attempts failed.")
        UIManager:show(InfoMessage:new{
            title = _("Send failed"),
            text = _("Could not contact any server."),
            timeout = 6,
        })
        return
    end

    local f = io.open(tmpfile, "r")
    if not f then
        logger.err("sendJsonToServer: Cannot read result file.")
        return
    end
    local content = f:read("*a")
    f:close()

    local success, response = pcall(function()
        return JSON.decode(content)
    end)

    if not success or not response then
        logger.err("sendJsonToServer: Invalid server response.")
        UIManager:show(InfoMessage:new{
            title = _("Error"),
            text = _("Invalid response from server."),
            timeout = 5,
        })
        return
    end

    -- Call user-defined handler
    callback(response)
end

function PageTextInfo:sendHighlightToServerForMood()
    logger.info("--- Sending highlight to /analyze via generic handler ---")

    if not self.ui.highlight.selected_text or not self.ui.highlight.selected_text.text or self.ui.highlight.selected_text.text == "" then
        logger.warn("No text selected.")
        UIManager:show(Notification:new{ text = _("No text selected.") })
        return
    end

    local util = require("util")
    local text = util.cleanupSelectedText(self.ui.highlight.selected_text.text)
    local book_id = self.ui.doc_props and self.ui.doc_props.title or self.ui.document:getFileName()

    local payload = {
        book_id = book_id,
        visible_text = text,
    }

    self:sendJsonToServer("/analyze", payload, function(response)
        if not response.words then
            logger.err("Analyze: Missing words in response.")
            UIManager:show(InfoMessage:new{
                title = _("Error"),
                text = _("Invalid response from analyze endpoint."),
                timeout = 5,
            })
            return
        end

        local lines = {}
        for _, entry in ipairs(response.words) do
            table.insert(lines, string.format("• %s (%s)", entry.word, entry.level or "?"))
        end

        if response.interpretation then
            table.insert(lines, "")
            table.insert(lines, "Mood: " .. (response.mood or "?"))
            table.insert(lines, response.interpretation)
        end

        UIManager:show(InfoMessage:new{
            title = _("Highlight analyzed"),
            text = table.concat(lines, "\n"),
            timeout = 10,
        })

        logger.info("--- Highlight analyzed successfully via /analyze ---")
    end)
end

function PageTextInfo:sendHighlightToServerForHeatmap()
    local text = util.cleanupSelectedText(self.ui.highlight.selected_text.text)
    local title = self.ui.document.file:match("([^/]+)$"):gsub("^'", ""):gsub("'$", "")
    local string_percentage  = "%0.1f"
    local percentage = string_percentage:format(self.view.footer.progress_bar.percentage * 100)


    local payload = {
        book_name = title,
        word = text,
        percent_limit = percentage,
    }

    self:sendJsonToServer("/heatmap", payload, function(response)
        local lines = {
            string.format("Word: %s", response.word or "?"),
            string.format("Progress: %s", response.progress or "?"),
            "",
            response.heatmap or "(no heatmap)"
        }

        if response.legend then
            table.insert(lines, "")
            table.insert(lines, "Legend:")
            for k, v in pairs(response.legend) do
                table.insert(lines, string.format(" %s = %s", k, v))
            end
        end

        UIManager:show(InfoMessage:new{
            title = _("Heatmap analyzed"),
            text = table.concat(lines, "\n"),
            face = Font:getFace("Consolas-Regular.ttf", 14),
            timeout = 10,
        })
    end)
end

function PageTextInfo:onToggleDoubleBar()
    if self.view.topbar.settings:isTrue("show_top_bar") or self.view.footer_visible then return true end
    local show_double_bar = G_reader_settings:isTrue("show_double_bar")
    G_reader_settings:saveSetting("show_double_bar", not show_double_bar)
    require("apps/reader/modules/doublebar").is_enabled = not show_double_bar
    self.view.doublebar:toggleBar()
    UIManager:setDirty(self.view.dialog, "ui")
    return true
end

function PageTextInfo:onShowNotebookFileRender()
    local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
    local notebook_file = FileManagerBookInfo:getNotebookFile(self.ui.doc_settings)
    local file, err = io.open(notebook_file, "r")
    if not file then
        local UIManager = require("ui/uimanager")
        local Notification = require("ui/widget/notification")
        UIManager:show(Notification:new{
            text = _("No file"),
        })
        return
    end
    local content = file:read("*a")
    file:close()
    local VIEWER_CSS = [[
    @page {
        margin: 20;
        font-family: 'Noto Sans CJK TC', 'Noto Sans Arabic', 'Noto Sans Devanagari UI', 'Noto Sans Bengali UI', 'FreeSans', 'Noto Sans', sans-serif;
    }

    body {
        margin: 20;
        line-height: 1.25;
        padding: 0;
    }

    blockquote, dd, pre {
        margin: 0 1em;
    }

    ol, ul, menu {
        margin: 0;
        padding-left: 1.5em;
    }

    ul {
        list-style-type: circle;
    }

    ul ul {
        list-style-type: square;
    }

    ul ul ul {
        list-style-type: disc;
    }

    ul li a {
        display: inline-block;
    }

    table {
        margin: 0;
        padding: 0;
        border-collapse: collapse;
        border-spacing: 0;
        font-size: 0.8em;
    }

    table td, table th {
        border: 1px solid black;
        padding: 0;
    }
    ]]
    local parser_path = "plugins/assistant.koplugin/assistant_mdparser.lua"
    local MD = dofile(parser_path)
    local html_body, err = MD(content)
    local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")

    self.scroll_text_w = ScrollHtmlWidget:new {
        html_body = html_body,
        css = VIEWER_CSS,
        default_font_size = Screen:scaleBySize(20),
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        scroll_bar_width = 20,
        text_scroll_span = 0,
        dialog = self.view.dialog,
        close_when_multiswipe = true,
        -- onTapScrollText = function()
        --     UIManager:close(self.scroll_text_w)
        -- end
    }

    UIManager:show(self.scroll_text_w)
end

function PageTextInfo:getCovers(filepath, max_w, max_h)
    local ReadCollection = require("readcollection")
    local BookInfoManager = require("bookinfomanager")
    -- Query database for books in this folder with covers
    local SQ3 = require("lua-ljsqlite3/init")
    local DataStorage = require("datastorage")
    local db_conn = SQ3.open(DataStorage:getSettingsDir() .. "/bookinfo_cache.sqlite3")
    db_conn:set_busy_timeout(5000)


    local res
    if not filepath:match("✪ Collections") then
            local query = string.format([[
                SELECT directory, filename FROM bookinfo
                WHERE directory = '%s/' AND has_cover = 'Y'
                ORDER BY filename ASC LIMIT 4;
        ]], filepath:gsub("'", "''"))
        res = db_conn:exec(query)
        db_conn:close()
    elseif filepath:match("✪ Collections$") then
        res = nil
    else
        local candidates = {}
        if filepath then
            local coll = ReadCollection.coll[filepath:match("([^/]+)$")]
            if coll then
                for _, book in pairs(coll) do
                    if book.file then table.insert(candidates, book.file) end
                end
            end
        else
            for _, coll in pairs(ReadCollection.coll) do
                for _, book in pairs(coll) do
                    if book.file then table.insert(candidates, book.file) end
                end
            end
        end
        local covers = {}
        local dirs = {}
        local files = {}
        while #dirs < 4 and #candidates > 0 do
            local rand_idx = math.random(1, #candidates)
            local fullpath = candidates[rand_idx]
            table.remove(candidates, rand_idx)

            if fullpath and util.fileExists(fullpath) then
                local bookinfo = BookInfoManager:getBookInfo(fullpath, true)
                table.insert(dirs, fullpath:match("(.*/)"))
                table.insert(files, fullpath:match("([^/]+)$"))
            end
        end
        res = {
            dirs,
            files,
        }
    end
    return res
end

function PageTextInfo:get_empty_folder_cover(max_h, max_w)
    local border_total = 2*Size.border.thin
    local ImageWidget = require("ui/widget/imagewidget")
    local BookInfoManager = require("bookinfomanager")

    local stock_image = "./plugins/pagetextinfo.koplugin/resources/folder.svg"
    -- local RenderImage = require("ui/renderimage")
    -- local cover_bb = RenderImage:renderImageFile(stock_image, false, nil, nil)

    local scale_factor
    local _, _, scale_factor = BookInfoManager.getCachedCoverSize(250, 500, max_w, max_h)

    local subfolder_cover_image = ImageWidget:new {
        file = stock_image,
        alpha = true,
        scale_factor = scale_factor,
        width = max_w,
        height = max_h,
        original_in_nightmode = false,
    }

    local cover_size = subfolder_cover_image:getSize()
    local frame_width = cover_size.w + border_total
    local frame_height = cover_size.h + border_total

    local widget = FrameContainer:new {
        width = frame_width,
        height = frame_height,
        -- radius = Size.radius.default,
        margin = 0,
        padding = 0,
        bordersize = 0, -- ((require("ui/widget/filechooser").display_mode_type == "mosaic" and self.settings:isTrue("enable_extra_tweaks_mosaic_view"))) and 0 or Size.border.thin,
        color = Blitbuffer.COLOR_BLACK,
        subfolder_cover_image,
    }

    local border_adjustment = 0
    if self.settings:isTrue("enable_extra_tweaks_mosaic_view")
        or self.settings:isTrue("enable_rounded_corners") then
        border_adjustment = border_total
        if self.settings:isTrue("enable_extra_tweaks_mosaic_view") then
            max_w = max_w - border_total
        end
    end

    return CenterContainer:new {
        dimen = Geom:new { w = frame_width - border_adjustment, h = max_h },
        wide = max_w,
        widget,
    }
    end
--     if self.settings:isTrue("covers_grid_mode") and require("ui/widget/filechooser").display_mode_type == "list" then
--         local w, h = 450, 680
--         local new_h = max_h
--         local new_w = math.floor(w * (new_h / h))
--         local stock_image = "./plugins/pagetextinfo.koplugin/resources/folder.svg"

--         local subfolder_cover_image = ImageWidget:new {
--             file = stock_image,
--             alpha = true,
--             scale_factor = nil,
--             width = new_w,
--             height = new_h,
--         }
--         local cover_size = subfolder_cover_image:getSize()
--         local widget = FrameContainer:new {
--             width = cover_size.w + border_total,
--             height = cover_size.h + border_total,
--             -- radius = Size.radius.default,
--             margin = 0,
--             padding = 0,
--             bordersize = border_size,
--             color = Blitbuffer.COLOR_BLACK,
--             subfolder_cover_image,
--         }
--         local width = math.floor(cover_size.w * 1.5 + border_total)
--         return CenterContainer:new {
--             dimen = Geom:new { w = width, h = max_h },
--             widget,
--         }
--     else
--         return CenterContainer:new {
--             dimen = Geom:new { w = frame_width - border_adjustment, h = max_h },
--             wide = max_w,
--             widget,
--         }
--     end

--     -- return CenterContainer:new {
--     --     dimen = Geom:new { w = max_w, h = max_h },
--     --     wide = math.floor(450 * (max_h / 680)),
--     --     subfolder_cover_image,
--     -- }
-- end

-- Function in VeeBui's KOReader-folder-stacks-series-author patch
function PageTextInfo:getSubfolderCoverStack(filepath, max_w, max_h, factor_x, factor_y, offset_x, offset_y, blanks, mosaic, width, height)
    local ImageWidget = require("ui/widget/imagewidget")
    local BookInfoManager = require("bookinfomanager")
    local res = self:getCovers(filepath, max_w, max_h)
    local border_total = 2*Size.border.thin
    if res and res[1] and res[2] and res[1][1] then
        local dir_ending = string.sub(res[1][1],-2,-2)
        local num_books = #res[1]

        -- Save all covers
        local covers = {}
        for i = 1, num_books do
            local fullpath = res[1][i] .. res[2][i]

            if util.fileExists(fullpath) then
                local bookinfo = BookInfoManager:getBookInfo(fullpath, true)
                if bookinfo and bookinfo.cover_bb and bookinfo.has_cover then
                    table.insert(covers, bookinfo)
                end
            end
        end
        local available_w = max_w - (#covers-1)*offset_x
        local available_h = max_h - (#covers-1)*offset_y
        -- Make sure this isn't an empty folder
        if #covers > 0 then
            -- Now make the Individual cover widgets
            local cover_widgets = {}
            local cover_max_w = max_w
            local cover_max_h = max_h

            local num_covers = #covers
            -- if num_covers > 1 then
            --     cover_max_h = math.ceil(max_h * (1 - (math.abs(factor_y) * (num_covers - 1))))
            -- end

            -- if self.blanks then
            --     cover_max_h = math.ceil(max_h * (1 - (math.abs(factor_y) * 3)))
            -- end

            for i, bookinfo in ipairs(covers) do
                -- figure out scale factor
                local scale_factor
                if blanks then
                    available_w = max_w - 3*offset_x
                    available_h = max_h - 3*offset_y
                    __, __, scale_factor = BookInfoManager.getCachedCoverSize(
                        bookinfo.cover_w, bookinfo.cover_h,
                        available_w, available_h
                    )
                else
                    __, __, scale_factor = BookInfoManager.getCachedCoverSize(
                        bookinfo.cover_w, bookinfo.cover_h,
                        available_w, available_h
                    )
                end
                -- if #covers == 1 and self.settings:isTrue("enable_extra_tweaks") then
                --     local w, h = bookinfo.cover_w, bookinfo.cover_h
                --     local new_h = cover_max_w
                --     local new_w = math.ceil(w * (new_h / h))
                --     cover_widget = ImageWidget:new{
                --         image = bookinfo.cover_bb,
                --         width = new_w,
                --         height = new_h,
                --     }
                -- end

                local cover_widget = ImageWidget:new {
                    image = bookinfo.cover_bb,
                    scale_factor = scale_factor,
                }

                if mosaic and self.settings:isTrue("enable_extra_tweaks_mosaic_view") then
                    local n = math.min(#covers, 4)
                    local w = width - offset_x * (n - 1)
                    local h = height - offset_y * (n - 1)

                    cover_widget = ImageWidget:new {
                        image = bookinfo.cover_bb,
                        scale_factor = nil,
                        width = w,
                        height = h,
                    }
                end
                if not mosaic and self.settings:isTrue("enable_extra_tweaks") then
                    local n = math.min(#covers, 4)

                    -- altura fina, exacta
                    local new_h = height - offset_y * (n - 1)

                    -- mantener aspecto: ancho proporcional a la nueva altura
                    local orig_w = bookinfo.cover_w
                    local orig_h = bookinfo.cover_h
                    local new_w  = math.floor(orig_w * (new_h / orig_h))

                    cover_widget = ImageWidget:new {
                        image = bookinfo.cover_bb,
                        scale_factor = nil,  -- MUY importante para no ignorar width/height
                        width  = new_w,
                        height = new_h,
                    }
                end
                local cover_size = cover_widget:getSize()
                table.insert(cover_widgets, {
                    widget = FrameContainer:new {
                        width = cover_size.w + border_total,
                        height = cover_size.h + border_total,
                        -- radius = Size.radius.default,
                        margin = 0,
                        padding = 0,
                        bordersize = Size.border.thin,
                        color = Blitbuffer.COLOR_BLACK,
                        cover_widget,
                    },
                    size = cover_size
                })
            end

            local num_covers = #covers
            local blanks_no = 0
            if num_covers == 3 then
                blanks_no = 1
            elseif num_covers == 2 then
                blanks_no = 2
            elseif num_covers == 1 then
                blanks_no = 3
            end

            -- blank covers
            if blanks then
                for i = 1, blanks_no do
                    local cover_size = cover_widgets[num_covers].size
                    table.insert(cover_widgets, 1, { -- To insert blank covers at the beginning
                        widget = FrameContainer:new {
                            width = cover_size.w + border_total,
                            height = cover_size.h + border_total,
                            radius = Size.radius.default,
                            margin = 0,
                            padding = 0,
                            bordersize = Size.border.thin, -- Always border for blank covers
                            color = Blitbuffer.COLOR_BLACK,
                            background = Blitbuffer.COLOR_LIGHT_GRAY,
                            HorizontalSpan:new { width = cover_size.w, height = cover_size.h },
                        },
                        size = cover_size
                    })
                end
                -- -- Reverse order
                -- for i = 1, blanks_no do
                --     local cover_size = cover_widgets[num_covers].size
                --     table.insert(cover_widgets, 1, {
                --         widget = FrameContainer:new {
                --             width = cover_size.w + border_total,
                --             height = cover_size.h + border_total,
                --             radius = Size.radius.default,
                --             margin = 0,
                --             padding = 0,
                --             bordersize = Size.border.thin,
                --             color = Blitbuffer.COLOR_BLACK,
                --             background = Blitbuffer.COLOR_LIGHT_GRAY,
                --             HorizontalSpan:new { width = cover_size.w, height = cover_size.h },
                --         },
                --         size = cover_size
                --     })
                -- end
            end
            -- if #covers == 1 and not self.blanks then
            --     -- if self.settings:isTrue("enable_extra_tweaks") then
            --     --     return LeftContainer:new {
            --     --         dimen = Geom:new { w = max_w, h = max_h },
            --     --         cover_widgets[1].widget,
            --     --     }
            --     -- end

            --     -- The width has to be the same than the width when there are 4 covers, so we escalate it and center it
            --     local cover_size = cover_widgets[1].size
            --     local width = math.floor((cover_size.w * (1 - (self.factor_y * 3))) + 3 * self.offset_x + border_total)
            --     return CenterContainer:new {
            --         dimen = Geom:new { w = width, h = max_h },
            --         cover_widgets[1].widget,
            --     }
            -- end

            local total_width = cover_widgets[1].size.w + border_total + (#cover_widgets-1)*offset_x
            local total_height = cover_widgets[1].size.h + border_total + (#cover_widgets-1)*offset_y

            if mosaic then
                local total_width, total_height = 0, 0
                for i, cover in ipairs(cover_widgets) do
                    total_width = math.max(total_width, cover.size.w + (i-1)*offset_x)
                    total_height = math.max(total_height, cover.size.h + (i-1)*offset_y)
                end

                -- calcular desplazamiento para centrar
                local start_x = math.floor((max_w - total_width)/2)
                local start_y = math.floor((max_h - total_height)/2)

                -- crear FrameContainer de cada portada con offset + centrado
                local children = {}
                local border_adjustment = 0
                if self.settings:isTrue("enable_extra_tweaks_mosaic_view")
                        or self.settings:isTrue("enable_rounded_corners") then
                        border_adjustment = Size.border.thin
                end
                for i, cover in ipairs(cover_widgets) do
                    children[#children+1] = FrameContainer:new{
                        margin = 0,
                        padding = 0,
                        padding_left = start_x + (i - 1) * offset_x - border_adjustment,
                        padding_top  = start_y + (i - 1) * offset_y,
                        bordersize = 0,
                        cover.widget,
                    }
                end
                local overlap = OverlapGroup:new {
                    dimen = Geom:new { w = total_width, h = total_height},
                    table.unpack(children),
                }

                -- return the center container
                return CenterContainer:new {
                    dimen = Geom:new { w = total_width, h = total_height},
                    FrameContainer:new {
                        width = total_width,
                        height = total_height,
                        margin = 0,
                        padding = 0,
                        -- background = Blitbuffer.colorFromName("orange"),
                        bordersize = 0,
                        color = Blitbuffer.COLOR_BLACK,
                        overlap,
                    },
                }
            else
                local overlap
                local children = {}
                for i, cover in ipairs(cover_widgets) do
                    children[#children + 1] = FrameContainer:new{
                        margin = 0,
                        padding = 0,
                        padding_left = (i - 1) * offset_x,
                        padding_top  = (i - 1) * offset_y,
                        bordersize = 0,
                        cover.widget,
                    }
                end
                -- -- Reverse order
                -- for i = #cover_widgets, 1, -1 do
                --     local idx = (#cover_widgets - i)
                --     children[#children + 1] = FrameContainer:new{
                --         margin = 0,
                --         padding = 0,
                --         padding_left = (i - 1) * offset_x,
                --         padding_top  = (i - 1) * offset_y,
                --         bordersize = 0,
                --         cover_widgets[i].widget,
                --     }
                -- end
                overlap = OverlapGroup:new {
                    dimen = Geom:new { w = total_width, h = total_height },
                    table.unpack(children),
                }

                -- I need the proper real size of a cover without reduction, I take the folder image
                local base_w, base_h = 450, 680
                local new_h = max_h
                local new_w = math.ceil(base_w * (new_h / base_h))
                local width = math.ceil((new_w* (1 - (factor_y * 3))) + 3 * offset_x + border_total)
                return CenterContainer:new {
                    dimen = Geom:new { w = width, h = max_h }, -- Center container to have whole width
                    overlap,
                }
            end
        end
    end

    if mosaic then
        return self:get_empty_folder_cover(max_h, max_w)
    else
        local w, h = 450, 680
        local new_h = max_h
        local new_w = math.floor(w * (new_h / h))
        local stock_image = "./plugins/pagetextinfo.koplugin/resources/folder.svg"
        -- local RenderImage = require("ui/renderimage")
        -- local cover_bb = RenderImage:renderImageFile(stock_image, false, nil, nil)
        local subfolder_cover_image = ImageWidget:new {
            file = stock_image,
            alpha = true,
            scale_factor = nil,
            width = new_w,
            height = new_h,
        }

        local cover_size = subfolder_cover_image:getSize()
        -- local widget = FrameContainer:new {
        --     width = cover_size.w + border_total,
        --     height = cover_size.h + border_total,
        --     -- radius = Size.radius.default,
        --     margin = 0,
        --     padding = 0,
        --     bordersize = border_size,
        --     color = Blitbuffer.COLOR_BLACK,
        --     subfolder_cover_image,
        -- }
        -- The width has to be the same than the width when there are 4 covers, so we escalate it and center it
        local width = math.floor((cover_size.w * (1 - (factor_y * 3))) + 3 * offset_x + border_total)
        return CenterContainer:new {
            dimen = Geom:new { w = width, h = max_h },
            subfolder_cover_image,
        }
    end
end

function PageTextInfo:getSubfolderCoverGrid(filepath, max_w, max_h, mosaic)
    local ImageWidget = require("ui/widget/imagewidget")
    local BookInfoManager = require("bookinfomanager")
    local res = self:getCovers(filepath, max_w, max_h)

    local function create_blank_cover(width, height, background_idx)
        local border_size = Size.border.thin
        if (mosaic and self.settings:isTrue("enable_extra_tweaks_mosaic_view"))
        or (not mosaic and self.settings:isTrue("enable_extra_tweaks")) then
            border_size = 0
        end
        local backgrounds = {
            Blitbuffer.COLOR_LIGHT_GRAY,
            Blitbuffer.COLOR_GRAY_D,
            Blitbuffer.COLOR_GRAY_E,
        }
        local max_img_w = width - (border_size * 2)
        local max_img_h = height - (border_size * 2)
        return FrameContainer:new {
            width = width,
            height = height,
            -- radius = Size.radius.default,
            margin = 0,
            padding = 0,
            bordersize = border_size,
            color = Blitbuffer.COLOR_DARK_GRAY,
            background = backgrounds[background_idx],
            CenterContainer:new {
                dimen = Geom:new { w = max_img_w, h = max_img_h },
                HorizontalSpan:new { width = max_img_w, height = max_img_h },
            }
        }
    end

    local function get_stack_grid_size(max_w, max_h)
        local max_img_w = 0
        local max_img_h = 0
        max_img_w = math.floor((max_w - (Size.border.thin * 2)) / 2)
        max_img_h = math.floor((max_h - (Size.border.thin * 2)) / 2)
        if max_img_w < 10 then max_img_w = max_w * 0.8 end
        if max_img_h < 10 then max_img_h = max_h * 0.8 end
        return max_img_w, max_img_h
    end
    local max_img_w, max_img_h = get_stack_grid_size(max_w, max_h)
    if res and res[1] and res[2] and res[1][1] then
        -- print("cover final entro")
        local dir_ending = string.sub(res[1][1],-2,-2)
        local num_books = #res[1]

        if num_books > 0 then
            -- Save all covers
            local images = {}
            local w, h = 0, 0
            for i = 1, num_books do
                local fullpath = res[1][i] .. res[2][i]

                if util.fileExists(fullpath) then
                    local bookinfo = BookInfoManager:getBookInfo(fullpath, true)
                    if bookinfo and bookinfo.cover_bb and bookinfo.has_cover then
                        local border_total = (Size.border.thin * 2)
                        local _, _, scale_factor = BookInfoManager.getCachedCoverSize(
                            bookinfo.cover_w, bookinfo.cover_h, max_img_w, max_img_h)
                        local wimage = ImageWidget:new {
                            image = bookinfo.cover_bb,
                            scale_factor = scale_factor,
                        }
                        -- if i == 1 then
                        -- Images sizes may varied depending the cached size
                        -- This is not noticed in stack view
                        local w = math.floor((bookinfo.cover_w * scale_factor) + border_total)
                        local h = math.floor((bookinfo.cover_h * scale_factor) + border_total)

                        local border_size = Size.border.thin
                        if (mosaic and self.settings:isTrue("enable_extra_tweaks_mosaic_view"))
                        or (not mosaic and self.settings:isTrue("enable_extra_tweaks")) then
                            local final_w = max_img_w + 2*Size.border.thin
                            local final_h = max_img_h + 2*Size.border.thin

                            wimage = ImageWidget:new {
                            image = bookinfo.cover_bb,
                            width = final_w,
                            height = final_h,
                            scale_factor = nil,
                            }

                            w = final_w
                            h = final_h
                            border_size = 0
                        end
                        -- end
                        -- print("cover final: ", w, h)
                        table.insert(images, FrameContainer:new {
                            width = w,
                            height = h,
                            margin = 0,
                            padding = 0,
                            -- radius = Size.radius.default,
                            bordersize = border_size,
                            color = Blitbuffer.COLOR_GRAY_3,
                            background = Blitbuffer.COLOR_GRAY_3,
                            wimage,
                        })
                    end
                end
            end
            if #images == 0 then
                return self:get_empty_folder_cover(max_h, max_w)
            end
            local row1 = HorizontalGroup:new {}
            local row2 = HorizontalGroup:new {}
            local layout = VerticalGroup:new {}

            if #images == 3 then
                local w3, h3 = images[3]:getSize().w, images[3]:getSize().h
                table.insert(images, 2, create_blank_cover(w3, h3, 3))
            elseif #images == 2 then
                local w1, h1 = images[1]:getSize().w, images[1]:getSize().h
                local w2, h2 = images[2]:getSize().w, images[2]:getSize().h
                table.insert(images, 2, create_blank_cover(w1, h1, 3))
                table.insert(images, 3, create_blank_cover(w2, h2, 2))
            elseif #images == 1 then
                local w1, h1 = images[1]:getSize().w, images[1]:getSize().h
                table.insert(images, 1, create_blank_cover(w1, h1, 3))
                table.insert(images, 2, create_blank_cover(w1, h1, 2))
                table.insert(images, 4, create_blank_cover(w1, h1, 3))
            end

            local gaps = true
            if (mosaic and self.settings:isTrue("enable_extra_tweaks_mosaic_view")) or (not mosaic and self.settings:isTrue("enable_extra_tweaks")) then
                gaps = false
            end
            for i, img in ipairs(images) do
                if i < 3 then
                    table.insert(row1, img)
                else
                    table.insert(row2, img)
                end
                if i == 1 and gaps then
                    table.insert(row1, HorizontalSpan:new { width = Size.padding.small })
                elseif i == 3 and gaps then
                    table.insert(row2, HorizontalSpan:new { width = Size.padding.small })
                end
            end

            table.insert(layout, row1)
            if gaps then
                table.insert(layout, VerticalSpan:new { width = Size.padding.small })
            end
            table.insert(layout, row2)
            -- return layout
            local border_adjustment = 2*Size.border.thin
            if self.settings:isTrue("enable_rounded_corners") then
                border_adjustment = 0
            end

            return CenterContainer:new {
                dimen = Geom:new { w = max_w + border_adjustment, h = max_h},
                wide = layout:getSize().w - 2*Size.border.thin,
                FrameContainer:new {
                    width = max_w,
                    height = max_h,
                    margin = 0,
                    padding = 0,
                    -- background = Blitbuffer.colorFromName("orange"),
                    bordersize = 0,
                    color = Blitbuffer.COLOR_BLACK,
                    layout,
                },
            }
        else
            return self:get_empty_folder_cover(max_h, max_w)
        end
    else
        return self:get_empty_folder_cover(max_h, max_w)
    end
end

return PageTextInfo
