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

function FileSearcher:onShowFileSearchAll()
    local search_dialog
    local check_button_case, check_button_subfolders, check_button_metadata
    self.path = G_reader_settings:readSetting("home_dir")
    self.search_string = "*.epub"
    self:onSearchSortCompleted(false, false)
end

function FileSearcher:onShowFileSearchAllRecent(callback)
    local search_dialog
    local check_button_case, check_button_subfolders, check_button_metadata
    self.path = G_reader_settings:readSetting("home_dir")
    self.search_string = "*.epub"
    self:onSearchSortCompleted(false, true, callback)
end

function FileSearcher:oncloseSearchMenu(callback)
    local callback_func = function(close)
        self.ui.history:fetchStatuses(false)
        self.ui.history:updateItemTable()
        if close then
            local Event = require("ui/event")
            UIManager:broadcastEvent(Event:new("closeSearchMenu"))
        end
    end
    UIManager:close(self.search_menu)
    self:onShowFileSearchAllRecent(callback_func)
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
    if self.ui.file_chooser then
        results = self.ui.file_chooser:genItemTable(dirs, files)
    else
        results = FileChooser:genItemTable(dirs, files)
    end
    if #results > 0 then
        self:showSearchResults(results, callbackfunc)
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

function FileSearcher:onSearchSortCompleted(show_complete, show_recent, callback)
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
    if (show_complete) then
        local table_complete = {}
        for key,value in ipairs(results) do
            if DocSettings:hasSidecarFile(value.path) then
                -- local stats = doc_settings:readSetting("stats")
                -- local book_props = require("apps/filemanager/filemanagerbookinfo").getDocProps(value.path).description
                local doc_settings = DocSettings:open(value.path)
                local status = doc_settings:readSetting("summary").status
                if status == "complete" then
                    table_complete[#table_complete+1] = value
                end


            end
        end
        results = table_complete
    else
        if show_recent then
            table.sort(results,function(a,b) return a.attr.modification>b.attr.modification end)
        end
    end

    if #results > 0 then
        if (show_complete) then
            self:showSearchResultsComplete(results, callback)
        else
            self:showSearchResults(results, callback)
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

function FileSearcher:showSearchResults(results, callback)
    self.search_menu = Menu:new{
        title = T(_("Search results (%1)"), #results),
        subtitle = T(_("Query: %1"), self.search_string),
        item_table = results,
        ui = self.ui,
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        onMenuSelect = self.onMenuSelect,
        onMenuHold = self.onMenuHold,
        handle_hold_on_hold_release = true,
    }

    if callback then
        self.search_menu.close_callback = callback
        -- UIManager:close(self.search_menu)
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

function FileSearcher:onMenuSelect(item, callback)
    local file = item.path
    local bookinfo, dialog
    local function close_dialog_callback()
        UIManager:close(dialog)
        local FileManager = require("apps/filemanager/filemanager")
        -- FileManager.instance.history:onShowHist()
        self.close_callback(true)

        -- local Event = require("ui/event")
        -- UIManager:broadcastEvent(Event:new("ShowFileSearchAllRecent"))
    end
    local function close_dialog_menu_callback()
        UIManager:close(dialog)
        self.close_callback()
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
                self.ui.collections:genAddToCollectionButton(file, close_dialog_callback),
            })
        end
        table.insert(buttons, {
            {
                text = _("Delete"),
                enabled = not is_currently_opened,
                callback = function()
                    local function post_delete_callback()
                        UIManager:close(dialog)
                        for i, menu_item in ipairs(self.item_table) do
                            if menu_item.path == file then
                                table.remove(self.item_table, i)
                                break
                            end
                            self:switchItemTable(T(_("Search results (%1)"), #self.item_table), self.item_table)
                        end
                    end
                    local FileManager = require("apps/filemanager/filemanager")
                    FileManager:showDeleteFileDialog(file, post_delete_callback)
                end,
            },
            filemanagerutil.genBookInformationButton(file, bookinfo, close_dialog_callback),
        })
    end
    table.insert(buttons, {
        filemanagerutil.genShowFolderButton(file, close_dialog_menu_callback),
        {
            text = _("Open"),
            enabled = DocumentRegistry:hasProvider(file, nil, true), -- allow auxiliary providers
            callback = function()
                close_dialog_callback()
                local FileManager = require("apps/filemanager/filemanager")
                FileManager.openFile(self.ui, file, nil, self.close_callback)
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
    if item.is_file then
        if DocumentRegistry:hasProvider(item.path, nil, true) then
            local FileManager = require("apps/filemanager/filemanager")
            FileManager.openFile(self.ui, item.path, nil, self.close_callback)
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

return FileSearcher
