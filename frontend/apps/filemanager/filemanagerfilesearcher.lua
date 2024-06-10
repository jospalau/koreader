local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local FileChooser = require("ui/widget/filechooser")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Utf8Proc = require("ffi/utf8proc")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template

local FileSearcher = WidgetContainer:extend{
    case_sensitive = false,
    include_subfolders = true,
    include_metadata = false,
}

function FileSearcher:onShowFileSearch(search_string, callbackfunc)
    local search_dialog
    local check_button_case, check_button_subfolders, check_button_metadata
    local callback_func = false
    self.recent = false
    search_dialog = InputDialog:new{
        title = _("Enter text to search for in filename"),
        input = search_string or self.search_string,
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
                    text = _("Home folder"),
                    enabled = G_reader_settings:has("home_dir"),
                    callback = function()
                        self.search_string = search_dialog:getInputText()
                        if self.search_string == "" then return end
                        UIManager:close(search_dialog)
                        self.path = G_reader_settings:readSetting("home_dir")
                        self:doSearch(callbackfunc)
                    end,
                },
                {
                    text = self.ui.file_chooser and _("Current folder") or _("Book folder"),
                    is_enter_default = true,
                    callback = function()
                        self.search_string = search_dialog:getInputText()
                        if self.search_string == "" then return end
                        UIManager:close(search_dialog)
                        self.path = self.ui.file_chooser and self.ui.file_chooser.path or self.ui:getLastDirFile()
                        self:doSearch()
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
    check_button_subfolders = CheckButton:new{
        text = _("Include subfolders"),
        checked = self.include_subfolders,
        parent = search_dialog,
        callback = function()
            self.include_subfolders = check_button_subfolders.checked
        end,
    }
    search_dialog:addWidget(check_button_subfolders)
    if self.ui.coverbrowser then
        check_button_metadata = CheckButton:new{
            text = _("Also search in book metadata"),
            checked = self.include_metadata,
            parent = search_dialog,
            callback = function()
                self.include_metadata = check_button_metadata.checked
            end,
        }
        search_dialog:addWidget(check_button_metadata)
    end
    UIManager:show(search_dialog)
    search_dialog:onShowKeyboard()
end

-- function FileSearcher:onShowFileSearchLists(recent, page, search_string, sorted_size)
function FileSearcher:onShowFileSearchLists(recent, page, search_string)
    -- local callback_func = function(file, restart)
    --         -- Coming nil when closing the search results list window with esc or clicking on X, Menu:onCloseAllMenus() in menu.lua
    --         if file == nil then
    --             -- if not self.search_menu.ui.history.hist_menu and not require("apps/reader/readerui").instance then
    --             --     local FileManager = require("apps/filemanager/filemanager")
    --             --     FileManager.instance.history:onShowHist()
    --             -- end
    --             UIManager:close(self.search_menu)
    --             return
    --         end

    --         -- Coming restart = false when clicking on Show folder for a file in the search results list window
    --         --  self.close_callback(file, false) in filemanagerutil.genShowFolderButton(file, caller_callback, button_disabled)
    --         if lfs.attributes(file, "mode") == "file" and not restart then
    --             if self.search_menu.ui.history.hist_menu then
    --                 self.search_menu.ui.history.hist_menu.close_callback()
    --             end
    --             UIManager:close(self.search_menu)
    --             return
    --         end

    --         -- Otherwise, restart = true when clicking in any other option for a file in the search results list window
    --         -- self.close_callback(file, true) in FileSearcher:onMenuSelect(item, callback)
    --         if self.search_menu.ui.history.hist_menu then
    --             self.ui.history:fetchStatuses(false)
    --             self.ui.history:updateItemTable()
    --         end
    --         local Event = require("ui/event")
    --         UIManager:broadcastEvent(Event:new("CloseSearchMenu", recent, self.search_string))
    --     end
    local search_dialog
    local check_button_case, check_button_subfolders, check_button_metadata
    self.path = G_reader_settings:readSetting("home_dir")
    self.search_string = search_string
    if self.search_string == nil then
        self.search_string = "*.epub"
    end
    self.recent = recent

    -- self:onSearchSortCompleted(false, recent, page, nil, sorted_size)
    self:onSearchSortCompleted(false, recent, page, nil)
end

function FileSearcher:onCloseSearchMenu(recent, search_string)
    UIManager:close(self.search_menu)
    self:onShowFileSearchLists(recent, self.search_menu.page, search_string)
end

function FileSearcher:onShowFileSearchAllCompleted()
    local search_dialog
    local check_button_case, check_button_subfolders, check_button_metadata
    self.path = G_reader_settings:readSetting("home_dir")
    self.search_string = "*.epub"
    self:onSearchSortCompleted(true, false)
end

function FileSearcher:doSearch(callbackfunc)
    local results
    local dirs, files = self:getList()
    -- If we have a FileChooser instance, use it, to be able to make use of its natsort cache
    local results = (self.ui.file_chooser or FileChooser):genItemTable(dirs, files)
    if #results > 0 then
        self:showSearchResults(results, nil, nil, callbackfunc)
    else
        self:showSearchResultsMessage(true)
    end
end


function FileSearcher:showSearchResultsComplete(results, callback)
    self.search_menu = Menu:new{
        title = T(_("Completed books (%1)"), #results),
        item_table = results,
        ui = self.ui,
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        handle_hold_on_hold_release = true,
    }

    if callback then
        self.search_menu.close_callback = callback
    else
        self.search_menu.close_callback = function()
            UIManager:close(self.search_menu)
            if self.ui.file_chooser then
                self.ui.file_chooser:refreshPath()
            end
        end
    end

    UIManager:show(self.search_menu)
    if self.no_metadata_count ~= 0 then
        self:showSearchResultsMessage()
    end
end

-- function FileSearcher:onSearchSortCompleted(show_complete, show_recent, page, callback, sorted_size)
function FileSearcher:onSearchSortCompleted(show_complete, show_recent, page, callback)
    local results
    local dirs, files = self:getList()


    -- If we have a FileChooser instance, use it, to be able to make use of its natsort cache
    if self.ui.file_chooser then
        results = self.ui.file_chooser:genItemTable(dirs, files)
    else
        results = FileChooser:genItemTable(dirs, files)
    end

    if show_complete and show_recent then
        table.sort(results,function(a,b) return b.text>a.text end)
    end
    -- if sorted_size then
    --     table.sort(results,function(a,b) return b.words<a.words end)
    -- end
    if (show_complete) then
        local table_complete = {}
        for key, value in ipairs(results) do
            if DocSettings:hasSidecarFile(value.path) then
                -- local stats = doc_settings:readSetting("stats")
                -- local book_props = require("apps/filemanager/filemanagerbookinfo").getDocProps(value.path).description
                local doc_settings = DocSettings:open(value.path)
                local status = doc_settings:readSetting("summary").status
                local modified_date = doc_settings:readSetting("summary").modified
                if status == "complete" then
                    value.modified_date = modified_date
                    value.text = modified_date .. " " .. value.text:gsub(string.match(value.text , "^.+(%..+)$"), "")
                    table_complete[#table_complete+1] = value
                end
            end
        end
        results = table_complete
        table.sort(results, function(a, b) return a.modified_date > b.modified_date end)
    else
        if show_recent then
            table.sort(results, function(a, b) return a.attr.modification > b.attr.modification end)
        end
    end

    if #results > 0 then
        if (show_complete) then
            self:showSearchResultsComplete(results, callback)
        else
            self:showSearchResults(results, show_recent, page, callback)
        end
    else
        self:showSearchResultsMessage(true)
    end
end


function FileSearcher:getList()
    self.no_metadata_count = 0
    local sys_folders = { -- do not search in sys_folders
        ["/dev"] = true,
        ["/proc"] = true,
        ["/sys"] = true,
    }
    local collate = FileChooser:getCollate()
    local search_string = self.search_string
    -- local calibre_data = util.loadCalibreData()
    if search_string ~= "*" then -- one * to show all files
        if not self.case_sensitive then
            search_string = Utf8Proc.lowercase(util.fixUtf8(search_string, "?"))
        end
        -- replace '.' with '%.'
        search_string = search_string:gsub("%.","%%%.")
        -- replace '*' with '.*'
        search_string = search_string:gsub("%*","%.%*")
        -- replace '?' with '.'
        search_string = search_string:gsub("%?","%.")
    end

    local dirs, files = {}, {}
    local scan_dirs = {self.path}
    while #scan_dirs ~= 0 do
        local new_dirs = {}
        -- handle each dir
        for _, d in ipairs(scan_dirs) do
            -- handle files in d
            local ok, iter, dir_obj = pcall(lfs.dir, d)
            if ok then
                for f in iter, dir_obj do
                    local fullpath = "/" .. f
                    if d ~= "/" then
                        fullpath = d .. fullpath
                    end
                    local attributes = lfs.attributes(fullpath) or {}
                    -- Don't traverse hidden folders if we're not showing them
                    if attributes.mode == "directory" and f ~= "." and f ~= ".."
                            and (FileChooser.show_hidden or not util.stringStartsWith(f, "."))
                            and FileChooser:show_dir(f) then
                        if self.include_subfolders and not sys_folders[fullpath] then
                            table.insert(new_dirs, fullpath)
                        end
                        if self:isFileMatch(f, fullpath, search_string) then
                            table.insert(dirs, FileChooser:getListItem(nil, f, fullpath, attributes, collate))
                        end
                    -- Always ignore macOS resource forks, too.
                    elseif attributes.mode == "file" and not util.stringStartsWith(f, "._")
                            and (FileChooser.show_unsupported or DocumentRegistry:hasProvider(fullpath))
                            and FileChooser:show_file(f) then
                        if self:isFileMatch(f, fullpath, search_string, true) then
                            table.insert(files, FileChooser:getListItem(nil, f, fullpath, attributes, collate))
                            -- local file = FileChooser:getListItem(nil, f, fullpath, attributes, collate)
                            -- file.pages = calibre_data[file.text] and calibre_data[file.text].pages or 0
                            -- file.words = calibre_data[file.text] and calibre_data[file.text].words or 0
                            -- table.insert(files, file)
                        end
                    end
                end
            end
        end
        scan_dirs = new_dirs
    end
    return dirs, files
end

function FileSearcher:isFileMatch(filename, fullpath, search_string, is_file)
    if search_string == "*" then
        return true
    end
    if not self.case_sensitive then
        filename = Utf8Proc.lowercase(util.fixUtf8(filename, "?"))
    end
    if string.find(filename, search_string) then
        return true
    end
    if self.include_metadata and is_file and DocumentRegistry:hasProvider(fullpath) then
        local book_props = self.ui.coverbrowser:getBookInfo(fullpath) or
                           self.ui.bookinfo.getDocProps(fullpath, nil, true) -- do not open the document
        if next(book_props) ~= nil then
            if self.ui.bookinfo:findInProps(book_props, search_string, self.case_sensitive) then
                return true
            end
        else
            self.no_metadata_count = self.no_metadata_count + 1
        end
    end
end

function FileSearcher:showSearchResultsMessage(no_results)
    local text = no_results and T(_("No results for '%1'."), self.search_string)
    if self.no_metadata_count == 0 then
        UIManager:show(InfoMessage:new{ text = text })
    else
        local txt = T(N_("1 book has been skipped.", "%1 books have been skipped.",
            self.no_metadata_count), self.no_metadata_count) .. "\n" ..
            _("Not all books metadata extracted yet.\nExtract metadata now?")
        text = no_results and text .. "\n\n" .. txt or txt
        UIManager:show(ConfirmBox:new{
            text = text,
            ok_text = _("Extract"),
            ok_callback = function()
                if not no_results then
                    self.search_menu.close_callback()
                end
                self.ui.coverbrowser:extractBooksInDirectory(self.path)
            end
        })
    end
end

function FileSearcher:showSearchResults(results, show_recent, page, callback)
    self.search_menu = Menu:new{
        subtitle = T(_("Query: %1"), self.search_string),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function() self:setSelectMode() end,
        onMenuSelect = self.onMenuSelect,
        onMenuHold = self.onMenuHold,
        handle_hold_on_hold_release = true,
        ui = self.ui,
        _manager = self,
        search = true,
    }

    -- -- Coming from the event declared in onShowFileSearchAll() to get a list, callback function coming from onShowFileSearchAll()
    -- if callback then
    --     self.search_menu.close_callback = callback
    --     -- UIManager:close(self.search_menu)
    -- else -- Coming from onShowFileSearch(), we create the callback function here
        -- self.search_menu.close_callback = function()
        --     UIManager:close(self.search_menu)
        --     local Event = require("ui/event")
        --     UIManager:broadcastEvent(Event:new("ShowFileSearchAll", show_recent))
        --     if self.ui.file_chooser then
        --         self.ui.file_chooser:refreshPath()
        --     end
        -- end


        -- If we are not in history and not in reader we want to go to a folder if a folder is selected and open history if a file is manipulated
        -- If we are in history and in fm we want to go to a folder is a folder is selected and remain in history if a file manipulated
        -- If we are in reader there is no menu for File Search so nothing to be done
        -- If we are in history and in reader we want to go to a folder if a folder is selected and remain in history if a file is manipulated
        self.search_menu.close_callback = function(file, actioned)
            self.selected_files = nil
            -- Coming nil when closing the search results list window with esc or clicking on X, Menu:onCloseAllMenus() in menu.lua
            if file == nil then
                UIManager:close(self.search_menu)
                return
            end

            -- If history open in previous search menu, refresh it
            if self.search_menu.ui.history.hist_menu then
                self.ui.history:fetchStatuses(false)
                self.ui.history:updateItemTable()


                -- self.search_menu.ui.history.hist_menu.close_callback()
                -- local Event = require("ui/event")
                -- UIManager:broadcastEvent(Event:new("CloseSearchMenu", false, self.search_string))
                -- return
            end

            -- -- If in reader and in history refresh it
            -- if require("apps/reader/readerui").instance and require("apps/reader/readerui").instance.history then
            --     -- UIManager:close(require("apps/reader/readerui").instance.history)
            --     self.ui.history:fetchStatuses(false)
            --     self.ui.history:updateItemTable()
            -- end


            -- If file is not false, it is a file or a directory
            if lfs.attributes(file, "mode") == "file" then
                -- Coming actioned = true when we select a file and we action anything different to Show folder
                -- self.close_callback(file, true) in FileSearcher:onMenuSelect(item, callback)
                if actioned then
                    -- We want to go to the history in this case if no history to show what we changed
                    -- if not self.search_menu.ui.history.hist_menu and not require("apps/reader/readerui").instance then
                    --     local FileManager = require("apps/filemanager/filemanager")
                    --     FileManager.instance.history:onShowHist()
                    -- end
                    -- -- If no history we open it
                    -- if not self.search_menu.ui.history.hist_menu and require("apps/reader/readerui").instance then
                    --     local FileManager = require("apps/filemanager/filemanager")
                    --     require("apps/reader/readerui").instance.history:onShowHist()
                    -- end

                    -- if self.search_menu.ui.history.hist_menu then
                    --     self.search_menu.ui.history.hist_menu.close_callback()
                    -- end
                    local Event = require("ui/event")
                    UIManager:broadcastEvent(Event:new("CloseSearchMenu", self.recent, self.search_string))
                    return
                else
                    -- When we select a file and we action Show folder. Closing history if it is open, to go to the folder containing the file
                    if self.search_menu.ui.history.hist_menu then
                        self.search_menu.ui.history.hist_menu.close_callback()
                    end
                end
            else -- Directory
                -- Coming a directory when we select a directory and we action Show folder. Closing history if open to go to the folder
                if self.search_menu.ui.history.hist_menu then
                    self.search_menu.ui.history.hist_menu.close_callback()
                end

            end


            UIManager:close(self.search_menu)
        end
    -- end

    if page then
        self.search_menu:onGotoPage(page)
    end
    self:updateMenu(results)
    UIManager:show(self.search_menu)
    if self.no_metadata_count ~= 0 then
        self:showSearchResultsMessage()
    end
end

function FileSearcher:updateMenu(item_table)
    item_table = item_table or self.search_menu.item_table
    self.search_menu:switchItemTable(T(_("Search results (%1)"), #item_table), item_table, -1)
end

function FileSearcher:onMenuSelect(item, callback)
    if self._manager.selected_files then
        if item.is_file then
            item.dim = not item.dim and true or nil
            self._manager.selected_files[item.path] = item.dim
            self._manager:updateMenu()
        end
    else
        self._manager:showFileDialog(item, callback)
    end
end


function FileSearcher:showFileDialog(item, callback)
    local file = item.path
    local bookinfo, dialog
    local function close_dialog_callback()
        UIManager:close(dialog)
        -- local FileManager = require("apps/filemanager/filemanager")
        -- FileManager.instance.history:onShowHist()
        -- Pass false instead of the file
        self.search_menu.close_callback(file, true)

        -- if self.ui.history.hist_menu then
        --     self.ui.history.hist_menu.close_callback()
        -- end
        -- local Event = require("ui/event")
        -- UIManager:broadcastEvent(Event:new("ShowFileSearchAll"))
    end
    -- When Show folder in file to the callback in onShowFileSearchAll()
    local function close_dialog_menu_callback(file)
        UIManager:close(dialog)
        self.search_menu.close_callback(file, false)
    end
    local function update_item_callback()
        item.mandatory = FileChooser:getMenuItemMandatory(item, FileChooser:getCollate())
        self:updateMenu()
    end
    local buttons = {}
    if item.is_file then
        local is_currently_opened = self.ui.document and self.ui.document.file == file
        if DocumentRegistry:hasProvider(file) or DocSettings:hasSidecarFile(file) then
            bookinfo = self.ui.coverbrowser and self.ui.coverbrowser:getBookInfo(file)
            local doc_settings_or_file = is_currently_opened and self.ui.doc_settings or file
            table.insert(buttons, filemanagerutil.genStatusButtonsRow(doc_settings_or_file, close_dialog_callback))
            table.insert(buttons, {}) -- separator
            table.insert(buttons, {
                filemanagerutil.genResetSettingsButton(file, close_dialog_callback, is_currently_opened),
                -- The last change calls update_item_callback() but I will continue calling close_dialog_callback() and the search it will be reopened
                -- Basically because I close the dialog always there is an action in close_dialog_callback()
                self.ui.collections:genAddToCollectionButton(file, close_dialog_callback, close_dialog_callback),
            })
        end
        table.insert(buttons, {
            {
                text = _("Delete"),
                enabled = not is_currently_opened,
                callback = function()
                    local function post_delete_callback()
                        UIManager:close(dialog)
                        table.remove(self.search_menu.item_table, item.idx)
                        self:updateMenu()
                    end
                    local FileManager = require("apps/filemanager/filemanager")
                    FileManager:showDeleteFileDialog(file, post_delete_callback)
                end,
            },
            filemanagerutil.genBookInformationButton(file, bookinfo, close_dialog_callback),
        })
    end
    table.insert(buttons, {
        -- not require("apps/reader/readerui").instance and filemanagerutil.genShowFolderButton(file, close_dialog_menu_callback),
        filemanagerutil.genShowFolderButton(file, close_dialog_menu_callback),
        {
            text = _("Open"),
            enabled = DocumentRegistry:hasProvider(file, nil, true), -- allow auxiliary providers
            callback = function()
                local FileManager = require("apps/filemanager/filemanager")
                FileManager.openFile(self.ui, file)
                close_dialog_menu_callback()
            end,
        },
    })
    local title = file
    if bookinfo then
        if bookinfo.title then
            title = title .. "\n\n" .. T(_("Title: %1"), bookinfo.title)
        end
        if bookinfo.authors then
            title = title .. "\n" .. T(_("Authors: %1"), bookinfo.authors:gsub("[\n\t]", "|"))
        end
    end
    dialog = ButtonDialog:new{
        title = title .. "\n",
        buttons = buttons,
        -- tap_close_callback = callback,
    }
    UIManager:show(dialog)
end

function FileSearcher:onMenuHold(item)
    if self._manager.selected_files then return true end
    if item.is_file then
        if DocumentRegistry:hasProvider(item.path, nil, true) then
            self.close_callback()
            local FileManager = require("apps/filemanager/filemanager")
            FileManager.openFile(self.ui, item.path)
        end
    else
        self.close_callback()
        if self.ui.file_chooser then
            local pathname = util.splitFilePathName(item.path)
            self.ui.file_chooser:changeToPath(pathname, item.path)
        else -- called from Reader
            self.ui:onClose()
            self.ui:showFileManager(item.path)
        end
    end
    return true
end

function FileSearcher:setSelectMode()
    if self.selected_files then
        self:showSelectModeDialog()
    else
        self.selected_files = {}
        self.search_menu:setTitleBarLeftIcon("check")
    end
end

function FileSearcher:showSelectModeDialog()
    local item_table = self.search_menu.item_table
    local select_count = util.tableSize(self.selected_files)
    local actions_enabled = select_count > 0
    local title = actions_enabled and T(N_("1 file selected", "%1 files selected", select_count), select_count)
        or _("No files selected")
    local select_dialog
    local buttons = {
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
                    self:updateMenu()
                end,
            },
            {
                text = _("Select all"),
                callback = function()
                    UIManager:close(select_dialog)
                    for _, item in ipairs(item_table) do
                        if item.is_file then
                            item.dim = true
                            self.selected_files[item.path] = true
                        end
                    end
                    self:updateMenu()
                end,
            },
        },
        {
            {
                text = _("Exit select mode"),
                callback = function()
                    UIManager:close(select_dialog)
                    self.selected_files = nil
                    self.search_menu:setTitleBarLeftIcon("appbar.menu")
                    if actions_enabled then
                        for _, item in ipairs(item_table) do
                            item.dim = nil
                        end
                    end
                    self:updateMenu()
                end,
            },
            {
                text = _("Select in file browser"),
                enabled = actions_enabled,
                callback = function()
                    UIManager:close(select_dialog)
                    local selected_files = self.selected_files
                    self.search_menu.close_callback()
                    if self.ui.file_chooser then
                        if self.search_menu.ui.history.hist_menu then
                            self.search_menu.ui.history.hist_menu.close_callback()
                        end
                        self.ui.selected_files = selected_files
                        self.ui.title_bar:setRightIcon("check")
                        self.ui.file_chooser:refreshPath()
                    else -- called from Reader
                        self.ui:onClose()
                        self.ui:showFileManager(self.path .. "/", selected_files)
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

return FileSearcher
