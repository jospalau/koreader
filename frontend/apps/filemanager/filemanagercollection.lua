local BD = require("ui/bidi")
local BookList = require("ui/widget/booklist")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local ReadCollection = require("readcollection")
local SortWidget = require("ui/widget/sortwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local Topbar = require("apps/reader/modules/topbar")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local T = ffiUtil.template

local FileManagerCollection = WidgetContainer:extend{
    title = _("Collections"),
    title2 = _("Series"),
    default_collection_title = _("All"),
    checkmark = "\u{2713}",
    empty_prop = "\u{0000}" .. _("N/A"), -- sorted first
}

function FileManagerCollection:init()
    self.calibre_data = util.loadCalibreData()
    self.show_mark = G_reader_settings:nilOrTrue("collection_show_mark")
    self.doc_props_cache = {}
    self.updated_collections = {}
    self.ui.menu:registerToMainMenu(self)
end

function FileManagerCollection:addToMainMenu(menu_items)
    menu_items.favorites = {
        text = self.default_collection_title,
        callback = function()
            self:onShowColl()
        end,
    }
    menu_items.collections = {
        text = self.title,
        callback = function()
            self:onShowCollList()
        end,
    }
    menu_items.bookmark_browser = {
        text = _("Bookmark browser"),
        callback = function()
            self:onShowBookmarkBrowser()
        end,
    }
    menu_items.series = {
        text = self.title2,
        callback = function()
            self:onShowSeriesList()
        end,
    }
end

-- collection

function FileManagerCollection:getCollectionTitle(collection_name)
    return collection_name == ReadCollection.default_collection_name
        and self.default_collection_title -- favorites
         or collection_name
end


function FileManagerCollection:getTotalAndRead(collection_name)
    local books = ReadCollection.coll[collection_name]
    local count = 0
    for _ in pairs(books) do
        count = count + 1
    end
    local read = 0
    for book_path, book_table in pairs(books) do
        if _G.all_files[book_path] and _G.all_files[book_path] and _G.all_files[book_path].status == "complete" then
            read = read + 1
        end
    end
    return tostring(read) .. "/" .. tostring(count)
end

function FileManagerCollection:refreshFileManager()
    if self.files_updated then
        if self.ui.file_chooser then
            self.ui.file_chooser:refreshPath()
        end
        self.files_updated = nil
    end
end

function FileManagerCollection:onShowColl(collection_name, series)
    collection_name = collection_name or ReadCollection.default_collection_name
    ReadCollection:updateCollectionFromFolder(collection_name, nil, true)
    -- This may be hijacked by CoverBrowser plugin and needs to be known as booklist_menu.
    self.booklist_menu = BookList:new{
        name = "collections",
        path = collection_name,
        title_bar_left_icon = "appbar.menu",
        title = "Collection",
        onLeftButtonTap = function()
            if self.selected_files then
                self:showSelectModeDialog()
            else
                self:showCollDialog()
            end
        end,
        onLeftButtonHold = function()
            self:toggleSelectMode()
        end,
        onReturn = function()
            self.from_collection_name = self:getCollectionTitle(collection_name)
            self.booklist_menu.close_callback()
            if series == true then
                self:onShowSeriesList()
            else
                self:onShowCollList()
            end
        end,
        onMenuSelect = self.onMenuSelect,
        onMenuHold = self.onMenuHold,
        onMultiSwipe = self.onMultiSwipe,
        onTap = self.onTapBottomRightCollection,
        onDoubleTapBottomRight = self.onDoubleTapBottomRightCollection,
        ui = self.ui,
        _manager = self,
        _recreate_func = function() self:onShowColl(collection_name) end,
        collection_name = collection_name,
        series = series,
        topbar = Topbar:new{
            view = nil,
            ui = nil,
            fm = true,
            collection = true,
        },
        search_callback = function(search_string)
            self:onShowCollectionsSearchDialog(search_string, collection_name)
        end,
    }
    self.booklist_menu.disable_double_tap = false
    table.insert(self.booklist_menu.paths, true) -- enable onReturn button
    self.booklist_menu.close_callback = function()
        self:refreshFileManager()
        UIManager:close(self.booklist_menu)
        self.booklist_menu = nil
        self.match_table = nil
        self.selected_files = nil
    end
    self:setCollate()
    self:updateItemTable()
    self.booklist_menu.initial_collate = G_reader_settings:readSetting("collate")
    self.booklist_menu.initial_reverse_collate_mode = G_reader_settings:readSetting("reverse_collate")
    G_reader_settings:saveSetting("collate", "strcoll")
    G_reader_settings:saveSetting("reverse_collate", nil)
    UIManager:show(self.booklist_menu)

    return true
end

function FileManagerCollection:updateItemTable(item_table, focused_file)
    if item_table == nil then
        item_table = {}
        for _, item in pairs(ReadCollection.coll[self.booklist_menu.path]) do
            if self:isItemMatch(item) then
                local item_tmp = {
                    file      = item.file,
                    text      = item.text,
                    order     = item.order,
                    attr      = item.attr,
                    mandatory = self.mandatory_func and self.mandatory_func(item) or util.getFriendlySize(item.attr.size or 0),
                }
                if self.item_func then
                    self.item_func(item_tmp, self.ui)
                end
                table.insert(item_table, item_tmp)
            end
        end
        if #item_table > 1 then
            table.sort(item_table, self.sorting_func)
        end
    end
    local title, subtitle = self:getBookListTitle(item_table)
    self.booklist_menu:switchItemTable(title, item_table, -1, focused_file and { file = focused_file }, subtitle)
end

function FileManagerCollection:isItemMatch(item)
    if self.match_table then
        if self.match_table.status then
            if self.match_table.status == "mbr" then

                local has_sidecar_file = BookList.hasBookBeenOpened(item.file)
                local in_history =  require("readhistory"):getIndexByFile(item.file)
                if in_history and not has_sidecar_file then
                    return true
                else
                    return false
                end
            else
                if self.match_table.status ~= BookList.getBookStatus(item.file) then
                    return false
                end
            end
        end
        if self.match_table.props then
            local doc_props = self.ui.bookinfo:getDocProps(item.file, nil, true)
            for prop, value in pairs(self.match_table.props) do
                if (doc_props[prop] or self.empty_prop) ~= value then
                    return false
                end
            end
        end
    end
    return true
end

function FileManagerCollection:getBookListTitle(item_table)
    local coll_name = self.booklist_menu.path
    local marker = self.getCollMarker(coll_name)
    local template = marker and "%1 (%2) " .. marker or "%1 (%2)"
    local title = T(template, self:getCollectionTitle(coll_name), self:getTotalAndRead(coll_name))
    local subtitle = ""
    if self.match_table then
        subtitle = {}
        if self.match_table.status then
            local status_string = BookList.getBookStatusString(self.match_table.status, true)
            table.insert(subtitle, "\u{0000}" .. status_string) -- sorted first
        end
        if self.match_table.props then
            for prop, value in pairs(self.match_table.props) do
                table.insert(subtitle, T("%1 %2", self.ui.bookinfo.prop_text[prop], value))
            end
        end
        if #subtitle == 1 then
            subtitle = subtitle[1]
        else
            table.sort(subtitle)
            subtitle = table.concat(subtitle, " | ")
        end
    end
    return title, subtitle
end

function FileManagerCollection:onSetDimensions(dimen)
    self.dimen = dimen
end

function FileManagerCollection:onMenuSelect(item)
    if self._manager.selected_files then
        item.dim = not item.dim and true or nil
        self._manager.selected_files[item.file] = item.dim
        self:updateItems(1, true)
    else
        if self.ui.document then
            if self.ui.document.file ~= item.file then
                if G_reader_settings:isTrue("top_manager_infmandhistory")
                    and item.file
                    and util.getFileNameSuffix(item.file) == "epub"
                    and _G.all_files
                    and _G.all_files[item.file]
                    and (_G.all_files[item.file].status == "mbr"
                        or _G.all_files[item.file].status == "tbr"
                        or _G.all_files[item.file].status == "new"
                        or _G.all_files[item.file].status == "complete") then
                    local MultiConfirmBox = require("ui/widget/multiconfirmbox")
                    local text = ", do you want to open it?"
                    if _G.all_files[item.file].status == "mbr" then
                        text = "Book in MBR" .. text
                    elseif _G.all_files[item.file].status == "tbr" then
                        text = "Book in TBR" .. text
                    elseif _G.all_files[item.file].status == "new" then
                        text = "Book not opened" .. text
                    else
                        text = "Book finished" .. text
                    end
                    local multi_box = MultiConfirmBox:new{
                        text = text,
                        choice1_text = _("Yes"),
                        choice1_callback = function()
                            if self.ui.history.booklist_menu then
                                UIManager:close(self.ui.history.booklist_menu)
                            end
                            filemanagerutil.openFile(self.ui, item.file, self.close_callback)
                        end,
                        choice2_text = _("Do not open it"),
                        choice2_callback = function()
                        end,
                        cancel_callback = function()
                        end,
                    }
                    UIManager:show(multi_box)
                    return true
                else
                    filemanagerutil.openFile(self.ui, item.file, self.close_callback)
                end
            end
        else
            if G_reader_settings:isTrue("top_manager_infmandhistory")
                and item.file
                and util.getFileNameSuffix(item.file) == "epub"
                and _G.all_files
                and _G.all_files[item.file]
                and (_G.all_files[item.file].status == "mbr"
                    or _G.all_files[item.file].status == "tbr"
                    or _G.all_files[item.file].status == "new"
                    or _G.all_files[item.file].status == "complete") then
                local MultiConfirmBox = require("ui/widget/multiconfirmbox")
                local text = ", do you want to open it?"
                if _G.all_files[item.file].status == "mbr" then
                    text = "Book in MBR" .. text
                elseif _G.all_files[item.file].status == "tbr" then
                    text = "Book in TBR" .. text
                elseif _G.all_files[item.file].status == "new" then
                    text = "Book not opened" .. text
                else
                    text = "Book finished" .. text
                end
                local multi_box = MultiConfirmBox:new{
                    text = text,
                    choice1_text = _("Yes"),
                    choice1_callback = function()
                        if self.ui.history.booklist_menu then
                            UIManager:close(self.ui.history.booklist_menu)
                        end
                        filemanagerutil.openFile(self.ui, item.file, self.close_callback)
                    end,
                    choice2_text = _("Do not open it"),
                    choice2_callback = function()
                    end,
                    cancel_callback = function()
                    end,
                }
                UIManager:show(multi_box)
                return true
            else
                filemanagerutil.openFile(self.ui, item.file, self.close_callback)
            end
        end
    end
end

function FileManagerCollection:onMenuHold(item)
    if self._manager.selected_files then
        self._manager:showSelectModeDialog()
        return true
    end

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
    local function close_dialog_menu_callback2()
        if self.ui.history.booklist_menu then
            UIManager:close(self.ui.history.booklist_menu)
        end
        UIManager:close(self.file_dialog)
        self.close_callback()
    end
    local function close_dialog_update_callback()
        UIManager:close(self.file_dialog)
        self._manager:updateItemTable()
        self._manager.files_updated = true
        -- if self.ui and self.ui.history.hist_menu then
        --     --self.ui.history:fetchStatuses(false)
        --     --self.ui.history:updateItemTable()
        --     self.ui.history.restart = true
        -- end
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
    table.insert(buttons, filemanagerutil.genStatusButtonsRow(doc_settings_or_file, close_dialog_update_callback))
    table.insert(buttons, {}) -- separator
    table.insert(buttons, {
        filemanagerutil.genResetSettingsButton(doc_settings_or_file, close_dialog_update_callback, is_currently_opened),
        self._manager:genAddToCollectionButton(file, close_dialog_callback, close_dialog_update_callback),
    })
    if Device:canExecuteScript(file) then
        table.insert(buttons, {
            filemanagerutil.genExecuteScriptButton(file, close_dialog_menu_callback)
        })
    end
    table.insert(buttons, {
        {
            text = _("Delete"),
            enabled = not is_currently_opened,
            callback = function()
                local FileManager = require("apps/filemanager/filemanager")
                FileManager:showDeleteFileDialog(file, close_dialog_update_callback)
            end,
        },
        {
            text = _("Remove from collection"),
            callback = function()
                self._manager.updated_collections[self.path] = true
                ReadCollection:removeItem(file, self.path, true)
                close_dialog_update_callback()
            end,
        },
    })
    if been_opened then
        local annotations = doc_settings_or_file:readSetting("annotations")
        if annotations and #annotations > 0 then
            table.insert(buttons, {
                self._manager:genExportHighlightsButton({ [file] = true }, close_dialog_callback),
                self._manager:genBookmarkBrowserButton({ [file] = true }, close_dialog_callback),
            })
        end
    end
    table.insert(buttons, {
        filemanagerutil.genShowFolderButton(file, close_dialog_menu_callback2),
        filemanagerutil.genBookInformationButton(doc_settings_or_file, book_props, close_dialog_callback),
    })
    table.insert(buttons, {
        filemanagerutil.genBookCoverButton(file, book_props, close_dialog_callback),
        filemanagerutil.genBookDescriptionButton(file, book_props, close_dialog_callback),
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
    if self.calibre_data[item.text] and self.calibre_data[item.text]["pubdate"]
        and self.calibre_data[item.text]["words"]
        and self.calibre_data[item.text]["grrating"]
        and self.calibre_data[item.text]["grvotes"] then
            title = title .. ", " ..  self.calibre_data[item.text]["pubdate"]:sub(1, 4) ..
            " - " .. self.calibre_data[item.text]["grrating"] .. "★ ("  ..
            self.calibre_data[item.text]["grvotes"] .. ") - " ..
            tostring(math.floor(self.calibre_data[item.text]["words"]/1000)) .."kw"
    end
    self.file_dialog = ButtonDialog:new{
        title = title,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.file_dialog)
    return true
end

function FileManagerCollection:onMultiSwipe(arg, ges_ev)
    UIManager:close(self)
    if self.series then
        self._manager.ui.collections:onShowSeriesList()
    else
        self._manager.ui.collections:onShowCollList()
    end
end

function FileManagerCollection.getMenuInstance()
    local ui = require("apps/filemanager/filemanager").instance or require("apps/reader/readerui").instance
    return ui.collections.booklist_menu
end

function FileManagerCollection:toggleSelectMode(rebuild)
    if self.selected_files then
        if rebuild then
            self:updateItemTable()
        else
            for _, item in ipairs(self.booklist_menu.item_table) do
                item.dim = nil
            end
            self.booklist_menu:updateItems(1, true)
        end
        self.booklist_menu:setTitleBarLeftIcon("appbar.menu")
        self.selected_files = nil
    else
        self.booklist_menu:setTitleBarLeftIcon("check")
        self.selected_files = {}
    end
end

function FileManagerCollection:showSelectModeDialog()
    local collection_name = self.booklist_menu.path
    local item_table = self.booklist_menu.item_table
    local select_count = util.tableSize(self.selected_files)
    local actions_enabled = select_count > 0
    local title = actions_enabled and T(N_("1 book selected", "%1 books selected", select_count), select_count)
        or _("No books selected")
    local select_dialog
    local buttons = {
        {
            {
                text = _("Remove from collection"),
                enabled = actions_enabled,
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Remove selected books from collection?"),
                        ok_text = _("Remove"),
                        ok_callback = function()
                            UIManager:close(select_dialog)
                            self.updated_collections[collection_name] = true
                            for file in pairs(self.selected_files) do
                                ReadCollection:removeItem(file, collection_name, true)
                            end
                            self.files_updated = self.show_mark
                            self:toggleSelectMode(true)
                        end,
                    })
                end,
            },
        },
        {
            {
                text = _("Move to collection"),
                enabled = actions_enabled,
                callback = function()
                    UIManager:close(select_dialog)
                    local caller_callback = function(selected_collections)
                        for name in pairs(selected_collections) do
                            self.updated_collections[name] = true
                        end
                        ReadCollection:addItemsMultiple(self.selected_files, selected_collections)
                        self.updated_collections[collection_name] = true
                        for file in pairs(self.selected_files) do
                            ReadCollection:removeItem(file, collection_name, true)
                        end
                        self.files_updated = self.show_mark
                        self:toggleSelectMode(true)
                    end
                    self:onShowCollList({}, caller_callback)
                end,
            },
            {
                text = _("Copy to collection"),
                enabled = actions_enabled,
                callback = function()
                    UIManager:close(select_dialog)
                    local caller_callback = function(selected_collections)
                        for name in pairs(selected_collections) do
                            self.updated_collections[name] = true
                        end
                        ReadCollection:addItemsMultiple(self.selected_files, selected_collections)
                        self.files_updated = self.show_mark
                        self:toggleSelectMode()
                    end
                    self:onShowCollList({}, caller_callback)
                end,
            },
        },
        {}, -- separator
        {
            {
                text = _("Deselect all"),
                enabled = actions_enabled,
                callback = function()
                    UIManager:close(select_dialog)
                    for file in pairs (self.selected_files) do
                        self.selected_files[file] = nil
                    end
                    for _, item in ipairs(item_table) do
                        item.dim = nil
                    end
                    self.booklist_menu:updateItems(1, true)
                end,
            },
            {
                text = _("Select all"),
                callback = function()
                    UIManager:close(select_dialog)
                    for _, item in ipairs(item_table) do
                        item.dim = true
                        self.selected_files[item.file] = true
                    end
                    self.booklist_menu:updateItems(1, true)
                end,
            },
        },
        {
            {
                text = _("Exit select mode"),
                callback = function()
                    UIManager:close(select_dialog)
                    self:toggleSelectMode()
                end,
            },
            {
                text = _("Select in file browser"),
                enabled = actions_enabled,
                callback = function()
                    if self.ui.history.booklist_menu then
                        UIManager:close(self.ui.history.booklist_menu)
                    end
                    UIManager:close(select_dialog)
                    local selected_files = self.selected_files
                    local files_updated = self.files_updated
                    self.files_updated = nil -- refresh fm later
                    self.booklist_menu.close_callback()
                    if self.ui.document then
                        self.ui:onClose()
                        self.ui:showFileManager(self.ui.document.file, selected_files)
                    else
                        self.ui.selected_files = selected_files
                        self.ui.title_bar:setRightIcon("check")
                        if files_updated then
                            self.ui.file_chooser:refreshPath()
                        else -- dim only
                            self.ui.file_chooser:updateItems(1, true)
                        end
                    end
                end,
            },
        },
    }
    select_dialog = ButtonDialog:new{
        title = title,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(select_dialog)
end

function FileManagerCollection:showCollDialog()
    local collection_name = self.booklist_menu.path
    local coll_not_empty = #self.booklist_menu.item_table > 0
    local coll_dialog
    local function genFilterByStatusButton(button_status)
        return {
            text = BookList.getBookStatusString(button_status),
            enabled = coll_not_empty,
            callback = function()
                UIManager:close(coll_dialog)
                util.tableSetValue(self, button_status, "match_table", "status")
                self:updateItemTable()
            end,
        }
    end
    local function genFilterByMetadataButton(button_text, button_prop)
        return {
            text = button_text,
            enabled = coll_not_empty,
            callback = function()
                UIManager:close(coll_dialog)
                local prop_values = {}
                for idx, item in ipairs(self.booklist_menu.item_table) do
                    local doc_prop = self.ui.bookinfo:getDocProps(item.file, nil, true)[button_prop]
                    if doc_prop == nil then
                        doc_prop = { self.empty_prop }
                    elseif button_prop == "series" then
                        doc_prop = { doc_prop }
                    elseif button_prop == "language" then
                        doc_prop = { doc_prop:lower() }
                    else -- "authors", "keywords"
                        doc_prop = util.splitToArray(doc_prop, "\n")
                    end
                    for _, prop in ipairs(doc_prop) do
                        prop_values[prop] = prop_values[prop] or {}
                        table.insert(prop_values[prop], idx)
                    end
                end
                self:showPropValueList(button_prop, prop_values)
            end,
        }
    end
    local buttons = {
        {{
            text = _("Collections"),
            callback = function()
                UIManager:close(coll_dialog)
                self.booklist_menu.close_callback()
                self:onShowCollList()
            end,
        }},
        {}, -- separator
        {
            genFilterByStatusButton("mbr"),
            genFilterByStatusButton("tbr"),
            genFilterByStatusButton("reading"),
        },
        {
            genFilterByStatusButton("abandoned"),
            genFilterByStatusButton("complete"),
        },
        {
            genFilterByMetadataButton(_("Filter by authors"), "authors"),
            genFilterByMetadataButton(_("Filter by series"), "series"),
        },
        {
            genFilterByMetadataButton(_("Filter by language"), "language"),
            genFilterByMetadataButton(_("Filter by keywords"), "keywords"),
        },
        {{
            text = _("Reset all filters"),
            enabled = self.match_table ~= nil,
            callback = function()
                UIManager:close(coll_dialog)
                self.match_table = nil
                self:updateItemTable()
            end,
        }},
        {}, -- separator
        {
            {
                text = _("Select"),
                enabled = coll_not_empty,
                callback = function()
                    UIManager:close(coll_dialog)
                    self:toggleSelectMode()
                end,
            },
            {
                text = _("Search"),
                enabled = coll_not_empty,
                callback = function()
                    UIManager:close(coll_dialog)
                    self:onShowCollectionsSearchDialog(nil, collection_name)
                end,
            },
        },
        {{
            text = _("Arrange books in collection"),
            enabled = coll_not_empty and self.match_table == nil,
            callback = function()
                UIManager:close(coll_dialog)
                self:showArrangeBooksDialog()
            end,
        }},
        {}, -- separator
        {{
            text = _("Add all books from a folder"),
            callback = function()
                UIManager:close(coll_dialog)
                self:addBooksFromFolder(false)
            end,
        }},
        {{
            text = _("Add all books from a folder and its subfolders"),
            callback = function()
                UIManager:close(coll_dialog)
                self:addBooksFromFolder(true)
            end,
        }},
        {{
            text = _("Add a book to collection"),
            callback = function()
                UIManager:close(coll_dialog)
                local PathChooser = require("ui/widget/pathchooser")
                local path_chooser = PathChooser:new{
                    path = G_reader_settings:readSetting("home_dir"),
                    select_directory = false,
                    onConfirm = function(file)
                        if not ReadCollection:isFileInCollection(file, collection_name) then
                            self.updated_collections[collection_name] = true
                            ReadCollection:addItem(file, collection_name)
                            self:updateItemTable(nil, file) -- show added item
                            self.files_updated = self.show_mark
                        end
                    end,
                }
                UIManager:show(path_chooser)
            end,
        }},
    }
    if self.ui.document then
        local file = self.ui.document.file
        local is_in_collection = ReadCollection:isFileInCollection(file, collection_name)
        table.insert(buttons, {{
            text_func = function()
                return is_in_collection and _("Remove current book from collection") or _("Add current book to collection")
            end,
            callback = function()
                UIManager:close(coll_dialog)
                self.updated_collections[collection_name] = true
                if is_in_collection then
                    ReadCollection:removeItem(file, collection_name, true)
                    file = nil
                else
                    ReadCollection:addItem(file, collection_name)
                end
                self:updateItemTable(nil, file)
                self.files_updated = self.show_mark
            end,
        }})
    end
    coll_dialog = ButtonDialog:new{
        buttons = buttons,
    }
    UIManager:show(coll_dialog)
end

function FileManagerCollection:showPropValueList(prop, prop_values)
    local prop_menu
    local prop_item_table = {}
    for value, item_idxs in pairs(prop_values) do
        table.insert(prop_item_table, {
            text = value,
            mandatory = #item_idxs,
            callback = function()
                UIManager:close(prop_menu)
                util.tableSetValue(self, value, "match_table", "props", prop)
                local item_table = {}
                for _, idx in ipairs(item_idxs) do
                    table.insert(item_table, self.booklist_menu.item_table[idx])
                end
                self:updateItemTable(item_table)
            end,
        })
    end
    if #prop_item_table > 1 then
        table.sort(prop_item_table, function(a, b) return ffiUtil.strcoll(a.text, b.text) end)
    end
    prop_menu = Menu:new{
        title = T("%1 (%2)", self.ui.bookinfo.prop_text[prop]:sub(1, -2), #prop_item_table),
        item_table = prop_item_table,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
    }
    UIManager:show(prop_menu)
end

function FileManagerCollection:setCollate(collate_id, collate_reverse)
    local coll_settings = ReadCollection.coll_settings[self.booklist_menu.path]
    if collate_id == nil then
        collate_id = coll_settings.collate
    else
        coll_settings.collate = collate_id or nil
    end
    if collate_reverse == nil then
        collate_reverse = coll_settings.collate_reverse
    else
        coll_settings.collate_reverse = collate_reverse or nil
    end
    if collate_id then
        local collate = BookList.collates[collate_id]
        self.item_func = collate.item_func
        self.mandatory_func = collate.mandatory_func
        self.sorting_func, self.sort_cache = collate.init_sort_func(self.sort_cache)
        if collate_reverse then
            local sorting_func_unreversed = self.sorting_func
            self.sorting_func = function(a, b) return sorting_func_unreversed(b, a) end
        end
    else -- manual
        self.item_func = nil
        self.mandatory_func = nil
        self.sorting_func = function(a, b) return a.order < b.order end
    end
end

function FileManagerCollection:showArrangeBooksDialog()
    local collection_name = self.booklist_menu.path
    local coll_settings = ReadCollection.coll_settings[collection_name]
    local curr_collate_id = coll_settings.collate
    local arrange_dialog
    local function genCollateButton(collate_id)
        local collate = BookList.collates[collate_id]
        return {
            text = collate.text .. (curr_collate_id == collate_id and "  ✓" or ""),
            callback = function()
                if curr_collate_id ~= collate_id then
                    UIManager:close(arrange_dialog)
                    self.updated_collections[collection_name] = true
                    self:setCollate(collate_id)
                    self:updateItemTable()
                end
            end,
        }
    end
    local buttons = {
        {
            genCollateButton("authors"),
            genCollateButton("title"),
        },
        {
            genCollateButton("keywords"),
            genCollateButton("series"),
        },
        {
            genCollateButton("natural"),
            genCollateButton("strcoll"),
        },
        {
            genCollateButton("size"),
            genCollateButton("access"),
        },
        {{
            text = _("Reverse sorting") .. (coll_settings.collate_reverse and "  ✓" or ""),
            enabled = curr_collate_id and true or false, -- disabled for manual sorting
            callback = function()
                UIManager:close(arrange_dialog)
                self.updated_collections[collection_name] = true
                self:setCollate(nil, not coll_settings.collate_reverse)
                self:updateItemTable()
            end,
        }},
        {}, -- separator
        {{
            text = _("Manual sorting") .. (curr_collate_id == nil and "  ✓" or ""),
            callback = function()
                UIManager:close(arrange_dialog)
                local sort_widget
                sort_widget = SortWidget:new{
                    title = _("Arrange books in collection"),
                    item_table = self.booklist_menu.item_table,
                    callback = function()
                        ReadCollection:updateCollectionOrder(collection_name, sort_widget.item_table)
                        self.updated_collections[collection_name] = true
                        self:setCollate(false, false)
                        self:updateItemTable()
                        self.initial_collate = ""
                        self.initial_reverse_collate_mode = G_reader_settings:readSetting("reverse_collate")
                        G_reader_settings:saveSetting("collate", "strcoll")
                        G_reader_settings:saveSetting("reverse_collate", nil)
                        self.booklist_menu.topbar:setCollectionCollate("")
                        self.booklist_menu.current_collate = nil
                        self.booklist_menu.current_reverse_collate_mode = nil
                        -- UIManager:setDirty(self, function()
                        --     return "ui"
                        -- end)
                    end,
                }
                UIManager:show(sort_widget)
            end,
        }},
    }
    arrange_dialog = ButtonDialog:new{
        title = _("Sort by"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(arrange_dialog)
end

function FileManagerCollection:addBooksFromFolder(include_subfolders)
    local PathChooser = require("ui/widget/pathchooser")
    local path_chooser = PathChooser:new{
        path = G_reader_settings:readSetting("home_dir"),
        select_file = false,
        onConfirm = function(folder)
            local count = ReadCollection:updateCollectionFromFolder(self.booklist_menu.path,
                 { [folder] = { subfolders = include_subfolders } })
            local text
            if count == 0 then
                text = _("No books added to collection")
            else
                self.updated_collections[self.booklist_menu.path] = true
                text = T(N_("1 book added to collection", "%1 books added to collection", count), count)
                self:updateItemTable()
                self.files_updated = self.show_mark
            end
            UIManager:show(InfoMessage:new{ text = text })
        end,
    }
    UIManager:show(path_chooser)
end

function FileManagerCollection:onBookMetadataChanged(prop_updated)
    local file
    if prop_updated then
        file = prop_updated.filepath
        self.doc_props_cache[file] = prop_updated.doc_props
    end
    if self.booklist_menu then
        self:updateItemTable(nil, file) -- keep showing the changed file after resorting
    end
end

-- collection list

function FileManagerCollection:onShowCollList(file_or_selected_collections, caller_callback, no_dialog)
    local title_bar_left_icon
    if file_or_selected_collections ~= nil then -- select mode
        title_bar_left_icon = "check"
        if type(file_or_selected_collections) == "string" then -- checkmark collections containing the file
            self.selected_collections = ReadCollection:getCollectionsWithFile(file_or_selected_collections)
        else
            self.selected_collections = util.tableDeepCopy(file_or_selected_collections)
        end
    else
        title_bar_left_icon = "appbar.menu"
        self.selected_collections = nil
    end
    self.coll_list = Menu:new{
        name = "collections",
        path = true, -- draw focus
        subtitle = "",
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        title_bar_left_icon = title_bar_left_icon,
        onLeftButtonTap = function() self:showCollListDialog(caller_callback, no_dialog) end,
        onDoubleTapBottomRight = self.onDoubleTapBottomRightCollections,
        onMenuChoice = self.onCollListChoice,
        onMenuHold = self.onCollListHold,
        _manager = self,
        collection_name = "listall",
        _recreate_func = function() self:onShowCollList(file_or_selected_collections, caller_callback, no_dialog) end,
    }
    self.coll_list.disable_double_tap = false

    self.coll_list.close_callback = function(force_close)
        if force_close or self.selected_collections == nil then
            self:refreshFileManager()
            UIManager:close(self.coll_list)
            if self.ui.history.booklist_menu then -- and self.ui.history.restart then
                --UIManager:close(self.ui.history.hist_menu)
                --self.ui.history:onShowHist()
                self.ui.history:fetchStatuses(false)
                self.ui.history:updateItemTable()
                -- No need to reopen the history nor call updateItems() to have covers
                -- The covers are refreshed as well if needed when the history is shown again
                -- I leave the variable name though
                --self.ui.history.hist_menu:updateItems()
                -- self.ui.history.restart = false
            end
            self.coll_list = nil
        end
    end
    self:updateCollListItemTable(true, nil, true) -- init
    UIManager:show(self.coll_list)
    return true
end

function FileManagerCollection:onShowSeriesList(file_or_files, caller_callback, no_dialog)
    self.selected_colections = nil
    if file_or_files then -- select mode
        if type(file_or_files) == "string" then -- checkmark collections containing the file
            self.selected_colections = ReadCollection:getCollectionsWithFile(file_or_files)
        else -- do not checkmark any
            self.selected_colections = {}
        end
    end
    self.coll_list = Menu:new{
        subtitle = "",
        name = "collections",
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        -- title_bar_left_icon = file_or_files and "check" or "appbar.menu",
        onLeftButtonTap = function() self:showCollListDialog(caller_callback, no_dialog) end,
        onDoubleTapBottomRight = self.onDoubleTapBottomRightCollections,
        onMenuChoice = self.onCollListChoice,
        -- onMenuHold = self.onCollListHold,
        _manager = self,
        collection_name = "series",
        _recreate_func = function() self:onShowCollList(file_or_files, caller_callback, no_dialog) end,
    }
    self.coll_list.disable_double_tap = false
    self.coll_list.close_callback = function(force_close)
        if force_close or self.selected_colections == nil then
            self:refreshFileManager()
            UIManager:close(self.coll_list)
            self.coll_list = nil
        end
    end
    self:updateSeriesListItemTable(true, true) -- init
    UIManager:show(self.coll_list)
    return true
end

function FileManagerCollection:onGenerateFavorites()
    local files = util.getListAll()
    local ReadCollection = require("readcollection")
    ReadCollection:RemoveAllFavoritesAll()
    local collections = {}
    collections["favorites"] = true
    ReadCollection:addItemsMultiple(files, collections)
    local ordered_files = ReadCollection:getOrderedCollectionName("favorites")
    ReadCollection:updateCollectionOrder("favorites", ordered_files)

    local UIManager = require("ui/uimanager")
    local Notification = require("ui/widget/notification")
    UIManager:show(Notification:new{
        text = _("All books added to the All collection."),
    })
    self.ui.collections:onShowColl()
    return true
end

function FileManagerCollection:updateCollListItemTable(do_init, item_number, toggle_sort)
    local item_table
    if do_init then
        item_table = {}
        for coll_name in pairs(ReadCollection.coll) do
            local mandatory
            if self.selected_collections then
                mandatory = self.selected_collections[coll_name] and self.checkmark or "  "
                self.coll_list.items_mandatory_font_size = self.coll_list.font_size
            else
                mandatory = self.getCollListItemMandatory(coll_name)
            end
            table.insert(item_table, {
                text      = self:getCollectionTitle(coll_name),
                mandatory = self:getTotalAndRead(coll_name),
                name      = coll_name,
                order     = ReadCollection.coll_settings[coll_name].order,
            })
        end
        if #item_table > 1 then
            table.sort(item_table, function(v1, v2) return v1.order < v2.order end)
        end
        if #item_table > 1 then
            if toggle_sort ~= nil then
                if toggle_sort then
                    table.sort(item_table, function(v1, v2) return (ReadCollection.coll_settings[v1.text] and ReadCollection.coll_settings[v2.text]) and ReadCollection.coll_settings[v1.text].number_files > ReadCollection.coll_settings[v2.text].number_files  end)
                else
                    table.sort(item_table, function(v1, v2) return (ReadCollection.coll_settings[v1.text] and ReadCollection.coll_settings[v2.text]) and ReadCollection.coll_settings[v1.text].number_files < ReadCollection.coll_settings[v2.text].number_files  end)
                end
            end
        end
    else
        item_table = self.coll_list.item_table
    end
    local title = T(_("Collections (%1)"), #item_table)
    local itemmatch, subtitle
    if self.selected_collections then
        local selected_nb = util.tableSize(self.selected_collections)
        subtitle = self.selected_collections and T(_("Selected: %1"), selected_nb)
        if do_init and selected_nb > 0 then -- show first collection containing the long-pressed book
            for i, item in ipairs(item_table) do
                if self.selected_collections[item.name] then
                    item_number = i
                    break
                end
            end
        end
    elseif self.from_collection_name ~= nil then
        itemmatch = { text = self.from_collection_name }
        self.from_collection_name = nil
    end
    self.coll_list:switchItemTable(title, item_table, item_number or -1, itemmatch, subtitle)
end

-- Don't need the parameter item_number for this function which is used when creating a new collection
-- First, there is no way to set a collection as series, it is done externally with a script from Calibre data
-- Second, the collections widget with the series view does not allow to create collections since top left menu is disabled
function FileManagerCollection:updateSeriesListItemTable(do_init, toggle_sort)
    local item_table
    if do_init then
        item_table = {}
        for name, coll in pairs(ReadCollection.coll) do
            local mandatory
            if self.selected_colections then
                mandatory = self.selected_colections[name] and self.checkmark or "  "
                self.coll_list.items_mandatory_font_size = self.coll_list.font_size
            else
                mandatory = util.tableSize(coll)
            end
            if ReadCollection.coll_settings[name]["series"] then
                table.insert(item_table, {
                    text      = self:getCollectionTitle(name),
                    mandatory = self:getTotalAndRead(name),
                    name      = name,
                    order     = ReadCollection.coll_settings[name].order,
                })
            end
        end
        if #item_table > 1 then
            if toggle_sort ~= nil then
                if toggle_sort then
                    table.sort(item_table, function(v1, v2) return (ReadCollection.coll_settings[v1.text] and ReadCollection.coll_settings[v2.text]) and ReadCollection.coll_settings[v1.text].number_files > ReadCollection.coll_settings[v2.text].number_files  end)
                else
                    table.sort(item_table, function(v1, v2) return (ReadCollection.coll_settings[v1.text] and ReadCollection.coll_settings[v2.text]) and ReadCollection.coll_settings[v1.text].number_files < ReadCollection.coll_settings[v2.text].number_files  end)
                end
            end
        end
    else
        item_table = self.coll_list.item_table
        if #item_table > 1 and toggle_sort ~= nil then
            if toggle_sort then
                table.sort(item_table, function(v1, v2) return v1.text > v2.text end)
            else
                table.sort(item_table, function(v1, v2) return v1.text < v2.text end)
            end
        end
    end
    local title = T(_("Series (%1)"), #item_table)
    self.coll_list:switchItemTable(title, item_table)
end

function FileManagerCollection.getCollListItemMandatory(coll_name)
    local marker = FileManagerCollection.getCollMarker(coll_name)
    local coll_nb = util.tableSize(ReadCollection.coll[coll_name])
    return marker and marker .. " " .. coll_nb or coll_nb
end

function FileManagerCollection.getCollMarker(coll_name)
    local coll_settings = ReadCollection.coll_settings[coll_name]
    local marker
    if coll_settings.folders then
        marker = "\u{F114}"
    end
    if util.tableGetValue(coll_settings, "filter", "add", "filetype") then
        marker = marker and "\u{F114} \u{F0B0}" or "\u{F0B0}"
    end
    return marker
end

function FileManagerCollection:onCollListChoice(item)
    if self._manager.selected_collections then
        if item.mandatory == self._manager.checkmark then
            self.item_table[item.idx].mandatory = "  "
            self._manager.selected_collections[item.name] = nil
        else
            self.item_table[item.idx].mandatory = self._manager.checkmark
            self._manager.selected_collections[item.name] = true
        end
        self._manager:updateCollListItemTable()
    else
        self._manager:onShowColl(item.name, self.collection_name == "series")
    end
end

function FileManagerCollection:onCollListHold(item)
    if self._manager.selected_collections then -- select mode
        return true
    end

    local button_dialog
    local buttons = {
        {
            {
                text = _("Filter new books"),
                callback = function()
                    UIManager:close(button_dialog)
                    self._manager:showCollFilterDialog(item)
                end
            },
            {
                text = _("Connect folders"),
                callback = function()
                    UIManager:close(button_dialog)
                    self._manager:showCollFolderList(item)
                end
            },
        },
        item.name ~= ReadCollection.default_collection_name and { -- Favorites non-editable
            {
                text = _("Remove collection"),
                callback = function()
                    UIManager:close(button_dialog)
                    self._manager:removeCollection(item)
                end
            },
            {
                text = _("Rename collection"),
                callback = function()
                    UIManager:close(button_dialog)
                    self._manager:renameCollection(item)
                end
            },
        } or nil,
    }
    button_dialog = ButtonDialog:new{
        title = item.text,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(button_dialog)
    return true
end

function FileManagerCollection:showCollFilterDialog(item)
    local coll_name = item.name
    local coll_settings = ReadCollection.coll_settings[coll_name]
    local input_dialog
    input_dialog = InputDialog:new{
        title =  _("Enter file type for new books"),
        input = util.tableGetValue(coll_settings, "filter", "add", "filetype"),
        input_hint = "epub, pdf",
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(input_dialog)
                end,
            },
            {
                text = _("Save"),
                callback = function()
                    UIManager:close(input_dialog)
                    local filetype = input_dialog:getInputText()
                    if filetype == "" then
                        util.tableRemoveValue(coll_settings, "filter", "add", "filetype")
                    else
                        util.tableSetValue(coll_settings, filetype:lower(), "filter", "add", "filetype")
                    end
                    self.coll_list.item_table[item.idx].mandatory = self.getCollListItemMandatory(coll_name)
                    self:updateCollListItemTable()
                    self.updated_collections[coll_name] = true
                end,
            },
        }},
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function FileManagerCollection:showCollFolderList(item)
    local coll_name = item.name
    self.coll_folder_list = Menu:new{
        path = coll_name,
        title = item.text,
        subtitle = "",
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        title_bar_left_icon = "plus",
        onLeftButtonTap = function() self:showAddCollFolderDialog() end,
        onMenuChoice = self.onCollFolderListChoice,
        onMenuHold = self.onCollFolderListHold,
        ui = self.ui,
        _manager = self,
    }
    self.coll_folder_list.close_callback = function()
        UIManager:close(self.coll_folder_list)
        self.coll_folder_list = nil
        if self.coll_list and self.updated_collections[coll_name] then
            -- folder has been connected, new books added to collection
            self.coll_list.item_table[item.idx].mandatory = self.getCollListItemMandatory(item.name)
            self:updateCollListItemTable()
        end
    end
    self:updateCollFolderListItemTable()
    UIManager:show(self.coll_folder_list)
end

function FileManagerCollection:updateCollFolderListItemTable()
    local item_table = {}
    local folders = ReadCollection.coll_settings[self.coll_folder_list.path].folders
    if folders then
        for folder, folder_settings in pairs(folders) do
            local mandatory
            if folder_settings.subfolders and folder_settings.scan_on_show then
                mandatory = "\u{F441} \u{F114}"
            elseif folder_settings.subfolders then
                mandatory = "\u{F114}"
            elseif folder_settings.scan_on_show then
                mandatory = "\u{F441}"
            end
            table.insert(item_table, {
                text      = folder,
                mandatory = mandatory,
            })
        end
        if #item_table > 1 then
            table.sort(item_table, function(a, b) return ffiUtil.strcoll(a.text, b.text) end)
        end
    end
    local subtitle = T(_("Connected folders: %1"), #item_table)
    self.coll_folder_list:switchItemTable(nil, item_table, -1, nil, subtitle)
end

function FileManagerCollection:onCollFolderListChoice(item)
    self._manager.update_files = nil
    self.close_callback()
    self._manager.coll_list.close_callback()
    if self.ui.file_chooser then
        self.ui.file_chooser:changeToPath(item.text)
    else -- called from Reader
        self.ui:onClose()
        self.ui:showFileManager(item.text .. "/")
    end
end

function FileManagerCollection:onCollFolderListHold(item)
    local folder = item.text
    local coll_name = self.path
    local coll_settings = ReadCollection.coll_settings[coll_name]
    local button_dialog
    local buttons = {
        {
            {
                text = _("Disconnect folder"),
                callback = function()
                    UIManager:close(button_dialog)
                    self._manager.updated_collections[coll_name] = true
                    coll_settings.folders[folder] = nil
                    if next(coll_settings.folders) == nil then
                        coll_settings.folders = nil
                    end
                    self._manager:updateCollFolderListItemTable()
                end,
            },
        },
        {}, -- separator
        {
            {
                text = _("Scan folder on showing collection"),
                checked_func = function()
                    return coll_settings.folders[folder].scan_on_show
                end,
                callback = function()
                    self._manager.updated_collections[coll_name] = true
                    coll_settings.folders[folder].scan_on_show = not coll_settings.folders[folder].scan_on_show
                    self._manager:updateCollFolderListItemTable()
                end,
            },
        },
        {
            {
                text = _("Include subfolders"),
                checked_func = function()
                    return coll_settings.folders[folder].subfolders
                end,
                callback = function()
                    self._manager.updated_collections[coll_name] = true
                    if coll_settings.folders[folder].subfolders then
                        coll_settings.folders[folder].subfolders = false
                    else
                        coll_settings.folders[folder].subfolders = true
                        ReadCollection:updateCollectionFromFolder(coll_name)
                    end
                    self._manager:updateCollFolderListItemTable()
                end,
            },
        },
    }
    button_dialog = ButtonDialog:new{
        title = folder,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(button_dialog)
end

function FileManagerCollection:showAddCollFolderDialog()
    local PathChooser = require("ui/widget/pathchooser")
    UIManager:show(PathChooser:new{
        path = G_reader_settings:readSetting("home_dir"),
        select_file = false,
        onConfirm = function(folder)
            local coll_name = self.coll_folder_list.path
            local coll_settings = ReadCollection.coll_settings[coll_name]
            coll_settings.folders = coll_settings.folders or {}
            if coll_settings.folders[folder] == nil then
                self.updated_collections[coll_name] = true
                coll_settings.folders[folder] = { subfolders = false }
                ReadCollection:updateCollectionFromFolder(coll_name)
                self:updateCollFolderListItemTable()
            end
        end,
    })
end

function FileManagerCollection:showCollListDialog(caller_callback, no_dialog)
    if no_dialog then
        caller_callback(self.selected_collections)
        self.coll_list.close_callback(true)
        return
    end

    local button_dialog, buttons
    local new_collection_button = {
        {
            text = _("New collection"),
            callback = function()
                UIManager:close(button_dialog)
                self:addCollection()
            end,
        },
    }
    if self.selected_collections then -- select mode
        buttons = {
            new_collection_button,
            {}, -- separator
            {
                {
                    text = _("Deselect all"),
                    callback = function()
                        UIManager:close(button_dialog)
                        for name in pairs(self.selected_collections) do
                            self.selected_collections[name] = nil
                        end
                        self:updateCollListItemTable(true)
                    end,
                },
                {
                    text = _("Select all"),
                    callback = function()
                        UIManager:close(button_dialog)
                        for name in pairs(ReadCollection.coll) do
                            self.selected_collections[name] = true
                        end
                        self:updateCollListItemTable(true)
                    end,
                },
            },
            {
                {
                    text = _("Apply selection"),
                    callback = function()
                        UIManager:close(button_dialog)
                        caller_callback(self.selected_collections)
                        self.coll_list.close_callback(true)
                    end,
                },
            },
        }
    else
        buttons = {
            new_collection_button,
            {
                {
                    text = _("Arrange collections"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self:sortCollections()
                    end,
                },
            },
            {},
            {
                {
                    text = _("Collections search"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self:onShowCollectionsSearchDialog()
                    end,
                },
            },
        }
    end
    button_dialog = ButtonDialog:new{
        buttons = buttons,
    }
    UIManager:show(button_dialog)
end

function FileManagerCollection:editCollectionName(editCallback, old_name)
    local input_dialog
    input_dialog = InputDialog:new{
        title =  _("Enter collection name"),
        input = old_name,
        input_hint = old_name,
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(input_dialog)
                end,
            },
            {
                text = _("Save"),
                callback = function()
                    local new_name = input_dialog:getInputText()
                    if new_name == "" or new_name == old_name then return end
                    if ReadCollection.coll[new_name] then
                        UIManager:show(InfoMessage:new{
                            text = T(_("Collection already exists: %1"), new_name),
                        })
                    else
                        UIManager:close(input_dialog)
                        editCallback(new_name)
                    end
                end,
            },
        }},
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function FileManagerCollection:addCollection()
    local editCallback = function(name)
        self.updated_collections[name] = true
        ReadCollection:addCollection(name)
        local mandatory
        if self.selected_collections then
            self.selected_collections[name] = true
            mandatory = self.checkmark
        else
            mandatory = 0
        end
        table.insert(self.coll_list.item_table, {
            text      = name,
            mandatory = mandatory,
            name      = name,
            order     = ReadCollection.coll_settings[name].order,
        })
        self:updateCollListItemTable(false, #self.coll_list.item_table) -- show added item
    end
    self:editCollectionName(editCallback)
end

function FileManagerCollection:renameCollection(item)
    local editCallback = function(name)
        self.updated_collections[name] = true
        ReadCollection:renameCollection(item.name, name)
        self.coll_list.item_table[item.idx].text = name
        self.coll_list.item_table[item.idx].name = name
        self:updateCollListItemTable()
    end
    self:editCollectionName(editCallback, item.name)
end

function FileManagerCollection:removeCollection(item)
    UIManager:show(ConfirmBox:new{
        text = _("Remove collection?") .. "\n\n" .. item.text,
        ok_text = _("Remove"),
        ok_callback = function()
            self.updated_collections[item.name] = true
            ReadCollection:removeCollection(item.name)
            table.remove(self.coll_list.item_table, item.idx)
            self:updateCollListItemTable()
            self.files_updated = self.show_mark
        end,
    })
end

function FileManagerCollection:sortCollections()
    local sort_widget
    sort_widget = SortWidget:new{
        title = _("Arrange collections"),
        item_table = self.coll_list.item_table,
        callback = function()
            self.updated_collections = { true } -- all
            ReadCollection:updateCollectionListOrder(sort_widget.item_table)
            self:updateCollListItemTable(true) -- init
        end,
    }
    UIManager:show(sort_widget)
end

function FileManagerCollection:onShowCollectionsSearchDialog(search_str, coll_name)
    local search_dialog, check_button_case, check_button_content
    search_dialog = InputDialog:new{
        title = _("Enter text to search for"),
        input = search_str or self.search_str,
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
                    callback = function()
                        local str = search_dialog:getInputText()
                        UIManager:close(search_dialog)
                        if str ~= "" then
                            self.search_str = str
                            self.case_sensitive = check_button_case.checked
                            self.include_content = check_button_content.checked
                            local Trapper = require("ui/trapper")
                            Trapper:wrap(function()
                                self:searchCollections(coll_name)
                            end)
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
    }
    search_dialog:addWidget(check_button_case)
    check_button_content = CheckButton:new{
        text = _("Also search in book content (slow)"),
        checked = self.include_content,
        enabled = not self.ui.document, -- avoid 2 instances of crengine
        parent = search_dialog,
    }
    search_dialog:addWidget(check_button_content)
    UIManager:show(search_dialog)
    search_dialog:onShowKeyboard()
    return true
end

function FileManagerCollection:searchCollections(coll_name)
    local function isFileMatch(file)
        if self.search_str == "*" then
            return true
        end
        if util.stringSearch(file:gsub(".*/", ""), self.search_str, self.case_sensitive) ~= 0 then
            return true
        end
        if not DocumentRegistry:hasProvider(file) then
            return false
        end
        local book_props = self.ui.bookinfo:getDocProps(file, nil, true)
        if next(book_props) ~= nil and self.ui.bookinfo:findInProps(book_props, self.search_str, self.case_sensitive) then
            return true
        end
        if self.include_content then
            logger.dbg("Search in book:", file)
            local ReaderUI = require("apps/reader/readerui")
            local provider = ReaderUI:extendProvider(file, DocumentRegistry:getProvider(file))
            local document = DocumentRegistry:openDocument(file, provider)
            if document then
                local loaded, found
                if document.loadDocument then -- CRE
                    -- We will be half-loading documents and may mess with crengine's state.
                    -- Fortunately, this is run in a subprocess, so we won't be affecting the
                    -- main process's crengine state or any document opened in the main
                    -- process (we furthermore prevent this feature when one is opened).
                    -- To avoid creating half-rendered/invalid cache files, it's best to disable
                    -- crengine saving of such cache files.
                    if not self.is_cre_cache_disabled then
                        local cre = require("document/credocument"):engineInit()
                        cre.initCache("", 0, true, 40)
                        self.is_cre_cache_disabled = true
                    end
                    loaded = document:loadDocument()
                else
                    loaded = true
                end
                if loaded then
                    found = document:findText(self.search_str, 0, 0, not self.case_sensitive, 1, false, 1)
                end
                document:close()
                if found then
                    return true
                end
            end
        end
        return false
    end

    local collections = coll_name and { [coll_name] = ReadCollection.coll[coll_name] } or ReadCollection.coll
    local Trapper = require("ui/trapper")
    local info = InfoMessage:new{ text = _("Sorting collection… (tap to cancel)") }
    UIManager:show(info)
    UIManager:forceRePaint()
    local completed, files_found, files_found_order = Trapper:dismissableRunInSubprocess(function()
        local match_cache, _files_found, _files_found_order = {}, {}, {}
        for collection_name, coll in pairs(collections) do
            local coll_order = ReadCollection.coll_settings[collection_name].order
            for _, item in pairs(coll) do
                local file = item.file
                if match_cache[file] == nil then -- a book can be included to several collections
                    match_cache[file] = isFileMatch(file)
                end
                if match_cache[file] then
                    local order_idx = _files_found[file]
                    if order_idx == nil then -- new
                        table.insert(_files_found_order, {
                            file = file,
                            coll_order = coll_order,
                            item_order = item.order,
                        })
                        _files_found[file] = #_files_found_order -- order_idx
                    else -- previously found, update orders
                        if _files_found_order[order_idx].coll_order > coll_order then
                            _files_found_order[order_idx].coll_order = coll_order
                            _files_found_order[order_idx].item_order = item.order
                        end
                    end
                end
            end
        end
        return _files_found, _files_found_order
    end, info)
    if not completed then return end
    UIManager:close(info)

    if #files_found_order == 0 then
        UIManager:show(InfoMessage:new{
            text = T(_("No results for: %1"), self.search_str),
        })
    else
        table.sort(files_found_order, function(a, b)
            if a.coll_order ~= b.coll_order then
                return a.coll_order < b.coll_order
            end
            if a.item_order and b.item_order then
                return a.item_order < b.item_order
            end
            return ffiUtil.strcoll(a.text, b.text)
        end)
        local new_coll_name = T(_("Search results: %1"), self.search_str)
        if coll_name then
            new_coll_name = new_coll_name .. " " .. T(_"(in %1)", coll_name)
            self.booklist_menu.close_callback()
        end
        self.updated_collections[new_coll_name] = true
        ReadCollection:removeCollection(new_coll_name)
        ReadCollection:addCollection(new_coll_name)
        ReadCollection:addItemsMultiple(files_found, { [new_coll_name] = true })
        ReadCollection:updateCollectionOrder(new_coll_name, files_found_order)
        if self.coll_list ~= nil then
            UIManager:close(self.coll_list)
            self.coll_list = nil
        end
        self:onShowColl(new_coll_name)
    end
end

function FileManagerCollection:onCloseWidget()
    if next(self.updated_collections) then
        ReadCollection:write(self.updated_collections)
    end
end

-- external

function FileManagerCollection:genAddToCollectionButton(file_or_files, caller_pre_callback, caller_post_callback, button_disabled)
    local is_single_file = type(file_or_files) == "string"
    return {
        text = _("Collections…"),
        enabled = not button_disabled,
        callback = function()
            if caller_pre_callback then
                caller_pre_callback()
            end
            local caller_callback = function(selected_collections)
                for name in pairs(selected_collections) do
                    self.updated_collections[name] = true
                end
                if is_single_file then
                    ReadCollection:addRemoveItemMultiple(file_or_files, selected_collections)
                else -- selected files
                    ReadCollection:addItemsMultiple(file_or_files, selected_collections)
                end
                if caller_post_callback then
                    caller_post_callback()
                end
            end
            -- if selected files, do not checkmark any collection on start
            self:onShowCollList(is_single_file and file_or_files or {}, caller_callback)
        end,
    }
end

function FileManagerCollection:onDoubleTapBottomRightCollections(arg, ges_ev)
    if self.order == nil or self.order == true then
        self.order = false
    else
        self.order = not self.order
    end

    if self.collection_name == "listall" then
        self._manager:updateCollListItemTable(true, nil, self.order)
    else
        self._manager:updateSeriesListItemTable(true, self.order)
    end

    self._manager.coll_list:onGotoPage(1)
    return true
end

-- When tapping on the bottom right of the collections lists we want to sort the collections
-- but just in memory, we don't to save the file when ordering them

-- Because some collections can have many books, we do it in a subprocess to be able to interrupt it if needed

-- Every time we open any collection, the hardcoded Sort text is shown on the bottom right of the topbar associated to the menu widget
-- and then we can start tapping and toggling the different sort modes starting with strcoll
-- This will be the default behaviour for any collection we open
-- Every time we close any collection, the fm will be set to strcoll sorting mode

-- The following does not apply since we reuse the widget instead of reopening:
-- -- When collections are opened, they may be sorted or not, we don't care, first time we tap they will be sorted using the current system collate
-- -- and the consecutive tappings will sort them toggling some of the system collates
-- -- When switching collections, the sorting will remain active for the last collection sorted if we don't start sorting other collections
-- -- When going back to the fm, the fm will be using the last sorting mode used while sorting collections for consistency


function FileManagerCollection:onTapBottomRightCollection(arg, ges_ev)
    if ReadCollection.coll_settings[self.collection_name].collate then
        self._manager.booklist_menu.topbar:setCollectionCollate("not_manual_sorting")
        G_reader_settings:saveSetting("reverse_collate", nil)
        UIManager:setDirty(self, function()
            return "ui"
        end)
        return
    end
    local DataStorage = require("datastorage")
    local DocSettings = require("docsettings")
    if ffiUtil.realpath(DataStorage:getSettingsDir() .. "/calibre.lua") then
        local Trapper = require("ui/trapper")
        Trapper:wrap(function()
            local info = InfoMessage:new{ text = _("Searching… (tap to cancel)") }
            UIManager:show(info)
            UIManager:forceRePaint()
            local completed, files_table = Trapper:dismissableRunInSubprocess(function()
                local files_with_metadata = {}
                local sort_by_mode = G_reader_settings:readSetting("collate")
                -- Reverse collate is always set to nil (ascending order) when creating the collection so topbar will show it blank
                -- This means, that while we toggle sorting modes and we don't reverse the sorting mode we will get ascending order
                local reverse_collate_mode = G_reader_settings:readSetting("reverse_collate") == nil and true or G_reader_settings:readSetting("reverse_collate")
                -- local FFIUtil = require("ffi/util")
                -- FFIUtil.sleep(2)
                if self.calibre_data then
                    for i = 1, #self.item_table do
                        local file = self.item_table[i]
                        if self.calibre_data[file.text] and
                        self.calibre_data[file.text]["pubdate"]
                            and self.calibre_data[file.text]["words"]
                            and self.calibre_data[file.text]["grrating"]
                            and self.calibre_data[file.text]["grvotes"]
                            and self.calibre_data[file.text]["series"] then
                            file.pubdate = tonumber(self.calibre_data[file.text]["pubdate"]:sub(1, 4) .. self.calibre_data[file.text]["pubdate"]:sub(6, 7))
                            file.words = tonumber(self.calibre_data[file.text]["words"])
                            file.grrating = tonumber(self.calibre_data[file.text]["grrating"])
                            file.grvotes = tonumber(self.calibre_data[file.text]["grvotes"])
                            file.series = self.calibre_data[file.text]["series"]
                        else
                            file.pubdate = 0
                            file.words = 0
                            file.grrating = 0
                            file.grvotes = 0
                            file.series = "zzzz"
                        end
                        local book_info = BookList.getBookInfo(file.file)
                        local summary = DocSettings:open(file.file):readSetting("summary")
                        local filename = file.text
                        file.opened = book_info.been_opened
                        file.finished_date = "zzzz" .. filename
                        --local dump = require("dump")
                        --print(dump(book_info))
                        local in_history = require("readhistory"):getIndexByFile(file.file)
                        if in_history and not file.opened then
                            file.finished_date = "zzz" .. filename
                        end
                        if file.opened then
                            if book_info.status == "complete" and summary.modified then
                                file.finished_date = summary.modified .. filename
                            end
                            if book_info.status == "tbr" then
                                file.finished_date = "zz" .. filename
                            end
                            if book_info.status == "reading" then
                                file.finished_date = "z" .. filename
                            end
                        end
                        files_with_metadata[i] = file
                    end

                    if reverse_collate_mode then
                        if sort_by_mode == "strcoll" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.text < v2.text
                            end)
                        elseif sort_by_mode == "finished" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.finished_date < v2.finished_date
                            end)
                        elseif sort_by_mode == "publication_date" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.pubdate < v2.pubdate
                            end)
                        elseif sort_by_mode == "word_count" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.words < v2.words
                            end)
                        elseif sort_by_mode == "gr_rating" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.grrating < v2.grrating
                            end)
                        elseif sort_by_mode == "gr_votes" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.grvotes < v2.grvotes
                            end)
                        elseif sort_by_mode == "series" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.series < v2.series
                            end)
                        else
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.text < v2.text
                            end)
                        end
                    else
                        if sort_by_mode == "strcoll" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.text > v2.text
                            end)
                        elseif sort_by_mode == "finished" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.finished_date > v2.finished_date
                            end)
                        elseif sort_by_mode == "publication_date" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.pubdate > v2.pubdate
                            end)
                        elseif sort_by_mode == "word_count" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.words > v2.words
                            end)
                        elseif sort_by_mode == "gr_rating" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.grrating > v2.grrating
                            end)
                        elseif sort_by_mode == "gr_votes" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.grvotes > v2.grvotes
                            end)
                        elseif sort_by_mode == "series" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.series > v2.series
                            end)
                        else
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.text < v2.text
                            end)
                        end
                    end
                else
                    table.sort(files_with_metadata, function(v1, v2)
                        return v1.text < v2.text
                    end)
                end

                local files = {}
                for i = 1, #files_with_metadata do
                    local file = self.item_table[i].file
                    files[file] = ""
                end

                ReadCollection:RemoveAllCollection(self.collection_name, true)
                local collections = {}
                collections[self.collection_name] = true
                ReadCollection:addItemsMultiple(files, collections, true)

                -- UIManager:forceRePaint()
                -- self:onShowColl(collection.collection_name)
                -- return UIManager:close(collection)
                return files_with_metadata
            end, info)
            if not completed then return end
            -- The write call needs to be out
            ReadCollection:updateCollectionOrder(self.collection_name, files_table, true)

            UIManager:close(info)

            -- We need to pass the previous sort mode to the topbar
            -- and can't use the current topbar object associated with this fm collection
            -- We use the fm or the reader main instance (depending if we are in fm or reader mode)
            -- to pass the previous sort mode to the topbar

            -- local ui = require("apps/filemanager/filemanager").instance or require("apps/reader/readerui").instance
            -- ui.collection_collate = sort_by_mode

            -- There is no need if we use the topbar object
            local sort_by_mode = G_reader_settings:readSetting("collate")
            if sort_by_mode == "strcoll" then
                G_reader_settings:saveSetting("collate", "finished")
                self._manager.booklist_menu.topbar:setCollectionCollate("strcoll")
                self.current_collate = "strcoll"
            elseif sort_by_mode == "finished" then
                G_reader_settings:saveSetting("collate", "publication_date")
                self._manager.booklist_menu.topbar:setCollectionCollate("finished")
                self.current_collate = "finished"
            elseif sort_by_mode == "publication_date" then
                G_reader_settings:saveSetting("collate", "word_count")
                self._manager.booklist_menu.topbar:setCollectionCollate("publication_date")
                self.current_collate = "publication_date"
            elseif sort_by_mode == "word_count" then
                G_reader_settings:saveSetting("collate", "gr_rating")
                self._manager.booklist_menu.topbar:setCollectionCollate("word_count")
                self.current_collate = "word_count"
            elseif sort_by_mode == "gr_rating" then
                G_reader_settings:saveSetting("collate", "gr_votes")
                self._manager.booklist_menu.topbar:setCollectionCollate("gr_rating")
                self.current_collate = "gr_rating"
            elseif sort_by_mode == "gr_votes" then
                G_reader_settings:saveSetting("collate", "series")
                self._manager.booklist_menu.topbar:setCollectionCollate("gr_votes")
                self.current_collate = "gr_votes"
            elseif sort_by_mode == "series" then
                G_reader_settings:saveSetting("collate", "strcoll")
                self._manager.booklist_menu.topbar:setCollectionCollate("series")
                self.current_collate = "series"
            else
                G_reader_settings:saveSetting("collate", "strcoll")
                self._manager.booklist_menu.topbar:setCollectionCollate("")
                self.current_collate = ""
            end

            if not self.current_reverse_collate_mode then
                G_reader_settings:saveSetting("reverse_collate", true)
                self.current_reverse_collate_mode = G_reader_settings:readSetting("reverse_collate")
            end

            -- UIManager:close(self)
            -- self._manager.ui.collections:onShowColl(self.collection_name)
            self._manager:updateItemTable()
            self._manager.booklist_menu:onGotoPage(1)
        end)
    end
    return
end

function FileManagerCollection:onDoubleTapBottomRightCollection(arg, ges_ev)
    if ReadCollection.coll_settings[self.collection_name].collate then
        self._manager.booklist_menu.topbar:setCollectionCollate("not_manual_sorting")
        G_reader_settings:saveSetting("reverse_collate", nil)
        UIManager:setDirty(self, function()
            return "ui"
        end)
        return
    end
    local DataStorage = require("datastorage")
    local DocSettings = require("docsettings")
    if ffiUtil.realpath(DataStorage:getSettingsDir() .. "/calibre.lua") then
        local Trapper = require("ui/trapper")
        Trapper:wrap(function()
            local info = InfoMessage:new{ text = _("Searching… (tap to cancel)") }
            UIManager:show(info)
            UIManager:forceRePaint()
            local completed, files_table = Trapper:dismissableRunInSubprocess(function()
                local files_with_metadata = {}
                local sort_by_mode = self.current_collate and self.current_collate or G_reader_settings:readSetting("collate")
                local reverse_collate_mode = not G_reader_settings:readSetting("reverse_collate")
                -- local FFIUtil = require("ffi/util")
                -- FFIUtil.sleep(2)
                if self.calibre_data then
                    for i = 1, #self.item_table do
                        local file = self.item_table[i]
                        if self.calibre_data[file.text] and
                        self.calibre_data[file.text]["pubdate"]
                            and self.calibre_data[file.text]["words"]
                            and self.calibre_data[file.text]["grrating"]
                            and self.calibre_data[file.text]["grvotes"]
                            and self.calibre_data[file.text]["series"] then
                            file.pubdate = tonumber(self.calibre_data[file.text]["pubdate"]:sub(1, 4) .. self.calibre_data[file.text]["pubdate"]:sub(6, 7))
                            file.words = tonumber(self.calibre_data[file.text]["words"])
                            file.grrating = tonumber(self.calibre_data[file.text]["grrating"])
                            file.grvotes = tonumber(self.calibre_data[file.text]["grvotes"])
                            file.series = self.calibre_data[file.text]["series"]
                        else
                            file.pubdate = 0
                            file.words = 0
                            file.grrating = 0
                            file.grvotes = 0
                            file.series = "zzzz"
                        end
                        local book_info = BookList.getBookInfo(file.file)
                        local summary = DocSettings:open(file.file):readSetting("summary")
                        local filename = file.text
                        file.opened = book_info.been_opened
                        file.finished_date = "zzzz" .. filename
                        --local dump = require("dump")
                        --print(dump(book_info))
                        local in_history = require("readhistory"):getIndexByFile(file.file)
                        if in_history and not file.opened then
                            file.finished_date = "zzz" .. filename
                        end
                        if file.opened then
                            if book_info.status == "complete" and summary.modified then
                                file.finished_date = summary.modified .. filename
                            end
                            if book_info.status == "tbr" then
                                file.finished_date = "zz" .. filename
                            end
                            if book_info.status == "reading" then
                                file.finished_date = "z" .. filename
                            end
                        end
                        files_with_metadata[i] = file
                    end

                    if reverse_collate_mode then
                        if sort_by_mode == "strcoll" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.text < v2.text
                            end)
                        elseif sort_by_mode == "finished" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.finished_date < v2.finished_date
                            end)
                        elseif sort_by_mode == "publication_date" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.pubdate < v2.pubdate
                            end)
                        elseif sort_by_mode == "word_count" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.words < v2.words
                            end)
                        elseif sort_by_mode == "gr_rating" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.grrating < v2.grrating
                            end)
                        elseif sort_by_mode == "gr_votes" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.grvotes < v2.grvotes
                            end)
                        elseif sort_by_mode == "series" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.series < v2.series
                            end)
                        else
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.text < v2.text
                            end)
                        end
                    else
                        if sort_by_mode == "strcoll" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.text > v2.text
                            end)
                        elseif sort_by_mode == "finished" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.finished_date > v2.finished_date
                            end)
                        elseif sort_by_mode == "publication_date" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.pubdate > v2.pubdate
                            end)
                        elseif sort_by_mode == "word_count" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.words > v2.words
                            end)
                        elseif sort_by_mode == "gr_rating" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.grrating > v2.grrating
                            end)
                        elseif sort_by_mode == "gr_votes" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.grvotes > v2.grvotes
                            end)
                        elseif sort_by_mode == "series" then
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.series > v2.series
                            end)
                        else
                            table.sort(files_with_metadata, function(v1, v2)
                                return v1.text < v2.text
                            end)
                        end
                    end
                else
                    table.sort(files_with_metadata, function(v1, v2)
                        return v1.text < v2.text
                    end)
                end

                local files = {}
                for i = 1, #files_with_metadata do
                    local file = self.item_table[i].file
                    files[file] = ""
                end

                ReadCollection:RemoveAllCollection(self.collection_name, true)
                local collections = {}
                collections[self.collection_name] = true
                ReadCollection:addItemsMultiple(files, collections, true)

                -- UIManager:forceRePaint()
                -- self:onShowColl(collection.collection_name)
                -- return UIManager:close(collection)
                return files_with_metadata
            end, info)
            if not completed then return end
            -- The write call needs to be out
            ReadCollection:updateCollectionOrder(self.collection_name, files_table, true)

            UIManager:close(info)

            -- We need to pass the previous sort mode to the topbar
            -- and can't use the current topbar object associated with this fm collection
            -- We use the fm or the reader main instance (depending if we are in fm or reader mode)
            -- to pass the previous sort mode to the topbar

            -- local ui = require("apps/filemanager/filemanager").instance or require("apps/reader/readerui").instance
            -- ui.collection_collate = sort_by_mode

            -- There is no need if we use the topbar object
            self.current_reverse_collate_mode = G_reader_settings:readSetting("reverse_collate")
            G_reader_settings:saveSetting("reverse_collate", not G_reader_settings:readSetting("reverse_collate"))
            if not self.current_collate then
                G_reader_settings:saveSetting("collate", "publication_date")
                self._manager.booklist_menu.topbar:setCollectionCollate("strcoll")
                self.current_collate = "strcoll"
            end


            -- UIManager:close(self)
            -- self._manager.ui.collections:onShowColl(self.collection_name)
            self._manager:updateItemTable()
            self._manager.booklist_menu:onGotoPage(1)
        end)
    end
    return
end

function FileManagerCollection:genExportHighlightsButton(files, caller_pre_callback, button_disabled)
    return {
        text = _("Export highlights"),
        enabled = (self.ui.exporter and self.ui.exporter:isReady()) and not button_disabled or false,
        callback = function()
            if caller_pre_callback then
                caller_pre_callback()
            end
            self.ui.exporter:exportFilesNotes(files)
        end,
    }
end

function FileManagerCollection:genBookmarkBrowserButton(files, caller_pre_callback, button_disabled)
    return {
        text = _("Bookmarks"),
        enabled = not button_disabled,
        callback = function()
            if caller_pre_callback then
                caller_pre_callback()
            end
            local BookmarkBrowser = require("ui/widget/bookmarkbrowser")
            BookmarkBrowser:show(files, self.ui)
        end,
    }
end

function FileManagerCollection:onShowBookmarkBrowser()
    local BookmarkBrowser = require("ui/widget/bookmarkbrowser")
    BookmarkBrowser:showSourceDialog(self.ui)
end

return FileManagerCollection
