local BD = require("ui/bidi")
local BookList = require("ui/widget/booklist")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local FileChooser = require("ui/widget/filechooser")
local FileManagerConverter = require("apps/filemanager/filemanagerconverter")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local Utf8Proc = require("ffi/utf8proc")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template

local FileSearcher = InputContainer:extend{
    case_sensitive = false,
    include_subfolders = true,
    include_metadata = false,
}

function FileSearcher:init()
    self:registerKeyEvents()
    if not self.ui.document then
        self.ui.menu:registerToMainMenu(self)
    end
end

function FileSearcher:registerKeyEvents()
    if Device:hasKeyboard() then
        self.key_events.ShowFileSearch = { { "Alt", "F" }, { "Ctrl", "F" } }
        self.key_events.ShowFileSearchBlank = { { "Alt", "Shift", "F" }, { "Ctrl", "Shift", "F" }, event = "ShowFileSearch", args = "" }
    end
end

function FileSearcher:addToMainMenu(menu_items)
    menu_items.file_search = {
        -- @translators Search for files by name.
        text = _("File search"),
        help_text = _([[Search a book by filename in the current or home folder and its subfolders.

Wildcards for one '?' or more '*' characters can be used.
A search for '*' will show all files.

The sorting order is the same as in filemanager.

Tap a book in the search results to open it.]]),
        callback = function()
            self:onShowFileSearch()
        end,
    }
    menu_items.file_search_results = {
        text = _("Last file search results"),
        callback = function()
            self:onShowSearchResults()
        end,
    }
end

function FileSearcher:onShowFileSearch(search_string, callbackfunc)
    local search_dialog, check_button_case, check_button_subfolders, check_button_metadata
    local function _doSearch()
        local search_str = search_dialog:getInputText()
        if search_str == "" then return end
        FileSearcher.search_string = search_str
        UIManager:close(search_dialog)
        self.case_sensitive = check_button_case.checked
        self.include_subfolders = check_button_subfolders.checked
        self.include_metadata = check_button_metadata and check_button_metadata.checked
        local Trapper = require("ui/trapper")
        Trapper:wrap(function()
            self:doSearch()
        end)
    end
    local callback_func = false
    self.recent = false
    search_dialog = InputDialog:new{
        title = _("Enter text to search for in filename"),
        input = search_string or FileSearcher.search_string,
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
                        FileSearcher.search_path = G_reader_settings:readSetting("home_dir")
                        _doSearch()
                    end,
                },
                {
                    text = self.ui.file_chooser and _("Current folder") or _("Book folder"),
                    is_enter_default = true,
                    callback = function()
                        FileSearcher.search_path = self.ui.file_chooser and self.ui.file_chooser.path or self.ui:getLastDirFile()
                        _doSearch()
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
    check_button_subfolders = CheckButton:new{
        text = _("Include subfolders"),
        checked = self.include_subfolders,
        parent = search_dialog,
    }
    search_dialog:addWidget(check_button_subfolders)
    if self.ui.coverbrowser then
        check_button_metadata = CheckButton:new{
            text = _("Also search in book metadata"),
            checked = self.include_metadata,
            parent = search_dialog,
        }
        search_dialog:addWidget(check_button_metadata)
    end
    UIManager:show(search_dialog)
    search_dialog:onShowKeyboard()
    return true
end

function FileSearcher:onShowFileSearchLists(recent, search_string)
    FileSearcher.search_path = G_reader_settings:readSetting("home_dir")
    FileSearcher.search_string = search_string
    if FileSearcher.search_string == nil then
        FileSearcher.search_string = "*.epub"
    end
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    self.path = G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
    self.case_sensitive = false
    self.include_subfolders = true
    self.include_metadata = false
    self.recent = recent

    -- self:onSearchSortCompleted(false, recent, page, nil, sorted_size)
    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
        self:doSearchCompleted(false, recent)
    end)
end

function FileSearcher:onShowFileSearchAllCompleted()
    FileSearcher.search_path = G_reader_settings:readSetting("home_dir")
    FileSearcher.search_string = "*.epub"
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    self.path = G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
    self.case_sensitive = false
    self.include_subfolders = true
    self.include_metadata = false
    -- self:onSearchSortCompleted(false, recent, page, nil, sorted_size)
    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
        self:doSearchCompleted(true, nil)
    end)
end

function FileSearcher:doSearch(callbackfunc)
    local search_hash = FileSearcher.search_path .. (FileSearcher.search_string or "") ..
        tostring(self.case_sensitive) .. tostring(self.include_subfolders) .. tostring(self.include_metadata) .. select(2, FileChooser:getCollate())
    local not_cached = FileSearcher.search_hash ~= search_hash
    if not_cached then
        local Trapper = require("ui/trapper")
        local info = InfoMessage:new{ text = _("Searching… (tap to cancel)") }
        UIManager:show(info)
        -- UIManager:forceRePaint()
        local completed, dirs, files, no_metadata_count = Trapper:dismissableRunInSubprocess(function()
            return self:getList()
        end, info)
        if not completed then return end
        UIManager:close(info)
        FileSearcher.search_hash = search_hash
        self.no_metadata_count = no_metadata_count
        -- Cannot do this in getList() within Trapper (cannot serialize function)
        local fc = self.ui.file_chooser or FileChooser:new{ ui = self.ui }
        local collate = fc:getCollate()
        for i, v in ipairs(dirs) do
            local f, fullpath, attributes = unpack(v)
            dirs[i] = fc:getListItem(nil, f, fullpath, attributes, collate)
        end
        for i, v in ipairs(files) do
            local f, fullpath, attributes = unpack(v)
            files[i] = fc:getListItem(nil, f, fullpath, attributes, collate)
        end
        FileSearcher.search_results = fc:genItemTable(dirs, files)
    end
    if #FileSearcher.search_results > 0 then
        self:onShowSearchResults(not_cached) --self:showSearchResults(results, nil, nil, callbackfunc)
    else
        self:showSearchResultsMessage(true)
    end
end


function FileSearcher:showSearchResultsComplete(results, callback)
    self.booklist_menu = Menu:new{
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
        self.booklist_menu.close_callback = callback
    else
        self.booklist_menu.close_callback = function()
            self:refreshFileManager()
            UIManager:close(self.booklist_menu)
            self.booklist_menu = nil
            if self.selected_files then
                self.selected_files = nil
                for _, item in ipairs(FileSearcher.search_results) do
                    item.dim = nil
                end
            end
        end
    end

    UIManager:show(self.booklist_menu)
    if self.no_metadata_count ~= 0 then
        self:showSearchResultsMessage()
    end
end

function FileSearcher:doSearchCompleted(show_complete, show_recent)
    local search_hash = self.path .. (FileSearcher.search_string or "") ..
        tostring(self.case_sensitive) .. tostring(self.include_subfolders) .. tostring(self.include_metadata) .. select(2, FileChooser:getCollate())
    local not_cached = true -- FileSearcher.search_hash ~= search_hash I don't want to cache for this case
    if not_cached then
        local Trapper = require("ui/trapper")
        local info = InfoMessage:new{ text = _("Searching… (tap to cancel)") }
        UIManager:show(info)
        -- UIManager:forceRePaint()
        local completed, dirs, files, no_metadata_count = Trapper:dismissableRunInSubprocess(function()
            return self:getList()
        end, info)
        if not completed then return end
        UIManager:close(info)
        FileSearcher.search_hash = search_hash
        self.no_metadata_count = no_metadata_count
        -- Cannot do this in getList() within Trapper (cannot serialize function)
        local collate = FileChooser:getCollate()
        for i, v in ipairs(dirs) do
            local f, fullpath, attributes = unpack(v)
            dirs[i] = FileChooser:getListItem(nil, f, fullpath, attributes, collate)
        end
        for i, v in ipairs(files) do
            local f, fullpath, attributes = unpack(v)
            files[i] = FileChooser:getListItem(nil, f, fullpath, attributes, collate)
        end
        -- If we have a FileChooser instance, use it, to be able to make use of its natsort cache
        FileSearcher.search_results = (self.ui.file_chooser or FileChooser):genItemTable(dirs, files)
        if show_complete and show_recent then
            table.sort(FileSearcher.search_results,function(a,b) return b.text>a.text end)
        end
        if (show_complete) then
            local table_complete = {}
            for key, value in ipairs(FileSearcher.search_results) do
                if require("docsettings"):hasSidecarFile(value.path) then
                    -- local stats = doc_settings:readSetting("stats")
                    -- local book_props = require("apps/filemanager/filemanagerbookinfo").getDocProps(value.path).description
                    local doc_settings = require("docsettings"):open(value.path)
                    local status = doc_settings:readSetting("summary").status
                    local modified_date = doc_settings:readSetting("summary").modified
                    if status == "complete" then
                        value.modified_date = modified_date
                        value.text = modified_date .. " " .. value.text --.. value.text:gsub(string.match(value.text , "^.+(%..+)$"), "")
                        table_complete[#table_complete+1] = value
                    end
                end
            end
            FileSearcher.search_results = table_complete
            table.sort(FileSearcher.search_results, function(a, b) return a.modified_date > b.modified_date end)
        else
            if show_recent then
                table.sort(FileSearcher.search_results, function(a, b) return a.attr.modification > b.attr.modification end)
            end
        end
    end
    -- Delay the search menu closure until here instead of in onCloseSearchMenu() so history is not shown when search menu it is reloaded
    UIManager:close(self.booklist_menu)
    if #FileSearcher.search_results > 0 then
        self:onShowSearchResults(not_cached, show_complete, show_recent)  --self:showSearchResults(results, nil, nil, callbackfunc)
    else
        self:showSearchResultsMessage(true)
    end
end

function FileSearcher:getList()
    self.no_metadata_count = 0 -- will be updated in doSearch() with result from subprocess
    local sys_folders = { -- do not search in sys_folders
        ["/dev"] = true,
        ["/proc"] = true,
        ["/sys"] = true,
        ["/mnt/base-us"] = true, -- Kindle
    }
    local search_string = FileSearcher.search_string

    local words = {}
    if search_string:find("|") then
        for word in string.gmatch(search_string, '([^%|]+)') do -- We scape | using %|
            table.insert(words, word)
        end
    end
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
    local scan_dirs = { FileSearcher.search_path }
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
                            table.insert(dirs, { f, fullpath, attributes })
                        end
                    -- Always ignore macOS resource forks, too.
                    elseif attributes.mode == "file" and not util.stringStartsWith(f, "._")
                            and (FileChooser.show_unsupported or DocumentRegistry:hasProvider(fullpath))
                            and FileChooser:show_file(f) then
                        if #words > 0 then
                            for _, word in ipairs(words) do
                                local title = word:sub(1, word:find("-") - 2)
                                if title:find("%(") then
                                    title = title:sub(1, title:find("%(") - 2)
                                end
                                -- local author = word:sub(word:find("-") + 2, word:len()):gsub(".epub", "")
                                if fullpath:find(title) then
                                    table.insert(dirs, { f, fullpath, attributes })
                                end
                            end
                        else
                            print(fullpath)
                            if self:isFileMatch(f, fullpath, search_string, true) then
                                table.insert(dirs, { f, fullpath, attributes })
                                -- local file = FileChooser:getListItem(nil, f, fullpath, attributes, collate)
                                -- file.pages = calibre_data[file.text] and calibre_data[file.text].pages or 0
                                -- file.words = calibre_data[file.text] and calibre_data[file.text].words or 0
                                -- table.insert(files, file)
                            end
                        end
                    end
                end
            end
        end
        scan_dirs = new_dirs
    end
    return dirs, files, self.no_metadata_count
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
        local book_props = self.ui.bookinfo:getDocProps(fullpath, nil, true) -- do not open the document
        if next(book_props) ~= nil then
            return self.ui.bookinfo:findInProps(book_props, search_string, self.case_sensitive)
        else
            self.no_metadata_count = self.no_metadata_count + 1
        end
    end
end

function FileSearcher:showSearchResultsMessage(no_results)
    local text = no_results and T(_("No results for '%1'."), FileSearcher.search_string)
    if self.no_metadata_count == 0 then
        UIManager:show(ConfirmBox:new{
            text = text,
            icon = "notice-info",
            ok_text = _("File search"),
            ok_callback = function()
                self:onShowFileSearch()
            end,
        })
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
                    self.booklist_menu.close_callback()
                end
                self.ui.coverbrowser:extractBooksInDirectory(FileSearcher.search_path)
            end,
        })
    end
end

function FileSearcher:refreshFileManager()
    if self.files_updated then
        if self.ui.file_chooser then
            self.ui.file_chooser:refreshPath()
        end
        self.files_updated = nil
    end
end

function FileSearcher:onShowSearchResults(not_cached, results, show_recent)
    if not not_cached and FileSearcher.search_results == nil then
        self:onShowFileSearch()
        return true
    end

   -- This may be hijacked by CoverBrowser plugin and needs to be known as booklist_menu.
    self.booklist_menu = BookList:new{
        name = "filesearcher",
        title = "filesearcher",
        subtitle = T(_("Query: %1"), FileSearcher.search_string),
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function() self:setSelectMode() end,
        onMenuSelect = self.onMenuSelect,
        onMenuHold = self.onMenuHold,
        ui = self.ui,
        _manager = self,
        _recreate_func = function() self:onShowSearchResults(not_cached) end,
    }
    self.booklist_menu.close_callback = function()
        self:refreshFileManager()
        if self.ui.history.booklist_menu then
            self.ui.history:fetchStatuses(false)
            self.ui.history:updateItemTable()
        end
        UIManager:close(self.booklist_menu)
        self.booklist_menu = nil
        if self.selected_files then
            self.selected_files = nil
            for _, item in ipairs(FileSearcher.search_results) do
                item.dim = nil
            end
        end
    end
    self:updateItemTable(FileSearcher.search_results)
    UIManager:show(self.booklist_menu)
    if not_cached and self.no_metadata_count ~= 0 then
        self:showSearchResultsMessage()
    end
    return true
end

function FileSearcher:updateItemTable(item_table)
    if item_table == nil then
        item_table = self.booklist_menu.item_table
    end
    local title = T(_("Search results (%1)"), #item_table)
    self.booklist_menu:switchItemTable(title, item_table, -1)
end

function FileSearcher:onMenuSelect(item, callback)
    if lfs.attributes(item.path) == nil then return end
    if self._manager.selected_files then
        if item.is_file then
            item.dim = not item.dim and true or nil
            self._manager.selected_files[item.path] = item.dim
            self._manager:updateItemTable()
        end
    else
        if item.is_file then
            if DocumentRegistry:hasProvider(item.path, nil, true) then
                if G_reader_settings:isTrue("top_manager_infmandhistory")
                and item.path
                and util.getFileNameSuffix(item.path) == "epub"
                and _G.all_files
                and _G.all_files[item.path]
                and (_G.all_files[item.path].status == "mbr"
                    or _G.all_files[item.path].status == "tbr"
                    or _G.all_files[item.path].status == "new"
                    or _G.all_files[item.path].status == "complete") then
                    local MultiConfirmBox = require("ui/widget/multiconfirmbox")
                    local text = ", do you want to open it?"
                    if _G.all_files[item.path].status == "mbr" then
                        text = "Book in MBR" .. text
                    elseif _G.all_files[item.path].status == "tbr" then
                        text = "Book in TBR" .. text
                    elseif _G.all_files[item.path].status == "new" then
                        text = "Book not opened" .. text
                    else
                        text = "Book finished" .. text
                    end

                    local multi_box= MultiConfirmBox:new{
                        text = text,
                        choice1_text = _("Yes"),
                        choice1_callback = function()
                            self.close_callback()
                            if self.ui.history.booklist_menu then
                                UIManager:close(self.ui.history.booklist_menu)
                            end
                            local FileManager = require("apps/filemanager/filemanager")
                            FileManager.openFile(self.ui, item.path)
                        end,
                        choice2_text = _("Do not open it"),
                        choice2_callback = function()
                            return
                        end,
                        cancel_callback = function()
                            return
                        end,
                    }
                    UIManager:show(multi_box)
                    return false
                else
                    self.close_callback()
                    if self.ui.history.booklist_menu then
                        UIManager:close(self.ui.history.booklist_menu)
                    end
                    local FileManager = require("apps/filemanager/filemanager")
                    FileManager.openFile(self.ui, item.path)
                end
            end
        else
            if self.ui.history.booklist_menu then
                UIManager:close(self.ui.history.booklist_menu)
            end
            self._manager.update_files = nil
            self.close_callback()
            if self.ui.file_chooser then
                local pathname = util.splitFilePathName(item.path)
                self.ui.file_chooser:changeToPath(pathname, item.path)
            else -- called from Reader
                self.ui:onClose()
                self.ui:showFileManager(item.path)
                -- When the title bar is hijacked by the page text info plugin
                -- the fm instance when showing folder for folders will be restarted
                -- in search lists (when listing from the reader mode and only for directories).
                -- We have the new instance here so we can change to path
                local ui = require("apps/filemanager/filemanager").instance
                if self.ui.pagetextinfo and self.ui.pagetextinfo.settings:isTrue("enable_change_bar_menu") then
                    local pathname = util.splitFilePathName(item.path)
                    ui.file_chooser:changeToPath(pathname, item.path)
                    -- ui:showFiles(item.path)
                end
            end
        end
    end
end

function FileSearcher:onMenuHold(item)
    if self._manager.selected_files or lfs.attributes(item.path) == nil then return true end
    local file = item.path
    local is_file = item.is_file or false
    self.file_dialog = nil

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
    end
    local function close_menu_refresh_callback()
        self._manager.files_updated = true
        self.close_callback()
    end

    local buttons = {}
    local book_props, is_currently_opened
    if is_file then
        local has_provider = DocumentRegistry:hasProvider(file)
        local been_opened = BookList.hasBookBeenOpened(file)
        local doc_settings_or_file = file
        if has_provider or been_opened then
            book_props = self.ui.coverbrowser and self.ui.coverbrowser:getBookInfo(file)
            is_currently_opened = file == (self.ui.document and self.ui.document.file)
            if is_currently_opened then
                doc_settings_or_file = self.ui.doc_settings
                if not book_props then
                    book_props = self.ui.doc_props
                    book_props.has_cover = true
                end
            elseif been_opened then
                doc_settings_or_file = BookList.getDocSettings(file)
                if not book_props then
                    local props = doc_settings_or_file:readSetting("doc_props")
                    book_props = self.ui.bookinfo.extendProps(props, file)
                    book_props.has_cover = true
                end
            end
            table.insert(buttons, filemanagerutil.genStatusButtonsRow(doc_settings_or_file, close_dialog_update_callback))
            table.insert(buttons, {}) -- separator
            table.insert(buttons, {
                filemanagerutil.genResetSettingsButton(doc_settings_or_file, close_dialog_update_callback, is_currently_opened),
                self._manager.ui.collections:genAddToCollectionButton(file, close_dialog_callback, close_dialog_update_callback),
            })
        end
        if Device:canExecuteScript(file) then
            table.insert(buttons, {
                filemanagerutil.genExecuteScriptButton(file, close_dialog_menu_callback)
            })
        end
        if FileManagerConverter:isSupported(file) then
            table.insert(buttons, {
                FileManagerConverter:genConvertButton(file, close_dialog_callback, close_menu_refresh_callback)
            })
        end
        table.insert(buttons, {
            {
                text = _("Delete"),
                enabled = not is_currently_opened,
                callback = function()
                    local function post_delete_callback()
                        table.remove(FileSearcher.search_results, item.idx)
                        table.remove(self.item_table, item.idx)
                        close_dialog_update_callback()
                    end
                    local FileManager = require("apps/filemanager/filemanager")
                    FileManager:showDeleteFileDialog(file, post_delete_callback)
                end,
            },
            {
                text = _("Open with…"),
                callback = function()
                    close_dialog_callback()
                    local FileManager = require("apps/filemanager/filemanager")
                    FileManager.showOpenWithDialog(self.ui, file)
                end,
            },
        })
        table.insert(buttons, {
            filemanagerutil.genShowFolderButton(file, close_dialog_menu_callback2),
            filemanagerutil.genBookInformationButton(doc_settings_or_file, book_props, close_dialog_callback),
        })
        if has_provider then
            table.insert(buttons, {
                filemanagerutil.genBookCoverButton(file, book_props, close_dialog_callback),
                filemanagerutil.genBookDescriptionButton(file, book_props, close_dialog_callback),
            })
        end
    else -- folder
        table.insert(buttons, {
            filemanagerutil.genShowFolderButton(file, close_dialog_menu_callback2),
        })
    end

    if self._manager.file_dialog_added_buttons ~= nil then
        for _, row_func in ipairs(self._manager.file_dialog_added_buttons) do
            local row = row_func(file, true, book_props)
            if row ~= nil then
                table.insert(buttons, row)
            end
        end
    end

    local title = file:gsub(".epub","")
    title = select(2, util.splitFilePathName(title))
    if self._manager.ui.history.calibre_data[item.text]
        and self._manager.ui.history.calibre_data[item.text]["pubdate"]
        and self._manager.ui.history.calibre_data[item.text]["words"]
        and self._manager.ui.history.calibre_data[item.text]["grrating"]
        and self._manager.ui.history.calibre_data[item.text]["grvotes"] then
            title = title .. ", " ..  self._manager.ui.history.calibre_data[item.text]["pubdate"]:sub(1, 4)
            .. " - " .. self._manager.ui.history.calibre_data[item.text]["grrating"] .. "★ ("
            .. self._manager.ui.history.calibre_data[item.text]["grvotes"] .. ") - "
            .. tostring(math.floor(self._manager.ui.history.calibre_data[item.text]["words"]/1000)) .."kw"
    end
    if bookinfo then
        if bookinfo.title then
            title = title .. "\n\n" .. T(_("Title: %1"), bookinfo.title)
        end
        if bookinfo.authors then
            title = title .. "\n" .. T(_("Authors: %1"), bookinfo.authors:gsub("[\n\t]", "|"))
        end
    end
    self.file_dialog = ButtonDialog:new{
        title = title .. "\n",
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.file_dialog)
    return true
end

function FileSearcher.getMenuInstance()
    local ui = require("apps/filemanager/filemanager").instance or require("apps/reader/readerui").instance
    return ui.filesearcher.booklist_menu
end

function FileSearcher:setSelectMode()
    if self.selected_files then
        self:showSelectModeDialog()
    else
        self.selected_files = {}
        self.booklist_menu:setTitleBarLeftIcon("check")
    end
end

function FileSearcher:showSelectModeDialog()
    local item_table = self.booklist_menu.item_table
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
                    self:updateItemTable()
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
                    self:updateItemTable()
                end,
            },
        },
        {
            {
                text = _("Exit select mode"),
                callback = function()
                    UIManager:close(select_dialog)
                    self.selected_files = nil
                    self.booklist_menu:setTitleBarLeftIcon("appbar.menu")
                    if actions_enabled then
                        for _, item in ipairs(item_table) do
                            item.dim = nil
                        end
                    end
                    self:updateItemTable()
                end,
            },
            {
                text = _("Select in file browser"),
                enabled = actions_enabled,
                callback = function()
                    UIManager:close(select_dialog)
                    local selected_files = self.selected_files
                    self.files_updated = nil -- refresh fm later
                    self.booklist_menu.close_callback()
                    if self.ui.file_chooser then
                        self.ui.selected_files = selected_files
                        self.ui.title_bar:setRightIcon("check")
                        self.ui.file_chooser:refreshPath()
                    else -- called from Reader
                        self.ui:onClose()
                        self.ui:showFileManager(FileSearcher.search_path .. "/", selected_files)
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

function FileSearcher.getMenuInstance()
    local ui = require("apps/filemanager/filemanager").instance or require("apps/reader/readerui").instance
    return ui.filesearcher.booklist_menu
end

function FileSearcher:setSelectMode()
    if self.selected_files then
        self:showSelectModeDialog()
    else
        self.selected_files = {}
        self.booklist_menu:setTitleBarLeftIcon("check")
    end
end

function FileSearcher:showSelectModeDialog()
    local item_table = self.booklist_menu.item_table
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
                    self:updateItemTable()
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
                    self:updateItemTable()
                end,
            },
        },
        {
            {
                text = _("Exit select mode"),
                callback = function()
                    UIManager:close(select_dialog)
                    self.selected_files = nil
                    self.booklist_menu:setTitleBarLeftIcon("appbar.menu")
                    if actions_enabled then
                        for _, item in ipairs(item_table) do
                            item.dim = nil
                        end
                    end
                    self:updateItemTable()
                end,
            },
            {
                text = _("Select in file browser"),
                enabled = actions_enabled,
                callback = function()
                    UIManager:close(select_dialog)
                    local selected_files = self.selected_files
                    self.files_updated = nil -- refresh fm later
                    self.booklist_menu.close_callback()
                    if self.ui.history.booklist_menu then
                        UIManager:close(self.ui.history.booklist_menu)
                    end
                    if self.ui.file_chooser then
                        self.ui.selected_files = selected_files
                        self.ui.title_bar:setRightIcon("check")
                        self.ui.file_chooser:refreshPath()
                    else -- called from Reader
                        self.ui:onClose()
                        self.ui:showFileManager(FileSearcher.search_path .. "/", selected_files)
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

function FileSearcher:onBookMetadataChanged()
    if self.booklist_menu then
        self.booklist_menu:updateItems()
    end
end

function FileSearcher:onCloseWidget()
    if self.booklist_menu then
        self.booklist_menu.close_callback()
    end
end

return FileSearcher
