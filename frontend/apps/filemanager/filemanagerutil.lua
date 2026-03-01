--[[--
This module contains miscellaneous helper functions for FileManager
]]

local BD = require("ui/bidi")
local BookList = require("ui/widget/booklist")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DocSettings = require("docsettings")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local Font = require("ui/font")
local _ = require("gettext")
local T = ffiUtil.template

local filemanagerutil = {}

function filemanagerutil.getDefaultDir()
    return Device.home_dir or "."
end

function filemanagerutil.abbreviate(path)
    if not path then return "" end
    if G_reader_settings:nilOrTrue("shorten_home_dir") then
        local home_dir = G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
        if path == home_dir or path == home_dir .. "/" then
            return _("Home")
        end
        local len = home_dir:len()
        local start = path:sub(1, len)
        if start == home_dir and path:sub(len+1, len+1) == "/" then
            return path:sub(len+2)
        end
    end
    return path
end

function filemanagerutil.splitFileNameType(filepath)
    local _, filename = util.splitFilePathName(filepath)
    local filename_without_suffix, filetype = util.splitFileNameSuffix(filename)
    filetype = filetype:lower()
    if filetype == "zip" then
        local filename_without_sub_suffix, sub_filetype = util.splitFileNameSuffix(filename_without_suffix)
        sub_filetype = sub_filetype:lower()
        local supported_sub_filetypes = { "fb2", "htm", "html", "log", "md", "rtf", "txt", }
        if util.arrayContains(supported_sub_filetypes, sub_filetype) then
            return filename_without_sub_suffix, sub_filetype .. ".zip"
        end
    end
    return filename_without_suffix, filetype
end

function filemanagerutil.getRandomFile(dir, match_func, max_files)
    local files = {}
    util.findFiles(dir, function(file)
        if match_func(file) then
            table.insert(files, file)
        end
    end, false, max_files)
    if #files > 0 then
        math.randomseed(os.time())
        return files[math.random(#files)]
    end
end

-- Purge doc settings except kept
function filemanagerutil.resetDocumentSettings(file)
    local settings_to_keep = {
        annotations = true,
        annotations_paging = true,
        annotations_rolling = true,
        bookmarks = true,
        bookmarks_paging = true,
        bookmarks_rolling = true,
        bookmarks_sorted_20220106 = true,
        bookmarks_version = true,
        cre_dom_version = true,
        highlight = true,
        highlight_paging = true,
        highlight_rolling = true,
        highlights_imported = true,
        last_page = true,
        last_xpointer = true,
    }
    local file_abs_path = ffiUtil.realpath(file)
    if file_abs_path then
        local doc_settings = DocSettings:open(file_abs_path)
        for k in pairs(doc_settings.data) do
            if not settings_to_keep[k] then
                doc_settings:delSetting(k)
            end
        end
        doc_settings:makeTrue("docsettings_reset_done") -- for readertypeset block_rendering_mode
        doc_settings:flush()
        BookList.setBookInfoCache(file_abs_path, doc_settings)
    end
end

-- Moved to booklist.lua
-- -- Get a document status ("new", "reading", "complete", or "abandoned")
-- function filemanagerutil.getStatus(file)
--     if DocSettings:hasSidecarFile(file) then
--         local summary = DocSettings:open(file):readSetting("summary")
--         if summary and summary.status and summary.status ~= "" then
--             return summary.status
--         end
--         return "reading"
--     end
--     -- Default status was new, now is call mbr
--     return "mbr"
--     -- local book_info = BookList.getBookInfo(file)
--     -- return book_info.been_opened and book_info.status or "new"
-- end

function filemanagerutil.getLastModified(file)
    if DocSettings:hasSidecarFile(file) then
        local summary = DocSettings:open(file):readSetting("summary")
        if summary and summary.modified and summary.modified ~= "" then
            return summary.modified
        end
        return nil
    end
    return nil
end

function filemanagerutil.saveSummary(doc_settings_or_file, summary)
    -- In case the book doesn't have a sidecar file, this'll create it
    if type(doc_settings_or_file) ~= "table" then
        doc_settings_or_file = DocSettings:open(doc_settings_or_file)
    end
    -- This code is not used but we could use it if needed
    -- The idea was removing the sidecar dir when putting the book to the tbr
    -- The dev has been made down when to_status == "tbr"
    -- if status == "tbr" and doc_settings_or_file.doc_sidecar_dir and util.pathExists(doc_settings_or_file.doc_sidecar_dir) then
    --     -- local purgeDir = require("ffi/util").purgeDir
    --     -- purgeDir(doc_settings_or_file.doc_sidecar_dir)
    --     -- doc_settings_or_file:purge()
    --     -- require("bookinfomanager"):deleteBookInfo(doc_settings_or_file.data.doc_path)
    --     -- local new = DocSettings:extend{}
    --     -- new:getSidecarDir(doc_settings_or_file.doc_sidecar_dir, "dir")
    -- end

    summary.modified = os.date("%Y-%m-%d", os.time())
    doc_settings_or_file:saveSetting("summary", summary)
    doc_settings_or_file:flush()
    return doc_settings_or_file
end

-- Generate all book status file dialog buttons in a row
function filemanagerutil.genStatusButtonsRow(doc_settings_or_file, caller_callback)
    local file, summary, status
    if type(doc_settings_or_file) == "table" then
        file = doc_settings_or_file:readSetting("doc_path")
        summary = doc_settings_or_file:readSetting("summary") or {}
        status = summary.status
    else
        file = doc_settings_or_file
        summary = {}
        status = BookList.getBookStatus(file)
    end
    local function genStatusButton(to_status)

        local enabled = false

        local ui = require("apps/reader/readerui").instance
        -- If we are not in the File Manager (we are in an opened book)
        -- don't allow to change the current reading book to the tbr
        -- because opened tbr books status is moved to reading when opening them (readerui.lua)
        -- don´t allow to change to any status
        if ui and ui.document and ui.document.file and file == ui.document.file then
            enabled = false
        else
            enabled = status ~= to_status
        end
        return {
            text = BookList.getBookStatusString(to_status, false, true) .. (status == to_status and "  ✓" or ""),
            enabled = enabled,
            callback = function()
                if to_status == "complete" then
                    require("readhistory"):removeItemByPath(file)
                end

                -- This is just for tbr, for abandoned (paused books) we don't want to remove the book settings
                local has_sidecar_file = DocSettings:hasSidecarFile(file)
                if to_status == "tbr" then
                    if has_sidecar_file then
                        -- If we put a book to the tbr, we want to remove all the info in the sidecar but the summary with the status
                        -- This is just in case it was in the TBR and previously opened
                        -- We also want to readd it to the history so that way we can reorder easily the tbr list if we want putting them on hold and back to tbr

                        -- A table will be coming from the fm and history and a file will be coming from the search list
                        if (type(doc_settings_or_file) == "table") then
                            doc_settings_or_file.data = {}
                            doc_settings_or_file:flush()
                        else
                            local doc_settings = DocSettings:open(file)
                            doc_settings.data.stats = {}
                            -- When coming from the search list because we set a book to be in tbr from there
                            -- The event DocSettingsItemsChanged won't change the cover cache because there are no covers in that view
                            -- Since we have to remove some stuff from here, we set percent_finished = nil and flush it the sidecar
                            -- Then when we go back to the FM view, we will have the cover without percentage if it was with percentage
                            doc_settings.data.percent_finished = nil
                            doc_settings:flush()
                        end
                    end
                    local first_element_history
                    if require("readhistory").hist and require("readhistory").hist[1] and require("readhistory").hist[1].file then
                        first_element_history = require("readhistory").hist[1].file
                    end
                    require("readhistory"):removeItemByPath(file)
                    require("readhistory"):addItem(file, os.time())

                    if first_element_history then
                        local DocSettings = require("docsettings")
                        local doc_settings = DocSettings:open(first_element_history)
                        local summary = doc_settings:readSetting("summary", {})
                        if summary.status == "reading" or (require("apps/reader/readerui").instance and require("apps/reader/readerui").instance.document and require("apps/reader/readerui").instance.document.file == first_element_history) then
                            require("readhistory"):removeItemByPath(first_element_history)
                            require("readhistory"):addItem(first_element_history, os.time() + 1)
                        end
                    end
                end

                summary.status = to_status
                filemanagerutil.saveSummary(doc_settings_or_file, summary)

                -- This is not necessary since there is a better way to refresh both history and fm:
                -- require("ui/widget/booklist").resetBookInfoCache(file)
                -- local ui = require("apps/filemanager/filemanager").instance
                -- if ui.history.hist_menu then
                --     ui.history:updateItemTable()
                -- end
                -- if ui.instance then
                --     ui.instance:onRefresh()
                -- end

                -- We just have to reset the cache:
                require("ui/widget/booklist").resetBookInfoCache(file)
                -- It is enough with this. When we reset the cache, this happens: BookList.book_info_cache[file] = nil
                -- So when BookList.getBookInfo() is invoked, the cached book information won't be found and it will be retrieved
                -- Empty if not sidecar: BookList.book_info_cache[file] = { been_opened = false }
                -- Or with the sidecar information if sidecar: BookList.setBookInfoCache(file, DocSettings:open(file))
                -- BookList.getBookInfo() is invoked in many places to retrieve the proper updated information
                -- require("bookinfomanager"):deleteBookInfo(file)

                if G_reader_settings:isTrue("top_manager_infmandhistory")
                    and util.getFileNameSuffix(file) == "epub"
                    and _G.all_files
                    and _G.all_files[file] then
                        _G.all_files[file].status = to_status
                        local pattern = "(%d+)-(%d+)-(%d+)"
                        local last_modified_date = filemanagerutil.getLastModified(file)
                        local ryear, rmonth, rday = last_modified_date:match(pattern)
                        _G.all_files[file].last_modified_year = ryear
                        _G.all_files[file].last_modified_month = rmonth
                        _G.all_files[file].last_modified_day = rday

                        local util = require("util")
                        util.generateStats()
                end
                caller_callback(file, to_status)
                local ui = require("apps/filemanager/filemanager").instance or require("apps/reader/readerui").instance
                ui.history:sortHistoryByStatus()
                if ui and ui.history and ui.history.booklist_menu then
                    ui.history:fetchStatuses(false)
                    ui.history:updateItemTable()
                end
            end,
        }
    end
    return {
        genStatusButton("reading"),
        genStatusButton("abandoned"),
        genStatusButton("tbr"),
        genStatusButton("complete"),
    }
end

function filemanagerutil.genMultipleStatusButtonsRow(files, caller_callback, button_disabled)
    local function genStatusButton(to_status)
        return {
            text = BookList.getBookStatusString(to_status, false, true),
            enabled = not button_disabled,
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = _("Set selected documents status?"),
                    ok_text = _("Set"),
                    ok_callback = function()
                        for file in pairs(files) do
                            local doc_settings = BookList.getDocSettings(file)
                            local summary = doc_settings:readSetting("summary") or {}
                            local has_sidecar_file = BookList.hasBookBeenOpened(file)
                            if to_status == "tbr" then
                                if has_sidecar_file then
                                    -- If we put a book to the tbr, we want to remove all the info in the sidecar but the summary with the status
                                    -- This is just in case it was in the TBR and previously opened
                                    -- We also want to readd it to the history so that way we can reorder easily the tbr list if we want putting them on hold and back to tbr
                                    doc_settings.data.stats = {}
                                    doc_settings.data.percent_finished = nil
                                    doc_settings:flush()
                                    require("ui/widget/booklist").resetBookInfoCache(file)
                                end
                                require("readhistory"):removeItemByPath(file)
                                require("readhistory"):addItem(file, os.time())
                            end
                            summary.status = to_status
                            filemanagerutil.saveSummary(doc_settings, summary)
                            BookList.setBookInfoCacheProperty(file, "status", to_status)
                            if G_reader_settings:isTrue("top_manager_infmandhistory")
                                and util.getFileNameSuffix(file) == "epub"
                                and _G.all_files
                                and _G.all_files[file] then
                                    _G.all_files[file].status = to_status
                                    local pattern = "(%d+)-(%d+)-(%d+)"
                                    local last_modified_date = filemanagerutil.getLastModified(file)
                                    local ryear, rmonth, rday = last_modified_date:match(pattern)
                                    _G.all_files[file].last_modified_year = ryear
                                    _G.all_files[file].last_modified_month = rmonth
                                    _G.all_files[file].last_modified_day = rday

                                    local util = require("util")
                                    util.generateStats()
                            end
                        end
                        caller_callback()
                    end,
                })
            end,
        }
    end
    return {
        genStatusButton("reading"),
        genStatusButton("tbr"),
        genStatusButton("abandoned"),
        genStatusButton("complete"),
    }
end

-- Generate "Reset" file dialog button
function filemanagerutil.genResetSettingsButton(doc_settings_or_file, caller_callback, button_disabled)
    local doc_settings, file, has_sidecar_file
    if type(doc_settings_or_file) == "table" then
        doc_settings = doc_settings_or_file
        file = doc_settings_or_file:readSetting("doc_path")
        has_sidecar_file = true
    else
        file = ffiUtil.realpath(doc_settings_or_file) or doc_settings_or_file
        has_sidecar_file = BookList.hasBookBeenOpened(file)
    end
    local custom_cover_file = DocSettings:findCustomCoverFile(file)
    local has_custom_cover_file = custom_cover_file and true or false
    local custom_metadata_file = DocSettings:findCustomMetadataFile(file)
    local has_custom_metadata_file = custom_metadata_file and true or false
    -- local text = "Add to MBR"
    -- local text2 = "Add this document to the MBR?"

    local in_history =  require("readhistory"):getIndexByFile(file)
    local text = "Reset/Add to MBR"
    local text2 = "Reset this document?"
    -- if debug.getinfo(2).name == "onMenuHold_orig" then
    --     text = "Add to MBR"
    --     text2 = "Add this document to the MBR?"
    -- end
    return {
        text = _(text),
        enabled = (not button_disabled and (has_sidecar_file or has_custom_metadata_file or has_custom_cover_file)) or not in_history,
        callback = function()
            local CheckButton = require("ui/widget/checkbutton")
            local ConfirmBox = require("ui/widget/confirmbox")
            local check_button_mbr, check_button_settings, check_button_cover, check_button_metadata
            local check_button_settings, check_button_cover, check_button_metadata
            local confirmbox = ConfirmBox:new{
                text = T(_(text2) .. "\n\n%1\n\n" ..
                         _("Information will be permanently lost."),
                    BD.filepath(file)),
                ok_text = _(text),
                flash_yes = true,
                ok_callback = function()
                    local first_element_history
                    if require("readhistory").hist and require("readhistory").hist[1] and require("readhistory").hist[1].file then
                        first_element_history = require("readhistory").hist[1].file
                    end
                    local data_to_purge = {
                        doc_settings         = check_button_settings.checked,
                        custom_cover_file    = check_button_cover.checked and custom_cover_file,
                        custom_metadata_file = check_button_metadata.checked and custom_metadata_file,
                    }
                    (doc_settings or DocSettings:open(file)):purge(nil, data_to_purge)

                    -- If Add to the history as MBR is not checked, it will be removed from the history always
                    if check_button_mbr.checked then
                        require("readhistory"):addItem(file, os.time())
                        require("apps/filemanager/filemanagerhistory"):sortHistoryByStatus()
                    else
                        require("readhistory"):removeItemByPath(file)
                    end

                    if data_to_purge.custom_cover_file or data_to_purge.custom_metadata_file then
                        UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", file))
                    end
                    if data_to_purge.doc_settings then
                        BookList.setBookInfoCacheProperty(file, "been_opened", false)
                        require("readhistory"):fileSettingsPurged(file)
                    end
                    if G_reader_settings:isTrue("top_manager_infmandhistory")
                        and util.getFileNameSuffix(file) == "epub"
                        and _G.all_files
                        and _G.all_files[file] then
                            if check_button_mbr.checked then
                                _G.all_files[file].status = "mbr"

                                if first_element_history then
                                    local DocSettings = require("docsettings")
                                    local doc_settings = DocSettings:open(first_element_history)
                                    local summary = doc_settings:readSetting("summary", {})
                                    if summary.status == "reading" or (require("apps/reader/readerui").instance and require("apps/reader/readerui").instance.document and require("apps/reader/readerui").instance.document.file == first_element_history) then
                                        require("readhistory"):removeItemByPath(first_element_history)
                                        require("readhistory"):addItem(first_element_history, os.time() + 1)
                                    end
                                end
                                G_reader_settings:flush()
                            else
                                _G.all_files[file].status = ""
                            end
                            _G.all_files[file].last_modified_year = 0
                            _G.all_files[file].last_modified_month = 0
                            _G.all_files[file].last_modified_day = 0
                            local util = require("util")
                            util.generateStats()
                    end
                    caller_callback(file, check_button_mbr.checked)
                end,
            }
            check_button_mbr = CheckButton:new{
                text = _("Add to the history as MBR"),
                checked = false,
                enabled = not in_history or (in_history and has_sidecar_file),
                parent = confirmbox,
            }

            confirmbox:addWidget(check_button_mbr)
            check_button_settings = CheckButton:new{
                text = _("document settings, progress, bookmarks, highlights, notes"),
                checked = has_sidecar_file,
                enabled = has_sidecar_file,
                parent = confirmbox,
            }
            confirmbox:addWidget(check_button_settings)
            check_button_cover = CheckButton:new{
                text = _("custom cover image"),
                checked = has_custom_cover_file,
                enabled = has_custom_cover_file,
                parent = confirmbox,
            }
            confirmbox:addWidget(check_button_cover)
            check_button_metadata = CheckButton:new{
                text = _("custom book metadata"),
                checked = has_custom_metadata_file,
                enabled = has_custom_metadata_file,
                parent = confirmbox,
            }
            confirmbox:addWidget(check_button_metadata)
            UIManager:show(confirmbox)
        end,
    }
end

function filemanagerutil.genMultipleResetSettingsButton(files, caller_callback, button_disabled)
    return {
        text = _("Reset"),
        enabled = not button_disabled,
        callback = function()
            UIManager:show(ConfirmBox:new{
                text = _("Reset selected documents?") .. "\n" ..
                       _("Information will be permanently lost."),
                ok_text = _("Reset"),
                ok_callback = function()
                    for file in pairs(files) do
                        if BookList.hasBookBeenOpened(file) then
                            DocSettings:open(file):purge()
                            UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", file))
                            BookList.setBookInfoCacheProperty(file, "been_opened", false)
                            require("readhistory"):fileSettingsPurged(file)
                        end
                        require("readhistory"):removeItemByPath(file)
                        if G_reader_settings:isTrue("top_manager_infmandhistory")
                            and util.getFileNameSuffix(file) == "epub"
                            and _G.all_files
                            and _G.all_files[file] then
                                _G.all_files[file].status = ""
                                _G.all_files[file].last_modified_year = 0
                                _G.all_files[file].last_modified_month = 0
                                _G.all_files[file].last_modified_day = 0
                            local util = require("util")
                            util.generateStats()
                        end
                    end
                    caller_callback()
                end,
            })
        end,
    }
end

function filemanagerutil.genShowFolderButton(file, caller_callback, button_disabled)
    return {
        text = _("Show folder"),
        enabled = not button_disabled,
        callback = function()
            caller_callback(file, false)
            local ui = require("apps/filemanager/filemanager").instance
            if ui then
                local pathname = util.splitFilePathName(file)
                ui.file_chooser:changeToPath(pathname, file)
                -- Since recently is possible to open the default collection from the history with a quick gesture. We close the history when in fm if opened. No needed if in ui
                -- For the file search lists it is done in the onCloseWidget() function
                -- if ui.history.booklist_menu then
                --     ui.history.booklist_menu.close_callback()
                -- end
            else
                ui = require("apps/reader/readerui").instance
                ui:onClose()
                ui:showFileManager(file)
                -- When the title bar is hijacked by the page text info plugin
                -- the fm instance when showing folder for folders will be restarted
                -- in search lists (when listing from the reader mode and only for directories).
                -- We have the new instance here so we can change to path
                local ui = require("apps/filemanager/filemanager").instance
                if ui.pagetextinfo and ui.pagetextinfo.settings:isTrue("enable_change_bar_menu") then
                    local pathname = util.splitFilePathName(file)
                    ui.file_chooser:changeToPath(pathname, file)
                    -- ui:showFiles(file)
                end
            end
        end,
    }
end

function filemanagerutil.genBookInformationButton(doc_settings_or_file, book_props, caller_callback, button_disabled)
    return {
        text = _("Book information"),
        enabled = not button_disabled,
        callback = function()
            caller_callback()
            local ui = require("apps/reader/readerui").instance or require("apps/filemanager/filemanager").instance
            ui.bookinfo:show(doc_settings_or_file, book_props and ui.bookinfo.extendProps(book_props))
        end,
    }
end

function filemanagerutil.genBookCoverButton(file, book_props, caller_callback, button_disabled)
    local has_cover = book_props and book_props.has_cover
    return {
        text = _("Book cover"),
        enabled = (not button_disabled and (not book_props or has_cover)) and true or false,
        callback = function()
            caller_callback()
            local ui = require("apps/reader/readerui").instance or require("apps/filemanager/filemanager").instance
            ui.bookinfo:onShowBookCover(file)
        end,
    }
end

function filemanagerutil.genBookDescriptionButton(file, book_props, caller_callback, button_disabled)
    local description = book_props and book_props.description
    return {
        text = _("Book description"),
        -- enabled for deleted books if description is kept in CoverBrowser bookinfo cache
        enabled = (not (button_disabled or book_props) or description) and true or false,
        callback = function()
            caller_callback()
            local ui = require("apps/reader/readerui").instance or require("apps/filemanager/filemanager").instance
            ui.bookinfo:onShowBookDescription(description, file)
        end,
    }
end

-- Generate "Execute script" file dialog button
function filemanagerutil.genExecuteScriptButton(file, caller_callback)
    return {
        -- @translators This is the script's programming language (e.g., shell or python)
        text = T(_("Execute %1 script"), util.getScriptType(file)),
        callback = function()
            filemanagerutil.executeScript(file, caller_callback)
        end,
    }
end

function filemanagerutil.executeScript(file, caller_callback)
    if caller_callback then
        caller_callback()
    end
    local InfoMessage = require("ui/widget/infomessage")
    local script_is_running_msg = InfoMessage:new{
        -- @translators %1 is the script's programming language (e.g., shell or python), %2 is the filename
        text = T(_("Running %1 script %2…"), util.getScriptType(file), BD.filename(ffiUtil.basename(file))),
    }
    UIManager:show(script_is_running_msg)
    UIManager:scheduleIn(0.5, function()
        local rv
        local output = ""
        if Device:isAndroid() then
            Device:setIgnoreInput(true)
            -- rv = os.execute("sh " .. ffiUtil.realpath(file)) -- run by sh, because sdcard has no execute permissions
            local execute = io.popen("sh " .. ffiUtil.realpath(file) .. " && echo $? || echo $?" ) -- run by sh, because sdcard has no execute permissions
            output = execute:read('*a')
            UIManager:show(InfoMessage:new{
                text = T(_(output)),
                face = Font:getFace("myfont"),
            })
            Device:setIgnoreInput(false)
        else
            -- rv = os.execute(ffiUtil.realpath(file))
            local execute = io.popen(ffiUtil.realpath(file) .. " && echo $? || echo $?" )
            output = execute:read('*a')
            UIManager:show(InfoMessage:new{
                text = T(_(output)),
                face = Font:getFace("myfont"),
            })
        end
        UIManager:close(script_is_running_msg)
        -- if rv == 0 then
        --     UIManager:show(InfoMessage:new{
        --         text = _("The script exited successfully."),
        --     })
        -- else
        --     --- @note: Lua 5.1 returns the raw return value from the os's system call. Counteract this madness.
        --     UIManager:show(InfoMessage:new{
        --         text = T(_("The script returned a non-zero status code: %1!"), bit.rshift(rv, 8)),
        --         icon = "notice-warning",
        --     })
        -- end
    end)
end

function filemanagerutil.showChooseDialog(title_header, caller_callback, current_path, default_path, file_filter)
    local is_file = file_filter and true or false
    local path = current_path or default_path
    local dialog
    local buttons = {
        {
            {
                text = is_file and _("Choose file") or _("Choose folder"),
                callback = function()
                    UIManager:close(dialog)
                    if path then
                        if is_file then
                            path = ffiUtil.dirname(path)
                        end
                        if lfs.attributes(path, "mode") ~= "directory" then
                            path = G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
                        end
                    end
                    local PathChooser = require("ui/widget/pathchooser")
                    local path_chooser = PathChooser:new{
                        select_directory = not is_file,
                        select_file = is_file,
                        show_files = is_file,
                        file_filter = file_filter,
                        path = path,
                        onConfirm = function(new_path)
                            caller_callback(new_path)
                        end,
                    }
                    UIManager:show(path_chooser)
                end,
            },
        }
    }
    if default_path then
        table.insert(buttons, {
            {
                text = _("Use default"),
                enabled = path ~= default_path,
                callback = function()
                    UIManager:close(dialog)
                    caller_callback(default_path)
                end,
            },
        })
    end
    local title_value = path and (is_file and BD.filepath(path) or BD.dirpath(path))
                              or _("not set")
    local ButtonDialog = require("ui/widget/buttondialog")
    dialog = ButtonDialog:new{
        title = title_header .. "\n\n" .. title_value .. "\n",
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function filemanagerutil.openFile(ui, file, caller_pre_callback, no_dialog)
    local openFile = function()
        if caller_pre_callback then
            caller_pre_callback()
        end
        if ui.document then -- Reader
            if ui.document.file ~= file then
                local DocumentRegistry = require("document/documentregistry")
                local provider = DocumentRegistry:getProvider(file, true) -- include auxiliary
                if provider and provider.order then -- auxiliary
                    -- keep the currently opened document, open the file over Reader
                    if provider.callback then -- module
                        provider.callback(file)
                    else -- plugin
                        ui[provider.provider]:openFile(file)
                    end
                else -- document
                    ui:switchDocument(file)
                end
            end
        else -- FM
            ui:openFile(file)
        end
    end

    if not no_dialog and G_reader_settings:isTrue("file_ask_to_open") then
        UIManager:show(ConfirmBox:new{
            text = _("Open this file?") .. "\n\n" .. BD.filename(file:match("([^/]+)$")),
            ok_text = _("Open"),
            ok_callback = openFile,
        })
    else
        openFile()
    end
end

return filemanagerutil
