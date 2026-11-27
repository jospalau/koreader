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
local MovableContainer = require("ui/widget/container/movablecontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local LineWidget = require("ui/widget/linewidget")
local Blitbuffer = require("ffi/blitbuffer")
local left_container = require("ui/widget/container/leftcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local TextViewer = require("ui/widget/textviewer")
local CrashLog = require("crashlog_overlay")
local MemoryOverlay = require("memory_overlay")
local WidgetTimeOverlay = require("widget_time_overlay")
local RefreshOverlay = require("refresh_overlay")
local ExitTiming = require("exit_timing")
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
local Version = require("version")
local lfs = require("libs/libkoreader-lfs")

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

local _original_setupLayout = nil
local _original_filechooser_init = nil

function PageTextInfo:_hookSetupLayout()
    if not _original_setupLayout then
        _original_setupLayout = FileManager.setupLayout
    end
    local FileChooser = require("ui/widget/filechooser")
    if not _original_filechooser_init then
        _original_filechooser_init = FileChooser.init
    end

    FileManager.setupLayout = function(instance, ...)
        local orig_init = _original_filechooser_init
        FileChooser.init = function(fc, ...)
            local Widget = require("ui/widget/widget")
            local EmptyTitleBar = Widget:extend{}
            function EmptyTitleBar:init()
                self.dimen = { x = 0, y = 0, w = Screen:getWidth(), h = 0 }
            end
            function EmptyTitleBar:getSize()                  return { w = 0, h = 0 } end
            function EmptyTitleBar:getHeight()                return 0 end
            function EmptyTitleBar:paintTo()                  end
            function EmptyTitleBar:handleEvent()              return false end
            function EmptyTitleBar:free()                     end
            function EmptyTitleBar:setTitle()                 end
            function EmptyTitleBar:setSubTitle()              end
            function EmptyTitleBar:setLeftIcon()              end
            function EmptyTitleBar:setRightIcon()             end
            function EmptyTitleBar:clear()                    end
            function EmptyTitleBar:generateHorizontalLayout() return {} end
            function EmptyTitleBar:generateVerticalLayout()   return {} end
            fc.custom_title_bar = EmptyTitleBar:new{}
            orig_init(fc, ...)
        end
        _original_setupLayout(instance, ...)
        FileChooser.init = orig_init
    end
end

function PageTextInfo:_unhookSetupLayout()
    if _original_setupLayout then
        FileManager.setupLayout = _original_setupLayout
        _original_setupLayout = nil
    end
    local FileChooser = require("ui/widget/filechooser")
    if _original_filechooser_init then
        FileChooser.init = _original_filechooser_init
        _original_filechooser_init = nil
    end
end

if settings:isTrue("enable_no_bar_menu") then
    PageTextInfo._hookSetupLayout(PageTextInfo)
end

function PageTextInfo:onDispatcherRegisterActions()
    Dispatcher:registerAction("toggle_dots_bg", {category="none", event="ToggleDotsAndBackground", title=_("Toggle dots / background"), general=true,})
    Dispatcher:registerAction("pagetextinfo_action", {category="none", event="PageTextInfo", title=_("Page text info widget"), general=true,})
    Dispatcher:registerAction("series", {category="none", event="ShowSeriesList", title=_("Series"), general=true,})
    Dispatcher:registerAction("generate_favorites", {category="none", event="GenerateFavorites", title=_("Generate favorites"), general=true,})
    Dispatcher:registerAction("filemanager_scripts", {category="none", event="Scripts", title=_("File browser scripts"), general=true, separator=true,})
    Dispatcher:registerAction("filemanager", {category="none", event="Home", title=_("File browser"), general=true,})
    Dispatcher:registerAction("notebook_file", {category="none", event="ShowNotebookFile", title=_("Notebook file"), general=true, separator=true,})
    Dispatcher:registerAction("random_profile", {category="none", event="RandomProfile", title=_("Random profile"), general=true, separator=true,})
    Dispatcher:registerAction("get_styles", {category="none", event="GetStyles", title=_("Get styles"), general=true, separator=true,})
    Dispatcher:registerAction("synchronize_code", {category="none", event="SynchronizeCode", title=_("Synchronize code"), general=true, separator=true,})
    Dispatcher:registerAction("synchronize_code_phone", {category="none", event="SynchronizeCodePhone", title=_("Synchronize code phone"), general=true, separator=true,})
    Dispatcher:registerAction("install_last_version", {category="none", event="InstallLastVersion", title=_("Install last KOReader version"), general=true, separator=true,})
    Dispatcher:registerAction("synchronize_statistics", {category="none", event="SynchronizeStatistics", title=_("Synchronize statistics script"), general=true, separator=true,})
    Dispatcher:registerAction("toggle_ssh", {category="none", event="ToggleSSH", title=_("Toggle SSH server"), general=true, separator=true,})
    Dispatcher:registerAction("get_tbr", {category="none", event="GetTBR", title=_("Get TBR"), general=true, separator=true,})
    Dispatcher:registerAction("sync_books", {category="none", event="SyncBooks", title=_("Synchronize Books"), general=true, separator=true,})
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
    Dispatcher:registerAction("notebook_file_render", {category="none", event="ShowNotebookFileRender", title=_("Notebook file render"), general=true,})
    Dispatcher:registerAction("toggle_debug_verbose", {category="none", event="ToggleDebugVerbose", title=_("Toggle verbose logging"), general=true,})
    Dispatcher:registerAction("show_fonts_menu", {category="none", event="ShowFonts", title=_("Show fonts menu"), reader=true, separator=true,})
    Dispatcher:registerAction("show_style_tweaks_menu", {category="none", event="ShowTweaks", title=_("Show style tweaks menu"), reader=true, separator=true,})
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

-- Size of the bottom left / bottom right tap zones (ratio of the screen width / height)
PageTextInfo.bottom_tap_zone = { ratio_w = 0.2, ratio_h = 0.08 }

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
        {
            id = "pagetextinfo_multiswipe",
            ges = "multiswipe",
            overrides = {
                "rolling_swipe",
                "paging_swipe",
                "readerhighlight_swipe",
            },
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onMultiSwipe(nil, ges) end,
        },
        {
            -- Two fingers swipe (up / down). Up: nothing for the moment. Down: Reading History Popup Table Plus.
            id = "pagetextinfo_two_finger_swipe",
            ges = "two_finger_swipe",
            overrides = {
                "rolling_swipe",
                "paging_swipe",
                "readerhighlight_swipe",
                "two_finger_swipe_north",
                "two_finger_swipe_south",
            },
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onTwoFingerSwipe(nil, ges) end,
        },
        {
            -- Tap in the bottom left corner: toggles the double tap detection (see onBottomTap)
            id = "pagetextinfo_tap_bottom_left",
            ges = "tap",
            screen_zone = {
                ratio_x = 0, ratio_y = 1 - PageTextInfo.bottom_tap_zone.ratio_h,
                ratio_w = PageTextInfo.bottom_tap_zone.ratio_w, ratio_h = PageTextInfo.bottom_tap_zone.ratio_h,
            },
            overrides = {
                "pagetextinfo_tap",
                "tap_backward",
                "tap_forward",
                "tap_left_bottom_corner",
                "readerfooter_tap",
                "readerconfigmenu_tap",
            },
            handler = function(ges) return self:onBottomTap("left", ges) end,
        },
        {
            -- Tap in the bottom right corner: detected, nothing to do for the moment (see onBottomTap)
            id = "pagetextinfo_tap_bottom_right",
            ges = "tap",
            screen_zone = {
                ratio_x = 1 - PageTextInfo.bottom_tap_zone.ratio_w, ratio_y = 1 - PageTextInfo.bottom_tap_zone.ratio_h,
                ratio_w = PageTextInfo.bottom_tap_zone.ratio_w, ratio_h = PageTextInfo.bottom_tap_zone.ratio_h,
            },
            overrides = {
                "pagetextinfo_tap",
                "tap_backward",
                "tap_forward",
                "tap_right_bottom_corner",
                "readerfooter_tap",
                "readerconfigmenu_tap",
            },
            handler = function(ges) return self:onBottomTap("right", ges) end,
        },
        {
            -- Double tap in the bottom left corner: lines on / off (see onBottomDoubleTap)
            id = "pagetextinfo_double_tap_bottom_left",
            ges = "double_tap",
            screen_zone = {
                ratio_x = 0, ratio_y = 1 - PageTextInfo.bottom_tap_zone.ratio_h,
                ratio_w = PageTextInfo.bottom_tap_zone.ratio_w, ratio_h = PageTextInfo.bottom_tap_zone.ratio_h,
            },
            overrides = {
                "pagetextinfo_double_tap",
                "double_tap_left_side",
                "double_tap_bottom_left_corner",
            },
            handler = function(ges) return self:onBottomDoubleTap("left", ges) end,
        },
        {
            -- Double tap in the bottom right corner: background (picture) on / off (see onBottomDoubleTap)
            id = "pagetextinfo_double_tap_bottom_right",
            ges = "double_tap",
            screen_zone = {
                ratio_x = 1 - PageTextInfo.bottom_tap_zone.ratio_w, ratio_y = 1 - PageTextInfo.bottom_tap_zone.ratio_h,
                ratio_w = PageTextInfo.bottom_tap_zone.ratio_w, ratio_h = PageTextInfo.bottom_tap_zone.ratio_h,
            },
            overrides = {
                "pagetextinfo_double_tap",
                "double_tap_right_side",
                "double_tap_bottom_right_corner",
            },
            handler = function(ges) return self:onBottomDoubleTap("right", ges) end,
        },
        {
            -- Tap in the bottom center (same zone as the stock footer / bookends): see onBottomCenterTap
            id = "pagetextinfo_tap_bottom_center",
            ges = "tap",
            screen_zone = (function()
                local z = G_defaults:readSetting("DTAP_ZONE_MINIBAR")
                return { ratio_x = z.x, ratio_y = z.y, ratio_w = z.w, ratio_h = z.h }
            end)(),
            overrides = {
                "bookends_footer_tap",
                "readerfooter_tap",
                "pagetextinfo_tap",
            },
            handler = function(ges) return self:onBottomCenterTap(ges) end,
        },
    })
end

-- Frontlight cycle, in % of the range of the device (Kindle, Kobo... have different ranges):
--   off -> level 1 -> level 2 -> ... -> off   (any other current value goes to off)
-- The next step is decided from the current state, so nothing is stored.
-- TO CHANGE THE LEVELS: edit the lists below (% of the range of the device, any number of steps, increasing).
-- Each device family has its own list; "default" is used for any other device (emulator, Android, PocketBook...).
PageTextInfo.frontlight_cycle_by_device = {
    kobo   = { 3, 10 },
    kindle = { 25, 40 },
    default = { 5, 10 },
}

function PageTextInfo:getFrontlightCyclePercents()
    local cfg = PageTextInfo.frontlight_cycle_by_device
    if Device:isKobo() then return cfg.kobo or cfg.default end
    if Device:isKindle() then return cfg.kindle or cfg.default end
    return cfg.default
end

-- Device intensities of the steps of the cycle (percent -> device intensity, never 0, which would be off;
-- strictly increasing). Shared by cycleFrontlight() and getCurrentFrontlightStep()
function PageTextInfo:getFrontlightCycleLevels()
    local powerd = Device:getPowerDevice()
    local fl_min = powerd.fl_min or 0
    local fl_max = powerd.fl_max or 100
    local pcts = self:getFrontlightCyclePercents()
    local levels = {}
    for i, pct in ipairs(pcts) do
        local level = math.floor(fl_min + (fl_max - fl_min) * pct / 100 + 0.5)
        level = math.max(level, fl_min + 1, (levels[i - 1] or 0) + 1)
        level = math.min(level, fl_max)
        levels[i] = level
    end
    return levels
end

-- Step of the frontlight cycle the light is on now: 1, 2... ; 0 = off; nil = on but at a level that is
-- not any step (changed with the slider, for instance). Shown by the top bar light indicator (☼1, ☼2)
function PageTextInfo:getCurrentFrontlightStep()
    if not Device:hasFrontlight() then return nil end
    local powerd = Device:getPowerDevice()
    if not powerd:isFrontlightOn() then return 0 end
    local current = powerd:frontlightIntensity()
    for i, level in ipairs(self:getFrontlightCycleLevels()) do
        if current == level then return i end
    end
    return nil
end

function PageTextInfo:cycleFrontlight()
    if not Device:hasFrontlight() then return false end
    local powerd = Device:getPowerDevice()
    -- local fl_min = powerd.fl_min or 0
    -- local fl_max = powerd.fl_max or 100
    -- -- percent -> device intensity (never 0, which would be off; strictly increasing)
    -- local pcts = self:getFrontlightCyclePercents()
    -- local levels = {}
    -- for i, pct in ipairs(pcts) do
    --     local level = math.floor(fl_min + (fl_max - fl_min) * pct / 100 + 0.5)
    --     level = math.max(level, fl_min + 1, (levels[i - 1] or 0) + 1)
    --     level = math.min(level, fl_max)
    --     levels[i] = level
    -- end
    -- Moved to getFrontlightCycleLevels(), also used by getCurrentFrontlightStep() for the top bar
    local levels = self:getFrontlightCycleLevels()
    local next_idx = nil -- nil = off
    if not powerd:isFrontlightOn() then
        next_idx = 1
    else
        local current = powerd:frontlightIntensity()
        for i, level in ipairs(levels) do
            if current == level and levels[i + 1] then
                next_idx = i + 1
                break
            end
        end
    end
    if not next_idx then
        powerd:turnOffFrontlight()
        -- "Off" big over the page, same style and fade as the bottom right tap (showSessionOverlay)
        -- the sun is the frontlight symbol of the KOReader footer; a line is painted over it
        self:showSessionOverlay({ "☼ " .. _("Off") }, "☼")
    else
        powerd:setIntensity(levels[next_idx])
    end
    UIManager:broadcastEvent(Event:new("FrontlightStateChanged"))
    return true
end

-- Double tap detection on / off. Disabled = page turns are immediate (no waiting to see if a second tap comes).
-- Disabled also means "hold corners ignored" (lock icon of the top bar) and no vocabulary highlight.
-- Turning the detection off also turns the vocabulary highlight off.
function PageTextInfo:isDoubleTapDisabled()
    return self.ui.disable_double_tap and true or false
end

function PageTextInfo:setDoubleTapDisabled(disabled)
    if self:isDoubleTapDisabled() == disabled then return end
    self.ui.disable_double_tap = disabled
    -- We need also to change this, otherwise the toggle does not work just with self.ui.disable_double_tap
    Device.input.disable_double_tap = disabled
    if self.ui.gestures then self.ui.gestures:onIgnoreHoldCorners(disabled) end
    if disabled and self.settings:readSetting("highlight_all_words_vocabulary_builder_and_notes") then
        -- turns the highlight off and refreshes the top bar
        self:toggleHighlightAllWordsVocabulary(false)
        return
    end
    pcall(function() self.view.topbar:toggleBar() end)
    UIManager:setDirty(self.view.dialog, "ui")
end

-- Vocabulary mode: double tap detection ON (to look words up) + vocabulary / notes highlighted.
PageTextInfo.vocabulary_ignores_hold_corners = true

function PageTextInfo:enterVocabularyMode()
    self.ui.disable_double_tap = false
    Device.input.disable_double_tap = false
    -- The corner mark of the top bar follows "hold corners ignored" (ignore_hold_corners):
    --   off -> no mark (double tap on, normal),  on + vocabulary -> striped triangle,  on + no vocabulary -> solid triangle
    -- So it has to be ON here for the striped "vocabulary" mark to show (and the corner words can be double tapped).
    if self.ui.gestures then
        self.ui.gestures:onIgnoreHoldCorners(PageTextInfo.vocabulary_ignores_hold_corners and true or false)
    end
    return self:toggleHighlightAllWordsVocabulary(true)
end

-- ===== Session overlay: session time (top half) and wpm (bottom half), big, grey, no background =====
-- It is painted straight over the page text (no frame, no background) and it fades out: the text is repainted a few
-- times with a lighter grey and then removed. Everything to tune is in this table.
PageTextInfo.session_overlay_cfg = {
    font_size = 100,                 -- biggest size (points); it is reduced if the text does not fit the screen width
    min_font_size = 24,
    width_ratio = 0.92,              -- max width of the text (ratio of the screen width)
    font = "NotoSans-Bold.ttf",      -- fallback only, used if the font of the document cannot be loaded
    color = 0x77,                    -- grey of the text (0x00 black ... 0xFF white)
    hold = 0.8,                      -- seconds fully visible
    fade_colors = { 0x99, 0xBB, 0xDD },  -- greys of the fade out steps (each one is a refresh)
    fade_interval = 0.2,             -- seconds between fade steps
    fade_end = 0xDD,                 -- last grey of the fade out (used when the color is chosen in the menu)
}

-- Kindle: the fade steps are skipped (its slow refresh showed the last grey instead of the chosen color) and the text
-- appears with "partial"
PageTextInfo.session_overlay_kindle = Device:isKindle()

-- Colors to choose in the menu ("Big texts color"); setting "overlay_color", without it cfg.color
PageTextInfo.session_overlay_colors = {
    { _("Black"), 0x00 },
    { _("Dark grey"), 0x44 },
    { _("Grey"), 0x77 },
    { _("Light grey"), 0xAA },
}

function PageTextInfo:getOverlayColor()
    local c = tonumber(self.settings and self.settings:readSetting("overlay_color"))
    return c or PageTextInfo.session_overlay_cfg.color
end

-- Seconds fully visible to choose in the menu ("Big texts duration"); setting "overlay_hold", without it cfg.hold
PageTextInfo.session_overlay_holds = { 0.3, 0.5, 0.8, 1.2, 1.5, 2, 3, 5 }

function PageTextInfo:getOverlayHold()
    local h = tonumber(self.settings and self.settings:readSetting("overlay_hold"))
    return h or PageTextInfo.session_overlay_cfg.hold
end

-- Fade greys from the chosen color to cfg.fade_end (with the default color: cfg.fade_colors as before)
function PageTextInfo:getOverlayFadeColors(color)
    local cfg = PageTextInfo.session_overlay_cfg
    if color == cfg.color then return cfg.fade_colors end
    local n = #cfg.fade_colors
    local steps = {}
    for i = 1, n do
        steps[i] = math.floor(color + (cfg.fade_end - color) * i / n + 0.5)
    end
    return steps
end

local SessionOverlay = WidgetContainer:extend{
    name = "pagetextinfo_session_overlay",
    toast = true, -- painted over everything and it does not take the events (the page below keeps working)
}

local function wpmFromJson()
    local f = io.open(DataStorage:getSettingsDir() .. "/wpm_session.json", "r")
    if not f then return 0 end
    local raw = f:read("*a")
    f:close()
    local wpm = tonumber(raw and raw:match('"wpm"%s*:%s*(%d+)'))
    local updated = tonumber(raw and raw:match('"updated"%s*:%s*(%d+)'))
    if not wpm or not updated or os.time() - updated > 300 then return 0 end
    return wpm
end

local function formatSessionTime(secs)
    secs = math.max(0, math.floor(secs))
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then
        return string.format("%dh %02dm", h, m)
    end
    return string.format("%dm %02ds", m, secs % 60)
end

-- Face of the font of the document at a given size (falls back to cfg.font)
function SessionOverlay:getFace(size)
    local cfg = PageTextInfo.session_overlay_cfg
    for _i, name in ipairs(self.font_candidates or {}) do
        local ok, face = pcall(Font.getFace, Font, name, size)
        if ok and face then return face end
    end
    return Font:getFace(cfg.font, size)
end

-- Three texts, one per vertical third of the screen: clock, session time, wpm
function SessionOverlay:buildTexts(color)
    local cfg = PageTextInfo.session_overlay_cfg
    for _i, w in ipairs(self.widgets or {}) do w:free() end
    self.widgets = {}
    self.sizes = self.sizes or {}
    local max_w = math.floor(Screen:getWidth() * cfg.width_ratio)
    for i, text in ipairs(self.texts) do
        local size = self.sizes[i] or cfg.font_size
        local w
        while true do
            w = TextWidget:new{ text = text, face = self:getFace(size), fgcolor = color, padding = 0 }
            if w:getSize().w <= max_w or size <= cfg.min_font_size then break end
            w:free()
            size = size - 6
        end
        self.widgets[i] = w
        self.sizes[i] = size
    end
    self.color = color
    -- strike_icon: the first text starts with this icon, a diagonal line is painted over it (see paintTo)
    if self.strike_icon and self.widgets[1] then
        local iw = TextWidget:new{ text = self.strike_icon, face = self:getFace(self.sizes[1]), fgcolor = color, padding = 0 }
        self.strike_w = iw:getSize().w
        iw:free()
    end
end

function SessionOverlay:init()
    local cfg = PageTextInfo.session_overlay_cfg
    -- self:buildTexts(Blitbuffer.Color8(cfg.color))
    self:buildTexts(Blitbuffer.Color8(self.text_color or cfg.color))
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local n = #self.widgets
    self.positions, self.regions = {}, {}
    local x1, y1, x2, y2
    for i, w in ipairs(self.widgets) do
        local sz = w:getSize()
        -- each text is centred in its own part of the screen (1/6, 3/6, 5/6 of the height with three texts)
        local cy = sh * (2 * i - 1) / (2 * n)
        local pos = { x = math.floor((sw - sz.w) / 2), y = math.floor(cy - sz.h / 2) }
        self.positions[i] = pos
        -- separate regions, so the e-ink does not refresh the page in between
        -- a little wider than the text: glyphs like the f overhang their box and left a ghost outside the refreshed area
        local pad = math.ceil((self.sizes[i] or cfg.font_size) * 0.2)
        self.regions[i] = Geom:new{ x = math.max(0, pos.x - pad), y = math.max(0, pos.y - pad),
            w = math.min(sw, sz.w + 2 * pad), h = sz.h + 2 * pad }
        x1 = x1 and math.min(x1, pos.x) or pos.x
        y1 = y1 and math.min(y1, pos.y) or pos.y
        x2 = x2 and math.max(x2, pos.x + sz.w) or (pos.x + sz.w)
        y2 = y2 and math.max(y2, pos.y + sz.h) or (pos.y + sz.h)
    end
    self.dimen = Geom:new{ x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

function SessionOverlay:setColor(grey)
    self:buildTexts(Blitbuffer.Color8(grey))
end

function SessionOverlay:paintTo(bb, x, y)
    for i, w in ipairs(self.widgets) do
        w:paintTo(bb, self.positions[i].x, self.positions[i].y)
    end
    -- line over the icon: from bottom left to top right, made of small squares (same grey as the text)
    if self.strike_w and self.widgets[1] then
        local pos = self.positions[1]
        local h = self.widgets[1]:getSize().h
        local bw = self.strike_w
        local thick = math.max(2, math.floor(self.sizes[1] / 10))
        local x0, y0 = pos.x, pos.y + math.floor(h * 0.85)
        local x1, y1 = pos.x + bw, pos.y + math.floor(h * 0.15)
        local steps = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
        for s = 0, steps do
            local px = math.floor(x0 + (x1 - x0) * s / steps - thick / 2)
            local py = math.floor(y0 + (y1 - y0) * s / steps - thick / 2)
            bb:paintRect(px, py, thick, thick, self.color)
        end
    end
end

function SessionOverlay:handleEvent(event)
    -- it takes no events (the page below keeps working), only frees its texts when it is closed
    if event and event.handler == "onCloseWidget" then self:onCloseWidget() end
    return false
end

function SessionOverlay:onCloseWidget()
    for _i, w in ipairs(self.widgets or {}) do w:free() end
end

-- Refresh of the text areas (not of the whole screen)
function SessionOverlay:refresh()
    for _i, r in ipairs(self.regions) do
        UIManager:setDirty(self, "ui", r)
    end
end

function PageTextInfo:closeSessionOverlay()
    self.session_overlay_token = (self.session_overlay_token or 0) + 1 -- cancels the pending fade steps
    local overlay = self.session_overlay
    self.session_overlay = nil
    if overlay then
        UIManager:close(overlay, "ui", overlay.regions[1])
        for i = 2, #overlay.regions do
            UIManager:setDirty(nil, "ui", overlay.regions[i])
        end
    end
end

-- wpm of the session in progress, the same number the statistics plugin saves: words / counted reading time. It is read
-- from the plugin itself (always current, no 5 minutes limit); the json file is only the fallback.
function PageTextInfo:getSessionWpm()
    local stats = self.ui and self.ui.statistics
    local words = stats and tonumber(stats._total_words) or 0
    local secs = stats and tonumber(stats._total_read_time) or 0
    -- Live part: the page being read now is counted as if it were turned at this moment
    -- (same rules as the statistics plugin: at least min_sec, at most max_sec per page)
    pcall(function()
        local page_data = stats.page_stat[stats.curr_page]
        local tuple = page_data and page_data[#page_data]
        if tuple and tuple[1] and not stats._reading_paused_ts then
            local elapsed = os.time() - tuple[1]
            if elapsed >= stats.settings.min_sec then
                secs = secs + math.min(elapsed, stats.settings.max_sec)
                words = words + (tonumber(stats._last_nbwords) or 0)
            end
        end
    end)
    if words > 0 and secs > 0 then
        return math.floor(words / (secs / 60))
    end
    return wpmFromJson()
end

-- texts (optional): list of texts to show, one per part of the screen. Without it: clock, session time, wpm.
-- strike_icon (optional): icon at the start of the first text that gets a diagonal line over it.
function PageTextInfo:showSessionOverlay(texts, strike_icon)
    local cfg = PageTextInfo.session_overlay_cfg
    self:closeSessionOverlay()

    if not texts then
        local topbar = self.view and self.view.topbar
        local stats = self.ui and self.ui.statistics
        local start = (topbar and topbar.start_session_time) or (stats and tonumber(stats.start_current_period))
        local secs = start and (os.time() - start) or 0
        texts = {
            os.date("%H:%M"),
            formatSessionTime(secs),
            string.format("%d wpm", self:getSessionWpm()),
        }
    end

    -- font of the document: the plugin's own helper if it has one, else the family of the document with "-Regular"
    local candidates = {}
    if self.getFaceName then
        local ok, name = pcall(self.getFaceName, self)
        if ok and name then candidates[#candidates + 1] = name end
    end
    pcall(function()
        local family = self.ui.document._document:getFontFace()
        if family then
            candidates[#candidates + 1] = family:gsub("%s+", "") .. "-Regular"
            candidates[#candidates + 1] = family
        end
    end)

    local color = self:getOverlayColor()
    local fade_colors = self:getOverlayFadeColors(color)
    local overlay = SessionOverlay:new{
        font_candidates = candidates,
        texts = texts,
        strike_icon = strike_icon,
        text_color = color,
    }
    self.session_overlay = overlay
    local token = self.session_overlay_token
    UIManager:show(overlay, PageTextInfo.session_overlay_kindle and "partial" or "ui", overlay.regions[1])
    for i = 2, #overlay.regions do
        UIManager:setDirty(overlay, PageTextInfo.session_overlay_kindle and "partial" or "ui", overlay.regions[i])
    end

    -- "Fade out big texts" off (menu): no fade steps, the text goes at once after the same total time
    if self.settings:isTrue("no_overlay_fade") or PageTextInfo.session_overlay_kindle then
        -- UIManager:scheduleIn(cfg.hold + #cfg.fade_colors * cfg.fade_interval, function()
        UIManager:scheduleIn(self:getOverlayHold() + #fade_colors * cfg.fade_interval, function()
            if self.session_overlay_token ~= token or self.session_overlay ~= overlay then return end
            self:closeSessionOverlay()
        end)
        return
    end

    local function fadeStep(i)
        if self.session_overlay_token ~= token or self.session_overlay ~= overlay then return end
        -- local grey = cfg.fade_colors[i]
        local grey = fade_colors[i]
        if not grey then
            self:closeSessionOverlay()
            return
        end
        overlay:setColor(grey)
        overlay:refresh()
        UIManager:scheduleIn(cfg.fade_interval, function() fadeStep(i + 1) end)
    end
    UIManager:scheduleIn(self:getOverlayHold(), function() fadeStep(1) end)
end

-- Taps in the bottom corners. Left: toggle the double tap detection (from vocabulary mode: double tap ON, vocabulary off).
-- Right: shows the session time and the wpm for a moment (showSessionOverlay).
function PageTextInfo:onBottomTap(side, ges)
    if not self.initialized then return false end
    if side == "left" then
        -- In vocabulary mode the double tap is already on: the tap leaves the vocabulary and keeps the double tap ON
        if self.settings:readSetting("highlight_all_words_vocabulary_builder_and_notes") then
            self.ui.disable_double_tap = false
            Device.input.disable_double_tap = false
            if self.ui.gestures then self.ui.gestures:onIgnoreHoldCorners(false) end
            self:toggleHighlightAllWordsVocabulary(false) -- highlight off and top bar refreshed
            -- UIManager:show(Notification:new{ text = _("Double tap on") })
            -- big over the page, same style and fade as the frontlight "Off" (showSessionOverlay)
            self:showSessionOverlay({ _("Double tap on") })
            return true
        end
        local disable = not self:isDoubleTapDisabled()
        self:setDoubleTapDisabled(disable)
        -- UIManager:show(Notification:new{
        --     text = disable and _("Double tap off") or _("Double tap on"),
        -- })
        -- big over the page, same style and fade as the frontlight "Off" (showSessionOverlay)
        self:showSessionOverlay({ disable and _("Double tap off") or _("Double tap on") })
        return true
    end
    -- side == "right": session time (top half) and wpm (bottom half) over the page, fading out after a moment
    self:showSessionOverlay()
    return true
end

-- Double tap in the bottom corners. Left: ruled lines on / off. Right: background (the configured picture) on / off.
-- Each one toggles only its own thing: bookends, the topbar and the other custombg part are left as they are.
function PageTextInfo:onBottomDoubleTap(side, ges)
    if not self.initialized then return false end
    if self.view.footer_visible then return false end
    local custombg = self.ui and self.ui.custombg
    if not custombg then return false end
    if side == "left" then
        local on = custombg.fs_enabled and true or false
        if custombg.setLinesEnabled then
            custombg:setLinesEnabled(not on)
        else
            custombg.fs_enabled = not on
            custombg:saveDocSetting("fs_lines_enabled", not on)
        end
    else
        local on = custombg:isPictureOn()
        -- applyBackground() repaints by itself; mute it so there is one repaint (the one below)
        local own_repaint = rawget(custombg, "toggleRepaint")
        custombg.toggleRepaint = function() end
        local ok, err = pcall(custombg.setPictureEnabled, custombg, not on)
        custombg.toggleRepaint = own_repaint
        if not ok then error(err, 0) end
    end
    if custombg.toggleRepaint then
        custombg:toggleRepaint(self.view.dialog)
    else
        UIManager:setDirty(self.view.dialog, "ui")
    end
    return true
end

-- True only when custombg says its picture is switched off (isPictureOn() == false). Switched off,
-- getCurrentDocBg() and getBottomMode() may still return the chosen background / mode, so they alone
-- do not tell whether a picture is showing. Without isPictureOn (older custombg): false.
function PageTextInfo:isCustomBgPictureOff(custombg)
    custombg = custombg or (self.ui and self.ui.custombg)
    if not (custombg and custombg.isPictureOn) then return false end
    local ok, on = pcall(custombg.isPictureOn, custombg)
    return ok and on == false
end

-- Cycles the custombg picture on each tap in the bottom center:
--   off -> image (background) -> book title (cover text) -> bookshelf hero -> background settings -> off ...
-- A type that cannot be made for this book (no cover, no hero, no images) is skipped.
-- self._bg_cycle_stage = "settings" remembers that the settings were just shown (next tap: off).
-- If the picture is changed in another way (menu, double tap), the cycle goes on from what is showing.
function PageTextInfo:cycleCustomBgPicture()
    local custombg = self.ui and self.ui.custombg
    if not (custombg and custombg.setBottomMode and custombg.applyBackground) then return false end
    local mode = custombg:getBottomMode()                    -- "cover" / "hero" / nil
    local current = mode or (custombg:getCurrentDocBg() and "image") or nil
    local picture_off = self:isCustomBgPictureOff(custombg)
    if picture_off then current = nil end
    local stage = current and self._bg_cycle_stage or nil

    -- applyBackground / setBottomMode repaint by themselves; mute it so there is one repaint at the end
    local own_repaint = rawget(custombg, "toggleRepaint")
    custombg.toggleRepaint = function() end

    local function showImage()
        if custombg:getGlobalDefaultBg() then
            custombg:applyBackground(nil)
        else
            local names = {}
            for name in pairs(custombg:getCurrentImageCache()) do names[#names + 1] = name end
            custombg:applyBackground(#names > 0 and names[math.random(#names)] or nil)
        end
        return custombg:getCurrentDocBg() ~= nil and custombg:getBottomMode() == nil
    end
    local function showBottom(m)
        custombg:setBottomMode(m)
        return custombg:getBottomMode() == m
    end
    local function turnOn()
        if picture_off and custombg.setPictureEnabled then custombg:setPictureEnabled(true) end
        if not showImage() and not showBottom("cover") then showBottom("hero") end
    end

    local open_settings = false
    local new_stage = nil
    local ok, err = pcall(function()
        if not current then
            turnOn()                                          -- off -> image
        elseif stage == "settings" then
            -- after the settings: off (older custombg without setPictureEnabled: back to the image)
            if custombg.setPictureEnabled then
                custombg:setPictureEnabled(false)
            else
                turnOn()
            end
        elseif current == "image" then
            if not showBottom("cover") and not showBottom("hero") then open_settings = true end
        elseif current == "cover" then
            if not showBottom("hero") then open_settings = true end
        else -- "hero"
            open_settings = true
        end
        if open_settings then new_stage = "settings" end
    end)
    custombg.toggleRepaint = own_repaint
    if not ok then
        self._bg_cycle_stage = nil
        error(err, 0)
    end
    self._bg_cycle_stage = new_stage

    if open_settings then
        self:showCustomBgSubMenu("background")
        return true
    end
    if custombg.toggleRepaint then
        custombg:toggleRepaint(self.view.dialog)
    else
        UIManager:setDirty(self.view.dialog, "ui")
    end
    -- -- the new state big over the page, same style and fade as the frontlight "Off" (showSessionOverlay);
    -- -- on the next tick, so it is painted over the repaint of the background
    -- local label
    -- if self:isCustomBgPictureOff(custombg) then
    --     label = _("Off")
    -- else
    --     local new_mode = custombg:getBottomMode()
    --     if new_mode == "cover" then
    --         label = _("Cover")
    --     elseif new_mode == "hero" then
    --         label = _("Hero")
    --     elseif custombg:getCurrentDocBg() then
    --         label = _("Image")
    --     end
    -- end
    -- if label then
    --     UIManager:nextTick(function() self:showSessionOverlay({ label }) end)
    -- end
    return true
end

-- Tap in the bottom center (the zone bookends uses for its "tap on the bottom bar" action):
--   bookends on                 -> next bookends preset
--   top bar "hidden" (or none)  -> custombg picture:
--                                  off -> image -> book title (cover text) -> hero -> settings -> off ...
--   top bar "on" or "minimal"   -> nothing
-- The tap is always consumed, so bookends does not act on its own.
function PageTextInfo:onBottomCenterTap(ges)
    if not self.initialized then return false end
    local bookends = self.ui and self.ui.bookends
    if bookends and bookends.enabled then
        if bookends.onCycleBookendsPreset then bookends:onCycleBookendsPreset() end
        return true
    end
    local topbar = self.view and self.view.topbar
    if topbar and self:getTopBarMode() ~= "hidden" then return true end
    if self.ui and self.ui.custombg then
        self:cycleCustomBgPicture()
    end
    return true
end

-- Bookends registers its own bottom center tap zone ("bookends_footer_tap") that toggles / cycles by itself.
-- The override in initGesListener should already put our zone first, but to be sure, the handler of the
-- bookends zone is replaced by ours, so that tap always goes through onBottomCenterTap.
-- (_ordered_touch_zones keeps the same zone tables as _zones, so changing the handler here is enough.)
function PageTextInfo:takeOverBookendsFooterTap()
    local zones = self.ui and self.ui._zones
    local zone = zones and zones["bookends_footer_tap"]
    if zone and not zone._pagetextinfo then
        zone.handler = function(ges) return self:onBottomCenterTap(ges) end
        zone._pagetextinfo = true
    end
end

-- Top bar display modes, cycled with the one-finger swipe north (when bookends is off):
--   "on"      -> full top bar                      (topbar.is_enabled = true)
--   "minimal" -> top bar disabled as before: page number bottom center + time left
--   "hidden"  -> top bar disabled and nothing of it painted
-- The hidden state is kept in this plugin's settings ("topbar_hidden"), so it survives restarts.
function PageTextInfo:getTopBarMode()
    local topbar = self.view and self.view.topbar
    if topbar and topbar.is_enabled then return "on" end
    if self.settings:isTrue("topbar_hidden") then return "hidden" end
    return "minimal"
end

-- With the top bar disabled, ReaderView paints it with TopBar:paintToDisabled (page number bottom center,
-- daily time left bottom left, chapter pages left and the corner mark). In the hidden mode that function
-- paints only the corner mark (vocabulary highlight / double tap off). Wrapped on this topbar instance only, so topbar.lua is not changed.
function PageTextInfo:installTopBarHiddenPaint()
    local topbar = self.view and self.view.topbar
    if not topbar or topbar._pagetextinfo_hidden_paint then return end
    local pti = self
    local function isHidden(tb)
        return not tb.is_enabled and pti.settings:isTrue("topbar_hidden")
    end
    -- In the hidden mode only the corner mark is painted (striped triangle: vocabulary highlight, solid triangle:
    -- double tap off, nothing: normal), at the same place as the first block of TopBar:paintToDisabled.
    local function paintCornerMark(tb, bb, x, y)
        local c = tb.ignore_corners_widget_container
        if not (c and c[1]) then return end
        local ok, err = pcall(function()
            c[1]:setText(tb.ignore_corners or "")
            local right = Screen:scaleBySize(Device:isAndroid() and 20 or 2)
            local py
            if (tb.status_bar and tb.status_bar == true and tb.view.footer.settings.bar_top) or tb.view.dogear_visible then
                py = Screen:getHeight() - (tb.MARGIN_BOTTOM or 0)
            else
                py = y + Screen:scaleBySize(6)
            end
            c:paintTo(bb, x + Screen:getWidth() - c[1]:getSize().w - right, py)
        end)
        if not ok then logger.warn("pagetextinfo: corner mark in hidden top bar failed:", err) end
        -- The light (☼) and margins (● / ○) indicator is shown in the hidden mode too
        if tb.paintLightAndMarginIndicator then
            local ok_ind, err_ind = pcall(tb.paintLightAndMarginIndicator, tb, bb, x, y)
            if not ok_ind then logger.warn("pagetextinfo: light/margins indicator in hidden top bar failed:", err_ind) end
        end
    end
    topbar._pagetextinfo_hidden_paint = true
    local orig_paintToDisabled = topbar.paintToDisabled
    if orig_paintToDisabled then
        topbar.paintToDisabled = function(tb, bb, x, y)
            if isHidden(tb) then return paintCornerMark(tb, bb, x, y) end
            return orig_paintToDisabled(tb, bb, x, y)
        end
    end
    local orig_paintTo = topbar.paintTo
    if orig_paintTo then
        topbar.paintTo = function(tb, bb, x, y)
            if isHidden(tb) then return paintCornerMark(tb, bb, x, y) end
            return orig_paintTo(tb, bb, x, y)
        end
    end
end

-- The custombg picture only goes with the "hidden" top bar: leaving "hidden" hides it, coming back to "hidden"
-- puts it back if it was on ("picture_before_topbar" setting). Returns true if the picture changed.
function PageTextInfo:topBarModeChanged(old_mode, new_mode)
    if old_mode == new_mode then return false end
    if old_mode == "hidden" then return self:hidePictureFor("picture_before_topbar") end
    if new_mode == "hidden" then return self:restorePictureFor("picture_before_topbar") end
    return false
end

function PageTextInfo:setTopBarMode(mode)
    local topbar = self.view and self.view.topbar
    if not topbar then return false end
    self:installTopBarHiddenPaint()
    local old_mode = self:getTopBarMode()
    self.settings:saveSetting("topbar_hidden", mode == "hidden")
    self.settings:flush()
    local want_on = (mode == "on")
    -- Only switch the bar itself when on/off changes (minimal <-> hidden is just a repaint)
    if (topbar.is_enabled and true or false) ~= want_on then
        topbar:quickToggleOnOff(want_on)
    end
    -- self:repaintAfterPictureChange(self:topBarModeChanged(old_mode, self:getTopBarMode()))
    -- Same as cycleTopBarMode(): indicators computed again with the new mode before the repaint
    local picture_changed = self:topBarModeChanged(old_mode, self:getTopBarMode())
    self:refreshTopBarIndicators(topbar)
    self:repaintAfterPictureChange(picture_changed)
    return true
end

-- on -> minimal -> hidden -> on ...
-- The on/off switching is exactly the original code (quickToggleOnOff by is_enabled);
-- the hidden step is only a flag + repaint on top of "disabled", so it can never block on/off.
-- The custombg picture is hidden when leaving "hidden" and put back when coming back to it (topBarModeChanged).
function PageTextInfo:cycleTopBarMode()
    local topbar = self.view and self.view.topbar
    if not topbar then return false end
    pcall(self.installTopBarHiddenPaint, self)
    local old_mode = self:getTopBarMode()
    local hidden = self.settings:isTrue("topbar_hidden")
    if topbar.is_enabled == nil or topbar.is_enabled == false then
        if not hidden then
            -- minimal -> hidden: bar stays disabled, just stop painting it
            self.settings:saveSetting("topbar_hidden", true)
            self.settings:flush()
        else
            -- hidden -> on (original enable)
            self.settings:saveSetting("topbar_hidden", false)
            self.settings:flush()
            topbar:quickToggleOnOff(true)
        end
    else
        -- on -> minimal (original disable)
        self.settings:saveSetting("topbar_hidden", false)
        self.settings:flush()
        topbar:quickToggleOnOff(false)
    end
    -- minimal -> hidden does not go through quickToggleOnOff, so the top bar texts (light and margins
    -- indicator) were not computed again. The expected margins also depend on the mode (preset 4 with
    -- "hidden": 15/15), so the indicator is computed again with the new mode before the repaint
    -- After topBarModeChanged(): the custombg picture (shown or hidden there) changes the expected bottom margin
    local picture_changed = self:topBarModeChanged(old_mode, self:getTopBarMode())
    self:refreshTopBarIndicators(topbar)
    self:repaintAfterPictureChange(picture_changed)
    return true
end

-- Every repaint of custombg (picture changed with the bottom center tap, settings, on / off...) also computes the
-- top bar indicators again. The picture changes the bottom margin the preset expects (getPictureBottomMargin) and
-- custombg repaints the reader by itself, so without this the indicators kept the old state (or were not painted)
-- until the next page turn / reload.
-- toggleRepaint is wrapped on this custombg instance only. The places that mute it for a moment
-- (rawget + no-op + restore) get the wrapper back with rawget, so they keep working.
-- After the repaint, on the next tick, they are computed once more and the top of the screen is repainted: custombg
-- can still be changing the margins at that point.
function PageTextInfo:installCustomBgIndicatorRefresh()
    local custombg = self.ui and self.ui.custombg
    if not custombg or rawget(custombg, "_pti_indicator_refresh") then return end
    local orig = custombg.toggleRepaint
    if type(orig) ~= "function" then return end
    custombg._pti_indicator_refresh = true
    local pti = self
    custombg.toggleRepaint = function(cb, ...)
        pti:refreshTopBarIndicators()
        UIManager:nextTick(function()
            if not (pti.ui and pti.ui.document and pti.view) then return end
            pti:refreshTopBarIndicators()
            local topbar = pti.view.topbar
            local h = Screen:scaleBySize(40)
            if topbar and topbar.getHeight then
                local ok, th = pcall(topbar.getHeight, topbar)
                if ok and type(th) == "number" and th > h then h = th end
            end
            UIManager:setDirty(pti.view.dialog, "ui", Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = h })
        end)
        return orig(cb, ...)
    end
end

-- Computes the top bar texts again (light and margins indicator included) for the current mode
function PageTextInfo:refreshTopBarIndicators(topbar)
    topbar = topbar or (self.view and self.view.topbar)
    if not (topbar and topbar.toggleBar) then return end
    local ok, err = pcall(topbar.toggleBar, topbar)
    if not ok then logger.warn("pagetextinfo: refreshing the top bar indicators failed:", err) end
end

-- Shows one submenu of the custombg plugin ("lines": Ruled lines, "background": Custom reading background)
-- on its own, as a TouchMenu, without going through the main menu.
-- The items are taken from custombg:addToMainMenu(), so they are always the current ones of the plugin.
function PageTextInfo:showCustomBgSubMenu(which)
    local custombg = self.ui and self.ui.custombg
    if not custombg or not custombg.addToMainMenu then return false end
    local menu_items = {}
    local ok = pcall(custombg.addToMainMenu, custombg, menu_items)
    local root = ok and menu_items.custombg and menu_items.custombg.sub_item_table
    if not root then return false end
    -- Look for the entry by its text, falling back to its position in the menu
    local wanted = which == "lines" and _("Ruled lines (horizontal/vertical)") or _("Custom reading background")
    local entry
    for _i, item in ipairs(root) do
        if item.text == wanted then entry = item break end
    end
    entry = entry or root[which == "lines" and 2 or 3]
    if not entry then return false end
    local items = entry.sub_item_table
    if not items and entry.sub_item_table_func then
        local ok_f, res = pcall(entry.sub_item_table_func)
        items = ok_f and res or nil
    end
    if not items then return false end

    local TouchMenu = require("ui/widget/touchmenu")
    local tab = { icon = "appbar.settings" }
    for i, item in ipairs(items) do tab[i] = item end
    local menu_container = CenterContainer:new{
        covers_header = true,
        ignore = "height",
        dimen = Screen:getSize(),
    }
    local touch_menu = TouchMenu:new{
        width = Screen:getWidth(),
        tab_item_table = { tab },
        show_parent = menu_container,
    }
    touch_menu.close_callback = function()
        UIManager:close(menu_container)
    end
    menu_container[1] = touch_menu
    UIManager:show(menu_container)
    return true
end

function PageTextInfo:onTwoFingerSwipe(arg, ges)
    if not self.initialized then return false end
    local direction = ges and ges.direction
    if direction == "north" then
        -- Two fingers up: cycle the frontlight through the levels of the device (see frontlight_cycle_by_device)
        self:cycleFrontlight()
        return true
    elseif direction == "south" then
        -- Two fingers down: show the Reading History Popup Table Plus window (data from wpm_stat_data)
        -- The module name is the file name of the window source (without .lua)
        pcall(require, "reading_history_popup_table_plus")
        UIManager:broadcastEvent(Event:new("ShowReadingHistoryPopupTablePlusV1"))
        return true
    end
    -- Other directions are not ours
    return false
end

function PageTextInfo:toggleHighlightAllWordsVocabulary(toggle)
    self.settings:saveSetting("highlight_all_words_vocabulary_builder_and_notes", toggle)
    self.settings:flush()
    if toggle then
        self:updateWordsVocabulary()
        self:updateNotes()
    end
    self.view.topbar:toggleBar()
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
        alpha = true,
        file_do_cache = false,
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
        widget_settings.file = "resources/rulerKoboClaraBW.png"
    elseif Device.model == "KindlePaperWhite6" then
        widget_settings.file = "resources/rulerKindlePW6.png"
    else
        widget_settings.file = "resources/rulerEmulator.png"
    end


    -- widget_settings.file_do_cache = false
    widget_settings.alpha = true


    self.ruler_widget = ImageWidget:new(widget_settings)
    self.pos_x = 0
    self.pos_y = 0
    self.last_pos_x = -1
end

-- Fraction of the line box height, measured from its top, where the top of
-- a lowercase letter (x-height) sits. Roughly 0.25-0.35 for most fonts.
-- Tune it until the 0 mark touches the top of an "x".
local X_HEIGHT_TOP_RATIO = 0.30

-- Row of the 0 mark inside the ruler PNG (the script draws it at y = 2).
local ZERO_MARK_Y = 2

-- Returns the screen box (x, y, w, h) of the word under the tap, or nil.
function RulerOverlay:wordBox(pos)
    local ui = require("apps/reader/readerui").instance
    local doc = ui and ui.document
    if not (doc and doc.getWordFromPosition) then return nil end
    local ok, word = pcall(doc.getWordFromPosition, doc, pos)
    if ok and word and word.sbox then
        return word.sbox
    end
end

-- Removes any temporary selection that the reader left on the tapped word.
local function clearWordHighlight()
    local ui = require("apps/reader/readerui").instance
    if ui and ui.highlight and ui.highlight.clear then
        ui.highlight:clear()
    end
end

function RulerOverlay:onTapRuler(arg, ges_ev)
    if self.tapped then return true end
    local x, y = ges_ev.pos.x, ges_ev.pos.y
    local box = self:wordBox(ges_ev.pos)
    if box then
        -- Center the ruler on the word and put the 0 mark at the
        -- estimated top of the lowercase letters.
        x = box.x + math.floor(box.w / 2)
        y = box.y + math.floor(box.h * X_HEIGHT_TOP_RATIO)
    end
    -- No highlight clearing here: the word stays highlighted while the
    -- ruler is shown.
    self.tapped = true
    self.pos_x, self.pos_y = x, y
    local ruler = self.ruler_widget
    UIManager:setDirty(require("apps/reader/readerui").instance.view.dialog, "ui")
    UIManager:scheduleIn(0.5, function()
        ruler:paintTo(Screen.bb, x - Screen:getWidth() / 2, y - ZERO_MARK_Y)
        UIManager:setDirty(nil, "ui")
        self.tapped = false
    end)
    return true
end

function RulerOverlay:onSwipeRuler(arg, ges_ev)
    -- Toggle off: remove the highlight and repaint the page so the ruler
    -- (drawn straight into the screen buffer) disappears too.
    clearWordHighlight()
    self.ruler_widget:free()
    UIManager:close(self)
    UIManager:setDirty(require("apps/reader/readerui").instance.view.dialog, "ui")
    return true
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

-- "Go back" bubble of the reading-location patch. Returns true if it was showing (it is closed now), false if not.
-- go_to_page = true: also jump to the page it points to (same as tapping it); false: only close it.
function PageTextInfo:_closeLocationBubble(go_to_page)
    local rlt = self.ui and self.ui._rlt_overlay
    if not (rlt and rlt.visible) then return false end
    local target = go_to_page and self.ui._rlt_anchor or nil
    local region = rlt.box_dimen
    rlt.visible = false
    if not target then
        -- Only closing: accept the current page as the new reference, like the "X" of the bubble does. If the
        -- anchor is left where it was, the bubble shows up again on the next page turn.
        if self.ui._rlt_current_page then
            self.ui._rlt_anchor = self.ui._rlt_current_page
            self.ui._rlt_anchor_ref = self.ui._rlt_current_ref
        end
    end
    if target then
        -- the jump repaints the whole page, already without the bubble
        self.ui:handleEvent(Event:new("GotoPage", target))
    elseif region then
        region = Geom:new{ x = region.x, y = region.y, w = region.w, h = region.h + Screen:scaleBySize(2) }
        UIManager:setDirty(self.ui.dialog or self.ui, function() return "flashui", region end)
    else
        UIManager:setDirty(self.view.dialog, "ui")
    end
    return true
end

function PageTextInfo:onSwipe(arg, ges)
    if not self.initialized then return end
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if direction == "west" then
        -- Toggle between two states: double tap OFF  <->  vocabulary mode (double tap on + vocabulary highlighted).
        -- From vocabulary mode it goes to double tap off silently; from the plain double tap on (the tap in the bottom
        -- left corner) it goes to double tap off and says so; from double tap off it goes to vocabulary mode.
        local in_vocabulary = self.settings:readSetting("highlight_all_words_vocabulary_builder_and_notes")
        if self:isDoubleTapDisabled() and not in_vocabulary then
            self:enterVocabularyMode()
        else
            self:setDoubleTapDisabled(true)
            -- leaving the vocabulary mode is silent (the top bar mark changes); only the plain double tap on says it
            if not in_vocabulary then
                UIManager:show(Notification:new{ text = _("Double tap off") })
            end
        end
        return true
    elseif direction == "north" then
        -- The "go back" bubble is showing: this swipe only closes it (it does NOT go to the page).
        -- Without the bubble the swipe does what it did before.
        if self:_closeLocationBubble(false) then return true end
        if self.ui and self.ui.bookends and self.ui.bookends.enabled then
            -- local statistics = self.ui and self.ui.statistics
            -- if statistics and statistics.isEnabled and statistics:isEnabled() then
            --     pcall(statistics.insertDB, statistics)
            -- end
            -- local ok, Screen = pcall(require, "book_rewind/ui/screen")
            -- if not ok then
            --     require("logger").warn("Book Rewind: require failed", Screen)
            --     return true
            -- end
            -- local ok2, screen = pcall(Screen.new, Screen, {})
            -- if not ok2 then
            --     require("logger").warn("Book Rewind: could not open", screen)
            --     return true
            -- end
            -- -- Solo si hay tarjetas (si no hay datos, el modo es "empty" y cards es nil)
            -- if screen.mode == "cards" and screen.cards and #screen.cards > 0 then
            --     screen.index = math.min(8, #screen.cards)
            -- end
            -- UIManager:show(screen)
            -- return true
            return UIManager:sendEvent(Event:new("OpenPresetManager"))
        end
        -- Cycle the three top bar modes: full -> minimal (page + time left) -> hidden -> full ...
        self:cycleTopBarMode()
    elseif direction == "south" then

        if self.settings:isTrue("enable_ruler") and
            (Device:isEmulator() or Device.model == "Kobo_spaBW" or Device.model == "Kobo_goldfinch" or Device.model == "Kobo_spaColour" or Device.model == "KindlePaperWhite6") then
            local ruler_overlay = RulerOverlay:new()
            -- UIManager:show(ruler_overlay.ruler_widget)
            ruler_overlay.ruler_widget:paintTo(Screen.bb, 0, 0)
            UIManager:show(ruler_overlay)
        else
            -- UIManager:broadcastEvent(Event:new("ShowReadingInsightsPopup"))
            -- UIManager:broadcastEvent(Event:new("ShowReadingHistoryPopupTablePlusV1"))
            UIManager:broadcastEvent(Event:new("ShowReadingHoursDaily"))
        end
    elseif direction == "east" then
        -- The "go back" bubble of the reading-location patch is showing: this swipe closes it and takes you to the page
        -- it points to (what tapping the bubble does). Nothing else happens.
        -- Without the bubble the swipe does what it did before.
        if self:_closeLocationBubble(true) then return true end
        -- local doc_settings = DocSettings:open(doc_path)
        -- local reference_page = self.ui.doc_settings:readSetting("reference_page_xpointer")
        -- if not reference_page then
            -- local xp = self.ui.document:getXPointer()
            -- self.ui.doc_settings:saveSetting("reference_page_xpointer", xp)
            -- self.ui.doc_settings:flush()
        -- else
            --[[local pageno = self.ui.document:getPageFromXPointer(reference_page)
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
            })]]
        -- end
        -- UIManager:broadcastEvent(Event:new("BookshelfOpenMicroModules"))
        -- UIManager:broadcastEvent(Event:new("BookshelfOpenStartMenu"))
        UIManager:broadcastEvent(Event:new("ShowLongestSessions"))
        return
    end
    return false
end

-- "Picture" below = the configured one of the custombg list: a background, the bookshelf hero or the cover text
-- (custombg:isPictureOn / setPictureEnabled).
-- Same as the menu item "Enable / disable full-screen ruled lines" of the custombg plugin.
-- custombg keeps ALL its settings (lines and background) in its own file, settings/custombg.lua. They are global,
-- not per book: this toggle affects every book and nothing is written to the book sidecar.
function PageTextInfo:toggleFullScreenRuledLines()
    local util = require("util")
    local is_pdf = self.document and util.getFileNameSuffix(self.document.file) == "pdf"
    if is_pdf then return end
    if self.view.footer_visible then return end
    if self.view.topbar.settings:isTrue("show_top_bar")
    or (self.ui.bookends and self.ui.bookends.enabled) then
        self.view.topbar:quickToggleOnOff(true)
        -- local footer = self.ui.view.footer
        -- footer:applyFooterMode(footer.mode_list.off)
        -- self.ui.bookends.stock_bar_disabled = true
        -- self.ui.bookends.settings:saveSetting("stock_bar_disabled", true)
        -- self.view.footer_visible = false
        self.ui.bookends.enabled = not self.ui.bookends.enabled
        self.ui.bookends.settings:saveSetting("enabled", self.ui.bookends.enabled)
    else
        local custombg = self.ui and self.ui.custombg
        if not custombg then return false end
        -- With the custombg setting "Lines gesture also toggles the background" ON (default):
        --   cycle: lines only -> background only -> lines + background -> nothing -> lines only ...
        --   (from "nothing on" it goes to lines only)
        -- With it OFF: only the ruled lines are toggled, the background is left as it is.
        local lines_on = custombg.fs_enabled and true or false
        local bg_on = custombg:isPictureOn()
        local with_bg = (custombg.isToggleWithBackground == nil) or custombg:isToggleWithBackground()
        local want_lines, want_bg
        if not with_bg then
            want_lines, want_bg = not lines_on, bg_on          -- lines only, background untouched
        elseif lines_on and not bg_on then
            want_lines, want_bg = false, true      -- background only
        elseif bg_on and not lines_on then
            want_lines, want_bg = true, true       -- lines + picture
        elseif lines_on and bg_on then
            want_lines, want_bg = false, false     -- nothing
        else
            want_lines, want_bg = true, false      -- lines only
        end
        if want_lines ~= lines_on then
            if custombg.setLinesEnabled then
                custombg:setLinesEnabled(want_lines)
            else
                -- older custombg without setLinesEnabled()
                custombg.fs_enabled = want_lines
                custombg:saveDocSetting("fs_lines_enabled", want_lines)
            end
        end
        if want_bg ~= bg_on then
            local function applyBg()
                custombg:setPictureEnabled(want_bg)   -- the configured one: background, hero or cover text
            end
            -- applyBackground() repaints by itself (loadBackgroundByName -> toggleRepaint("all"))
            -- and the repaint of the reader below follows right after it: two repaints of the whole screen for ONE
            -- toggle, the first one with the background half applied. The inner one is muted here and the one below
            -- does the job for both.
            -- The override is an instance field that hides the class method; putting back what rawget returned
            -- (nil if there was none) restores the original lookup.
            local own_repaint = rawget(custombg, "toggleRepaint")
            custombg.toggleRepaint = function() end
            local ok, err = pcall(applyBg)
            custombg.toggleRepaint = own_repaint
            if not ok then error(err, 0) end
        end
        -- Repaint the reader itself so custombg:paintTo() runs again with the new value.
        -- setDirty(nil, ...) would only refresh the screen buffer as it is (the old state)
        if custombg.toggleRepaint then
            custombg:toggleRepaint(self.view.dialog)
            return
        end
        UIManager:setDirty(self.view.dialog, "ui")
    end
    return UIManager:setDirty(self.view.dialog, "ui")
end

-- Switches the custombg picture (background image, hero or cover text) on or off, without repainting
-- (the caller repaints once). Returns true if it changed.
function PageTextInfo:switchCustomBgPicture(on)
    local custombg = self.ui and self.ui.custombg
    if not (custombg and custombg.setPictureEnabled) then return false end
    if (not self:isCustomBgPictureOff(custombg)) == on then return false end
    -- setPictureEnabled repaints by itself; muted here
    local own_repaint = rawget(custombg, "toggleRepaint")
    custombg.toggleRepaint = function() end
    local ok, err = pcall(custombg.setPictureEnabled, custombg, on)
    custombg.toggleRepaint = own_repaint
    self._bg_cycle_stage = nil
    if not ok then
        logger.warn("pagetextinfo: switching the picture on / off failed:", err)
        return false
    end
    return true
end

-- Hides the custombg picture while something else uses the screen (bookends, the top bar out of "hidden"),
-- remembering in this plugin's settings (key) whether it was on, so it survives closing the book or KOReader.
-- Returns true if the picture changed.
function PageTextInfo:hidePictureFor(key)
    local custombg = self.ui and self.ui.custombg
    if not (custombg and custombg.setPictureEnabled) then return false end
    local was_on = not self:isCustomBgPictureOff(custombg)
    self.settings:saveSetting(key, was_on)
    self.settings:flush()
    return was_on and self:switchCustomBgPicture(false) or false
end

-- Puts the picture back if it was on when hidePictureFor(key) hid it. Returns true if the picture changed.
function PageTextInfo:restorePictureFor(key)
    if self.settings:readSetting(key) == nil then return false end
    local was_on = self.settings:isTrue(key)
    self.settings:delSetting(key)
    self.settings:flush()
    return was_on and self:switchCustomBgPicture(true) or false
end

-- One repaint: custombg's own (so its paintTo runs again) when the picture changed, a plain one otherwise.
function PageTextInfo:repaintAfterPictureChange(changed)
    local custombg = self.ui and self.ui.custombg
    if changed and custombg and custombg.toggleRepaint then
        custombg:toggleRepaint(self.view.dialog)
    else
        UIManager:setDirty(self.view.dialog, "ui")
    end
end

-- Bookends on / off. Turning bookends on also hides the custombg picture (background image, hero or cover text);
-- turning them off puts it back if it was on before ("picture_before_bookends" setting).
-- The ruled lines are not touched (double tap bottom left). The topbar is left as it is.
function PageTextInfo:toggleFullScreenRuledLinesNoTopbar()
    local util = require("util")
    local is_pdf = self.document and util.getFileNameSuffix(self.document.file) == "pdf"
    if is_pdf then return end
    if self.view.footer_visible then return end

    local bookends = self.ui and self.ui.bookends
    if not bookends then return false end
    bookends.enabled = not bookends.enabled
    if bookends.settings then bookends.settings:saveSetting("enabled", bookends.enabled) end

    local changed
    if bookends.enabled then
        changed = self:hidePictureFor("picture_before_bookends")
    else
        changed = self:restorePictureFor("picture_before_bookends")
    end
    self:repaintAfterPictureChange(changed)
    return true
end

-- Cycles between the "paperdots" plugin, the "custombg" background and the bookends bars:
--   bookends on: dots only -> background only -> dots + background
--   -> bookends OFF (dots and background stay as they are)
--   -> bookends ON again with dots and background OFF -> dots only -> ...
-- Without the bookends plugin the bookends steps are skipped: dots + background -> nothing -> dots only.
-- Works with the paperdots plugin as it is: the state is read from settings/paperdots.lua and changed with the plugin's own
-- "PaperDotsToggle" event. That event asks for a flashing full refresh, so setDirty is muted while it runs; the reader is
-- repainted once at the end of this function instead.
function PageTextInfo:toggleDotsAndBackground()
    local util = require("util")
    local is_pdf = self.document and util.getFileNameSuffix(self.document.file) == "pdf"
    local dots = self.ui and self.ui.paperdots
    local custombg = (not is_pdf) and self.ui and self.ui.custombg or nil
    local bookends = self.ui and self.ui.bookends
    if not dots and not custombg then return false end

    local function bookendsOn()
        return bookends ~= nil and bookends.enabled and true or false
    end
    local function setBookends(on)
        if not bookends or (bookends.enabled and true or false) == on then return end
        bookends.enabled = on
        if bookends.settings then bookends.settings:saveSetting("enabled", on) end
        -- The topbar is left as it is (active): only bookends is switched
    end

    local function dotsOn()
        if not dots then return false end
        if dots.isEnabled then return dots:isEnabled() end
        local DataStorage = require("datastorage")
        local LuaSettings = require("luasettings")
        local v = LuaSettings:open(DataStorage:getSettingsDir() .. "/paperdots.lua"):readSetting("enabled")
        return v ~= false
    end
    local function setDots(on)
        if not dots or dotsOn() == on then return end
        if dots.setEnabled then
            dots:setEnabled(on)
        else
            local Event = require("ui/event")
            local real_setDirty = UIManager.setDirty
            UIManager.setDirty = function() end
            local ok, err = pcall(self.ui.handleEvent, self.ui, Event:new("PaperDotsToggle"))
            UIManager.setDirty = real_setDirty
            if not ok then error(err, 0) end
        end
    end

    local dots_on = dotsOn()
    local bg_on = custombg ~= nil and custombg:isPictureOn()
    local bk_on = bookendsOn()
    local want_dots, want_bg, want_bk = dots_on, bg_on, bk_on
    if bookends and not bk_on then
        want_dots, want_bg, want_bk = false, false, true   -- bookends back ON, dots and background OFF
    elseif dots_on and not bg_on then
        want_dots, want_bg = false, true       -- background only
    elseif bg_on and not dots_on then
        want_dots, want_bg = true, true        -- dots + background
    elseif dots_on and bg_on then
        if bookends then
            want_bk = false                    -- bookends OFF, dots and background stay
        else
            want_dots, want_bg = false, false  -- nothing
        end
    else
        want_dots, want_bg = true, false       -- dots only
    end
    -- without custombg (or in a PDF) only the dots can change: just flip them
    if not custombg then want_dots, want_bg = not dots_on, false end
    -- without the dots plugin only the background can change
    if not dots then want_dots, want_bg = false, not bg_on end

    setDots(want_dots)
    setBookends(want_bk)

    if custombg and want_bg ~= bg_on then
        local function applyBg()
                custombg:setPictureEnabled(want_bg)   -- the configured one: background, hero or cover text
        end
        -- applyBackground() repaints by itself; mute it so there is ONE repaint for the whole toggle (see below)
        local own_repaint = rawget(custombg, "toggleRepaint")
        custombg.toggleRepaint = function() end
        local ok, err = pcall(applyBg)
        custombg.toggleRepaint = own_repaint
        if not ok then error(err, 0) end
    end

    -- Repaint the reader itself so the page is drawn again with the new state (the dots are added on refresh)
    if custombg and custombg.toggleRepaint then
        custombg:toggleRepaint(self.view.dialog)
        return true
    end
    UIManager:setDirty(self.view.dialog, "ui")
    return true
end

-- Gesture action: "Toggle dots / background" (Gestures -> General)
function PageTextInfo:onToggleDotsAndBackground()
    self:toggleDotsAndBackground()
    return true
end

-- Handle multiswipes: only "north east" is used, everything else is ignored
function PageTextInfo:onMultiSwipe(arg, ges)
    if ges and ges.multiswipe_directions == "north east" then
        -- Open the fonts menu (change this to whatever action you want)
        self:onShowFonts()
        return true
    end
    if ges and ges.multiswipe_directions == "south east" then
        -- Open the fonts menu (change this to whatever action you want)
        self:onShowSettingsMenu()
        return true
    end
    if ges and ges.multiswipe_directions == "east south" then
        -- Toggle the full-screen ruled lines of the custombg plugin
        self:toggleFullScreenRuledLinesNoTopbar()
        return true
    end
    if ges and ges.multiswipe_directions == "west north" then
        -- Bottom margin only, the same as the margin adjustment gives (picture, preset, narrow preset "hidden")
        self:onAdjustBottomMargin()
        return true
    end
    if ges and ges.multiswipe_directions == "north south" then
        -- Ruled lines of custombg on / off, the same as the double tap bottom left, but it does not need the
        -- double tap detection to be on
        self:onBottomDoubleTap("left", ges)
        return true
    end
    -- Not our gesture: let other handlers deal with it
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
    return true
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
    local _time = require("ui/time")
    local _t_init = _time.now()
    ExitTiming.setEnabled(G_reader_settings:isTrue("exittiming_enabled"))
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
    CrashLog.setEnabled(G_reader_settings:isTrue("crashlog_enabled"))
    MemoryOverlay.setEnabled(G_reader_settings:isTrue("memoryoverlay_enabled"))
    WidgetTimeOverlay.setEnabled(G_reader_settings:isTrue("widgettimeoverlay_enabled"))
    RefreshOverlay.setEnabled(G_reader_settings:isTrue("refreshoverlay_enabled"))
    -- The "×" of an overlay switches its flag off by itself: close KOReader's top menu
    -- if it is open (it would still show the old flag) and redraw the actions menu
    local function onOverlayClosed()
        pcall(function()
            self.ui:handleEvent(Event:new("CloseReaderMenu"))       -- reader
            self.ui:handleEvent(Event:new("CloseFileManagerMenu"))  -- file manager
        end)
        pcall(function()
            if self.actions_dialog and self.actions_dialog.updateActive then
                self.actions_dialog:updateActive()
            end
        end)
    end
    CrashLog.setOnClose(onOverlayClosed)
    MemoryOverlay.setOnClose(onOverlayClosed)
    WidgetTimeOverlay.setOnClose(onOverlayClosed)
    RefreshOverlay.setOnClose(onOverlayClosed)
    ExitTiming.setOnClose(onOverlayClosed)
    ExitTiming.record("PageTextInfo.init", _time.to_ms(_time.since(_t_init)))
end

-- function PageTextInfo:_postInit()
--     self.initialized = true
-- end

function PageTextInfo:isScaleByXHeight()
    -- default off (matches the committed behaviour); use nilOrTrue for default on
    return G_reader_settings:isTrue("pagetextinfo_scale_by_xheight")
end
function PageTextInfo:isCompensateRem()
    return G_reader_settings:isTrue("pagetextinfo_compensate_rem")
end
require("settings_menu")(PageTextInfo)
require("font_selection_menu")(PageTextInfo)
require("actions_menu")(PageTextInfo)
require("top_reading_sessions")(PageTextInfo)
require("highlight_translate_vocabulary_words")(PageTextInfo)

function PageTextInfo:readSettingsFile()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/pagetextinfo.lua")
end

function PageTextInfo:onReaderReady()
    PageTextInfo.closeReadingMotive()
    local _time = require("ui/time")
    local _t_ready = _time.now()
    if self.warmUpOnReady then self:warmUpOnReady() end
    ExitTiming.record("PageTextInfo.warmUpOnReady", _time.to_ms(_time.since(_t_ready)))
    ExitTiming.readerReady()
    -- self.ui.menu:registerToMainMenu(self)
    self.view:registerViewModule("pagetextinfo", self)
    self.initialized = true
    -- The bottom picture chosen in custombg (hero or cover text) is made now, before the first page is painted
    do
        local custombg = self.ui and self.ui.custombg
        local mode = custombg and custombg.getBottomMode and custombg:getBottomMode()
        if mode then pcall(self.buildBottomHero, self, mode) end
    end
    -- The bottom center tap is ours, also when bookends' own zone would be reached first
    self:takeOverBookendsFooterTap()
    -- Lets the top bar be fully hidden (third mode of cycleTopBarMode)
    pcall(self.installTopBarHiddenPaint, self)
    -- Top bar indicators computed again every time custombg repaints (picture changed with the tap, etc.)
    pcall(self.installCustomBgIndicatorRefresh, self)


    -- This is just for Android devices, at least the Boox Palma
    -- We have self.ui.gestures.ignore_hold_corners == true
    -- We exit from KOReader and for some reason KOReader is stopped or we stop it
    -- When we come back to KOReader and we open a document, the top bar lock icon is on
    -- because self.ui.gestures.ignore_hold_corners is still true so we set it always to be false when opening the document
    if Device:isAndroid() then
        self.ui.gestures:onIgnoreHoldCorners(false)
    end
    -- Every document opens with the double tap detection disabled (fast page turns).
    -- onCloseDocument() leaves it enabled again, so this is the only place that sets the default.
    self:setDoubleTapDisabled(true)
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

-- Margin adjustment (moved here from ReaderUI:onAdjustMarginsTopbar and TopBar:onAdjustMarginsTopbar)

-- Presets cycled through by the margin adjustment (tap top left), whatever bars are on.
-- Format: { left, top, right, bottom, xheight_mm = target font x-height } in configurable units (unscaled).
--   1 = minimal margins, 15 everywhere, font x-height 1.80 mm
--   2 = normal margins (35/50), font x-height 1.80 mm
--   3 = a little bit wider margins, keeping the ~sqrt(2) proportion (60/42 = 1.43, same as 50/35),
--       font x-height 1.80 mm
--   4 = big side margins (100) to get a narrow text column, top/bottom as preset 2 (50/50),
--       with a smaller font (x-height 1.35 mm). hidden_top_bottom: top and bottom used instead when the
--       top bar is in the "hidden" mode.
-- With a custombg picture at the bottom (image, hero, cover text) the bottom margin is the picture one.
-- The left and right margins are different in every preset: they are what tells which preset is on
-- (margins not matching any preset: the next tap goes to preset 1).
PageTextInfo.margin_presets = {
    { 15, 15, 15, 15, xheight_mm = 1.80 },
    { 35, 50, 35, 50, xheight_mm = 1.80 },
    { 42, 60, 42, 60, xheight_mm = 1.80 },
    { 100, 50, 100, 50, xheight_mm = 1.35, hidden_top_bottom = 15 },
}

-- Sends an event while hiding any notification toast it (or the handlers it triggers) may show,
-- e.g. the "font size set" message. Notifications are blocked until two UI ticks after the
-- event so that toasts queued with nextTick() are covered too.
local notifications_silenced = false
local function sendEventSilently(event)
    if notifications_silenced then
        UIManager:sendEvent(event)
        return
    end
    notifications_silenced = true
    local orig_notify = Notification.notify
    local orig_show = UIManager.show
    Notification.notify = function() end
    UIManager.show = function(self_, widget, ...)
        local mt = widget and getmetatable(widget)
        if mt and mt.__index == Notification then return end
        return orig_show(self_, widget, ...)
    end
    local ok, err = pcall(UIManager.sendEvent, UIManager, event)
    UIManager:nextTick(function()
        UIManager:nextTick(function()
            Notification.notify = orig_notify
            UIManager.show = orig_show
            notifications_silenced = false
        end)
    end)
    if not ok then logger.warn("pagetextinfo: sendEventSilently failed:", err) end
end

-- Bottom margin while custombg shows a picture (configurable units, unscaled):
--   hero / cover text: the real height of the picture + picture_bottom_air, so the text ends just above it
--   background image: picture_bottom_margin
PageTextInfo.picture_bottom_margin = 60
PageTextInfo.picture_bottom_air = 4

-- Smallest bottom margin (unscaled units) whose text area ends at least px pixels above the screen bottom.
-- ReaderTypeset:onSetPageMargins uses Screen:scaleBySize(margin) (rounded up).
-- The footer is not taken into account: the margin depends only on the picture.
-- Before, the footer height was subtracted when the footer did not overlap the text ("Overlap status bar" off):
-- local footer = self.view and self.view.footer
-- if footer and not footer.reclaim_height and footer.getHeight then
--     px = px - (footer:getHeight() or 0)
-- end
function PageTextInfo:pxToBottomMargin(px)
    if px <= 0 then return 0 end
    local per100 = Screen:scaleBySize(100)
    local u = math.max(0, math.floor(px * 100 / per100) - 2)
    while Screen:scaleBySize(u) < px do u = u + 1 end
    while u > 0 and Screen:scaleBySize(u - 1) >= px do u = u - 1 end
    return u
end

-- Bottom margin to use with the current custombg picture, or nil when there is no picture.
function PageTextInfo:getPictureBottomMargin()
    local custombg = self.ui and self.ui.custombg
    if not custombg then return nil end
    if self:isCustomBgPictureOff(custombg) then return nil end   -- switched off: nothing at the bottom
    if custombg.getBottomMode then
        local ok, mode = pcall(custombg.getBottomMode, custombg)
        if ok and mode ~= nil then
            if not self.bottom_picture_px then pcall(self.buildBottomHero, self, mode) end
            if self.bottom_picture_px then
                return self:pxToBottomMargin(self.bottom_picture_px) + PageTextInfo.picture_bottom_air
            end
            return PageTextInfo.picture_bottom_margin
        end
    end
    if custombg.getCurrentDocBg then
        local ok, bg = pcall(custombg.getCurrentDocBg, custombg)
        if ok and bg ~= nil then return PageTextInfo.picture_bottom_margin end
    end
    return nil
end

function PageTextInfo:keepBottomMargin()
    return self:getPictureBottomMargin() ~= nil
end

-- Index of the preset matching the current margins, or nil if none does.
-- Only left and right are compared (they are different in every preset): top and bottom can change
-- (custombg picture, "hidden" top bar, west-north multiswipe) and the preset must still be recognized.
function PageTextInfo:getCurrentPresetIndex()
    local cfg = self.ui.document.configurable
    local h = cfg.h_page_margins
    if not h then return nil end
    for i, p in ipairs(PageTextInfo.margin_presets) do
        if h[1] == p[1] and h[2] == p[3] then
            return i
        end
    end
end

-- Applies { left, top, right, bottom }. Returns true if anything changed.
-- With a custombg picture the bottom margin is getPictureBottomMargin(), whatever t says.
function PageTextInfo:applyMargins(t)
    local cfg = self.ui.document.configurable
    local left, top, right, bottom = t[1], t[2], t[3], t[4]
    local picture_bottom = self:getPictureBottomMargin()
    if picture_bottom then bottom = picture_bottom end
    local h = cfg.h_page_margins
    if cfg.t_page_margin == top and cfg.b_page_margin == bottom
        and h and h[1] == left and h[2] == right then
        return false
    end
    local side_margins = { left, right }
    cfg.t_page_margin = top
    cfg.b_page_margin = bottom
    cfg.h_page_margins = side_margins
    UIManager:sendEvent(Event:new("SetPageHorizMargins", side_margins))
    -- top and bottom together: sent one by one, "Sync T/B margins" would make them equal
    local typeset = self.ui.typeset
    if typeset and typeset.onSetPageTopAndBottomMargin then
        UIManager:sendEvent(Event:new("SetPageTopAndBottomMargin", { top, bottom }))
    else
        UIManager:sendEvent(Event:new("SetPageTopMargin", top))
        UIManager:sendEvent(Event:new("SetPageBottomMargin", bottom))
    end
    return true
end

-- Current effective x-height of the book font, in mm (nil if it cannot be measured).
-- Uses the plugin's own getXHeightMm() when available (the one shown in the top bar and
-- the settings menu); otherwise it measures the font face the same way the top bar does.
function PageTextInfo:getCurrentXHeightMm()
    if self.getXHeightMm then
        local mm = self:getXHeightMm()
        if mm and mm > 0 then return mm end
    end
    local ui = self.ui
    local dpi = Device:getDeviceScreenDPI() or Screen:getDPI()
    local size_pt = ui.document.configurable.font_size
    local size_px = math.floor(dpi * size_pt / 72 + 0.5)
    local face_name = (self.getFaceName and self:getFaceName())
        or (ui.document._document:getFontFace():gsub("%s+", "") .. "-Regular")
    local face = Font:getFace(face_name, size_px, 0, true)
    if not face then return nil end
    local xh = face.ftsize:getXHeight()
    local xh_px = (xh < 1) and (xh * size_px) or xh
    return xh_px * 25.4 / dpi
end

-- Sets the font size so that the x-height gets target_mm. The x-height is linear in the
-- font size, so a single rule of three is enough (rounded to 0.1 pt). Nothing is done if the
-- x-height is already within 0.02 mm of the target. No message is shown.
function PageTextInfo:setXHeightFont(target_mm)
    if not target_mm then return end
    local cfg = self.ui.document.configurable
    local current_mm = self:getCurrentXHeightMm()
    if not current_mm or current_mm <= 0 then return end
    if math.abs(current_mm - target_mm) < 0.02 then return end
    local new_size = math.floor(cfg.font_size * target_mm / current_mm * 10 + 0.5) / 10
    if new_size == cfg.font_size then return end
    sendEventSilently(Event:new("SetFontSize", new_size))
end

-- Same event name as before, so gestures/dispatcher actions keep working.
-- Tap top left: always the next preset (1 -> 2 -> 3 -> 4 -> 1), with its font x-height; its number is shown big
-- over the page for a moment. Top bar and footer are not looked at. Preset 4 (narrow column) with the top bar
-- "hidden": top and bottom 15. A custombg picture at the bottom sets the
-- bottom margin (applyMargins).
function PageTextInfo:onAdjustMarginsTopbar()
    if not self.ui.rolling then return end
    local presets = PageTextInfo.margin_presets
    local idx = self:getCurrentPresetIndex()
    local next_idx = idx and (idx % #presets) + 1 or 1
    local p = presets[next_idx]
    local t = { p[1], p[2], p[3], p[4] }
    if p.hidden_top_bottom and self.view and self.view.topbar and self:getTopBarMode() == "hidden" then
        t[2], t[4] = p.hidden_top_bottom, p.hidden_top_bottom
    end
    self:applyMargins(t)
    self:setXHeightFont(p.xheight_mm)
    -- the number of the preset big over the page, same style and fade as the frontlight "Off" (showSessionOverlay)
    self:showSessionOverlay({ tostring(next_idx) })
    return true
end

-- West-north multiswipe, only the bottom margin, the same one the margin adjustment (tap top left) gives:
--   custombg picture on (image, hero, cover text) -> margin for the picture
--   top bar "hidden" and a preset with hidden_top_bottom (preset 4, narrow column) -> that value
--   otherwise -> bottom of the current preset
-- Left, top and right stay as they are; the preset and the font are not changed.
function PageTextInfo:onAdjustBottomMargin()
    local ui = self.ui
    if not ui.rolling then return true end
    local bottom = self:getPictureBottomMargin()
    if not bottom then
        -- the preset is recognized by its left and right margins
        local p = PageTextInfo.margin_presets[self:getCurrentPresetIndex() or 1]
        bottom = p[4]
        if p.hidden_top_bottom and self.view and self.view.topbar and self:getTopBarMode() == "hidden" then
            bottom = p.hidden_top_bottom
        end
    end

    local cfg = ui.document.configurable
    if cfg.b_page_margin == bottom then return true end
    local top = cfg.t_page_margin
    cfg.b_page_margin = bottom
    -- top and bottom together: sent alone, "Sync T/B margins" would also change the top one
    local typeset = ui.typeset
    if typeset and typeset.onSetPageTopAndBottomMargin and top ~= nil then
        UIManager:sendEvent(Event:new("SetPageTopAndBottomMargin", { top, bottom }))
    else
        UIManager:sendEvent(Event:new("SetPageBottomMargin", bottom))
    end
    return true
end

-- Switch the widget time overlay on/off from the menu entry (same flag the "×" of the overlay switches off)

function PageTextInfo:onPageUpdate(pageno)
    -- Avoid double execution when loading document
    if not self.initialized then return end

    -- the bottom picture (if chosen in custombg) is built again so its progress and time left advance with the page
    local custombg = self.ui and self.ui.custombg
    local bottom_mode = custombg and custombg.getBottomMode and custombg:getBottomMode()
    if bottom_mode then
        self:buildBottomHero(bottom_mode, { page_turn = true })
    end

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
-- MONKEY PATCHES -----------------------------------------------------------------------------
-- A function is "original" when it is defined in the file where KOReader defines it. If it is
-- defined anywhere else (a plugin, a user patch, a wrapper made at run time...) somebody replaced
-- it. The chain of wrappers is followed through the upvalues they keep to call the previous one
-- (orig, orig_show, raw, old...). Patches made inside the original file itself cannot be seen.
local function wrappedFunction(f)
    local i = 1
    while true do
        local name, value = debug.getupvalue(f, i)
        if not name then return nil end
        if type(value) == "function" then
            local n = name:lower()
            if n:find("orig", 1, true) or n:find("^raw") or n:find("^old") or n:find("^prev") then
                return value
            end
        end
        i = i + 1
    end
end

local function shortSource(info)
    if info.what == "C" then return "C function" end
    local src = info.short_src or "?"
    src = src:match("([^/]+/[^/]+)$") or src
    return src .. ":" .. (info.linedefined or 0)
end

local function isExpected(info, expected)
    if expected == "C" then return info.what == "C" end
    if info.what == "C" then return false end
    local src = info.short_src or ""
    if type(expected) == "string" then expected = { expected } end
    for _, e in ipairs(expected) do
        if src:find(e, 1, true) then return true end
    end
    return false
end

-- Returns the list of wrappers found over the original (empty = not patched) and
-- whether the original was reached at the end of the chain
local function inspectFunction(f, expected)
    local chain, seen, cur = {}, {}, f
    for _ = 1, 8 do
        if type(cur) ~= "function" or seen[cur] then break end
        seen[cur] = true
        local info = debug.getinfo(cur, "S")
        if not info then break end
        if isExpected(info, expected) then return chain, true end
        chain[#chain + 1] = shortSource(info)
        if info.what == "C" then break end
        cur = wrappedFunction(cur)
    end
    return chain, false
end

function PageTextInfo:showMonkeyPatches()
    local targets = {}
    local function add(label, getter, expected)
        targets[#targets + 1] = { label = label, getter = getter, expected = expected }
    end
    local function loaded(modname, name)
        return function()
            local m = package.loaded[modname]
            return type(m) == "table" and m[name] or nil
        end
    end

    for _, name in ipairs({ "show", "close", "setDirty", "_repaint", "_refresh", "sendEvent",
                            "broadcastEvent", "nextTick", "tickAfterNext", "scheduleIn", "unschedule",
                            "getTopmostVisibleWidget", "_checkTasks", "handleInput" }) do
        add("UIManager:" .. name, function() return UIManager[name] end, "ui/uimanager.lua")
    end
    add("Widget:new", loaded("ui/widget/widget", "new"), "ui/widget/")
    add("Notification:notify", function() return Notification.notify end, "ui/widget/notification.lua")
    add("FileManager:setupLayout", function() return FileManager.setupLayout end, "apps/filemanager/filemanager.lua")
    add("FileManager:updateTitleBarPath", function() return FileManager.updateTitleBarPath end, "apps/filemanager/filemanager.lua")
    add("FileChooser:init", function() return FileChooser.init end, "ui/widget/filechooser.lua")
    add("Menu:init", loaded("ui/widget/menu", "init"), "ui/widget/menu.lua")
    add("ReaderUI:init", loaded("apps/reader/readerui", "init"), "apps/reader/readerui.lua")
    add("ReaderView:paintTo", loaded("apps/reader/modules/readerview", "paintTo"), "apps/reader/modules/readerview.lua")
    for _, name in ipairs({ "refresh", "refreshFullImp", "refreshPartialImp", "refreshUIImp", "refreshFlashUIImp",
                            "refreshFlashPartialImp", "refreshFastImp", "refreshA2Imp" }) do
        add("Screen:" .. name, function() return Screen[name] end, { "framebuffer", "device/screen" })
    end
    add("require", function() return require end, "C")
    add("dofile", function() return dofile end, "C")
    add("io.popen", function() return io.popen end, "C")
    add("os.execute", function() return os.execute end, "C")

    local patched, clean, missing = {}, {}, 0
    for __, t in ipairs(targets) do
        local ok, f = pcall(t.getter)
        if not ok or type(f) ~= "function" then
            missing = missing + 1
        else
            local chain, reached = inspectFunction(f, t.expected)
            if #chain == 0 then
                clean[#clean + 1] = t.label
            else
                -- from the outermost wrapper down to the original (or "?" if the chain was lost)
                patched[#patched + 1] = "• " .. t.label .. "\n    " .. table.concat(chain, "\n    → ")
                    .. "\n    → " .. (reached and _("original") or "?")
            end
        end
    end

    local lines = {
        T(_("%1 of %2 functions patched"), #patched, #patched + #clean),
        "",
    }
    if #patched > 0 then
        table.insert(lines, table.concat(patched, "\n"))
        table.insert(lines, "")
    end
    table.insert(lines, T(_("Not patched (%1): %2"), #clean, table.concat(clean, ", ")))
    if missing > 0 then
        table.insert(lines, "")
        table.insert(lines, T(_("Not found or not loaded: %1"), missing))
    end
    UIManager:show(TextViewer:new{
        title = _("Monkey patches"),
        text = table.concat(lines, "\n"),
        justified = false,
    })
end

-- ===== Dogear icon picker =====
-- Returns the sub menu with every dogear-*.png / dogear-*.svg found in <koreader>/resources/icons and
-- <koreader>/icons. Picking one stores its file name in G_reader_settings "custom_dogear_icon" and rebuilds the live dogear
-- (the custom dogear patch, 2-custom-dogear.lua, provides ReaderDogear:reloadCustomIcon()).
function PageTextInfo:getDogearIconMenu()
    local lfs = require("libs/libkoreader-lfs")
    local base = DataStorage:getDataDir()
    local found, seen = {}, {}
    for __, dir in ipairs({ base .. "/resources/icons", base .. "/icons" }) do
        local ok, iter, dir_obj = pcall(lfs.dir, dir)
        if ok and iter then
            for entry in iter, dir_obj do
                local lower = entry:lower()
                if not seen[entry] and (lower:match("^dogear%-.*%.png$") or lower:match("^dogear%-.*%.svg$")) then
                    seen[entry] = true
                    table.insert(found, entry)
                end
            end
        end
    end
    table.sort(found, function(a, b) return a:lower() < b:lower() end)

    local function current()
        return G_reader_settings:readSetting("custom_dogear_icon")
    end
    local function choose(value, touchmenu_instance)
        G_reader_settings:saveSetting("custom_dogear_icon", value)
        G_reader_settings:flush()
        local dogear = self.ui and self.ui.view and self.ui.view.dogear
        if dogear and dogear.reloadCustomIcon then
            pcall(dogear.reloadCustomIcon, dogear)
        end
        if touchmenu_instance then touchmenu_instance:updateItems() end
        UIManager:setDirty("all", "ui")
    end

    local items = {}
    for __, name in ipairs(found) do
        table.insert(items, {
            text = name,
            checked_func = function()
                local sel = current()
                return sel == name or (sel == nil and name == "dogear-custom.png")
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance) choose(name, touchmenu_instance) end,
        })
    end
    if #items == 0 then
        table.insert(items, {
            text = _("No dogear-*.png found in koreader/resources/icons"),
            enabled = false,
        })
    end
    table.insert(items, {
        text = _("KOReader default dogear"),
        checked_func = function() return current() == "@stock" end,
        keep_menu_open = true,
        callback = function(touchmenu_instance) choose("@stock", touchmenu_instance) end,
    })
    return items
end

-- ===== Note mark icon picker =====
-- Icon drawn by this plugin over words that have a note (drawXPointerSavedHighlightNotes).
-- Stored in G_reader_settings "highlight_note_mark_text" / "highlight_note_mark_size".
-- nil or "@stock" = the plugin's own default icon.
function PageTextInfo:getNoteMarkMenu()
    local DEFAULT_SIZE = 14
    local signs = {
        { "\u{F040}", _("Pencil") },
        { "\u{F02E}", _("Bookmark") },
        { "\u{F075}", _("Speech bubble") },
        { "\u{F005}", _("Star") },
        { "✎", "✎" }, { "✍", "✍" }, { "※", "※" }, { "¶", "¶" },
        { "†", "†" }, { "★", "★" }, { "◆", "◆" }, { "•", "•" }, { "*", "*" },
    }

    local function current()
        return G_reader_settings:readSetting("highlight_note_mark_text")
    end
    local function currentSize()
        return G_reader_settings:readSetting("highlight_note_mark_size") or DEFAULT_SIZE
    end
    -- Repaint the page so the change shows at once.
    local function refresh(touchmenu_instance)
        G_reader_settings:flush()
        if touchmenu_instance then touchmenu_instance:updateItems() end
        UIManager:setDirty("all", "ui")
    end
    local function choose(value, touchmenu_instance)
        G_reader_settings:saveSetting("highlight_note_mark_text", value)
        refresh(touchmenu_instance)
    end

    local items = {
        {
            text = _("Default icon"),
            checked_func = function() local sel = current(); return sel == nil or sel == "@stock" end,
            keep_menu_open = true,
            separator = true,
            callback = function(touchmenu_instance) choose("@stock", touchmenu_instance) end,
        },
    }
    local known = {}
    for __, s in ipairs(signs) do
        local sign, label = s[1], s[2]
        known[sign] = true
        table.insert(items, {
            text = sign == label and sign or (sign .. "  " .. label),
            checked_func = function()
                local sel = current()
                return sel == sign
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance) choose(sign, touchmenu_instance) end,
        })
    end
    table.insert(items, {
        text_func = function()
            local sel = current()
            if sel and sel ~= "@stock" and not known[sel] then
                return T(_("Custom: %1"), sel)
            end
            return _("Custom…")
        end,
        checked_func = function()
            local sel = current()
            return sel ~= nil and sel ~= "@stock" and not known[sel]
        end,
        keep_menu_open = true,
        separator = true,
        callback = function(touchmenu_instance)
            local InputDialog = require("ui/widget/inputdialog")
            local dialog
            dialog = InputDialog:new{
                title = _("Note mark: any character or short text"),
                input = (current() ~= "@stock" and current()) or "",
                buttons = {{
                    {
                        text = _("Cancel"),
                        id = "close",
                        callback = function() UIManager:close(dialog) end,
                    },
                    {
                        text = _("Save"),
                        is_enter_default = true,
                        callback = function()
                            local value = dialog:getInputText()
                            UIManager:close(dialog)
                            if value and value:match("%S") then
                                choose(value, touchmenu_instance)
                            end
                        end,
                    },
                }},
            }
            UIManager:show(dialog)
            dialog:onShowKeyboard()
        end,
    })
    local size_items = {}
    for __, size in ipairs({ 10, 12, 14, 16, 18, 20, 24, 28 }) do
        table.insert(size_items, {
            text = size == DEFAULT_SIZE and T(_("%1 (default)"), size) or tostring(size),
            checked_func = function() return currentSize() == size end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                G_reader_settings:saveSetting("highlight_note_mark_size", size)
                refresh(touchmenu_instance)
            end,
        })
    end
    table.insert(items, {
        text_func = function() return T(_("Size: %1"), currentSize()) end,
        sub_item_table = size_items,
    })
    return items
end

function PageTextInfo:addToMainMenu(menu_items)
    -- If we don't want this being called for the filemanager, better to call self.ui.menu:registerToMainMenu(self) in the onReaderReady() event handler function
    -- Although we can set in the init() function and skip it like this:
    local FileManager = require("apps/filemanager/filemanager")
    local plugin = self
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
                        if self.settings:isTrue("enable_no_bar_menu") then
                            _original_setupLayout = nil
                            _original_filechooser_init = nil
                            plugin:_hookSetupLayout()
                        end
                        -- local ok, err = pcall(dofile, "plugins/pagetextinfo.koplugin/patch.lua")
                        --FileManager.instance:setupLayout()
                        --FileManager.instance:updateTitleBarTitle(true)
                        self.settings:flush()
                        --FileManager:onClose() -- No need to close. The instance will be closed whe calling the showFiles() function
                        local path = FileManager.instance.file_chooser.path
                        if path:match("✪ Collections") then
                            path = G_reader_settings:readSetting("home_dir")
                        end
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
                  text = _("No bar menu"),
                    checked_func = function() return self.settings:isTrue("enable_no_bar_menu") end,
                    enabled_func = function()
                        local tb = G_reader_settings:readSetting("shortcutstoolbar_fb")
                        return tb == nil or tb.enabled == true
                    end,
                    callback = function(touchmenu_instance)
                        local enable_no_bar_menu = not self.settings:isTrue("enable_no_bar_menu")
                        self.settings:saveSetting("enable_no_bar_menu", enable_no_bar_menu)
                        self.settings:flush()
                        if enable_no_bar_menu then
                            plugin:_hookSetupLayout()
                        else
                            plugin:_unhookSetupLayout()
                        end
                        local path = FileManager.instance.file_chooser.path
                        if path:match("✪ Collections") then
                            path = G_reader_settings:readSetting("home_dir")
                        end
                        touchmenu_instance:closeMenu()
                        local cur_page = FileManager.instance.file_chooser.page
                        FileManager:showFiles(path)  -- esto llama setupLayout ya sin hook
                        FileManager.instance.file_chooser:onGotoPage(cur_page)
                        return true
                    end,
                },
                {
                  text = _("No pager"),
                    checked_func = function() return self.settings:isTrue("enable_no_pager") end,
                    callback = function(touchmenu_instance)
                        local enable_no_pager = not self.settings:isTrue("enable_no_pager")
                        self.settings:saveSetting("enable_no_pager", enable_no_pager)
                        self.settings:flush()
                        local path = FileManager.instance.file_chooser.path
                        if path:match("✪ Collections") then
                            path = G_reader_settings:readSetting("home_dir")
                        end
                        touchmenu_instance:closeMenu()
                        local cur_page = FileManager.instance.file_chooser.page
                        FileManager:showFiles(path)  -- esto llama setupLayout ya sin hook
                        FileManager.instance.file_chooser:onGotoPage(cur_page)
                        return true
                    end,
                },
                {
                    text_func = function()
                        local cur = self:getOverlayColor()
                        for _i, c in ipairs(PageTextInfo.session_overlay_colors) do
                            if c[2] == cur then return T(_("Big texts color: %1"), c[1]) end
                        end
                        return _("Big texts color")
                    end,
                    help_text = _([[Color of the big texts over the page (frontlight "Off", margin preset, background of the bottom tap, clock / session time / wpm). The fade out goes from this color to a light grey.]]),
                    sub_item_table_func = function()
                        local items = {}
                        for _i, c in ipairs(PageTextInfo.session_overlay_colors) do
                            items[#items + 1] = {
                                text = c[1],
                                radio = true,
                                checked_func = function() return self:getOverlayColor() == c[2] end,
                                callback = function()
                                    self.settings:saveSetting("overlay_color", c[2])
                                    self.settings:flush()
                                    self:showSessionOverlay({ c[1] }) -- preview
                                end,
                            }
                        end
                        return items
                    end,
                },
                {
                    text_func = function()
                        return T(_("Big texts duration: %1 s"), self:getOverlayHold())
                    end,
                    help_text = _([[Seconds the big texts over the page (frontlight "Off", profiles / margin preset, double tap on/off, clock / session time / wpm) stay fully visible before the fade out starts (or before they go away, if the fade out is unchecked).]]),
                    sub_item_table_func = function()
                        local items = {}
                        for _i, h in ipairs(PageTextInfo.session_overlay_holds) do
                            items[#items + 1] = {
                                text = T(_("%1 s"), h) .. (h == PageTextInfo.session_overlay_cfg.hold and " (" .. _("default") .. ")" or ""),
                                radio = true,
                                checked_func = function() return self:getOverlayHold() == h end,
                                callback = function()
                                    self.settings:saveSetting("overlay_hold", h)
                                    self.settings:flush()
                                    self:showSessionOverlay({ T(_("%1 s"), h) }) -- preview
                                end,
                            }
                        end
                        return items
                    end,
                },
                {
                    text = _("Diagnostic timing"),
                    checked_func = function() return G_reader_settings:isTrue("diagtiming_enabled") end,
                    help_text = _([[Log (as warnings) any require(), scheduled callback, event dispatch or screen refresh slower than 15 ms.]]),
                    callback = function()
                        local enable = not G_reader_settings:isTrue("diagtiming_enabled")
                        G_reader_settings:saveSetting("diagtiming_enabled", enable)
                        G_reader_settings:flush()
                        local Event = require("ui/event")
                        UIManager:broadcastEvent(Event:new("DiagTimingToggled", enable))
                        return true
                    end,
                },
                {
                    text = _("Crash log overlay"),
                    checked_func = function() return G_reader_settings:isTrue("crashlog_enabled") end,
                    help_text = _([[Show the last lines of crash.log, updated live, on every screen.]]),
                    callback = function()
                        local enable = not G_reader_settings:isTrue("crashlog_enabled")
                        G_reader_settings:saveSetting("crashlog_enabled", enable)
                        G_reader_settings:flush()
                        local Event = require("ui/event")
                        UIManager:broadcastEvent(Event:new("CrashLogToggled", enable))
                        return true
                    end,
                },
                -- Menu entry
                {
                    text = _("Memory overlay"),
                    checked_func = function() return G_reader_settings:isTrue("memoryoverlay_enabled") end,
                    help_text = _([[Show the memory of KOReader (Lua heap, resident memory, free memory), updated live, on every screen.]]),
                    callback = function()
                        local enable = not G_reader_settings:isTrue("memoryoverlay_enabled")
                        G_reader_settings:saveSetting("memoryoverlay_enabled", enable)
                        G_reader_settings:flush()
                        local Event = require("ui/event")
                        UIManager:broadcastEvent(Event:new("MemoryOverlayToggled", enable))
                        return true
                    end,
                },
                {
                    text = _("Widget time overlay"),
                    checked_func = function() return G_reader_settings:isTrue("widgettimeoverlay_enabled") end,
                    help_text = _([[Show how long each widget takes to be created (name and ms), live, in a scrollable window on every screen. Nothing is measured while it is off.]]),
                    callback = function()
                        local enable = not G_reader_settings:isTrue("widgettimeoverlay_enabled")
                        G_reader_settings:saveSetting("widgettimeoverlay_enabled", enable)
                        G_reader_settings:flush()
                        local Event = require("ui/event")
                        UIManager:broadcastEvent(Event:new("WidgetTimeOverlayToggled", enable))
                        return true
                    end,
                },
                {
                    text = _("Refresh overlay"),
                    checked_func = function() return G_reader_settings:isTrue("refreshoverlay_enabled") end,
                    help_text = _([[Show the screen refreshes of UIManager (setDirty calls and the refreshes really sent, with mode, region and caller), live, in a scrollable window on every screen. Needs the refresh_logger hook in uimanager.lua. Nothing is hooked while it is off.]]),
                    callback = function()
                        local enable = not G_reader_settings:isTrue("refreshoverlay_enabled")
                        G_reader_settings:saveSetting("refreshoverlay_enabled", enable)
                        G_reader_settings:flush()
                        local Event = require("ui/event")
                        UIManager:broadcastEvent(Event:new("RefreshOverlayToggled", enable))
                        return true
                    end,
                },
                {
                    text = _("Exit timing"),
                    checked_func = function() return G_reader_settings:isTrue("exittiming_enabled") end,
                    help_text = _([[Print (stdout) where the time goes when a book is opened or closed and the file manager is built again: plugin init, reader close and file manager creation. Nothing is hooked while it is off.]]),
                    callback = function()
                        local enable = not G_reader_settings:isTrue("exittiming_enabled")
                        G_reader_settings:saveSetting("exittiming_enabled", enable)
                        G_reader_settings:flush()
                        local Event = require("ui/event")
                        UIManager:broadcastEvent(Event:new("ExitTimingToggled", enable))
                        return true
                    end,
                },
                {
                    text = _("Monkey patches"),
                    help_text = _([[Check the most important functions (UIManager, Widget, FileManager, Screen refreshes, require...) and show which ones have been replaced by something other than the original KOReader source, with the file and line of every wrapper.]]),
                    callback = function(touchmenu_instance)
                        if touchmenu_instance and touchmenu_instance.closeMenu then touchmenu_instance:closeMenu() end
                        self:showMonkeyPatches()
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
                    text = _("Enable extra tweaks list menu view"),
                    checked_func = function() return self.settings:isTrue("enable_extra_tweaks_list_menu_view") end,
                    help_text = _([[Extra tweaks list menu view.]]),
                    callback = function(touchmenu_instance)
                        local enable_extra_tweaks_list_menu_view = not self.settings:isTrue("enable_extra_tweaks_list_menu_view")
                        self.settings:saveSetting("enable_extra_tweaks_list_menu_view", enable_extra_tweaks_list_menu_view)
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
                {
                    text = _("Draw borders on mosaic cover overlays"),
                    checked_func = function() return self.settings:isTrue("draw_borders_mosaic_overlays") end,
                    help_text = _([[Draw borders on mosaic cover overlays.]]),
                    callback = function()
                        local draw_borders_mosaic_overlays = not self.settings:isTrue("draw_borders_mosaic_overlays")
                        self.settings:saveSetting("draw_borders_mosaic_overlays", draw_borders_mosaic_overlays)
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
                    text = _("Invert covers stack"),
                    checked_func = function() return self.settings:isTrue("invert_covers_stack") end,
                    help_text = _([[Invert covers stack.]]),
                    callback = function()
                        local invert_covers_stack = not self.settings:isTrue("invert_covers_stack")
                        self.settings:saveSetting("invert_covers_stack", invert_covers_stack)
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
                    text = _("Custom covers for collections"),
                    checked_func = function() return self.settings:isTrue("custom_covers_collections") end,
                    help_text = _([[Custom covers for collections.]]),
                    callback = function()
                        local custom_covers_collections = not self.settings:isTrue("custom_covers_collections")
                        self.settings:saveSetting("custom_covers_collections", custom_covers_collections)
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
                    -- Lists every dogear-*.png / .svg found in resources/icons and icons (rescanned each time the menu opens).
                    -- The choice is stored in G_reader_settings "custom_dogear_icon" and read by the custom dogear patch.
                    text_func = function()
                        local sel = G_reader_settings:readSetting("custom_dogear_icon")
                        if sel == "@stock" then return _("Dogear icon") .. ": " .. _("KOReader default") end
                        return _("Dogear icon") .. ": " .. (sel or "dogear-custom.png")
                    end,
                    sub_item_table_func = function() return self:getDogearIconMenu() end,
                },
                {
                    -- 100 % = the size the custom dogear patch uses by default (4x the stock dogear).
                    -- Stored in G_reader_settings "custom_dogear_size_pct", read by the custom dogear patch.
                    text_func = function()
                        return _("Dogear size") .. ": " .. (G_reader_settings:readSetting("custom_dogear_size_pct") or 100) .. "%"
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        local SpinWidget = require("ui/widget/spinwidget")
                        UIManager:show(SpinWidget:new{
                            title_text = _("Dogear size (% of the default size)"),
                            value = G_reader_settings:readSetting("custom_dogear_size_pct") or 100,
                            value_min = 20,
                            value_max = 300,
                            value_step = 5,
                            value_hold_step = 25,
                            default_value = 100,
                            unit = "%",
                            callback = function(spin)
                                G_reader_settings:saveSetting("custom_dogear_size_pct", spin.value)
                                G_reader_settings:flush()
                                local dogear = self.ui and self.ui.view and self.ui.view.dogear
                                if dogear and dogear.reloadCustomIcon then
                                    pcall(dogear.reloadCustomIcon, dogear)
                                end
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                                UIManager:setDirty("all", "ui")
                            end,
                        })
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
                -- {
                --     text = _("Scale font by x-height"),
                --     checked_func = function() return self:isScaleByXHeight() end,
                --     help_text = _([[Keep the same x-height (mm) when changing font face, and show mm-based font presets. When off, presets are fixed point sizes.]]),
                --     callback = function()
                --         -- Remember the active font preset in the current mode (before the change)
                --         local preset = self:getActivePreset()
                --         G_reader_settings:saveSetting("pagetextinfo_scale_by_xheight", not self:isScaleByXHeight())
                --         G_reader_settings:flush()
                --         -- Re-select the same preset in the new mode
                --         self:applyPreset(preset)
                --         return true
                --     end,
                -- },
                -- {
                --     text = _("Compensate book rem/em"),
                --     checked_func = function()
                --         return self:hasRemStyles() and (self:isScaleByXHeight() or self:isCompensateRem())
                --     end,
                --     help_text = _([[Divide the small and big font presets by the book's font-size factor (rem/em/%) so the effective size matches. Always on when "Scale font by x-height" is on. Disabled when the book has no rem/em styles.]]),
                --     enabled_func = function()
                --         return not self:isScaleByXHeight() and self:hasRemStyles()
                --     end,
                --     callback = function()
                --         G_reader_settings:saveSetting("pagetextinfo_compensate_rem", not self:isCompensateRem())
                --         G_reader_settings:flush()
                --         -- Re-apply the current effective size so the new mode takes effect
                --         -- immediately (re-renders without losing the reading position).
                --         self:reapplyFontCompensation(self:isCompensateRem())
                --         return true
                --     end,
                -- },
                {
                    text = _("Fade out big texts"),
                    checked_func = function() return not self.settings:isTrue("no_overlay_fade") end,
                    help_text = _([[The big texts over the page (frontlight "Off", the number of the margin preset and the clock / session time / wpm of the bottom right tap) fade out in some steps. Each step is a refresh of the screen. Unchecked, they go away at once.]]),
                    callback = function()
                        self.settings:saveSetting("no_overlay_fade", not self.settings:isTrue("no_overlay_fade"))
                        self.settings:flush()
                        return true
                    end,
                },
                {
                    text_func = function()
                        local cur = self:getOverlayColor()
                        for _i, c in ipairs(PageTextInfo.session_overlay_colors) do
                            if c[2] == cur then return T(_("Big texts color: %1"), c[1]) end
                        end
                        return _("Big texts color")
                    end,
                    help_text = _([[Color of the big texts over the page (frontlight "Off", margin preset, background of the bottom tap, clock / session time / wpm). The fade out goes from this color to a light grey.]]),
                    sub_item_table_func = function()
                        local items = {}
                        for _i, c in ipairs(PageTextInfo.session_overlay_colors) do
                            items[#items + 1] = {
                                text = c[1],
                                radio = true,
                                checked_func = function() return self:getOverlayColor() == c[2] end,
                                callback = function()
                                    self.settings:saveSetting("overlay_color", c[2])
                                    self.settings:flush()
                                    self:showSessionOverlay({ c[1] }) -- preview
                                end,
                            }
                        end
                        return items
                    end,
                },
                {
                    text_func = function()
                        return T(_("Big texts duration: %1 s"), self:getOverlayHold())
                    end,
                    help_text = _([[Seconds the big texts over the page (frontlight "Off", profiles / margin preset, double tap on/off, clock / session time / wpm) stay fully visible before the fade out starts (or before they go away, if the fade out is unchecked).]]),
                    sub_item_table_func = function()
                        local items = {}
                        for _i, h in ipairs(PageTextInfo.session_overlay_holds) do
                            items[#items + 1] = {
                                text = T(_("%1 s"), h) .. (h == PageTextInfo.session_overlay_cfg.hold and " (" .. _("default") .. ")" or ""),
                                radio = true,
                                checked_func = function() return self:getOverlayHold() == h end,
                                callback = function()
                                    self.settings:saveSetting("overlay_hold", h)
                                    self.settings:flush()
                                    self:showSessionOverlay({ T(_("%1 s"), h) }) -- preview
                                end,
                            }
                        end
                        return items
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
                    text = _("Translation panel as dictionary"),
                    checked_func = function() return G_reader_settings:isTrue("translation_panel_dictionary") end,
                    help_text = _([[Show dictionary lookups in the translation panel (swipe left / right to change dictionary) instead of KOReader's standard dictionary window.]]),
                    callback = function()
                        local show = not G_reader_settings:isTrue("translation_panel_dictionary")
                        G_reader_settings:saveSetting("translation_panel_dictionary", show)
                        G_reader_settings:flush()

                        return true
                    end,
                },
                {
                    text = _("Show bookshelf hero as reload motive"),
                    checked_func = function() return G_reader_settings:isTrue("reading_motive_bookshelf_hero") end,
                    help_text = _([[On a document reload, show the bookshelf "currently reading" card as the motive instead of the image. Off: the image is shown.]]),
                    callback = function()
                        local show = not G_reader_settings:isTrue("reading_motive_bookshelf_hero")
                        G_reader_settings:saveSetting("reading_motive_bookshelf_hero", show)
                        G_reader_settings:flush()

                        return true
                    end,
                },
                {
                    text = _("Show page turn time"),
                    checked_func = function() return G_reader_settings:isTrue("show_page_turn_time") end,
                    help_text = _([[Show a notification with the time (in ms) it took to turn the page. The time is also always written to the log.]]),
                    callback = function()
                        local show = not G_reader_settings:isTrue("show_page_turn_time")
                        G_reader_settings:saveSetting("show_page_turn_time", show)
                        G_reader_settings:flush()

                        return true
                    end,
                },
                {
                    text = _("Diagnostic timing"),
                    checked_func = function() return G_reader_settings:isTrue("diagtiming_enabled") end,
                    help_text = _([[Log (as warnings) any require(), scheduled callback, event dispatch or screen refresh slower than 15 ms.]]),
                    callback = function()
                        local enable = not G_reader_settings:isTrue("diagtiming_enabled")
                        G_reader_settings:saveSetting("diagtiming_enabled", enable)
                        G_reader_settings:flush()
                        local Event = require("ui/event")
                        UIManager:broadcastEvent(Event:new("DiagTimingToggled", enable))
                        return true
                    end,
                },
                {
                    text = _("Crash log overlay"),
                    checked_func = function() return G_reader_settings:isTrue("crashlog_enabled") end,
                    help_text = _([[Show the last lines of crash.log, updated live, on every screen.]]),
                    callback = function()
                        local enable = not G_reader_settings:isTrue("crashlog_enabled")
                        G_reader_settings:saveSetting("crashlog_enabled", enable)
                        G_reader_settings:flush()
                        local Event = require("ui/event")
                        UIManager:broadcastEvent(Event:new("CrashLogToggled", enable))
                        return true
                    end,
                },
                -- Menu entry
                {
                    text = _("Memory overlay"),
                    checked_func = function() return G_reader_settings:isTrue("memoryoverlay_enabled") end,
                    help_text = _([[Show the memory of KOReader (Lua heap, resident memory, free memory), updated live, on every screen.]]),
                    callback = function()
                        local enable = not G_reader_settings:isTrue("memoryoverlay_enabled")
                        G_reader_settings:saveSetting("memoryoverlay_enabled", enable)
                        G_reader_settings:flush()
                        local Event = require("ui/event")
                        UIManager:broadcastEvent(Event:new("MemoryOverlayToggled", enable))
                        return true
                    end,
                },
                {
                    text = _("Widget time overlay"),
                    checked_func = function() return G_reader_settings:isTrue("widgettimeoverlay_enabled") end,
                    help_text = _([[Show how long each widget takes to be created (name and ms), live, in a scrollable window on every screen. Nothing is measured while it is off.]]),
                    callback = function()
                        local enable = not G_reader_settings:isTrue("widgettimeoverlay_enabled")
                        G_reader_settings:saveSetting("widgettimeoverlay_enabled", enable)
                        G_reader_settings:flush()
                        local Event = require("ui/event")
                        UIManager:broadcastEvent(Event:new("WidgetTimeOverlayToggled", enable))
                        return true
                    end,
                },
                {
                    text = _("Refresh overlay"),
                    checked_func = function() return G_reader_settings:isTrue("refreshoverlay_enabled") end,
                    help_text = _([[Show the screen refreshes of UIManager (setDirty calls and the refreshes really sent, with mode, region and caller), live, in a scrollable window on every screen. Needs the refresh_logger hook in uimanager.lua. Nothing is hooked while it is off.]]),
                    callback = function()
                        local enable = not G_reader_settings:isTrue("refreshoverlay_enabled")
                        G_reader_settings:saveSetting("refreshoverlay_enabled", enable)
                        G_reader_settings:flush()
                        local Event = require("ui/event")
                        UIManager:broadcastEvent(Event:new("RefreshOverlayToggled", enable))
                        return true
                    end,
                },
                {
                    text = _("Exit timing"),
                    checked_func = function() return G_reader_settings:isTrue("exittiming_enabled") end,
                    help_text = _([[Print (stdout) where the time goes when a book is opened or closed and the file manager is built again: plugin init, reader close and file manager creation. Nothing is hooked while it is off.]]),
                    callback = function()
                        local enable = not G_reader_settings:isTrue("exittiming_enabled")
                        G_reader_settings:saveSetting("exittiming_enabled", enable)
                        G_reader_settings:flush()
                        local Event = require("ui/event")
                        UIManager:broadcastEvent(Event:new("ExitTimingToggled", enable))
                        return true
                    end,
                },
                {
                    text = _("Monkey patches"),
                    help_text = _([[Check the most important functions (UIManager, Widget, FileManager, Screen refreshes, require...) and show which ones have been replaced by something other than the original KOReader source, with the file and line of every wrapper.]]),
                    callback = function(touchmenu_instance)
                        if touchmenu_instance and touchmenu_instance.closeMenu then touchmenu_instance:closeMenu() end
                        self:showMonkeyPatches()
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
                            text = _("Note mark icon"),
                            sub_item_table_func = function() return self:getNoteMarkMenu() end,
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
                            sub_item_table_func = function() return self:getDictionariesMenu() end,
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
    local _time = require("ui/time")
    local _t_close = _time.now()
    -- UIManager:unschedule(self.insertSession)
    self.ui.gestures:onIgnoreHoldCorners(false)
    self.ui.disable_double_tap = false
    -- Every document starts with the detection disabled, so give it back when leaving (file manager, other books)
    Device.input.disable_double_tap = false
    self.settings:saveSetting("highlight_all_notes_and_allow_to_edit_them_on_tap", false)
    self.settings:saveSetting("highlight_all_words_vocabulary_builder_and_notes", false)
    self.settings:flush()
    ExitTiming.record("PageTextInfo.onCloseDocument", _time.to_ms(_time.since(_t_close)))
end

-- function PageTextInfo:onPreserveCurrentSession()
--     PageTextInfo.preserved_hightlight_all_notes = self.settings:readSetting("highlight_all_notes")
--     PageTextInfo.preserved_highlight_all_words_vocabulary = self.settings:readSetting("highlight_all_words_vocabulary")
-- end

function PageTextInfo:paintTo(bb, x, y)

    if util.getFileNameSuffix(self.ui.document.file) ~= "epub" then return end
    -- Vocabulary first, notes after: the note icon goes on top of the dictionary gloss
    if self.words and self.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") then
        self:drawXPointerVocabulary(bb, x, y)
    end

    if self.settings:isTrue("highlight_all_notes_and_allow_to_edit_them_on_tap") or self.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") then
        self:drawXPointerSavedHighlightNotes(bb, x, y)
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
        local WordCount = require("wordcount_overlay")
        WordCount.paint(self, bb, x, y)
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

-- ===== Hero de bookshelf (adaptado del parche del banner) =====
local HERO_SETT = {
    width_pct = 85,     -- ancho del hero (% de pantalla)
    height_pct = 30,    -- alto de la tarjeta (% de pantalla)
    bottom_height_pct = 9,   -- alto de la tarjeta cuando va abajo de la pagina (% de pantalla): achatado
    bottom_padding = 6,      -- aire alrededor del hero cuando va abajo (px sin escalar)
    hide_regions = { "status", "rating", "metadata", "description", "tags" },
    show_progress = true,
    cover_text_height_pct = 7,  -- alto (% de pantalla) del recorte de la portada cuando va abajo
    cover_text_width_pct = 100, -- ancho (% de pantalla) del recorte de la portada: 100 = todo el ancho
    cover_text_stretch = true,  -- true: el recorte rellena justo ese ancho y alto (se estira); false: mantiene su proporcion
    cover_bands_paths = { "/media/partition/cover_title_bands.lua" }, -- donde busca el resultado de cover_title_bands.py (ademas de la carpeta de ajustes)
    cover_text_candidates = 5,  -- cuantas franjas de la portada se pueden ir probando (menu: next cover text)
    title_crop_pct = 24,     -- alto de la franja de la portada que se recorta como titulo en el hero de abajo (% del alto de la portada)
    background = Blitbuffer.COLOR_WHITE,  -- fondo detrás del hero: Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_GRAY_E (gris claro) o Blitbuffer.COLOR_LIGHT_GRAY
    padding = 12,        -- aire alrededor del hero (px sin escalar)
    border = 2,          -- grosor del borde (0 = sin borde)
    outer_border = 2,    -- marco exterior hueco (0 = sin marco hueco)
    outer_gap = 6,       -- separación entre el recuadro y el marco hueco
    -- adorno del hero de abajo en lugar del recuadro:
    --   "rule"    = filete encima que se aclara hacia los lados, con un rombo en el centro (separador de libro)
    --   "corners" = solo las cuatro esquinas, como un marco de foto
    --   "box"     = el recuadro de antes (borde + padding)
    frame_style = "rule",
    rule_height = 14,            -- alto de la franja del filete (px sin escalar)
    rule_diamond = 4,            -- medio lado del rombo central (px sin escalar)
    rule_gap = 6,                -- hueco a cada lado del rombo (px sin escalar)
    rule_dark = 0x22,            -- gris del filete en el centro (0x00 negro)
    rule_light = 0xDD,           -- gris del filete en los extremos (casi blanco = se desvanece)
    corner_length = 16,          -- largo de cada brazo de las esquinas (px sin escalar)
    chapter_bar_scale = 0.8,     -- barra del capitulo encima de la del libro: fraccion de su ancho y alto
    chapter_bar_gap = 4,         -- hueco entre la barra del capitulo y la del libro (px sin escalar)
}

local function buildHeroProgressRow(width, pct, book, device_state, progress_cfg)
    local Bb = require("ffi/blitbuffer")
    local Font = require("ui/font")
    local util = require("util")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local TextWidget = require("ui/widget/textwidget")
    local HeroBar = require("lib/bookshelf_hero_bar")

    local face = Font:getFace("cfont", 17)
    local gap = Screen:scaleBySize(8)

    local pct_widget = TextWidget:new{
        text = string.format("%d%%", math.floor(math.max(0, math.min(1, pct)) * 100 + 0.5)),
        face = face, padding = 0, fgcolor = Bb.COLOR_BLACK,
    }

    local left_text = ""
    pcall(function()
        local Tokens = require("lib/bookshelf_tokens")
        left_text = util.trim(tostring(Tokens.expand("%book_time_left", book, device_state) or ""))
    end)
    local left_widget
    if left_text ~= "" then
        left_widget = TextWidget:new{
            text = left_text, face = face, padding = 0,
            fgcolor = Bb.COLOR_BLACK,
        }
    end

    local used = pct_widget:getSize().w + gap * 2 + (left_widget and left_widget:getSize().w or 0)
    local bar_colors
    if progress_cfg.bar_style ~= "pacman" then
        local ok_cp, CP = pcall(require, "lib/bookshelf_cover_progress")
        if ok_cp and CP and CP.pickedBarColors then
            bar_colors = CP.pickedBarColors()
        end
    end
    local bar = HeroBar:new{
        width = math.max(10, width - used),
        height = Screen:scaleBySize(8),
        percentage = pct,
        style = progress_cfg.bar_style or "bordered",
        colors = bar_colors,
    }

    local row = HorizontalGroup:new{ align = "center", pct_widget, HorizontalSpan:new{ width = gap }, bar }
    if left_widget then
        table.insert(row, HorizontalSpan:new{ width = gap })
        table.insert(row, left_widget)
    end
    return row
end

-- settings/calibre.lua: { ["Book file name.epub"] = { pages=, words=, pubdate=, grrating=, grvotes=, ...,
-- ... } }. Also used for the metadata line of the bottom hero.
-- Read once per session. Returns the entry of a book file name, or nil.
local calibre_lua_cache
local function heroCalibreEntry(name)
    if calibre_lua_cache == nil then
        calibre_lua_cache = false
        pcall(function()
            local DataStorage = require("datastorage")
            local chunk = loadfile(DataStorage:getSettingsDir() .. "/calibre.lua")
            local t = chunk and chunk()
            if type(t) == "table" then calibre_lua_cache = t end
        end)
    end
    return calibre_lua_cache and name and calibre_lua_cache[name] or nil
end

-- cover_title_bands.lua, written by cover_title_bands.py: { ["Book file name.epub"] = {top, bottom} or false }, the
-- position of the title on the cover as fractions of its height. It is looked for in HERO_SETT.cover_bands_paths.
local cover_bands_cache
local function heroCoverBand(name)
    if cover_bands_cache == nil then
        cover_bands_cache = false
        pcall(function()
            local DataStorage = require("datastorage")
            local paths = { DataStorage:getSettingsDir() .. "/cover_title_bands.lua" }
            for _, p in ipairs(HERO_SETT.cover_bands_paths or {}) do table.insert(paths, p) end
            for _, path in ipairs(paths) do
                local chunk = loadfile(path)
                local t = chunk and chunk()
                if type(t) == "table" then cover_bands_cache = t return end
            end
        end)
    end
    local b = cover_bands_cache and name and cover_bands_cache[name]
    if type(b) == "table" and tonumber(b[1]) and tonumber(b[2]) then return tonumber(b[1]), tonumber(b[2]) end
end

-- Metadata line "1984 - 275kw - 4.1★ (1234) - 71" (publication year, kilowords, Goodreads rating and votes, prose complexity score). Same data as the
-- file dialog title; it lives in the calibre_data table of the file manager's file chooser, keyed by file name.
-- Returns "" when there is nothing for the open book.
local function heroMetadataText(book, ui)
    local text, extra = "", nil
    pcall(function()
        local rui = ui or require("apps/reader/readerui").instance
        local file = (rui and rui.document and rui.document.file) or (book and book.file) or (book and book.path)
        if not file then return end
        local name = tostring(file):match("([^/]+)$")
        local data
        local FM = package.loaded["apps/filemanager/filemanager"]
        local fc = FM and FM.instance and FM.instance.file_chooser
        if fc and type(fc.calibre_data) == "table" then
            data = fc.calibre_data[name] or fc.calibre_data[(name:gsub("%.[^.]+$", ""))]
        end
        data = data or heroCalibreEntry(name)
        -- each field comes from the calibre data first and from the bookshelf book if it is missing there
        local function field(...)
            for _, src in ipairs({ data or {}, book or {} }) do
                for _, key in ipairs({ ... }) do
                    local v = src[key]
                    if v ~= nil and v ~= "" then return v end
                end
            end
        end
        local parts = {}
        local pub = field("pubdate", "pub_date", "publication_date", "published", "pubyear", "pub_year", "year", "date")
        local year = pub and tostring(pub):match("(%d%d%d%d)")
        if year then table.insert(parts, year) end
        local words = tonumber(field("words"))
        if words then table.insert(parts, math.floor(words / 1000) .. "kw") end
        local rating, votes = field("grrating"), field("grvotes")
        if rating then
            table.insert(parts, tostring(rating) .. "★" .. (votes and (" (" .. tostring(votes) .. ")") or ""))
        end
        -- prose complexity score of the text (bookComplexity.py, through calibre.lua): "71", only the number, added by the caller if it fits
        local score = tonumber(field("complexity_score"))
        if score then
            extra = { full = tostring(math.floor(score + 0.5)) }
        end
        text = table.concat(parts, " - ")
    end)
    return text, extra
end

-- The text taken from the cover itself (only used by the "Bottom: cover text" option of custombg): the band of the cover with the most text-like detail (many light/dark changes
-- in a row) is cut out of the picture and scaled to fit max_w x max_h. A dark band is inverted so it is dark on light.
-- Returns an ImageWidget, or nil when the book has no cover.
-- ui: the reader (self.ui). ReaderUI.instance is not set yet while the book is opening, which made this give nothing
-- (and the hero card appear instead of the cover text) when the picture was made at ReaderReady.
local function heroTitleFromCover(max_w, max_h, ui)
    local ok, widget = pcall(function()
        local rui = ui or require("apps/reader/readerui").instance
        if not (rui and rui.document and rui.document.getCoverPageImage) then return nil end
        local cover = rui.document:getCoverPageImage()
        if not cover then return nil end
        local ImageWidget = require("ui/widget/imagewidget")
        local RenderImage = require("ui/renderimage")
        local W, H = cover:getWidth(), cover:getHeight()
        local frac = math.max(5, math.min(60, HERO_SETT.title_crop_pct or 24)) / 100
        -- small gray copy to measure detail per row
        local sw = 64
        local sh = math.max(8, math.floor(H * sw / W))
        local small = RenderImage:scaleBlitBuffer(cover, sw, sh, false)
        local lum = {}
        for y = 0, sh - 1 do
            local row = {}
            for x = 0, sw - 1 do row[x] = small:getPixel(x, y):getColor8().a end
            lum[y] = row
        end
        local detail, mean = {}, {}
        for y = 0, sh - 1 do
            local d, m = 0, 0
            for x = 0, sw - 1 do
                local v = lum[y][x]
                m = m + v
                if x > 0 then d = d + math.abs(v - lum[y][x - 1]) end
                if y > 0 then d = d + math.abs(v - lum[y - 1][x]) end
            end
            detail[y], mean[y] = d, m / sw
        end
        pcall(function() small:free() end)
        local best_y, band
        -- exact position found beforehand by cover_title_bands.py (OCR against the real title)
        local jb
        local file_name = rui.document.file:match("([^/]+)$")
        local entry = heroCalibreEntry(file_name) -- cover_y0 / cover_y1, put there when calibre.lua is generated
        if type(entry) == "table" and tonumber(entry.cover_y0) and tonumber(entry.cover_y1) then
            jb = { y0 = tonumber(entry.cover_y0), y1 = tonumber(entry.cover_y1) }
        else
            local top, bottom = heroCoverBand(file_name)
            if top then jb = { y0 = top, y1 = bottom } end
        end
        if jb and (jb.y1 - jb.y0 > 0.6 or jb.y1 <= jb.y0) then jb = nil end -- too big to be a title: use the detail search
        if jb then
            best_y = math.max(0, math.min(sh - 2, math.floor(jb.y0 * sh)))
            band = math.max(2, math.min(sh - best_y, math.ceil((jb.y1 - jb.y0) * sh)))
        else
            -- candidates: the best band, then the best one that does not overlap it, and so on.
            -- Which one is the title cannot be known without reading the text, so the chosen rank is saved per book.
            band = math.max(2, math.floor(sh * frac))
            local taken = {}
            local candidates = {}
            for _ = 1, HERO_SETT.cover_text_candidates do
                local best_y, best = nil, -1
                for y0 = 0, sh - band do
                    local free = true
                    for y = y0, y0 + band - 1 do if taken[y] then free = false break end end
                    if free then
                        local sum = 0
                        for y = y0, y0 + band - 1 do sum = sum + detail[y] end
                        if sum > best then best, best_y = sum, y0 end
                    end
                end
                if not best_y then break end
                table.insert(candidates, best_y)
                for y = best_y, best_y + band - 1 do taken[y] = true end
            end
            if #candidates == 0 then return nil end
            local rank = 1
            if rui.doc_settings then rank = tonumber(rui.doc_settings:readSetting("cover_text_rank")) or 1 end
            rank = ((rank - 1) % #candidates) + 1
            best_y = candidates[rank]
        end
        local avg = 0
        for y = best_y, best_y + band - 1 do avg = avg + mean[y] end
        avg = avg / band
        local y0 = math.floor(best_y * H / sh)
        local ch = math.min(H - y0, math.floor(band * H / sh))
        if jb then
            -- exact rows from the saved position (the small copy used above is rounded to about 15 rows of the cover)
            y0 = math.max(0, math.floor(jb.y0 * H))
            ch = math.max(2, math.min(H - y0, math.ceil((jb.y1 - jb.y0) * H)))
        end
        local crop = Blitbuffer.new(W, ch, cover:getType())
        crop:blitFrom(cover, 0, 0, 0, y0, W, ch)
        pcall(function() cover:free() end)
        if avg < 128 then crop:invert() end
        if HERO_SETT.cover_text_stretch then
            -- fills the whole width x height asked for (the band is stretched sideways)
            local stretched = RenderImage:scaleBlitBuffer(crop, max_w, max_h, true)
            return ImageWidget:new{ image = stretched, image_disposable = true }
        end
        return ImageWidget:new{
            image = crop,
            image_disposable = true,
            width = max_w,
            height = max_h,
            scale_factor = 0,
        }
    end)
    return ok and widget or nil
end

-- Progress inside the current chapter (0..1), counting the page on screen as read like the book bar.
-- nil when the book has no table of contents.
local function heroChapterPct(ui)
    local ok, v = pcall(function()
        local rui = ui or require("apps/reader/readerui").instance
        if not (rui and rui.toc and rui.document) then return nil end
        local page = (rui.view and rui.view.state and rui.view.state.page) or rui.document:getCurrentPage()
        if not page then return nil end
        local done = rui.toc:getChapterPagesDone(page)
        local left = rui.toc:getChapterPagesLeft(page)
        if not done or not left then return nil end
        local total = done + left + 1
        if total <= 0 then return nil end
        return math.max(0, math.min(1, (done + 1) / total))
    end)
    return ok and v or nil
end

-- Right side of the narrow hero at the bottom of the page: the metadata line and a long progress bar, centered
-- vertically next to the card. No percentage and no time left.
local function buildHeroProgressSide(width, pct, book, device_state, progress_cfg, ui)
    local Bb = require("ffi/blitbuffer")
    local Font = require("ui/font")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local TextWidget = require("ui/widget/textwidget")
    local HeroBar = require("lib/bookshelf_hero_bar")

    local col = VerticalGroup:new{ align = "center" }
    local meta, extra = heroMetadataText(book, ui)
    if meta ~= "" then
        -- the complexity score goes at the end only if the whole line fits, so it never cuts the year, the words or the rating
        local face = Font:getFace("cfont", 15)
        local candidates = {}
        if extra then
            table.insert(candidates, meta .. " - " .. extra.full)
        end
        table.insert(candidates, meta)
        local tw
        for i, text in ipairs(candidates) do
            if tw then tw:free() end
            local last = (i == #candidates)
            -- the last one (without the complexity) is cut only if it does not fit by itself
            tw = TextWidget:new{ text = text, face = face, padding = 0, fgcolor = Bb.COLOR_BLACK,
                                 max_width = last and width or nil }
            if last or tw:getSize().w <= width then break end
        end
        table.insert(col, CenterContainer:new{ dimen = Geom:new{ w = width, h = tw:getSize().h }, tw })
        table.insert(col, VerticalSpan:new{ width = Screen:scaleBySize(6) })
    end
    local bar_colors
    if progress_cfg.bar_style ~= "pacman" then
        local ok_cp, CP = pcall(require, "lib/bookshelf_cover_progress")
        if ok_cp and CP and CP.pickedBarColors then bar_colors = CP.pickedBarColors() end
    end
    -- chapter bar above the book bar, at chapter_bar_scale of its size (width and height), centered
    local ch_pct = heroChapterPct(ui)
    if ch_pct then
        local k = HERO_SETT.chapter_bar_scale or 0.8
        local ch_w = math.max(40, math.floor(width * k))
        -- at least 10 px high: the drawn styles of 2-bookshelf-bar-styles.lua need w >= 40 and h >= 10,
        -- below that they fall back to "rounded"
        local ch_h = math.max(10, math.floor(Screen:scaleBySize(8) * k + 0.5))
        table.insert(col, CenterContainer:new{
            dimen = Geom:new{ w = width, h = ch_h },
            HeroBar:new{
                width = ch_w,
                height = ch_h,
                percentage = ch_pct,
                style = progress_cfg.bar_style or "bordered",
                colors = bar_colors,
            },
        })
        table.insert(col, VerticalSpan:new{ width = Screen:scaleBySize(HERO_SETT.chapter_bar_gap or 4) })
    end
    table.insert(col, HeroBar:new{
        width = width,
        height = Screen:scaleBySize(8),
        percentage = pct,
        style = progress_cfg.bar_style or "bordered",
        colors = bar_colors,
    })
    return col
end

-- Book progress (0..1) read live from the reader, without going to disk.
local function heroCurrentPct(rui, book)
    local pct
    if rui and rui.document then
        local ok, v = pcall(function()
            local page = (rui.view and rui.view.state and rui.view.state.page) or rui.document:getCurrentPage()
            return page / rui.document:getPageCount()
        end)
        if ok and type(v) == "number" and v == v then pct = math.max(0, math.min(1, v)) end
    end
    pct = pct or tonumber(book and book.book_pct)
    if not pct and rui and rui.doc_settings then
        pct = tonumber(rui.doc_settings:readSetting("percent_finished"))
    end
    return pct
end

-- Cache of the card of the bottom hero (cover + regions): it does not change from one page to the next, so it is
-- made once per book and size, and only the progress column on its right is made again at each page turn.
-- { key, card, book, device_state, progress_cfg }
local hero_card_cache = nil

local function freeHeroCardCache()
    if hero_card_cache and hero_card_cache.card then
        pcall(function() hero_card_cache.card:free() end)
    end
    hero_card_cache = nil
end

-- Devuelve el widget del hero, o nil si bookshelf no está instalado / falla algo.
-- With opts.side the progress goes to the right of the card (centered vertically) instead of under it.
-- With opts.side the card is kept in hero_card_cache, and two more values are returned: true (the card is cached:
-- do not free it) and the progress column (the only part that may be freed).
-- With opts.page_turn and a cached card for this book and size, nothing is saved or read from disk: the cached card
-- is reused and only the progress column is made, with the progress read live from the reader.
local function buildBookshelfHero(width, height, opts)
    local side = opts and opts.side
    local side_w = side and math.floor(width * 0.40) or 0
    local side_gap = side and Screen:scaleBySize(8) or 0
    local full_width = width
    width = width - side_w - side_gap
    local logger = require("logger")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")

    -- fast path: page turn with the card already made
    if side and opts.page_turn and hero_card_cache then
        local rui = opts.ui or require("apps/reader/readerui").instance
        local file = rui and rui.document and rui.document.file
        local key = table.concat({ tostring(file), width, height }, "|")
        if file and hero_card_cache.key == key then
            local ok_fast, hero, side_col = pcall(function()
                local c = hero_card_cache
                local pct = heroCurrentPct(rui, c.book) or 0
                local col = buildHeroProgressSide(side_w, pct, c.book, c.device_state, c.progress_cfg, rui)
                return HorizontalGroup:new{
                    align = "center",
                    c.card,
                    HorizontalSpan:new{ width = side_gap },
                    col,
                }, col
            end)
            if ok_fast and hero then return hero, true, side_col end
            logger.warn("[reading-motive] hero rápido falló, se reconstruye entero:", hero)
        end
    end

    local cached_side_col = nil
    local ok, card = pcall(function()
        local HeroCard = require("lib/bookshelf_hero_card")
        local Repo = require("lib/bookshelf_book_repository")
        local Space = require("lib/bookshelf_space")
        local BookshelfWidget = require("lib/bookshelf_widget")

        -- guardar el libro abierto para que el progreso esté en disco
        local rui = (opts and opts.ui) or require("apps/reader/readerui").instance
        if rui and rui.document then
            pcall(function() rui:saveSettings() end)
            local file = rui.document.file
            if Repo.invalidateProgressCache then pcall(Repo.invalidateProgressCache, file) end
            if Repo.invalidateStatsCache then pcall(Repo.invalidateStatsCache, file) end
        end

        local book = Repo.getCurrent()
        if not book then return nil end
        if not book.book_pct and rui and rui.doc_settings then
            book.book_pct = rui.doc_settings:readSetting("percent_finished")
        end
        if Repo.enrichStats then Repo.enrichStats(book) end
        local device_state = BookshelfWidget._buildDeviceState({})

        local pad = math.min(math.floor(Space.padding.fullscreen * 2 * 0.8),
                             math.floor(Screen:getWidth() * 0.03))
        local cover_h = math.max(1, height)
        local cover_w = math.max(1, math.floor(cover_h / 1.5))
        local max_cover_w = math.max(1, math.floor(width * 0.58))
        if cover_w > max_cover_w then
            cover_w = max_cover_w
            cover_h = math.max(1, math.floor(cover_w * 1.5))
        end

        -- parchear Regions.read solo mientras se construye la tarjeta
        local Regions = require("lib/bookshelf_hero_regions")
        local original_read = Regions.read
        local progress_cfg = original_read().progress or {}
        Regions.read = function(...)
            local base = original_read(...)
            local patched = {}
            for key, region in pairs(base) do patched[key] = region end
            local function withDisabled(key, disabled)
                if type(patched[key]) == "table" then
                    local copy = {}
                    for k, v in pairs(patched[key]) do copy[k] = v end
                    copy.disabled = disabled
                    patched[key] = copy
                end
            end
            for _, key in ipairs(HERO_SETT.hide_regions or {}) do withDisabled(key, true) end
            if HERO_SETT.show_progress then withDisabled("progress", true) end
            return patched
        end

        local ok_card, card_or_err = pcall(HeroCard.new, HeroCard, {
            book = book,
            has_wallpaper = true,   -- tarjeta sin fondo propio (transparente)
            width = width,
            height = height,
            cover_w = cover_w,
            cover_h = cover_h,
            pad = pad,
            device_state = device_state,
        })
        Regions.read = original_read -- siempre restaurar
        if not ok_card then error(card_or_err) end
        if not HERO_SETT.show_progress then return card_or_err end

        local pct = tonumber(book.book_pct)
        if not pct and rui and rui.doc_settings then
            pct = tonumber(rui.doc_settings:readSetting("percent_finished"))
        end
        if not pct and rui and rui.document then
            local ok_pg, v = pcall(function()
                return rui.document:getCurrentPage() / rui.document:getPageCount()
            end)
            pct = ok_pg and v or nil
        end
        if side then
            -- keep the card for the next page turns (the previous one, of another book or size, is freed)
            freeHeroCardCache()
            local file = rui and rui.document and rui.document.file
            if file then
                hero_card_cache = {
                    key = table.concat({ tostring(file), width, height }, "|"),
                    card = card_or_err,
                    book = book,
                    device_state = device_state,
                    progress_cfg = progress_cfg,
                }
            end
            local col = buildHeroProgressSide(side_w, pct or 0, book, device_state, progress_cfg, rui)
            if hero_card_cache then cached_side_col = col end
            return HorizontalGroup:new{
                align = "center",
                card_or_err,
                HorizontalSpan:new{ width = side_gap },
                col,
            }
        end
        local row = buildHeroProgressRow(width, pct or 0, book, device_state, progress_cfg)
        return VerticalGroup:new{
            align = "left",
            card_or_err,
            VerticalSpan:new{ width = Screen:scaleBySize(6) },
            row,
        }
    end)
    if not ok then
        logger.warn("[reading-motive] no se pudo construir el hero de bookshelf:", card)
        return nil
    end
    if cached_side_col then return card, true, cached_side_col end
    return card
end

-- What the bottom picture shows that can change from one page to the next: if it is the same as the last one painted,
-- the page turn does not make the picture again. For the hero: the pixel the book bar and the chapter bar reach.
-- For the cover text: nothing (only the book and the screen size).
local function bottomHeroSignature(ui, mode, plain)
    if not (ui and ui.document) then return nil end
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local file = tostring(ui.document.file)
    if plain then return table.concat({ mode, "plain", file, screen_w, screen_h }, "|") end
    local width = math.floor(screen_w * HERO_SETT.width_pct / 100)
    local side_w = math.floor(width * 0.40)
    local ch_w = math.max(40, math.floor(side_w * (HERO_SETT.chapter_bar_scale or 0.8)))
    local pct = heroCurrentPct(ui) or 0
    local ch = heroChapterPct(ui)
    return table.concat({
        mode, file, screen_w, screen_h,
        math.floor(pct * side_w),
        ch and math.floor(ch * ch_w) or -1,
    }, "|")
end

-- The bottom picture is chosen in the custombg menu ("Bottom: bookshelf hero" / "Bottom: cover text", never both and
-- never together with the background or the ruled lines). custombg paints it (custombg:setBottomImage) and calls
-- buildBottomHero(mode) to make it; it is made again at every page turn (see onPageUpdate) so its progress advances.

-- Cover text: the next band of the cover, for books that have no title position saved by cover_title_bands.py
function PageTextInfo:nextCoverText()
    local ds = self.ui and self.ui.doc_settings
    if not ds then return false end
    local max_rank = HERO_SETT.cover_text_candidates
    local rank = (tonumber(ds:readSetting("cover_text_rank")) or 1) + 1
    if rank > max_rank then rank = 1 end
    ds:saveSetting("cover_text_rank", rank)
    self:buildBottomHero("cover")
    UIManager:show(Notification:new{ text = string.format("%d / %d", rank, max_rank) })
    return true
end

-- Ornament of the bottom hero, "rule" style: a thin line across the width that fades out towards the ends
-- (rule_dark in the middle, rule_light at the ends) with a small diamond in the middle, like the separators
-- between sections in printed books. Painted in the band of height band_h at the top of bb.
local function paintHeroRule(bb, w, band_h)
    local Bb = Blitbuffer
    local cy = math.floor(band_h / 2)
    local cx = math.floor(w / 2)
    local r = Screen:scaleBySize(HERO_SETT.rule_diamond)
    local hole = r + Screen:scaleBySize(HERO_SETT.rule_gap)
    local th = math.max(1, Screen:scaleBySize(1))
    local dark, light = HERO_SETT.rule_dark, HERO_SETT.rule_light
    local step = math.max(2, Screen:scaleBySize(3))
    local half = math.max(1, cx - hole)
    -- the line, in short segments, lighter the farther from the middle
    for x = 0, w - 1, step do
        local d = math.abs(x + step / 2 - cx)
        if d > hole then
            local t = math.min(1, (d - hole) / half)
            local grey = math.floor(dark + (light - dark) * t ^ 0.6)
            bb:paintRect(x, cy - math.floor(th / 2), math.min(step, w - x), th, Bb.Color8(grey))
        end
    end
    -- the diamond
    for dy = -r, r do
        local hw = r - math.abs(dy)
        bb:paintRect(cx - hw, cy + dy, 2 * hw + 1, 1, Bb.Color8(dark))
    end
end

-- Ornament of the bottom hero, "corners" style: only the four corners of the frame, like photo corners.
local function paintHeroCorners(bb, w, h)
    local Bb = Blitbuffer
    local len = math.min(Screen:scaleBySize(HERO_SETT.corner_length), math.floor(w / 3), math.floor(h / 3))
    local th = math.max(1, Screen:scaleBySize(HERO_SETT.border))
    local c = Bb.COLOR_BLACK
    -- top left, top right, bottom left, bottom right: one horizontal and one vertical arm each
    bb:paintRect(0, 0, len, th, c)              bb:paintRect(0, 0, th, len, c)
    bb:paintRect(w - len, 0, len, th, c)        bb:paintRect(w - th, 0, th, len, c)
    bb:paintRect(0, h - th, len, th, c)         bb:paintRect(0, h - len, th, len, c)
    bb:paintRect(w - len, h - th, len, th, c)   bb:paintRect(w - th, h - len, th, len, c)
end

-- Builds the hero picture with the current progress and hands it to the custombg plugin
-- opts.page_turn (from onPageUpdate): nothing is made when the picture would look the same as the one on screen,
-- the cached hero card is reused, and no repaint is asked for (the page turn already repaints the reader).
function PageTextInfo:buildBottomHero(mode, opts)
    local custombg = self.ui and self.ui.custombg
    if not (custombg and custombg.setBottomImage) or not mode then return false end
    local page_turn = opts and opts.page_turn
    if page_turn and self._bottom_hero_sig and self.bottom_picture_px then
        local ok_sig, sig = pcall(bottomHeroSignature, self.ui, mode, self._bottom_hero_plain)
        if ok_sig and sig and sig == self._bottom_hero_sig then return true end
    end
    do
        local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
        local hero, keep_card, side_part
        local plain = false  -- the cover text goes without the box (border and padding) around it
        if mode == "cover" then
            -- the text cut out of the cover, as a plain rectangle (no hero)
            hero = heroTitleFromCover(
                math.floor(screen_w * HERO_SETT.cover_text_width_pct / 100),
                math.floor(screen_h * HERO_SETT.cover_text_height_pct / 100),
                self.ui
            )
            plain = hero ~= nil
        end
        if not hero then
            hero, keep_card, side_part = buildBookshelfHero(
                math.floor(screen_w * HERO_SETT.width_pct / 100),
                math.floor(screen_h * HERO_SETT.bottom_height_pct / 100),
                { side = true, ui = self.ui, page_turn = page_turn }
            )
        end
        if not hero then return false end
        local style = plain and "plain" or (HERO_SETT.frame_style or "rule")
        -- square corners: the picture is a buffer, so rounded ones would show white wedges over the text
        local frame = FrameContainer:new{
            background = HERO_SETT.background,
            color = Blitbuffer.COLOR_BLACK,
            bordersize = style == "box" and Screen:scaleBySize(HERO_SETT.border) or 0,
            radius = 0,
            margin = 0,
            padding = style == "plain" and 0 or Screen:scaleBySize(HERO_SETT.bottom_padding),
            hero,
        }
        local fsize = frame:getSize()
        -- "rule": a band above the hero for the ornament
        local top = style == "rule" and Screen:scaleBySize(HERO_SETT.rule_height) or 0
        local size = { w = fsize.w, h = fsize.h + top }
        -- drawn in grays on white, then turned into a mask (dark = opaque, white = nothing): transparent hero
        local bb = Blitbuffer.new(size.w, size.h, Blitbuffer.TYPE_BB8)
        bb:fill(Blitbuffer.COLOR_WHITE)
        frame:paintTo(bb, 0, top)
        if keep_card then
            -- the card stays in the cache for the next page: only the progress column is freed
            if side_part then pcall(function() side_part:free() end) end
        else
            pcall(function() frame:free() end)
        end
        if style == "rule" then
            paintHeroRule(bb, size.w, top)
        elseif style == "corners" then
            paintHeroCorners(bb, size.w, size.h)
        end
        bb:invert()
        -- the cover text banner sits flush with the bottom edge of the screen; the hero keeps a small gap
        local gap = plain and 0 or Screen:scaleBySize(HERO_SETT.outer_gap)
        -- height taken at the bottom of the screen (picture + gap), used for the bottom margin
        self.bottom_picture_px = size.h + gap
        custombg:setBottomImage(bb, gap, true)
        self._bottom_hero_plain = plain
        local ok_sig, sig = pcall(bottomHeroSignature, self.ui, mode, plain)
        self._bottom_hero_sig = ok_sig and sig or nil
    end
    if not page_turn then
        UIManager:setDirty(self.view.dialog, "ui")
    end
    return true
end

-- The reading motive on screen (nil when there is none). It is closed in onReaderReady of the new reader, in the
-- same step where the reload icon goes away (a timer would close it later than the icon).
local reading_motive_widget = nil

function PageTextInfo.closeReadingMotive()
    local widget = reading_motive_widget
    if not widget then return end
    reading_motive_widget = nil
    pcall(UIManager.close, UIManager, widget)
end


-- ===== Función principal =====
function PageTextInfo:onShowReadingMotive()
    -- BookLoadCover Plus (patches/2-bookloadcover.lua) already shows its own cover on internal
    -- reloads when "Show cover on internal reload/document switch" is on and the opening mode
    -- shows a cover: in that case this popup is not shown.
    if G_reader_settings:isTrue("bookloadcover_close_on_teardown") then
        local open_mode = G_reader_settings:readSetting("bookloadcover_open_mode", "cover_only")
        if open_mode == "cover_only" or open_mode == "cover_with_widgets" then
            return
        end
    end
    local ScreenSaverWidget = require("ui/widget/screensaverwidget")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local ImageWidget = require("ui/widget/imagewidget")
    local Geom = require("ui/geometry")

    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()

    -- Closes what is on top of the reader (the "reloading" notices and their icon), as BookLoadCover does before
    -- and after its cover: the widgets above the reader / file manager / bookshelf, except `keep`.
    local function closeOverlays(keep)
        local stack = UIManager._window_stack
        if not stack then return end
        local widgets = {}
        for i = #stack, 1, -1 do
            local w = stack[i] and stack[i].widget
            if w then widgets[#widgets + 1] = w end
        end
        for _i, w in ipairs(widgets) do
            if w ~= keep then
                local name = type(w.name) == "string" and w.name:lower() or nil
                if name == "readerui" or name == "filemanager" or name == "bookshelf" then break end
                pcall(UIManager.close, UIManager, w)
            end
        end
    end
    closeOverlays(nil)

    -- hero de bookshelf (nil si no hay bookshelf o falla)
    -- menu setting (Show bookshelf hero as reload motive), off by default: then the image is shown
    local hero = G_reader_settings:isTrue("reading_motive_bookshelf_hero") and buildBookshelfHero(
        math.floor(screen_w * HERO_SETT.width_pct / 100),
        math.floor(screen_h * HERO_SETT.height_pct / 100)
    ) or nil

    local content
    local transparent = false
    if hero then
        -- hero centrado, sin fondo: el resto de la pantalla queda transparente
        transparent = true
        content = CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = screen_h },
            FrameContainer:new{      -- marco exterior hueco (sin fondo: se ve lo de debajo)
                color = Blitbuffer.COLOR_BLACK,
                bordersize = Screen:scaleBySize(HERO_SETT.outer_border),
                radius = Size.radius.window,
                margin = 0,
                padding = Screen:scaleBySize(HERO_SETT.outer_gap),
                FrameContainer:new{
                    background = HERO_SETT.background,
                    color = Blitbuffer.COLOR_BLACK,
                    bordersize = Screen:scaleBySize(HERO_SETT.border),
                    radius = Size.radius.window,
                    margin = 0,
                    padding = Screen:scaleBySize(HERO_SETT.padding),
                    hero,
                },
            },
        }
    else
        -- sin bookshelf: la imagen de siempre
        content = ImageWidget:new{
            width = screen_w,
            height = screen_h,
            scale_factor = G_reader_settings:isFalse("screensaver_stretch_images") and 0 or nil,
            stretch_limit_percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage"),
            image_disposable = true,
            file = "resources/books.jpg",
            file_do_cache = false,
            alpha = true,
        }
    end

    local group = OverlapGroup:new{
        dimen = { w = screen_w, h = screen_h },
        content,
        nil,
    }
    local screensaver_widget = ScreenSaverWidget:new{
        widget = group,
        background = (not transparent) and Blitbuffer.COLOR_WHITE or nil,
        covers_fullscreen = not transparent,
    }
    screensaver_widget.modal = true
    screensaver_widget.dithered = not transparent
    screensaver_widget.name = "ReadingMotive"
    screensaver_widget.onCloseWidget = function() end
    -- ScreenSaverWidget:onShow() requests its own "full" refresh whatever UIManager:show() is
    -- given, which is what flashed. Neutralise it so the "ui" refresh below is the only one.
    screensaver_widget.onShow = function() return true end
    -- "ui" instead of "full": no full-screen flash when the popup appears
    UIManager:show(screensaver_widget, "ui")
    -- reloadDocument() blocks right after this event, so paint now or the popup is never seen
    UIManager:forceRePaint()

    -- The popup goes away in onReaderReady of the new reader. If that never happens (the reload failed) it is
    -- closed after 10 s.
    reading_motive_widget = screensaver_widget
    UIManager:scheduleIn(10, function()
        if reading_motive_widget == screensaver_widget then PageTextInfo.closeReadingMotive() end
    end)
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

    local w = Screen:getWidth()
    local h = Screen:getHeight()

    local framed = FrameContainer:new{
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        self.scroll_text_w,
    }
    local centered = CenterContainer:new{
        dimen = Geom:new{
            w = w,
            h = h,
        },
        framed,
    }

    local movable = MovableContainer:new{
        centered,
    }

    local widget = WidgetContainer:new{
        dimen = Geom:new{
            w = w,
            h = h,
        },
        movable,
    }

    local fc = InputContainer:new{
        width = w,
        height = h,
        widget,
    }

    self.scroll_text_w.dialog = fc

    -- fc:registerTouchZones({
    --     {
    --         id = "close_multiswipe",
    --         ges = "multi_swipe",
    --         handler = function(ges)
    --             UIManager:close(fc, "full")
    --             return true
    --         end,
    --         screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
    --     }
    -- })

    UIManager:show(fc)
end

function PageTextInfo:getCovers(filepath, max_w, max_h)
    local ReadCollection = require("readcollection")
    local BookInfoManager = require("bookinfomanager")
    -- Query database for books in this folder with covers
    local SQ3 = require("lua-ljsqlite3/init")
    local DataStorage = require("datastorage")


    local res
    local special_cover = nil
    if not filepath:match("✪ Collections") and not filepath:match(" Metadata") then
            local db_conn = SQ3.open(DataStorage:getSettingsDir() .. "/bookinfo_cache.sqlite3")
            db_conn:set_busy_timeout(5000)
            local query = string.format([[
                SELECT directory, filename FROM bookinfo
                WHERE directory = '%s/' AND has_cover = 'Y'
                ORDER BY filename ASC LIMIT 40;
        ]], filepath:gsub("'", "''"))
        res = db_conn:exec(query)
        db_conn:close()
    else
        local candidates = {}
        local DataStorage = require("datastorage")
        local last = filepath
        if filepath:match("✪ Collections$") then
            last = filepath:gsub("✪ Collections",("Collections"))
        end
        last = last:gsub("/+$", ""):gsub(" ", ""):match("([^/]+)$")
        local image = "resources/icons/folder." .. last .. ".png"

        local fake_cover ={}
        -- local android = require("android")
        -- android.LOGW("paso " .. image)
        if util.fileExists(image) and self.settings:isTrue("custom_covers_collections") then
            local RenderImage = require("ui/renderimage")
            local bb = RenderImage:renderImageFile(image, false, nil, nil)
            if bb then
                fake_cover.cover_bb = bb
                fake_cover.cover_w  = bb.w
                fake_cover.cover_h  = bb.h
                fake_cover.has_cover = true

                return fake_cover, true
            end
        else
            if filepath then
                local coll = ReadCollection.coll[filepath:match("([^/]+)$")]
                if filepath:match("✪ Collections$") then
                    coll = ReadCollection.coll["favorites"]
                end
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
                if bookinfo then
                    table.insert(dirs, fullpath:match("(.*/)"))
                    table.insert(files, fullpath:match("([^/]+)$"))
                end
            end
        end
        res = {
            dirs,
            files,
        }
    end
    return res
end

function PageTextInfo:get_empty_folder_cover(max_w, max_h)
        return nil
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
    local res, fake_cover = self:getCovers(filepath, max_w, max_h)
    local border_total = 2*Size.border.thin
    if (res and res[1] and res[2] and res[1][1]) or fake_cover then
        local covers = {}
        if fake_cover then
            table.insert(covers, res)
        else
            local dir_ending = string.sub(res[1][1],-2,-2)
            local num_books = #res[1]
            -- Save all covers
            for i = 1, num_books do
                if #covers >= 4 then break end
                local fullpath = res[1][i] .. res[2][i]

                if util.fileExists(fullpath) then
                    local bookinfo = BookInfoManager:getBookInfo(fullpath, true)
                    if bookinfo and bookinfo.cover_bb and bookinfo.has_cover then
                        table.insert(covers, bookinfo)
                    end
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
                -- if #covers == 1 and self.settings:isTrue("enable_extra_tweaks_list_menu_view") then
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
                if not mosaic and self.settings:isTrue("enable_extra_tweaks_list_menu_view") then
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
            --     -- if self.settings:isTrue("enable_extra_tweaks_list_menu_view") then
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
                    local padding_left = start_x + (i - 1) * offset_x - border_adjustment
                    if self.settings:isTrue("invert_covers_stack") then
                        local cw = cover.size.w
                        local x = (total_width - cw) - ((i - 1) * offset_x)
                        padding_left = start_x + x - border_adjustment
                    end
                    children[#children+1] = FrameContainer:new{
                        margin = 0,
                        padding = 0,
                        padding_left = padding_left,
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
                    dont_draw = fake_cover and true or false,
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
                    local padding_left = (i - 1) * offset_x
                    if self.settings:isTrue("invert_covers_stack") then
                        local cw = cover.size.w + border_total
                        padding_left  = (total_width - cw) - ((i - 1) * offset_x)
                    end
                    children[#children + 1] = FrameContainer:new{
                        margin = 0,
                        padding = 0,
                        padding_left = padding_left,
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
        return self:get_empty_folder_cover(max_w, max_h)
    else
        return nil
    end
end

function PageTextInfo:getSubfolderCoverGrid(filepath, max_w, max_h, mosaic)
    local ImageWidget = require("ui/widget/imagewidget")
    local BookInfoManager = require("bookinfomanager")
    local res, fake_cover = self:getCovers(filepath, max_w, max_h)

    local function create_blank_cover(width, height, background_idx)
        local border_size = Size.border.thin
        if (mosaic and self.settings:isTrue("enable_extra_tweaks_mosaic_view"))
        or (not mosaic and self.settings:isTrue("enable_extra_tweaks_list_menu_view")) then
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
        local border = Size.border.thin
        local gap    = Size.padding.small
        if ((mosaic and self.settings:isTrue("enable_extra_tweaks_mosaic_view"))
            or (not mosaic and self.settings:isTrue("enable_extra_tweaks_list_menu_view"))) then
            gap = 0
        end
        local max_img_w = math.floor((max_w - (border * 4) - gap) / 2)
        local max_img_h = math.floor((max_h - (border * 4) - gap) / 2)

        if not mosaic then
            max_img_w = math.ceil((max_w - (border * 4) - gap) / 2)
            max_img_h = math.ceil((max_h - (border * 4) - gap) / 2)
        end
        if max_img_w < 10 then max_img_w = max_w * 0.8 end
        if max_img_h < 10 then max_img_h = max_h * 0.8 end

        return max_img_w, max_img_h
    end

    if fake_cover then
        local bb = res.cover_bb

        local border_total = 2 * Size.border.thin

        -- Usar todo el espacio disponible del hueco (max_w x max_h)
        local scale_w = (max_w - border_total) / res.cover_w
        local scale_h = (max_h - border_total) / res.cover_h
        local scale = math.min(scale_w, scale_h)

        local final_w = math.floor(res.cover_w * scale)
        local final_h = math.floor(res.cover_h * scale)

        if (mosaic and self.settings:isTrue("enable_extra_tweaks_mosaic_view"))
            or (not mosaic and self.settings:isTrue("enable_extra_tweaks_list_menu_view")) then
            final_w = max_w
            final_h = max_h
        end

        local img = ImageWidget:new {
            image = res.cover_bb,
            width = final_w,
            height = final_h,
            scale_factor = nil,
        }

        local border_adjustment = border_total
        if (mosaic and (self.settings:isTrue("enable_rounded_corners") or self.settings:isTrue("enable_extra_tweaks_mosaic_view")) or not mosaic) then
            border_adjustment = 0
        end
        return CenterContainer:new {
            dimen = Geom:new { w = max_w + border_adjustment, h = max_h },
            wide = final_w,
            dont_draw = fake_cover and true or false,
            FrameContainer:new {
                margin = 0,
                padding = 0,
                bordersize = (not mosaic and self.settings:isTrue("enable_extra_tweaks_list_menu_view")) and 0 or Size.border.thin,
                color = Blitbuffer.COLOR_BLACK,
                img,
            },
        }
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
                if #images >= 4 then break end -- the grid only has 4 slots
                local fullpath = res[1][i] .. res[2][i]

                if util.fileExists(fullpath) then
                    local bookinfo = BookInfoManager:getBookInfo(fullpath, true)
                    -- local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
                    -- local image = FileManagerBookInfo:getCoverImage(nil, fullpath)
                    -- bookinfo.cover_bb = image
                    -- bookinfo.cover_w = 450
                    -- bookinfo.cover_h = 680
                    if bookinfo and bookinfo.cover_bb and bookinfo.has_cover then
                        local border_total = (Size.border.thin * 2)
                        local _, _, scale_factor = BookInfoManager.getCachedCoverSize(
                            bookinfo.cover_w, bookinfo.cover_h, max_img_w, max_img_h)
                        local wimage = ImageWidget:new{
                            image = bookinfo.cover_bb,
                            width  = max_img_w,
                            height = max_img_h,
                            scale_factor = nil,
                        }

                        w = max_img_w
                        h = max_img_h
                        -- if i == 1 then
                        -- Images sizes may varied depending the cached size
                        -- This is not noticed in stack view
                        local w = math.floor((bookinfo.cover_w * scale_factor) + border_total)
                        local h = math.floor((bookinfo.cover_h * scale_factor) + border_total)

                        local border_size = Size.border.thin
                        if (mosaic and self.settings:isTrue("enable_extra_tweaks_mosaic_view"))
                        or (not mosaic and self.settings:isTrue("enable_extra_tweaks_list_menu_view")) then
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
                            width = max_img_w + (border_size * 2),
                            height = max_img_h + (border_size * 2),
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
            if (mosaic and self.settings:isTrue("enable_extra_tweaks_mosaic_view")) or (not mosaic and self.settings:isTrue("enable_extra_tweaks_list_menu_view")) then
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
            if (mosaic and (self.settings:isTrue("enable_rounded_corners") or self.settings:isTrue("enable_extra_tweaks_mosaic_view"))) or not mosaic then
                border_adjustment = 0
            end
            return CenterContainer:new {
                dimen = Geom:new { w = max_w + border_adjustment, h = max_h},
                wide = self.settings:isTrue("enable_extra_tweaks_mosaic_view") and layout:getSize().w or layout:getSize().w - 2*Size.border.thin,
                FrameContainer:new {
                    margin = 0,
                    padding = 0,
                    -- background = Blitbuffer.colorFromName("orange"),
                    bordersize = (mosaic and self.settings:isTrue("enable_extra_tweaks_mosaic_view")) and Size.border.thin or 0,
                    color = Blitbuffer.COLOR_BLACK,
                    layout,
                },
            }
        else
            return self:get_empty_folder_cover(max_w, max_h)
        end
    else
        return self:get_empty_folder_cover(max_w, max_h)
    end
end

-- Collects the leaf tweaks (with category headers) from the style tweaks menu table
local function collectTweaks(items, out)
    for __, item in ipairs(items) do
        local title = item.text or (item.text_func and item.text_func())
        if type(item.sub_item_table) == "table" then
            if title then table.insert(out, { header = title }) end
            collectTweaks(item.sub_item_table, out)
        elseif item.checked_func and item.callback then
            table.insert(out, { item = item, label = title or "?" })
        end
    end
end

local function buildTweakEntries(ui)
    local raw = {}
    local tweaks_table = ui.styletweak and ui.styletweak.tweaks_table
    if type(tweaks_table) ~= "table" then return raw end
    collectTweaks(tweaks_table, raw)
    -- Drop headers with no tweaks under them
    local out = {}
    for i, e in ipairs(raw) do
        if not e.header or (raw[i + 1] and not raw[i + 1].header) then
            table.insert(out, e)
        end
    end
    return out
end

function PageTextInfo:closeTweaksMenu()
    local UIManager = require("ui/uimanager")
    local d = self.tweaks_dialog
    self.tweaks_dialog = nil
    if d then
        UIManager:close(d, "ui", d.frame_rect)
    end
end

-- Toggle a tweak (the menu item's own callback applies/removes it), then reopen
function PageTextInfo:toggleTweakAndReopen(item)
    local UIManager = require("ui/uimanager")
    local page = self.tweaks_page

    local ok, err = pcall(item.callback)
    if not ok then
        require("logger").dbg("toggle tweak failed:", err)
    end

    UIManager:nextTick(function()
        self:onShowTweaks(page)
    end)
end

function PageTextInfo:onShowTweaks(page)
    local Blitbuffer = require("ffi/blitbuffer")
    local Device = require("device")
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local Size = require("ui/size")
    local UIManager = require("ui/uimanager")
    local TextWidget = require("ui/widget/textwidget")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local Screen = Device.screen

    local ROWS_PER_PAGE = 8
    local FONT_SIZE = 18

    local ui = self.ui
    -- Only reflowable documents
    if not ui or not ui.document or ui.paging or not ui.styletweak then
        return true
    end

    local old_dialog = self.tweaks_dialog
    local old_region = old_dialog and old_dialog.frame_rect
        and old_dialog.frame_rect:copy()
    self.tweaks_dialog = nil

    local entries = buildTweakEntries(ui)
    if #entries == 0 then return true end

    local total_pages = math.max(1, math.ceil(#entries / ROWS_PER_PAGE))
    page = math.min(math.max(page or 1, 1), total_pages)
    self.tweaks_page = page

    local has_prev = page > 1
    local has_next = page < total_pages
    local first = (page - 1) * ROWS_PER_PAGE + 1
    local last = math.min(first + ROWS_PER_PAGE - 1, #entries)

    -- Sizes
    local screen = Screen:getSize()
    local dialog_w = math.floor(screen.w * 0.85)
    local font_px = Screen:scaleBySize(FONT_SIZE)
    local row_h = math.floor(font_px * 2.2)
    local text_h = math.floor(font_px * 1.6)
    local baseline = math.floor(font_px * 1.15)
    local thin = Screen:scaleBySize(1)
    local thick = Screen:scaleBySize(3)
    local pad_x = Screen:scaleBySize(8)
    local cells = {}

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

    function dialog:onSwipe(arg, ges)
        local dir = ges.direction
        if dir == "west" and has_next then
            UIManager:nextTick(function() self.plugin:onShowTweaks(page + 1) end)
        elseif dir == "east" and has_prev then
            UIManager:nextTick(function() self.plugin:onShowTweaks(page - 1) end)
        end
        return true
    end

    -- Long press: the tweak's own description (if the item defines hold_callback)
    function dialog:onHold(arg, ges)
        for __, cell in ipairs(cells) do
            if cell.frame.dimen and ges.pos:intersectWith(cell.frame.dimen)
                    and cell.item.hold_callback then
                pcall(cell.item.hold_callback)
                break
            end
        end
        return true
    end

    local grid = VerticalGroup:new{ align = "center" }

    for i = first, last do
        local e = entries[i]
        if e.header then
            -- Category header (not tappable)
            table.insert(grid, FrameContainer:new{
                bordersize = 0, margin = 0, padding = 0,
                LeftContainer:new{
                    dimen = Geom:new{ w = dialog_w, h = row_h },
                    FrameContainer:new{
                        bordersize = 0, margin = 0, padding = 0,
                        padding_left = pad_x,
                        TextWidget:new{
                            text = e.header,
                            face = Font:getFace("smallinfofontbold", FONT_SIZE),
                            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                            forced_height = text_h,
                            forced_baseline = baseline,
                            max_width = dialog_w - 2 * pad_x,
                        },
                    },
                },
            })
        else
            local ok, checked = pcall(e.item.checked_func)
            checked = ok and checked and true or false

            local cell_frame = FrameContainer:new{
                bordersize = thin,
                color = Blitbuffer.COLOR_BLACK,
                margin = 0,
                padding = 0,
                FrameContainer:new{
                    -- Thick border only on enabled tweaks
                    bordersize = thick - thin,
                    color = checked and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
                    background = Blitbuffer.COLOR_WHITE,
                    margin = 0,
                    padding = 0,
                    LeftContainer:new{
                        dimen = Geom:new{
                            w = dialog_w - 2 * thick,
                            h = row_h - 2 * thick,
                        },
                        FrameContainer:new{
                            bordersize = 0, margin = 0, padding = 0,
                            padding_left = pad_x,
                            TextWidget:new{
                                text = (checked and "✓ " or "    ") .. e.label,
                                face = Font:getFace("cfont", FONT_SIZE),
                                forced_height = text_h,
                                forced_baseline = baseline,
                                max_width = dialog_w - 2 * thick - 2 * pad_x,
                            },
                        },
                    },
                },
            }
            table.insert(grid, cell_frame)
            table.insert(cells, { frame = cell_frame, item = e.item })
        end
    end

    -- Navigation row
    local nav_w = math.floor(dialog_w / 3)
    local nav_h = math.floor(font_px * 2)

    local function navCell(text, enabled)
        return FrameContainer:new{
            bordersize = 0, padding = 0, margin = 0,
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
    table.insert(grid, HorizontalGroup:new{
        navCell("‹", has_prev),
        navCell(string.format("%d / %d", page, total_pages), true),
        navCell("›", has_next),
    })

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

    function dialog:onTap(arg, ges)
        for __, cell in ipairs(cells) do
            if cell.frame.dimen and ges.pos:intersectWith(cell.frame.dimen) then
                self.plugin:toggleTweakAndReopen(cell.item)
                return true
            end
        end

        if ges.pos:intersectWith(frame_rect) then
            local nav_top = frame_rect.y + frame_rect.h
                            - Size.border.window - Size.padding.small - nav_h
            if ges.pos.y >= nav_top then
                local third = frame_rect.w / 3
                local rel_x = ges.pos.x - frame_rect.x
                if rel_x < third then
                    if has_prev then
                        UIManager:nextTick(function() self.plugin:onShowTweaks(page - 1) end)
                    end
                elseif rel_x > 2 * third then
                    if has_next then
                        UIManager:nextTick(function() self.plugin:onShowTweaks(page + 1) end)
                    end
                end
            end
            return true
        end

        self.plugin:closeTweaksMenu()
        return true
    end

    function dialog:onClose()
        self.plugin:closeTweaksMenu()
        return true
    end

    dialog.plugin = self
    dialog.frame_rect = frame_rect
    self.tweaks_dialog = dialog

    local region = frame_rect
    if old_region then region = region:combine(old_region) end

    UIManager:show(dialog, "ui", region)
    if old_dialog then
        UIManager:close(old_dialog, "ui", region)
    end
    return true
end

return PageTextInfo
