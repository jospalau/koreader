local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local DocSettings = require("docsettings")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local ReadCollection = require("readcollection")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen
local Utf8Proc = require("ffi/utf8proc")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local Topbar = require("apps/reader/modules/topbar")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local T = require("ffi/util").template

local FileManagerHistory = WidgetContainer:extend{
    hist_menu_title = _("History"),
}

local filter_text = {
    all       = C_("Book status filter", "All"),
    reading   = C_("Book status filter", "Reading"),
    abandoned = C_("Book status filter", "On hold"),
    complete  = C_("Book status filter", "Finished"),
    deleted   = C_("Book status filter", "Deleted"),
    mbr       = C_("Book status filter", "MBR"),
    tbr       = C_("Book status filter", "TBR"),
}

function FileManagerHistory:init()
    self.ui.menu:registerToMainMenu(self)
end

function FileManagerHistory:addToMainMenu(menu_items)
    menu_items.history = {
        text = self.hist_menu_title,
        callback = function()
            self:onShowHist()
        end,
    }
end

function FileManagerHistory:fetchStatuses(count)
    for _, v in ipairs(require("readhistory").hist) do
        local status
        if v.dim then -- deleted file
            status = "deleted"
        elseif v.file == (self.ui.document and self.ui.document.file) then -- currently opened file
            status = self.ui.doc_settings:readSetting("summary").status
        else
            status = filemanagerutil.getStatus(v.file)
        end
        if not filter_text[status] then
            status = "reading"
        end
        if count then
            self.count[status] = self.count[status] + 1
        end
        v.status = status
    end
    self.statuses_fetched = true
end

function FileManagerHistory:updateItemTable()
    self.count = { all = #require("readhistory").hist,
        reading = 0, abandoned = 0, complete = 0, deleted = 0, mbr = 0, tbr = 0,}
    local item_table = {}
    for _, v in ipairs(require("readhistory").hist) do
        if self:isItemMatch(v) then
            v.mandatory_dim = (self.is_frozen and v.status == "complete") and true or nil
            table.insert(item_table, v)
        end
        if self.statuses_fetched then
            self.count[v.status] = self.count[v.status] + 1
        end
    end
    local subtitle = ""
    if self.search_string then
        subtitle = T(_("Search results (%1)"), #item_table)
    elseif self.selected_colections then
        subtitle = T(_("Filtered by collections (%1)"), #item_table)
    elseif self.filter ~= "all" then
        subtitle = T(_("Status: %1 (%2)"), filter_text[self.filter]:lower(), #item_table)
    end
    self.hist_menu:switchItemTable(nil, item_table, -1, nil, subtitle)
end

function FileManagerHistory:isItemMatch(item)
    if self.search_string then
        local filename = self.case_sensitive and item.text or Utf8Proc.lowercase(util.fixUtf8(item.text, "?"))
        if not filename:find(self.search_string) then
            local book_props
            if self.ui.coverbrowser then
                book_props = self.ui.coverbrowser:getBookInfo(item.file)
            end
            if not book_props then
                book_props = self.ui.bookinfo.getDocProps(item.file, nil, true) -- do not open the document
            end
            if not self.ui.bookinfo:findInProps(book_props, self.search_string, self.case_sensitive) then
                return false
            end
        end
    end
    if self.selected_colections then
        for name in pairs(self.selected_colections) do
            if not ReadCollection:isFileInCollection(item.file, name) then
                return false
            end
        end
    end
    return self.filter == "all" or item.status == self.filter
end

function FileManagerHistory:onSetDimensions(dimen)
    self.dimen = dimen
end

function FileManagerHistory:onMenuChoice(item)
    if self.ui.document then
        if self.ui.document.file ~= item.file then
            self.ui:switchDocument(item.file)
        end
    else
        self.ui:openFile(item.file)
    end
end

function FileManagerHistory:onMenuHold(item)
    local file = item.file
    self.histfile_dialog = nil
    self.book_props = self.ui.coverbrowser and self.ui.coverbrowser:getBookInfo(file)

    local function close_dialog_callback()
        UIManager:close(self.histfile_dialog)
    end
    local function close_dialog_menu_callback()
        UIManager:close(self.histfile_dialog)
        self._manager.hist_menu.close_callback()
    end
    local function close_dialog_update_callback()
        UIManager:close(self.histfile_dialog)
        if self._manager.filter ~= "all" or self._manager.is_frozen then
            self._manager:fetchStatuses(false)
        else
            self._manager.statuses_fetched = false
        end
        self._manager:updateItemTable()
        self._manager.files_updated = true -- sidecar folder may be created/deleted
    end
    local is_currently_opened = file == (self.ui.document and self.ui.document.file)

    local buttons = {}
    local doc_settings_or_file
    if is_currently_opened then
        doc_settings_or_file = self.ui.doc_settings
        if not self.book_props then
            self.book_props = self.ui.doc_props
            self.book_props.has_cover = true
        end
    else
        if DocSettings:hasSidecarFile(file) then
            doc_settings_or_file = DocSettings:open(file)
            if not self.book_props then
                local props = doc_settings_or_file:readSetting("doc_props")
                self.book_props = FileManagerBookInfo.extendProps(props, file)
                self.book_props.has_cover = true
            end
        else
            doc_settings_or_file = file
        end
    end
    if not item.dim then
        table.insert(buttons, filemanagerutil.genStatusButtonsRow(doc_settings_or_file, close_dialog_update_callback))
        table.insert(buttons, {}) -- separator
    end
    table.insert(buttons, {
        filemanagerutil.genResetSettingsButton(doc_settings_or_file, close_dialog_update_callback, is_currently_opened),
        self._manager.ui.collections:genAddToCollectionButton(file, close_dialog_callback, nil, item.dim),
        {
            text = _("Readd to history"),
            callback = function()
                UIManager:close(self.histfile_dialog)
                require("readhistory"):removeItem(item)
                require("readhistory"):addItem(item.file,os.time())
                self._manager:fetchStatuses(false)
                self._manager:updateItemTable()
            end,
        },
    })
    table.insert(buttons, {
        {
            text = _("Delete"),
            enabled = not (item.dim or is_currently_opened),
            callback = function()
                local function post_delete_callback()
                    UIManager:close(self.histfile_dialog)
                    self._manager:updateItemTable()
                    self._manager.files_updated = true
                end
                local FileManager = require("apps/filemanager/filemanager")
                FileManager:showDeleteFileDialog(file, post_delete_callback)
            end,
        },
        {
            text = _("Remove from history"),
            callback = function()
                UIManager:close(self.histfile_dialog)
                require("readhistory"):removeItem(item)
                self._manager:updateItemTable()
            end,
        },
    })
    table.insert(buttons, {
        filemanagerutil.genShowFolderButton(file, close_dialog_menu_callback, item.dim),
        filemanagerutil.genBookInformationButton(file, self.book_props, close_dialog_callback, item.dim),
    })
    table.insert(buttons, {
        filemanagerutil.genBookCoverButton(file, self.book_props, close_dialog_callback, item.dim),
        filemanagerutil.genBookDescriptionButton(file, self.book_props, close_dialog_callback, item.dim),
    })

    self.histfile_dialog = ButtonDialog:new{
        title = BD.filename(item.text),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.histfile_dialog)
    return true
end

-- Can't *actually* name it onSetRotationMode, or it also fires in FM itself ;).
function FileManagerHistory:MenuSetRotationModeHandler(rotation)
    if rotation ~= nil and rotation ~= Screen:getRotationMode() then
        UIManager:close(self._manager.hist_menu)
        -- Also re-layout ReaderView or FileManager itself
        if self._manager.ui.view and self._manager.ui.view.onSetRotationMode then
            self._manager.ui.view:onSetRotationMode(rotation)
        elseif self._manager.ui.onSetRotationMode then
            self._manager.ui:onSetRotationMode(rotation)
        else
            Screen:setRotationMode(rotation)
        end
        self._manager:onShowHist()
    end
    return true
end

function FileManagerHistory:onShowHist(search_info)
    local ReadHistory = require("readhistory")
    ReadHistory.hist = {}
    ReadHistory:reload(true)

    local title = ""
    -- if self.ui.document and self.ui.document.file then
    --     title = self.hist_menu_title .. " " .. self.ui.document._document:getDocumentProps().title
    -- else
    --     title = self.hist_menu_title
    -- end

    self.hist_menu = Menu:new{
        ui = self.ui,
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        is_borderless = true,
        is_popout = false,
        title = self.hist_menu_title,
        -- item and book cover thumbnail dimensions in Mosaic and Detailed list display modes
        -- must be equal in File manager, History and Collection windows to avoid image scaling
        title_bar_fm_style = true,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function() self:showHistDialog() end,
        onMenuChoice = self.onMenuChoice,
        onMenuHold = self.onMenuHold,
        onMultiSwipe = self.onMultiSwipe,
        onSetRotationMode = self.MenuSetRotationModeHandler,
        _manager = self,
    }


    self.hist_menu.topbar = Topbar:new{
        view = nil,
        ui = nil,
        fm = true,
    }

    if search_info then
        self.search_string = search_info.search_string
        self.case_sensitive = search_info.case_sensitive
    else
        self.search_string = nil
        self.selected_colections = nil
    end
    self.filter = G_reader_settings:readSetting("history_filter", "all")

    -- The original filter for books in tbr was new but I have change it to mbr.
    -- Books in the history that are not being read or marked in other status are in tbr
    -- Basically they are in the history and don't have sidecar directory
    if self.filter == "new" then
        self.filter = "mbr"
    end
    self.is_frozen = G_reader_settings:isTrue("history_freeze_finished_books")
    if self.filter ~= "all" or self.is_frozen then
        self:fetchStatuses(false)
    end
    self:updateItemTable()
    self.hist_menu.close_callback = function()
        if self.files_updated then -- refresh Filemanager list of files
            if self.ui.file_chooser then
                self.ui.file_chooser:refreshPath()
            end
            self.files_updated = nil
        end
        self.statuses_fetched = nil
        UIManager:close(self.hist_menu)
        self.hist_menu = nil
        G_reader_settings:saveSetting("history_filter", self.filter)
    end
    UIManager:show(self.hist_menu, "flashui")
    return true
end

function FileManagerHistory:onMultiSwipe(arg, ges_ev)
    local Event = require("ui/event")
    if string.find("east north", ges_ev.multiswipe_directions) then
        -- UIManager:broadcastEvent(Event:new("ShowFileSearch", "", function()
        --     self._manager:fetchStatuses(false)
        --     self._manager:updateItemTable()
        -- end))
        UIManager:broadcastEvent(Event:new("ShowFileSearch", ""))
    elseif string.find("west north", ges_ev.multiswipe_directions) then
        -- local callback_func = function(close)
        --     self._manager:fetchStatuses(false)
        --     self._manager:updateItemTable()
        --     if close then
        --         UIManager:broadcastEvent(Event:new("CloseSearchMenu"))
        --     end
        -- end
        -- We pass this anonymous function as a callback so the history can be refreshed in case any status has been updated
        -- We don't need to pass a history variable since we refresh in the event handler the history if it is opened
        UIManager:broadcastEvent(Event:new("ShowFileSearchLists", true, nil, "*.epub"))
    elseif string.find("west north east", ges_ev.multiswipe_directions) then
        self._manager.filter = "all"UIManager:broadcastEvent(Event:new("ShowFileSearchAllCompleted"))
    elseif string.find("east north west", ges_ev.multiswipe_directions) then
        local FileManager = require("apps/filemanager/filemanager")
        -- FileManager:openFile(G_reader_settings:readSetting("home_dir") .. "/Shakespeare, William/Romeo and Juliet - William Shakespeare.epub")
        FileManager:openFile("resources/arthur-conan-doyle_the-hound-of-the-baskervilles.epub")
    elseif string.find("east south west", ges_ev.multiswipe_directions) then
        local FileManager = require("apps/filemanager/filemanager")
        FileManager:openFile("resources/Forthcoming_Books.pdf")
    elseif string.find("east south", ges_ev.multiswipe_directions) then
        self._manager.filter = "all"
        self._manager.search_string = nil
        self._manager.selected_colections = nil
        self._manager:updateItemTable()
    else
        self:onClose()
        -- if self._manager.ui.history.send then
        --     local FileManager = require("apps/filemanager/filemanager")
        --     local dir = util.splitFilePathName(self._manager.ui.history.file)
        --     FileManager:showFiles(dir, self._manager.ui.history.send)
        --     self._manager.ui.history.send = nil
        --     self._manager.ui.history.file = nil
        -- end

        local FileManager = require("apps/filemanager/filemanager")
        -- FileManager.instance:onRefresh()
    end
    return true
end

function FileManagerHistory:fetchStatusesOut(count)
    for _, v in ipairs(require("readhistory").hist) do
        local status
        status = filemanagerutil.getStatus(v.file)
        if not filter_text[status] then
            status = "reading"
        end
        if count then
            self.count[status] = self.count[status] + 1
        end
        v.status = status
    end
    self.statuses_fetched = true
end

function FileManagerHistory:onMenuSelect(item)
    local FileManager = require("apps/filemanager/filemanager")

    FileManager:openFile(item.file)
    return true
end

function FileManagerHistory:onShowHistMBR()
    local ReadHistory = require("readhistory")
    -- ReadHistory.hist = {}
    -- ReadHistory:reload(true)
    self.hist_menu = Menu:new{
        ui = self.ui,
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        is_borderless = true,
        is_popout = false,
        title = "MBR",
        -- item and book cover thumbnail dimensions in Mosaic and Detailed list display modes
        -- must be equal in File manager, History and Collection windows to avoid image scaling
        onMenuChoice = self.onMenuSelect,
        _manager = self,
    }

    self.filter = "mbr"
    self:fetchStatusesOut(false)
    self:updateItemTable()
    self.hist_menu.close_callback = function()
        if self.files_updated then -- refresh Filemanager list of files
            if self.ui.file_chooser then
                self.ui.file_chooser:refreshPath()
            end
            self.files_updated = nil
        end
        self.statuses_fetched = nil
        UIManager:close(self.hist_menu)
        self.hist_menu = nil
    end
    UIManager:show(self.hist_menu)
    return true
end

function FileManagerHistory:onShowHistTBR()
    local ReadHistory = require("readhistory")
    -- ReadHistory.hist = {}
    -- ReadHistory:reload(true)
    self.hist_menu = Menu:new{
        ui = self.ui,
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        is_borderless = true,
        is_popout = false,
        title = "TBR",
        -- item and book cover thumbnail dimensions in Mosaic and Detailed list display modes
        -- must be equal in File manager, History and Collection windows to avoid image scaling
        onMenuChoice = self.onMenuSelect,
        _manager = self,
    }

    self.filter = "tbr"
    self:fetchStatusesOut(false)
    self:updateItemTable()
    self.hist_menu.close_callback = function()
        if self.files_updated then -- refresh Filemanager list of files
            if self.ui.file_chooser then
                self.ui.file_chooser:refreshPath()
            end
            self.files_updated = nil
        end
        self.statuses_fetched = nil
        UIManager:close(self.hist_menu)
        self.hist_menu = nil
    end
    UIManager:show(self.hist_menu)
    return true
end
function FileManagerHistory:showHistDialog()
    if not self.statuses_fetched then
        self:fetchStatuses(true)
    end

    local hist_dialog
    local buttons = {}
    local function genFilterButton(filter)
        return {
            text = T(_("%1 (%2)"), filter_text[filter], self.count[filter]),
            callback = function()
                UIManager:close(hist_dialog)
                self.filter = filter
                if filter == "all" then -- reset all filters
                    self.search_string = nil
                    self.selected_colections = nil
                end
                self:updateItemTable()
            end,
        }
    end
    table.insert(buttons, {
        genFilterButton("all"),
        genFilterButton("mbr"),
        genFilterButton("deleted"),
    })
    table.insert(buttons, {
        genFilterButton("reading"),
        genFilterButton("abandoned"),
        genFilterButton("tbr"),
        -- genFilterButton("complete"),
    })
    table.insert(buttons, {
        {
            text = _("Filter by collections"),
            callback = function()
                UIManager:close(hist_dialog)
                local caller_callback = function()
                    self.selected_colections = self.ui.collections.selected_colections
                    self:updateItemTable()
                end
                self.ui.collections:onShowCollList({}, caller_callback, true) -- do not select any, no dialog to apply
            end,
        },
    })
    table.insert(buttons, {
        {
            text = _("Search in filename and book metadata"),
            callback = function()
                UIManager:close(hist_dialog)
                self:onSearchHistory()
            end,
        },
    })
    table.insert(buttons, {
        {
            text = _("Open random MBR file"),
            callback = function()
                self:onOpenRandomFav(hist_dialog)
            end,
        },
    })
    if self.count.deleted > 0 then
        table.insert(buttons, {}) -- separator
        table.insert(buttons, {
            {
                text = _("Clear history of deleted files"),
                callback = function()
                    local confirmbox = ConfirmBox:new{
                        text = _("Clear history of deleted files?"),
                        ok_text = _("Clear"),
                        ok_callback = function()
                            UIManager:close(hist_dialog)
                            require("readhistory"):clearMissing()
                            self:updateItemTable()
                        end,
                    }
                    UIManager:show(confirmbox)
                end,
            },
        })
    end
    hist_dialog = ButtonDialog:new{
        title = _("Filter by book status"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(hist_dialog)
end

function FileManagerHistory:onOpenRandomFav(hist_dialog)

    local UIManager = require("ui/uimanager")
    local Notification = require("ui/widget/notification")
    if self.filter ~= "mbr" then
        UIManager:show(Notification:new{
            text = _("Only allowed in MBR view"),
        })
        return
    end
    if require("apps/reader/readerui").instance then
        UIManager:show(Notification:new{
            text = _("Only allowed in File Mananager mode"),
        })
        return
    end


    local ReadHistory = require("readhistory")
    local mbr_list = {}
    -- ReadHistory.hist = {}
    -- ReadHistory:reload(true)
    for _, v in ipairs(require("readhistory").hist) do
        -- MBR books are in the history file but dont;t have sidecard directory
        -- local status = filemanagerutil.getStatus(v.file)
        if not DocSettings:hasSidecarFile(v.file) then
            table.insert(mbr_list, v)
        end
    end


    if #mbr_list == 0 then
        UIManager:show(Notification:new{
            text = _("No books in the mbr list"),
        })
        return
    end
    local i = 1
    local file_name = nil
    local random_fav = math.random(1, #mbr_list)
    for _, v in ipairs(mbr_list) do
        if i == random_fav then
            file_name = v.file
            break
        end
        i = i + 1
    end
    UIManager:close(hist_dialog)
    UIManager:show(Notification:new{
        text = _(file_name),
    })
    local ReaderUI = require("apps/reader/readerui")
    ReaderUI:showReader(file_name)
end

function FileManagerHistory:onSearchHistory()
    local search_dialog, check_button_case
    search_dialog = InputDialog:new{
        title = _("Enter text to search history for"),
        input = self.search_string,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(search_dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local search_string = search_dialog:getInputText()
                        if search_string ~= "" then
                            UIManager:close(search_dialog)
                            self.search_string = self.case_sensitive and search_string or search_string:lower()
                            if self.hist_menu then -- called from History
                                self:updateItemTable()
                            else -- called by Dispatcher
                                local search_info = {
                                    search_string = self.search_string,
                                    case_sensitive = self.case_sensitive,
                                }
                                self:onShowHist(search_info)
                            end
                        end
                    end,
                },
            },
        },
    }
    check_button_case = CheckButton:new{
        text = _("Case sensitive"),
        checked = self.case_sensitive,
        parent = search_dialog,
        callback = function()
            self.case_sensitive = check_button_case.checked
        end,
    }
    search_dialog:addWidget(check_button_case)
    UIManager:show(search_dialog)
    search_dialog:onShowKeyboard()
    return true
end

function FileManagerHistory:onBookMetadataChanged()
    if self.hist_menu then
        self.hist_menu:updateItems()
    end
end

return FileManagerHistory
