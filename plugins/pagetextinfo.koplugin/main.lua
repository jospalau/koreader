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
    Dispatcher:registerAction("toggle_double_bar", {category="none", event="ToggleDoubleBar", title=_("Toggle double bar"), reader=true, separator=true,})
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
            return UIManager:sendEvent(Event:new("ShowLongestSessions"))
        end
        if self.view.topbar.is_enabled == nil or self.view.topbar.is_enabled == false then
            self.view.topbar:quickToggleOnOff(true)
        else
            self.view.topbar:quickToggleOnOff(false)
        end
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
        UIManager:broadcastEvent(Event:new("BookshelfOpenStartMenu"))
        return
    end
    return false
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
    CrashLog.setEnabled(G_reader_settings:isTrue("crashlog_enabled"))
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
    screensaver_widget.name = "ReadingMotive"
    screensaver_widget.onCloseWidget = function() end
    UIManager:show(screensaver_widget, "full")


    UIManager:scheduleIn(0.25, function()
        -- Screen:refreshFullImp(0, 0, Screen:getWidth(), Screen:getHeight()) --
        -- UIManager:setDirty("all", "full")
        UIManager:close(screensaver_widget)
    end)
end

-- Per-platform paths (defined once, shared by both functions)
local function getPlatformPaths()
    if Device:isKobo() then
        return {
            scripts_dir = "/mnt/onboard/.adds/scripts",
            fbink       = "/mnt/onboard/.adds/koreader/fbink",
            font        = "/mnt/onboard/fonts/Capita-Regular.otf",
            font_size   = ",size=14",
            cd_first    = true, -- On Kobo, scripts are run after cd'ing into their directory
        }
    elseif Device:isKindle() then
        return {
            scripts_dir = "/mnt/us/scripts",
            fbink       = "/mnt/us/koreader/fbink",
            font        = "/mnt/us/fonts/Capita-Regular.otf",
            font_size   = ",size=14",
        }
    elseif Device:isPocketBook() then
        return {
            scripts_dir = "/mnt/ext1/scripts",
            fbink       = "/mnt/ext1/applications/koreader/fbink",
            font        = "/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf",
            font_size   = "", -- The original code did not pass a size on PocketBook
        }
    else -- Emulator
        return {
            scripts_dir = "~/.local/scripts",
            fbink       = "~/koreader/koreader-emulator-x86_64-pc-linux-gnu-debug/koreader/fbink",
            font        = "~/fontsFinal/Capita-Regular.otf",
        }
    end
end

-- Show a short message on the e-ink screen with fbink
local function showFbinkMessage(paths, text)
    local f = io.popen(string.format(
        "%s -mM -f -c -t regular=%s%s %s", paths.fbink, paths.font, paths.font_size, text))
    if f then f:read("*a"); f:close() end
end

-- Show a full-screen "Restarting..." page using KOReader's own widgets
local function showMessage(paths, text)
    local Blitbuffer = require("ffi/blitbuffer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local Geom = require("ui/geometry")
    local Screen = Device.screen

    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local face = Font:getFace("myfont2") or Font:getFace("infofont", 32)

    local page = FrameContainer:new{
        width = screen_w,
        height = screen_h,
        padding = 0,
        margin = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = screen_h },
            TextBoxWidget:new{
                text = text,
                face = face,
                width = math.floor(screen_w * 0.8),
                alignment = "center",
            },
        },
    }
    -- "full" makes it a flashing refresh, so the page really lands on the e-ink
    UIManager:show(page, "full")
    UIManager:forceRePaint()
end

-- Show a "Restarting..." message with fbink, then restart (or quit) KOReader
local function restartKOReader(paths, widget)
    UIManager:nextTick(function()
        UIManager:close(widget, "full")
        showMessage(paths, "Restarting...")
        if Device:canRestart() then
            UIManager:restartKOReader()
        else
            UIManager:quit()
        end
    end)
end

-- Refresh file list, history and stats after books changed on disk
-- (used when the user chooses not to restart)
local function refreshAfterBookSync(paths)
    if not G_reader_settings:isTrue("top_manager_infmandhistory") then
        return
    end
    showFbinkMessage(paths, "Updating...")

    local util = require("util")
    _G.all_files = util.getListAll()
    -- Read the history file again, because it can contain books
    -- that are not physically in the device
    require("readhistory"):reload(true)
    util.generateStats()

    -- The file manager may not be open, so guard against a nil instance
    local FileManager = require("apps/filemanager/filemanager")
    if FileManager.instance then
        FileManager.instance.file_chooser:refreshPath()
    end
    UIManager:broadcastEvent(Event:new("BookMetadataChanged"))
end

-- Run a sync script and handle its result.
-- opts.ask_restart:   if true, offer to restart KOReader after a successful run.
-- opts.flash_no:      flash the screen when pressing "No need to restart".
-- opts.on_no_restart: function(paths) called when the user chooses not to restart.
-- opts.progress_text: text shown while the script runs.
-- opts.error_text:    text shown (followed by the output) when the script fails.
-- Returns true only if the script ran and succeeded.
local function runSyncScript(script_name, opts)
    opts = opts or {}
    -- Texts can be overridden per call (defaults keep the sync wording)
    local progress_text = opts.progress_text or _("Synchronizing...")
    local error_text = opts.error_text or _("Problem synching")

    local InfoMessage = require("ui/widget/infomessage")
    local ConfirmBox = require("ui/widget/confirmbox")
    local NetworkMgr = require("ui/network/manager")

    -- Scripts are only available on e-ink devices, not on Android
    if Device:isAndroid() then
        UIManager:show(InfoMessage:new{ text = _("Not supported on Android") })
        return false
    end

    local server = G_reader_settings:readSetting("rsync_server") or "192.168.50.252"
    local port = G_reader_settings:readSetting("rsync_port") or ""
    local paths = getPlatformPaths()

    -- Make sure we are online before running rsync
    if not NetworkMgr:isWifiOn() then
        NetworkMgr:turnOnWifiAndWaitForConnection()
    end

    -- Build the command line
    local script = paths.scripts_dir .. "/" .. script_name
    local cmd = string.format("%s %s %s", script, server, port)
    if paths.cd_first then
        cmd = string.format("cd %s && %s", paths.scripts_dir, cmd)
    end
    -- Capture stderr too, and append the real exit code to the output
    cmd = string.format('(%s) 2>&1; echo "EXIT:$?"', cmd)

    -- Show progress so the UI doesn't look frozen while the script runs
    local syncing = InfoMessage:new{ text = progress_text, face = Font:getFace("myfont") }
    UIManager:show(syncing)
    UIManager:forceRePaint()

    local p = io.popen(cmd)
    if not p then
        UIManager:close(syncing)
        UIManager:show(InfoMessage:new{ text = _("Could not run sync script") })
        return false
    end
    local output = p:read("*a")
    p:close()
    UIManager:close(syncing)

    -- Split the exit code marker from the script's actual output
    local code = tonumber(output:match("EXIT:(%d+)%s*$"))
    local clean = output:gsub("EXIT:%d+%s*$", "")

    -- Failure: non-zero exit code, or known error strings in the output
    if code ~= 0 or clean:find("Problem") or clean:find("not connected") then
        UIManager:show(InfoMessage:new{
            text = error_text .. "\n" .. clean,
            face = Font:getFace("myfont"),
        })
        return false
    end

    if opts.ask_restart then
        -- Show the output and the restart question in a single dialog
        -- so they can't cover each other
        local confirm_box = ConfirmBox:new{
            dismissable = false,
            text = clean .. "\n\n" .. _("KOReader needs to be restarted."),
            ok_text = Device:canRestart() and _("Restart") or _("Quit"),
            cancel_text = _("No need to restart"),
            flash_yes = true,
            flash_no = opts.flash_no,
            ok_callback = function()
                restartKOReader(paths, confirm_box)
            end,
            cancel_callback = function()
                -- Optional hook, e.g. refresh the library instead of restarting
                if opts.on_no_restart then
                    opts.on_no_restart(paths)
                end
            end,
        }

        UIManager:show(confirm_box)
    else
        -- Nothing to restart: just show the script output
        UIManager:show(InfoMessage:new{
            text = clean,
            face = Font:getFace("myfont"),
        })
    end
    return true
end

function PageTextInfo:onSynchronizeCode()
    runSyncScript("syncKOReaderCode.sh", { ask_restart = true })
end

function PageTextInfo:onPullConfig()
    runSyncScript("pullConfig.sh", { ask_restart = true })
    -- Regenerate stats if enabled (runs regardless of the pull result, as in the original)
    if G_reader_settings:isTrue("top_manager_infmandhistory") then
        require("util").generateStats()
    end
end

function PageTextInfo:onPushConfig()
    -- Pushing config to the server doesn't affect the local install, so no restart prompt
    runSyncScript("pushConfig.sh")
end

function PageTextInfo:onGetLastPushingConfig()
    -- Read-only query: no restart prompt, custom progress/error texts
    runSyncScript("getLastPushing.sh", {
        progress_text = _("Checking last push..."),
        error_text = _("Could not get last push info"),
    })
end

function PageTextInfo:onSyncBooks()
    runSyncScript("syncBooks.sh", {
        ask_restart = true,
        flash_no = true,
        on_no_restart = refreshAfterBookSync,
    })
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
        if self.ui and self.ui.bookends and self.ui.bookends.enabled then return end
        local show_double_bar = G_reader_settings:isTrue("show_double_bar")
        G_reader_settings:saveSetting("show_double_bar", not show_double_bar)
        require("apps/reader/modules/doublebar").is_enabled = not show_double_bar
        self.view.doublebar:toggleBar()
    end
    return UIManager:setDirty(self.view.dialog, "ui")
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
    local db_conn = SQ3.open(DataStorage:getSettingsDir() .. "/bookinfo_cache.sqlite3")
    db_conn:set_busy_timeout(5000)


    local res
    local special_cover = nil
    if not filepath:match("✪ Collections") and not filepath:match(" Metadata") then
            local query = string.format([[
                SELECT directory, filename FROM bookinfo
                WHERE directory = '%s/' AND has_cover = 'Y'
                ORDER BY filename ASC LIMIT 4;
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

function PageTextInfo:onToggleDebugVerbose()
    if G_reader_settings:isTrue("debug_verbose") then
        dbg:setVerbose(false)
        dbg:turnOff()
        G_reader_settings:makeFalse("debug_verbose")
        G_reader_settings:makeFalse("debug")
        UIManager:askForRestart(_("Verbose logging is now Off. Restart to apply changes."))
    else
        dbg:turnOn()
        dbg:setVerbose(true)
        G_reader_settings:makeTrue("debug")
        G_reader_settings:makeTrue("debug_verbose")
        UIManager:askForRestart(_("Verbose logging is now On. Restart to apply changes."))
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

function PageTextInfo:onCrashLogToggled(enable)
    if enable == nil then
        -- no value given (e.g. from an action): flip the saved flag
        enable = not G_reader_settings:isTrue("crashlog_enabled")
        G_reader_settings:saveSetting("crashlog_enabled", enable)
        G_reader_settings:flush()
    end
    CrashLog.setEnabled(enable)
    return true
end

return PageTextInfo
