local BD = require("ui/bidi")
local BookList = require("ui/widget/booklist")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local InputDialog = require("ui/widget/inputdialog")
local ReadCollection = require("readcollection")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local Topbar = require("apps/reader/modules/topbar")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local FileManagerHistory = WidgetContainer:extend{
    title = _("Reading Planner & Tracker"),
}

function FileManagerHistory:init()
    self.calibre_data = util.loadCalibreData()
    self.ui.menu:registerToMainMenu(self)
end

function FileManagerHistory:addToMainMenu(menu_items)
    menu_items.history = {
        text = self.title,
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
            status = BookList.getBookStatus(v.file)
        end
        if count then
            self.count[status] = self.count[status] + 1
        end
        v.status = status
    end
    self.statuses_fetched = true
end

function FileManagerHistory:refreshFileManager()
    if self.files_updated then
        if self.ui.file_chooser then
            self.ui.file_chooser:refreshPath()
        end
        self.files_updated = nil
    end
end

function FileManagerHistory:onShowHist(search_info)
    -- This may be hijacked by CoverBrowser plugin and needs to be known as booklist_menu.
    self.booklist_menu = BookList:new{
        name = "history",
        title = "Reading Planner & Tracker",
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function() self:showHistDialog() end,
        onMenuChoice = self.onMenuChoice,
        onMenuHold = self.onMenuHold,
        onMultiSwipe = self.onMultiSwipe,
        onTap = self.onTap,
        onDoubleTapBottomLeft = self.onDoubleTapBottomLeft,
        onDoubleTapBottomRight = self.onDoubleTapBottomRight,
        ui = self.ui,
        _manager = self,
        _recreate_func = function() self:onShowHist(search_info) end,
        search_callback = function(search_string)
            self.search_string = search_string
            self:onSearchHistory()
        end,
    }
    self.booklist_menu.disable_double_tap = false

    self.booklist_menu.topbar = Topbar:new{
        view = nil,
        ui = nil,
        fm = true,
        history = true
    }
    self.booklist_menu.close_callback = function()
        self:refreshFileManager()
        UIManager:close(self.booklist_menu)
        self.booklist_menu = nil
        self.statuses_fetched = nil
        G_reader_settings:saveSetting("history_filter", self.filter)
    end

    if search_info then
        self.search_string = search_info.search_string
        self.case_sensitive = search_info.case_sensitive
    else
        self.search_string = nil
        self.selected_collections = nil
    end
    self.filter = G_reader_settings:readSetting("history_filter", "all")
    self.is_frozen = G_reader_settings:isTrue("history_freeze_finished_books")
    if self.filter ~= "all" or self.is_frozen then
        self:fetchStatuses(false)
    end
    self:updateItemTable()
    UIManager:show(self.booklist_menu)
    return true
end

function FileManagerHistory:updateItemTable()
    self.count = { all = #require("readhistory").hist,
        reading = 0, abandoned = 0, complete = 0, deleted = 0, mbr = 0, tbr = 0,}
    local item_table = {}
    for _, v in ipairs(require("readhistory").hist) do
        if self:isItemMatch(v) then
            local item = util.tableDeepCopy(v)
            if item.select_enabled and ReadCollection:isFileInCollections(item.file) then
                item.mandatory = "☆ " .. item.mandatory
            end
            if self.is_frozen and item.status == "complete" then
                item.mandatory_dim = true
            end
            table.insert(item_table, item)
        end
        if self.statuses_fetched then
            self.count[v.status] = self.count[v.status] + 1
        end
    end
    local title, subtitle = self:getBookListTitle(item_table)
    self.booklist_menu:switchItemTable(title, item_table, -1, nil, subtitle)
end

function FileManagerHistory:isItemMatch(item)
    if self.search_string then
        if util.stringSearch(item.text, self.search_string, self.case_sensitive) == 0 then
            local book_props = self.ui.bookinfo:getDocProps(item.file, nil, true) -- do not open the document
            if not self.ui.bookinfo:findInProps(book_props, self.search_string, self.case_sensitive) then
                return false
            end
        end
    end
    if self.selected_collections then
        for name in pairs(self.selected_collections) do
            if not ReadCollection:isFileInCollection(item.file, name) then
                return false
            end
        end
    end
    return self.filter == "all" or item.status == self.filter
end

function FileManagerHistory:getBookListTitle(item_table)
    local title = T(_("Reading Planner & Tracker (%1)"), #item_table)
    local subtitle = ""
    if self.search_string then
        subtitle = T(_("Query: %1"), self.search_string)
    elseif self.selected_collections then
        local collections = {}
        for collection in pairs(self.selected_collections) do
            table.insert(collections, self.ui.collections:getCollectionTitle(collection))
        end
        if #collections == 1 then
            collections = collections[1]
        else
            table.sort(collections)
            collections = table.concat(collections, ", ")
        end
        subtitle = T(_("Collections: %1"), collections)
    -- elseif self.filter ~= "all" then
    else
        subtitle = BookList.getBookStatusString(self.filter, true)
    end
    return title, subtitle
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
    self.file_dialog = nil
    local book_props = self.ui.coverbrowser and self.ui.coverbrowser:getBookInfo(file)

    local function close_dialog_callback()
        UIManager:close(self.file_dialog)
    end
    local function close_dialog_menu_callback()
        UIManager:close(self.file_dialog)
        self.close_callback()
    end
    local function close_dialog_update_callback()
        UIManager:close(self.file_dialog)
        if self._manager.filter ~= "all" or self._manager.is_frozen then
            self._manager:fetchStatuses(false)
        else
            self._manager.statuses_fetched = false
        end
        self._manager:updateItemTable()
        self._manager.files_updated = true
    end
    local function update_callback()
        self._manager:updateItemTable()
    end
    local is_currently_opened = file == (self.ui.document and self.ui.document.file)

    local buttons = {}
    local been_opened, doc_settings_or_file
    if is_currently_opened then
        been_opened = true
        doc_settings_or_file = self.ui.doc_settings
        if not book_props then
            book_props = self.ui.doc_props
            book_props.has_cover = true
        end
    else
        been_opened = BookList.hasBookBeenOpened(file)
        if been_opened then
            doc_settings_or_file = BookList.getDocSettings(file)
            if not book_props then
                local props = doc_settings_or_file:readSetting("doc_props")
                book_props = self.ui.bookinfo.extendProps(props, file)
                book_props.has_cover = true
            end
        else
            doc_settings_or_file = file
        end
    end
    local status = nil
    if BookList.hasBookBeenOpened(file) then
        status = doc_settings_or_file:readSetting("summary", {}).status
    end

    if not item.dim then
        table.insert(buttons, filemanagerutil.genStatusButtonsRow(doc_settings_or_file, close_dialog_update_callback))
        table.insert(buttons, {}) -- separator
    end
    table.insert(buttons, {
        filemanagerutil.genResetSettingsButton(doc_settings_or_file, close_dialog_update_callback, is_currently_opened),
        self._manager.ui.collections:genAddToCollectionButton(file, close_dialog_callback, update_callback, item.dim),
    })
    local left_up = self.ui.history.booklist_menu.display_mode_type == "mosaic" and "Move left" or "Move up"
    local right_down = self.ui.history.booklist_menu.display_mode_type == "mosaic" and "Move right" or "Move down"
    local is_being_read = (self.ui.document and self.ui.document.file and self.ui.document.file == file) and true or false

    table.insert(buttons, {
        {
            text = _(left_up),
            enabled = item.idx and item.idx > 1,

            callback = function()
                UIManager:close(self.file_dialog)
                local ReadHistory = require("readhistory")
                local items = ReadHistory.hist or {}
                local index = item.idx  -- el índice actual del libro en la vista

                if index and index > 1 then
                    -- intercambiar con el anterior
                    local tmp = items[index-1]
                    items[index-1] = items[index]
                    items[index] = tmp

                    -- reasignar la tabla
                    ReadHistory.hist = items

                    -- refrescar vista
                    self._manager:fetchStatuses(false)
                    self._manager:updateItemTable()
                end
            end,
        },
        {
            text = _(right_down),
            enabled = item.idx and require("readhistory").hist and item.idx < #require("readhistory").hist and not is_being_read,
            callback = function()
                UIManager:close(self.file_dialog)
                local ReadHistory = require("readhistory")
                local items = ReadHistory.hist or {}
                local index = item.idx  -- índice actual del libro en la vista

                -- solo continuar si no es el último
                if not index or index >= #items then return end

                -- intercambiar con el siguiente
                local tmp = items[index+1]
                items[index+1] = items[index]
                items[index] = tmp

                -- reasignar la tabla
                ReadHistory.hist = items

                -- refrescar vista
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
                local FileManager = require("apps/filemanager/filemanager")
                FileManager:showDeleteFileDialog(file, close_dialog_update_callback)
            end,
        },
        {
            text = _("Remove from history"),
            enabled = (status ~= "tbr" and not is_being_read) or not require("util").fileExists(file),
            callback = function()
                UIManager:close(self.file_dialog)
                -- The item's idx field is tied to the current *view*, so we can only pass it as-is when there's no filtering *at all* involved.
                local index = item.idx
                if self._manager.search_string or self._manager.selected_collections or self._manager.filter ~= "all" then
                    index = nil
                end
                require("readhistory"):removeItem(item, index)
                self._manager:updateItemTable()
                if _G.all_files[item.file]
                and _G.all_files[item.file].status == "mbr" then
                    _G.all_files[file].status = ""
                    _G.all_files[item.file].last_modified_year = 0
                    _G.all_files[item.file].last_modified_month = 0
                    _G.all_files[item.file].last_modified_day = 0
                    local util = require("util")
                    util.generateStats()
                end
            end,
        },
    })
    if been_opened then
        local annotations = doc_settings_or_file:readSetting("annotations")
        if annotations and #annotations > 0 then
            table.insert(buttons, {
                self._manager.ui.collections:genExportHighlightsButton({ [file] = true }, close_dialog_callback),
                self._manager.ui.collections:genBookmarkBrowserButton({ [file] = true }, close_dialog_callback),
            })
        end
    end
    table.insert(buttons, {
        filemanagerutil.genShowFolderButton(file, close_dialog_menu_callback, item.dim),
        filemanagerutil.genBookInformationButton(doc_settings_or_file, book_props, close_dialog_callback, item.dim),
    })
    table.insert(buttons, {
        filemanagerutil.genBookCoverButton(file, book_props, close_dialog_callback, item.dim),
        filemanagerutil.genBookDescriptionButton(file, book_props, close_dialog_callback, item.dim),
    })

    if self._manager.file_dialog_added_buttons ~= nil then
        for _, row_func in ipairs(self._manager.file_dialog_added_buttons) do
            local row = row_func(file, true, book_props)
            if row ~= nil then
                table.insert(buttons, row)
            end
        end
    end

    local title = BD.filename(item.text):gsub(".epub","")
    if self.calibre_data[item.text]
        and self.calibre_data[item.text]["pubdate"]
        and self.calibre_data[item.text]["words"]
        and self.calibre_data[item.text]["grrating"]
        and self.calibre_data[item.text]["grvotes"] then
            title = title .. ", " ..  self.calibre_data[item.text]["pubdate"]:sub(1, 4) ..
            " - " .. self.calibre_data[item.text]["grrating"] .. "★ ("
            .. self.calibre_data[item.text]["grvotes"] .. ") - "
            .. tostring(math.floor(self.calibre_data[item.text]["words"]/1000)) .."kw"
    end

    self.file_dialog = ButtonDialog:new{
        title = title,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.file_dialog)
    return true
end

function FileManagerHistory.getMenuInstance()
    local ui = require("apps/filemanager/filemanager").instance or require("apps/reader/readerui").instance
    return ui.history.booklist_menu
end

function FileManagerHistory:onMultiSwipe(arg, ges_ev)
    if require("apps/reader/readerui").instance and util.getFileNameSuffix(require("apps/reader/readerui").instance.document.file) ~= "epub" then return true end
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
        local Device = require("device")
        local Screen = Device.screen
        if not Device:isEmulator() then
            UIManager:broadcastEvent(Event:new("ShowFileSearchLists", true, nil, "*.epub"))
        else
            -- local CanvasContext = require("document/canvascontext")
            -- local _view_mode = G_defaults:readSetting("DCREREADER_VIEW_MODE") == "scroll" and 0 or 1 -- and self.SCROLL_VIEW_MODE or self.PAGE_VIEW_MODE
            -- local cre = require("document/credocument"):engineInit()
            -- local ok, _document = pcall(cre.newDocView, CanvasContext:getWidth(), CanvasContext:getHeight(), _view_mode)
            -- if not ok then
            --     error(_document)  -- will contain error message
            -- end

            -- _document:loadDocument("/home/jospalau/save/Addison, Katherine/The Goblin Emperor - Addison, Katherine.epub")
            -- _document:renderDocument()
            local DocumentRegistry = require("document/documentregistry")

            local files = util.getListAll()

            local dump = require("dump")
            -- print(dump(files))

            for file, _ in pairs(files) do
                print(file)
                local document = DocumentRegistry:openDocument(file)
                if document and document.loadDocument then
                    if document:loadDocument() then
                        -- print("si")
                        local time = require("ui/time")
                        local start_time = time.now()
                        document:enablePartialRerendering(false)
                        -- document:setEmbeddedStyleSheet(0)
                        document:setStyleSheet("./data/epub.css", "") -- Empty tweaks

                        document._document:invalidateCacheFile()
                        -- Por defecto coge los estilos de def_stylesheet del fuente lvdocview.cpp
                        document._document:renderDocument()
                        print(string.format("  rendering took %.3f seconds", time.to_s(time.since(start_time))))
                        local pages = document:getPageCount()
                        print(pages)
                        -- local res = document._document:findAllText("en", true, 5, 5000, 0, 0)
                        -- print(dump(res))
                        if pages >= 100 then
                            document._document:gotoPage(100)
                        else
                            document._document:gotoPage(50)
                        end
                        local res = document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(), false, false)
                        local text_properties=""
                        if res and res.pos1 ~= ".0" then
                            -- print(dump(res.text))
                            local name, name2, height, unitheight, height2, unitheight2, indent, unitindent, indent2, unitindent2, margin, unitmargin, margin2, unitmargin2, alignment, alignment2, fontsize, unitfontsize, fontsize2, unitfontsize2 = document:getHeight(res.pos1)

                            if name == "" and res.pos0 ~= ".0"  then
                                local name, name2, height, unitheight, height2, unitheight2, indent, unitindent, indent2, unitindent2, margin, unitmargin, margin2, unitmargin2, alignment, alignment2, fontsize, unitfontsize, fontsize2, unitfontsize2 = document:getHeight(res.pos0)
                            end

                            if unitheight == "Font" then
                                height = height * document.configurable.line_spacing/100
                                height2 = height2 * document.configurable.line_spacing/100
                            end

                            if name ~= "" then
                                local Math = require("optmath")
                                height = Math.round(height*100)/100 .. unitheight
                                height2 = Math.round(height2*100)/100 .. unitheight2
                                indent = Math.round(indent*100)/100 .. unitindent
                                indent2 = Math.round(indent2*100)/100 .. unitindent2
                                margin =  Math.round(margin*100)/100 .. unitmargin
                                margin2 = Math.round(margin2*100)/100 .. unitmargin2
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
                            print(text_properties)
                        end
                    end
                else
                    print("Problem loading document")
                end
                document:close()
                collectgarbage()
            end
        end
    elseif string.find("west north east", ges_ev.multiswipe_directions) then
        self._manager.filter = "all"
        UIManager:broadcastEvent(Event:new("ShowFileSearchAllCompleted"))
    -- elseif string.find("east north west", ges_ev.multiswipe_directions) and require("apps/reader/readerui").instance == nil then
    elseif string.find("north west", ges_ev.multiswipe_directions) then
        -- local FileManager = require("apps/filemanager/filemanager")
        -- -- FileManager:openFile(G_reader_settings:readSetting("home_dir") .. "/Shakespeare, William/Romeo and Juliet - William Shakespeare.epub")
        -- FileManager:openFile("resources/arthur-conan-doyle_the-hound-of-the-baskervilles.epub")

        local ReadCollection = require("readcollection")
        local files = ReadCollection:OpenRandomFav()

        if not files then
            local UIManager = require("ui/uimanager")
            local Notification = require("ui/widget/notification")
            UIManager:show(Notification:new{
                text = _("No MBR collection or no books in collection"),
            })
            return
        end
        UIManager:broadcastEvent(Event:new("ShowFileSearchLists", true, files))
    elseif string.find("east south", ges_ev.multiswipe_directions) then
        self._manager.filter = "all"
        self._manager.search_string = nil
        self._manager.selected_colections = nil
        self._manager:updateItemTable()
        self._manager.booklist_menu:onGotoPage(1)
        local UIManager = require("ui/uimanager")
        local Notification = require("ui/widget/notification")
        UIManager:show(Notification:new{
            text = _("Showing all books in history."),
        })
    -- elseif string.find("east south west", ges_ev.multiswipe_directions) and require("apps/reader/readerui").instance == nil then
    --     local FileManager = require("apps/filemanager/filemanager")
    --     FileManager:openFile("resources/Forthcoming_Books.pdf")
    else
        self:onClose()
        if require("apps/reader/readerui").instance then
            self.ui.view.topbar:toggleBar()
            UIManager:setDirty(self.ui.view.topbar, "ui")
        -- else
        --     UIManager:tickAfterNext(function()
        --         UIManager:setDirty(self._manager.file_chooser, "flashui")
        --     end)
        else
            require("apps/filemanager/filemanager").instance.file_chooser:refreshPath()
        end
        -- if self._manager.ui.history.send then
        --     local FileManager = require("apps/filemanager/filemanager")
        --     local dir = util.splitFilePathName(self._manager.ui.history.file)
        --     FileManager:showFiles(dir, self._manager.ui.history.send)
        --     self._manager.ui.history.send = nil
        --     self._manager.ui.history.file = nil
        -- end

        -- local FileManager = require("apps/filemanager/filemanager")
        -- FileManager.instance:onRefresh()
    end
    return true
end

function FileManagerHistory:onTap(arg, ges_ev)
    self._manager.ui.statistics:onShowCalendarView()
    return true
end


function FileManagerHistory:onDoubleTapBottomLeft(arg, ges_ev)
    --local FileManager = require("apps/filemanager/filemanager")
    --FileManager:openFile("resources/arthur-conan-doyle_the-hound-of-the-baskervilles.epub")
    return true
end


function FileManagerHistory:onDoubleTapBottomRight(arg, ges_ev)
    -- -- This would be top the left menu callback function for collection widget if used
    -- local caller_callback = function()
    --     self.ui.history:fetchStatuses(false)
    --     self.ui.history:updateItemTable()
    -- end
    -- --self._manager.ui.collections:onShowCollList(nil, caller_callback, true)
    self._manager.ui.collections:onShowCollList()
    return true
end

function FileManagerHistory:fetchStatusesOut(count)
    local BookList = require("ui/widget/booklist")
    for _, v in ipairs(require("readhistory").hist) do
        local status
        status = BookList.getBookStatus(v.file)
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
    self.booklist_menu = BookList:new{
        name = "history",
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
    self.booklist_menu.close_callback = function()
        if self.files_updated then -- refresh Filemanager list of files
            if self.ui.file_chooser then
                self.ui.file_chooser:refreshPath()
            end
            self.files_updated = nil
        end
        self.statuses_fetched = nil
        UIManager:close(self.booklist_menu)
        self.booklist_menu = nil
    end
    UIManager:show(self.booklist_menu)
    return true
end

function FileManagerHistory:onShowHistTBR()
    local ReadHistory = require("readhistory")
    -- ReadHistory.hist = {}
    -- ReadHistory:reload(true)
    self.booklist_menu = BookList:new{
        name = "history",
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
    self.booklist_menu.close_callback = function()
        if self.files_updated then -- refresh Filemanager list of files
            if self.ui.file_chooser then
                self.ui.file_chooser:refreshPath()
            end
            self.files_updated = nil
        end
        self.statuses_fetched = nil
        UIManager:close(self.booklist_menu)
        self.booklist_menu = nil
    end
    UIManager:show(self.booklist_menu)
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
            text = T(_("%1 (%2)"), BookList.getBookStatusString(filter), self.count[filter]),
            callback = function()
                UIManager:close(hist_dialog)
                self.filter = filter
                if filter == "all" then -- reset all filters
                    self.search_string = nil
                    self.selected_collections = nil
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
                local caller_callback = function(selected_collections)
                    self.selected_collections = selected_collections
                    self:updateItemTable()
                end
                self.ui.collections:onShowCollList(self.selected_collections or {}, caller_callback, true) -- no dialog to apply
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
            text = _("Sort history by status"),
            callback = function()
                UIManager:close(hist_dialog)
                require("apps/filemanager/filemanagerhistory"):sortHistoryByStatus()
                self:fetchStatuses(false)
                self:updateItemTable()
            end,
        },
    })
    table.insert(buttons, {
        {
            text = _("Open random MBR file"),
            callback = function()
                self:onOpenRandomFav(hist_dialog)
            end,
        }
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

    local Notification = require("ui/widget/notification")
    --[[
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
    ]]

    local ReadHistory = require("readhistory")
    local mbr_list = {}
    -- ReadHistory.hist = {}
    -- ReadHistory:reload(true)
    for _, v in ipairs(require("readhistory").hist) do
        -- MBR books are in the history file but dont;t have sidecard directory
        -- local status = filemanagerutil.getStatus(v.file)
        if not require("docsettings"):hasSidecarFile(v.file) then
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
                            if self.booklist_menu then -- called from History
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
    if self.booklist_menu then
        self.booklist_menu:updateItems()
    end
end

function FileManagerHistory:sortHistoryByStatus()
    local ReadHistory = require("readhistory")
    local DocSettings = require("docsettings")

    local items = ReadHistory.hist or {}
    local reading, tbr, mbr, abandoned, others = {}, {}, {}, {}, {}

    for _, entry in ipairs(items) do
        local doc_settings = DocSettings:open(entry.file)
        local summary = doc_settings:readSetting("summary", {})
        local status = summary.status
        --local status = entry.status
        if status == nil then status = "mbr" end
        if status == "reading" then
            table.insert(reading, entry)
        elseif status == "tbr" then
            table.insert(tbr, entry)
        elseif status == "mbr" then
            table.insert(mbr, entry)
        elseif status == "abandoned" then
            table.insert(abandoned, entry)
        else
            table.insert(others, entry)
        end
    end

    local function get_filename(path)
        return path:match("^.+/(.+)$") or path
    end

    local function get_author(path)
        local author = path:match("^.+/(.+)/[^/]+$")
        return author or "Unknown"
    end

    local function get_author(path)
        local author = path:match("^.+/(.+)/[^/]+$")
        return author or "Unknown"
    end

    local function get_filename(path)
        return path:match("^.+/(.+)$") or path
    end

    local function sort_by_file(a, b)
        local author_a = get_author(a.file):lower()
        local author_b = get_author(b.file):lower()

        if author_a == author_b then
            -- Si el autor es el mismo, ordenar por nombre de archivo
            return get_filename(a.file):lower() < get_filename(b.file):lower()
        else
            -- Si no, ordenar por autor
            return author_a < author_b
        end
    end

    --table.sort(reading, sort_by_file)
    -- No need to sort TBR items, to respect custom order
    --table.sort(tbr, sort_by_file)
    table.sort(mbr, sort_by_file)
    table.sort(abandoned, sort_by_file)
    table.sort(others, sort_by_file)

    --[[
    -- No needed
    -- Rebuild the history with consecutive timestamps
    local new_hist = {}
    local next_time = os.time()        -- partir del tiempo actual
    local increment = 1                -- segundos entre libros

    local function insert_with_new_time(list)
        for _, v in ipairs(list) do
            next_time = next_time + increment
            v.time = next_time
            table.insert(new_hist, v)
        end
    end

    insert_with_new_time(reading)
    insert_with_new_time(tbr)
    insert_with_new_time(mbr)
    insert_with_new_time(abandoned)
    insert_with_new_time(others)
    ]]

    local new_hist = {}
    for _, v in ipairs(reading) do table.insert(new_hist, v) end
    for _, v in ipairs(abandoned) do table.insert(new_hist, v) end
    for _, v in ipairs(tbr)     do table.insert(new_hist, v) end
    for _, v in ipairs(mbr)     do table.insert(new_hist, v) end
    for _, v in ipairs(others)  do table.insert(new_hist, v) end  -- al final siempre

    ReadHistory.hist = new_hist
    ReadHistory:_flush()
end

function FileManagerHistory:getTBRPosition(file_path)
    local ReadHistory = require("readhistory")
    -- local DocSettings = require("docsettings")

    local items = ReadHistory.hist or {}
    local tbr_items = {}

    for _, entry in ipairs(items) do
        -- local doc_settings = DocSettings:open(entry.file)
        -- local summary = doc_settings:readSetting("summary", {})
        -- local status = summary.status or "mbr"
        local status = (_G.all_files and _G.all_files[entry.file] and _G.all_files[entry.file].status) and _G.all_files[entry.file].status or ""
        if status == "tbr" then
            table.insert(tbr_items, entry)
        end
    end

    for idx, entry in ipairs(tbr_items) do
        if entry.file == file_path then
            return idx
        end
    end

    return nil
end

return FileManagerHistory
