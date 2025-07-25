--[[
ReaderUI is an abstraction for a reader interface.

It works using data gathered from a document interface.
]]--

local Archiver = require("ffi/archiver")
local BD = require("ui/bidi")
local BookList = require("ui/widget/booklist")
local Device = require("device")
local DeviceListener = require("device/devicelistener")
local DocCache = require("document/doccache")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local Event = require("ui/event")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local FileManagerCollection = require("apps/filemanager/filemanagercollection")
local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local FileManagerFileSearcher = require("apps/filemanager/filemanagerfilesearcher")
local FileManagerShortcuts = require("apps/filemanager/filemanagershortcuts")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LanguageSupport = require("languagesupport")
local NetworkListener = require("ui/network/networklistener")
local Notification = require("ui/widget/notification")
local PluginLoader = require("pluginloader")
local ReaderActivityIndicator = require("apps/reader/modules/readeractivityindicator")
local ReaderAnnotation = require("apps/reader/modules/readerannotation")
local ReaderBack = require("apps/reader/modules/readerback")
local ReaderBookmark = require("apps/reader/modules/readerbookmark")
local ReaderConfig = require("apps/reader/modules/readerconfig")
local ReaderCoptListener = require("apps/reader/modules/readercoptlistener")
local ReaderCropping = require("apps/reader/modules/readercropping")
local ReaderDeviceStatus = require("apps/reader/modules/readerdevicestatus")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local ReaderFont = require("apps/reader/modules/readerfont")
local ReaderGoto = require("apps/reader/modules/readergoto")
local ReaderHandMade = require("apps/reader/modules/readerhandmade")
local ReaderHinting = require("apps/reader/modules/readerhinting")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local ReaderScrolling = require("apps/reader/modules/readerscrolling")
local ReaderKoptListener = require("apps/reader/modules/readerkoptlistener")
local ReaderLink = require("apps/reader/modules/readerlink")
local ReaderMenu = require("apps/reader/modules/readermenu")
local ReaderPageMap = require("apps/reader/modules/readerpagemap")
local ReaderPanning = require("apps/reader/modules/readerpanning")
local ReaderPaging = require("apps/reader/modules/readerpaging")
local ReaderRolling = require("apps/reader/modules/readerrolling")
local ReaderSearch = require("apps/reader/modules/readersearch")
local ReaderStatus = require("apps/reader/modules/readerstatus")
local ReaderStyleTweak = require("apps/reader/modules/readerstyletweak")
local ReaderThumbnail = require("apps/reader/modules/readerthumbnail")
local ReaderToc = require("apps/reader/modules/readertoc")
local ReaderTypeset = require("apps/reader/modules/readertypeset")
local ReaderTypography = require("apps/reader/modules/readertypography")
local ReaderUserHyph = require("apps/reader/modules/readeruserhyph")
local ReaderView = require("apps/reader/modules/readerview")
local ReaderWikipedia = require("apps/reader/modules/readerwikipedia")
local ReaderRsync = require("apps/reader/modules/readerrsync")
local ReaderZooming = require("apps/reader/modules/readerzooming")
local Screenshoter = require("ui/widget/screenshoter")
local SettingsMigration = require("ui/data/settings_migration")
local UIManager = require("ui/uimanager")
local ffiUtil  = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen
local T = ffiUtil.template

local ReaderUI = InputContainer:extend{
    name = "ReaderUI",
    active_widgets = nil, -- array

    -- if we have a parent container, it must be referenced for now
    dialog = nil,

    -- the document interface
    document = nil,

    -- password for document unlock
    password = nil,

    postInitCallback = nil,
    postReaderReadyCallback = nil,
}

function ReaderUI:registerModule(name, ui_module, always_active)
    if name then
        self[name] = ui_module
        ui_module.name = "reader" .. name
    end
    table.insert(self, ui_module)
    if always_active then
        -- to get events even when hidden
        table.insert(self.active_widgets, ui_module)
    end
end

function ReaderUI:registerPostInitCallback(callback)
    table.insert(self.postInitCallback, callback)
end

function ReaderUI:registerPostReaderReadyCallback(callback)
    table.insert(self.postReaderReadyCallback, callback)
end

function ReaderUI:init()
    self.active_widgets = {}

    -- cap screen refresh on pan to 2 refreshes per second
    local pan_rate = Screen.low_pan_rate and 2.0 or 30.0

    Input:inhibitInput(true) -- Inhibit any past and upcoming input events.
    Device:setIgnoreInput(true) -- Avoid ANRs on Android with unprocessed events.

    self.postInitCallback = {}
    self.postReaderReadyCallback = {}
    -- if we are not the top level dialog ourselves, it must be given in the table
    if not self.dialog then
        self.dialog = self
    end

    self.doc_settings = DocSettings:open(self.document.file)
    self.document.is_new = self.doc_settings:readSetting("doc_props") == nil
    -- Handle local settings migration
    SettingsMigration:migrateSettings(self.doc_settings)

    self:registerKeyEvents()

    -- a view container (so it must be child #1!)
    -- all paintable widgets need to be a child of reader view
    self:registerModule("view", ReaderView:new{
        dialog = self.dialog,
        dimen = self.dimen,
        ui = self,
        document = self.document,
    })
    -- goto link controller
    self:registerModule("link", ReaderLink:new{
        dialog = self.dialog,
        view = self.view,
        ui = self,
        document = self.document,
    })
    -- text highlight
    self:registerModule("highlight", ReaderHighlight:new{
        dialog = self.dialog,
        view = self.view,
        ui = self,
        document = self.document,
    })
    -- menu widget should be registered after link widget and highlight widget
    -- so that taps on link and highlight areas won't popup reader menu
    -- reader menu controller
    self:registerModule("menu", ReaderMenu:new{
        view = self.view,
        ui = self
    })
    -- Handmade/custom ToC and hidden flows
    self:registerModule("handmade", ReaderHandMade:new{
        dialog = self.dialog,
        view = self.view,
        ui = self,
        document = self.document,
    })
    -- Table of content controller
    self:registerModule("toc", ReaderToc:new{
        dialog = self.dialog,
        view = self.view,
        ui = self
    })
    -- bookmark controller
    self:registerModule("bookmark", ReaderBookmark:new{
        dialog = self.dialog,
        view = self.view,
        ui = self
    })
    self:registerModule("annotation", ReaderAnnotation:new{
        dialog = self.dialog,
        view = self.view,
        ui = self,
        document = self.document,
    })
    -- reader goto controller
    -- "goto" being a dirty keyword in Lua?
    self:registerModule("gotopage", ReaderGoto:new{
        dialog = self.dialog,
        view = self.view,
        ui = self,
        document = self.document,
    })
    self:registerModule("languagesupport", LanguageSupport:new{
        ui = self,
        document = self.document,
    })
    -- dictionary
    self:registerModule("dictionary", ReaderDictionary:new{
        dialog = self.dialog,
        view = self.view,
        ui = self,
        document = self.document,
    })
    -- wikipedia
    self:registerModule("wikipedia", ReaderWikipedia:new{
        dialog = self.dialog,
        view = self.view,
        ui = self,
        document = self.document,
    })
    -- Rsync
    self:registerModule("rsync", ReaderRsync:new{
        dialog = self.dialog,
        view = self.view,
        ui = self,
        document = self.document,
    })
    -- screenshot controller
    self:registerModule("screenshot", Screenshoter:new{
        prefix = 'Reader',
        dialog = self.dialog,
        view = self.view,
        ui = self
    }, true)
    -- device status controller
    self:registerModule("devicestatus", ReaderDeviceStatus:new{
        ui = self,
    })
    -- configurable controller
    if self.document.info.configurable then
        -- config panel controller
        self:registerModule("config", ReaderConfig:new{
            configurable = self.document.configurable,
            dialog = self.dialog,
            view = self.view,
            ui = self,
            document = self.document,
        })
        if self.document.info.has_pages then
            -- kopt option controller
            self:registerModule("koptlistener", ReaderKoptListener:new{
                dialog = self.dialog,
                view = self.view,
                ui = self,
                document = self.document,
            })
        else
            -- cre option controller
            self:registerModule("crelistener", ReaderCoptListener:new{
                dialog = self.dialog,
                view = self.view,
                ui = self,
                document = self.document,
            })
        end
        -- activity indicator for when some settings take time to take effect (Kindle under KPV)
        if not ReaderActivityIndicator:isStub() then
            self:registerModule("activityindicator", ReaderActivityIndicator:new{
                dialog = self.dialog,
                view = self.view,
                ui = self,
                document = self.document,
            })
        end
    end
    -- for page specific controller
    if self.document.info.has_pages then
        -- cropping controller
        self:registerModule("cropping", ReaderCropping:new{
            dialog = self.dialog,
            view = self.view,
            ui = self,
            document = self.document,
        })
        -- paging controller
        self:registerModule("paging", ReaderPaging:new{
            pan_rate = pan_rate,
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
        -- zooming controller
        self:registerModule("zooming", ReaderZooming:new{
            dialog = self.dialog,
            document = self.document,
            view = self.view,
            ui = self
        })
        -- panning controller
        self:registerModule("panning", ReaderPanning:new{
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
        -- hinting controller
        self:registerModule("hinting", ReaderHinting:new{
            dialog = self.dialog,
            zoom = self.zooming,
            view = self.view,
            ui = self,
            document = self.document,
        })
    else
        -- load crengine default settings (from cr3.ini, some of these
        -- will be overridden by our settings by some reader modules below)
        if self.document.setupDefaultView then
            self.document:setupDefaultView()
        end
        -- make sure we render document first before calling any callback
        self:registerPostInitCallback(function()
            local start_time = time.now()
            if not self.document:loadDocument() then
                self:dealWithLoadDocumentFailure()
            end
            logger.dbg(string.format("  loading took %.3f seconds", time.to_s(time.since(start_time))))

            -- used to read additional settings after the document has been
            -- loaded (but not rendered yet)
            self:handleEvent(Event:new("PreRenderDocument", self.doc_settings))

            start_time = time.now()
            self.document:render()
            logger.dbg(string.format("  rendering took %.3f seconds", time.to_s(time.since(start_time))))

            -- Uncomment to output the built DOM (for debugging)
            -- logger.dbg(self.document:getHTMLFromXPointer(".0", 0x6830))
        end)
        -- styletweak controller (must be before typeset controller)
        self:registerModule("styletweak", ReaderStyleTweak:new{
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
        -- typeset controller
        self:registerModule("typeset", ReaderTypeset:new{
            configurable = self.document.configurable,
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
        -- font menu
        self:registerModule("font", ReaderFont:new{
            configurable = self.document.configurable,
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
        -- user hyphenation (must be registered before typography)
        self:registerModule("userhyph", ReaderUserHyph:new{
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
        -- typography menu (replaces previous hyphenation menu / ReaderHyphenation)
        self:registerModule("typography", ReaderTypography:new{
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
        -- rolling controller
        self:registerModule("rolling", ReaderRolling:new{
            configurable = self.document.configurable,
            pan_rate = pan_rate,
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
        -- pagemap controller
        self:registerModule("pagemap", ReaderPageMap:new{
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
    end
    self.disable_double_tap = G_reader_settings:nilOrTrue("disable_double_tap")
    -- scrolling (scroll settings + inertial scrolling)
    self:registerModule("scrolling", ReaderScrolling:new{
        pan_rate = pan_rate,
        dialog = self.dialog,
        ui = self,
        view = self.view,
    })
    -- back location stack
    self:registerModule("back", ReaderBack:new{
        ui = self,
        view = self.view,
    })
    -- fulltext search
    self:registerModule("search", ReaderSearch:new{
        dialog = self.dialog,
        view = self.view,
        ui = self
    })
    -- book status
    self:registerModule("status", ReaderStatus:new{
        ui = self,
        document = self.document,
    })
    -- thumbnails service (book map, page browser)
    self:registerModule("thumbnail", ReaderThumbnail:new{
        ui = self,
        document = self.document,
    })
    -- file searcher
    self:registerModule("filesearcher", FileManagerFileSearcher:new{
        dialog = self.dialog,
        ui = self,
    })
    -- folder shortcuts
    self:registerModule("folder_shortcuts", FileManagerShortcuts:new{
        dialog = self.dialog,
        ui = self,
    })
    -- history view
    self:registerModule("history", FileManagerHistory:new{
        dialog = self.dialog,
        ui = self,
    })
    -- collections/favorites view
    self:registerModule("collections", FileManagerCollection:new{
        dialog = self.dialog,
        ui = self,
    })
    -- book info
    self:registerModule("bookinfo", FileManagerBookInfo:new{
        dialog = self.dialog,
        document = self.document,
        ui = self,
    })
    -- event listener to change device settings
    self:registerModule("devicelistener", DeviceListener:new {
        document = self.document,
        view = self.view,
        ui = self,
    })
    self:registerModule("networklistener", NetworkListener:new {
        document = self.document,
        view = self.view,
        ui = self,
    })

    -- koreader plugins
    for _, plugin_module in ipairs(PluginLoader:loadPlugins()) do
        if plugin_module.name == "statistics" and util.getFileNameSuffix(self.document.file) == "pdf" then goto continue end
        local ok, plugin_or_err = PluginLoader:createPluginInstance(
            plugin_module,
            {
                dialog = self.dialog,
                view = self.view,
                ui = self,
                document = self.document,
            })
        if ok then
            self:registerModule(plugin_module.name, plugin_or_err)
            logger.dbg("RD loaded plugin", plugin_module.name,
                        "at", plugin_module.path)
        end
        ::continue::
    end

    -- Allow others to change settings based on external factors
    -- Must be called after plugins are loaded & before setting are read.
    self:handleEvent(Event:new("DocSettingsLoad", self.doc_settings, self.document))
    -- we only read settings after all the widgets are initialized
    self:handleEvent(Event:new("ReadSettings", self.doc_settings))

    for _,v in ipairs(self.postInitCallback) do
        v()
    end
    self.postInitCallback = nil

    -- Now that document is loaded, store book metadata in settings.
    local props = self.document:getProps()
    self.doc_settings:saveSetting("doc_props", props)
    -- And have an extended and customized copy in memory for quick access.
    self.doc_props = FileManagerBookInfo.extendProps(props, self.document.file)

    local md5 = self.doc_settings:readSetting("partial_md5_checksum")
    if md5 == nil then
        md5 = util.partialMD5(self.document.file)
        self.doc_settings:saveSetting("partial_md5_checksum", md5)
    end

    local summary = self.doc_settings:readSetting("summary", {})
    if BookList.getBookStatusString(summary.status) == nil then
        summary.status = "reading"
        summary.modified = os.date("%Y-%m-%d", os.time())
    end

    if summary.status ~= "complete" or not G_reader_settings:isTrue("history_freeze_finished_books") then
        require("readhistory"):addItem(self.document.file) -- (will update "lastfile")
    end

    if summary.status == "tbr" then
        summary.status = "reading"
    end

    if G_reader_settings:isTrue("top_manager_infmandhistory")
    and not self.document.file:find("resources/arthur%-conan%-doyle%_the%-hound%-of%-the%-baskervilles.epub")
    and _G.all_files
    and _G.all_files[self.document.file] then
        if _G.all_files[self.document.file].status ~= "complete" then
            _G.all_files[self.document.file].status = "reading"
            local pattern = "(%d+)-(%d+)-(%d+)"
            local ryear, rmonth, rday = summary.modified:match(pattern)
            _G.all_files[self.document.file].last_modified_year = ryear
            _G.all_files[self.document.file].last_modified_month = rmonth
            _G.all_files[self.document.file].last_modified_day = rday
            local util = require("util")
            util.generateStats()
        end
    end

    -- After initialisation notify that document is loaded and rendered
    -- CREngine only reports correct page count after rendering is done
    -- Need the same event for PDF document
    self:handleEvent(Event:new("ReaderReady", self.doc_settings))

    -- if util.getFileNameSuffix(self.document.file) == "epub" then
    --     -- There is a small delay when manipulating the cover in the coverimage plugin
    --     -- so the start_session_time in the topbar may be shown a bit delayed when opening the document
    --     -- This happens for devices using the coverimage plugin like PocketBook or Android devices
    --     -- but we do it here for all devices after having executed all the ReaderReady event handlers for all the objects
    --     -- self.view[4] is the topbar object created in readerview.lua
    --     -- self.menu:registerToMainMenu(self.view.topbar)
    --     -- self.menu:registerToMainMenu(self.view[5])
    --     -- We do this in a postReaderReadyCallback function in the topbar
    --     -- if os.time() - self.view.topbar.start_session_time < 5 then
    --     --     self.view.topbar.start_session_time = os.time()
    --     -- end
    --     -- Some things are broken when opening pdf files. I just read epubs with KOReader, but in any case we can avoid the crashes putting some conditions for epub format
    --     -- local file_type = string.lower(string.match(self.document.file, ".+%.([^.]+)") or "")
    --     -- if file_type == "epub" then
    -- end
    for _,v in ipairs(self.postReaderReadyCallback) do
        v()
    end
    self.postReaderReadyCallback = nil
    self.reloading = nil

    Device:setIgnoreInput(false) -- Allow processing of events (on Android).
    Input:inhibitInputUntil(0.2)

    -- print("Ordered registered gestures:")
    -- for _, tzone in ipairs(self._ordered_touch_zones) do
    --     print("  "..tzone.def.id)
    -- end

    if ReaderUI.instance == nil then
        logger.dbg("Spinning up new ReaderUI instance", tostring(self))
    else
        -- Should never happen, given what we did in (do)showReader...
        logger.err("ReaderUI instance mismatch! Opened", tostring(self), "while we still have an existing instance:", tostring(ReaderUI.instance), debug.traceback())
    end
    -- if G_reader_settings:isTrue("highlight_all_words_vocabulary") and self.pagetextinfo and self.pagetextinfo and util.getFileNameSuffix(self.document.file) == "epub" then
    --     self.pagetextinfo:updateWordsVocabulary()
    -- end

    -- if G_reader_settings:isTrue("highlight_all_notes") and self.pagetextinfo and self.pagetextinfo and util.getFileNameSuffix(self.document.file) == "epub" then
    --     self.pagetextinfo:updateNotes()
    -- end
    ReaderUI.instance = self
end

function ReaderUI:registerKeyEvents()
    if Device:hasKeys() then
        self.key_events.Home = { { "Home" } }
        self.key_events.Reload = { { "F5" } }
        if Device:hasDPad() and Device:useDPadAsActionKeys() then
            self.key_events.StartHighlightIndicator = { { { "Up", "Down" } } }
        end
        if Device:hasScreenKB() or Device:hasSymKey() then
            if Device:hasKeyboard() then
                self.key_events.ToggleWifi = { { "Shift", "Home" } }
                self.key_events.OpenLastDoc = { { "Shift", "Back" } }
            else -- Currently exclusively targets Kindle 4.
                self.key_events.ToggleWifi = { { "ScreenKB", "Home" } }
                self.key_events.OpenLastDoc = { { "ScreenKB", "Back" } }
            end
        end
    end
end

ReaderUI.onPhysicalKeyboardConnected = ReaderUI.registerKeyEvents

function ReaderUI:setLastDirForFileBrowser(dir)
    if dir and #dir > 1 and dir:sub(-1) == "/" then
        dir = dir:sub(1, -2)
    end
    self.last_dir_for_file_browser = dir
end

function ReaderUI:getLastDirFile(to_file_browser)
    if to_file_browser and self.last_dir_for_file_browser then
        local dir = self.last_dir_for_file_browser
        self.last_dir_for_file_browser = nil
        return dir
    end
    local QuickStart = require("ui/quickstart")
    local last_dir
    local last_file = G_reader_settings:readSetting("lastfile")
    -- ignore quickstart guide as last_file so we can go back to home dir
    if last_file and last_file ~= QuickStart.quickstart_filename then
        last_dir = last_file:match("(.*)/")
    end
    return last_dir, last_file
end

function ReaderUI:showFileManager(file, selected_files)
    local last_dir, last_file
    if file then
        last_dir = util.splitFilePathName(file)
        last_file = file
    else
        last_dir, last_file = self:getLastDirFile(true)
    end
    local FileManager = require("apps/filemanager/filemanager")
    FileManager:showFiles(last_dir, last_file, selected_files)
end

function ReaderUI:showFileManagerScripts()
    local FileManager = require("apps/filemanager/filemanager")
    local last_file, last_dir = ""
    if Device:isAndroid() then
        last_dir = "/mnt/sdcard/koreader/scripts"
    else
        last_dir = "/mnt/onboard/.adds/scripts"
    end

    if FileManager.instance then
        FileManager.instance:reinit(last_dir, last_file)
    else
        FileManager:showFiles(last_dir, last_file)
    end
end

function ReaderUI:onShowingReader()
    -- Allows us to optimize out a few useless refreshes in various CloseWidgets handlers...
    self.tearing_down = true
    self.dithered = nil

    -- Don't enforce a "full" refresh, leave that decision to the next widget we'll *show*.
    self:onClose(false)
end

-- Same as above, except we don't close it yet. Useful for plugins that need to close custom Menus before calling showReader.
function ReaderUI:onSetupShowReader()
    self.tearing_down = true
    self.dithered = nil
end

--- @note: Will sanely close existing FileManager/ReaderUI instance for you!
---        This is the *only* safe way to instantiate a new ReaderUI instance!
---        (i.e., don't look at the testsuite, which resorts to all kinds of nasty hacks).
function ReaderUI:showReader(file, provider, seamless, is_provider_forced)
    logger.dbg("show reader ui")

    if lfs.attributes(file, "mode") ~= "file" then
        UIManager:show(InfoMessage:new{
             text = T(_("File '%1' does not exist."), BD.filepath(filemanagerutil.abbreviate(file)))
        })
        return
    end

    if provider == nil and DocumentRegistry:hasProvider(file) then
        provider = DocumentRegistry:getProvider(file)
    end
    if provider ~= nil then
        provider = self:extendProvider(file, provider, is_provider_forced)
    end
    if provider and provider.provider then
        -- We can now signal the existing ReaderUI/FileManager instances that it's time to go bye-bye...
        UIManager:broadcastEvent(Event:new("ShowingReader"))
        self:showReaderCoroutine(file, provider, seamless)
    else
        UIManager:show(InfoMessage:new{
            text = T(_("File '%1' is not supported."), BD.filepath(filemanagerutil.abbreviate(file)))
        })
        self:showFileManager(file)
    end
end

function ReaderUI:extendProvider(file, provider, is_provider_forced)
    -- If file extension is single "zip", check the archive content and choose the appropriate provider,
    -- except when the provider choice is forced in the "Open with" dialog.
    -- Also pass to crengine is_fb2 property, based on the archive content (single "zip" extension),
    -- or on the original file double extension ("fb2.zip" etc).
    local _, file_type = filemanagerutil.splitFileNameType(file) -- supports double-extension
    if file_type == "zip" then
        local arc = Archiver.Reader:new()
        if arc:open(file) then
            for entry in arc:iterate() do
                local ext = util.getFileNameSuffix(entry.path)
                if ext and entry.mode == "file" and entry.size > 0 then
                    file_type = ext:lower()
                    break
                end
            end
            arc:close()
        end
        if not is_provider_forced then
            local providers = DocumentRegistry:getProviders("dummy." .. file_type)
            if providers then
                for _, p in ipairs(providers) do
                    if p.provider.provider == "crengine" or p.provider.provider == "mupdf" then -- only these can unzip
                        provider = p.provider
                        break
                    end
                end
            end
        end
    end
    provider.is_fb2 = file_type:sub(1, 2) == "fb"
    provider.is_txt = file_type == "txt"
    return provider
end

function ReaderUI:showReaderCoroutine(file, provider, seamless)
    UIManager:show(InfoMessage:new{
        text = T(_("Opening file '%1'."), BD.filepath(filemanagerutil.abbreviate(file))),
        timeout = 0.0,
        invisible = seamless,
    })
    -- doShowReader might block for a long time, so force repaint here
    UIManager:forceRePaint()
    UIManager:nextTick(function()
        logger.dbg("creating coroutine for showing reader")
        local co = coroutine.create(function()
            self:doShowReader(file, provider, seamless)
        end)
        local ok, err = coroutine.resume(co)
        if err ~= nil or ok == false then
            io.stderr:write('[!] doShowReader coroutine crashed:\n')
            io.stderr:write(debug.traceback(co, err, 1))
            -- Restore input if we crashed before ReaderUI has restored it
            Device:setIgnoreInput(false)
            Input:inhibitInputUntil(0.2)
            UIManager:show(InfoMessage:new{
                text = _(debug.traceback(co, err, 1))
            })
            self:showFileManager(file)
        end
    end)
end

function ReaderUI:doShowReader(file, provider, seamless)
    if seamless then
        UIManager:avoidFlashOnNextRepaint()
    end
    logger.info("opening file", file)
    -- Only keep a single instance running
    if ReaderUI.instance then
        logger.warn("ReaderUI instance mismatch! Tried to spin up a new instance, while we still have an existing one:", tostring(ReaderUI.instance))
        ReaderUI.instance:onClose()
    end
    local document = DocumentRegistry:openDocument(file, provider)
    if not document then
        UIManager:show(InfoMessage:new{
            text = _(debug.traceback(co, err, 1))
        })
        self:showFileManager(file)
        return
    end
    if document.is_locked then
        logger.info("document is locked")
        self._coroutine = coroutine.running() or self._coroutine
        self:unlockDocumentWithPassword(document)
        if coroutine.running() then
            local unlock_success = coroutine.yield()
            if not unlock_success then
                self:showFileManager(file)
                return
            end
        end
    end
    local reader = ReaderUI:new{
        dimen = Screen:getSize(),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        document = document,
        reloading = self.reloading,
    }

    Screen:setWindowTitle(reader.doc_props.display_title)
    Device:notifyBookState(reader.doc_props.display_title, document)

    -- This is mostly for the few callers that bypass the coroutine shenanigans and call doShowReader directly,
    -- instead of showReader...
    -- Otherwise, showReader will have taken care of that *before* instantiating a new RD,
    -- in order to ensure a sane ordering of plugins teardown -> instantiation.
    local FileManager = require("apps/filemanager/filemanager")
    if FileManager.instance then
        FileManager.instance:onClose()
    end


    -- Onyx Boox devices has a delay in the full refreshes, so
    -- we start the document without a full refresh to avoid the refresh that occurs after the document has been opened
    if Device:isAndroid() then
        UIManager:show(reader, seamless and "ui" or "ui")
    else
        UIManager:show(reader, seamless and "ui" or "full")
    end
end

function ReaderUI:unlockDocumentWithPassword(document, try_again)
    logger.dbg("show input password dialog")
    self.password_dialog = InputDialog:new{
        title = try_again and _("Password is incorrect, try again?")
            or _("Input document password"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        self:closeDialog()
                        coroutine.resume(self._coroutine)
                    end,
                },
                {
                    text = _("OK"),
                    callback = function()
                        local success = self:onVerifyPassword(document)
                        self:closeDialog()
                        if success then
                            coroutine.resume(self._coroutine, success)
                        else
                            self:unlockDocumentWithPassword(document, true)
                        end
                    end,
                },
            },
        },
        text_type = "password",
    }
    UIManager:show(self.password_dialog)
    self.password_dialog:onShowKeyboard()
end

function ReaderUI:onVerifyPassword(document)
    local password = self.password_dialog:getInputText()
    return document:unlock(password)
end

function ReaderUI:closeDialog()
    self.password_dialog:onClose()
    UIManager:close(self.password_dialog)
end

function ReaderUI:onScreenResize(dimen)
    self.dimen = dimen
    self:updateTouchZonesOnScreenResize(dimen)
end

function ReaderUI:saveSettings()
    self:handleEvent(Event:new("SaveSettings"))
    self.doc_settings:flush()
    G_reader_settings:flush()
end

function ReaderUI:onFlushSettings(show_notification)
    self:saveSettings()
    if show_notification then
        -- Invoked from dispatcher to explicitly flush settings
        Notification:notify(_("Book metadata saved."))
    end
end

function ReaderUI:closeDocument()
    self.document:close()
    self.document = nil
end

function ReaderUI:onClose(full_refresh)
    logger.dbg("closing reader")
    PluginLoader:finalize()
    Device:notifyBookState(nil, nil)
    -- if self.dialog is us, we'll have our onFlushSettings() called
    -- by UIManager:close() below, so avoid double save
    if self.dialog ~= self then
        self:saveSettings()
    end
    local file
    if self.document ~= nil then
        file = self.document.file
        require("readhistory"):updateLastBookTime(self.tearing_down)
        require("readcollection"):updateLastBookTime(file)

        -- -- Ensure current document is always last in history
        -- require("readhistory"):removeItemByPath(file)
        -- require("readhistory"):addItem(file, os.time())

        -- Serialize the most recently displayed page for later launch
        DocCache:serialize(file)
        logger.dbg("closing document")
        self:handleEvent(Event:new("CloseDocument"))
        if self.document:isEdited() and not self.highlight.highlight_write_into_pdf then
            self.document:discardChange()
        end
        self:closeDocument()
    end
    UIManager:close(self.dialog, full_refresh ~= false and "full")
    if file then
        BookList.setBookInfoCache(file, self.doc_settings)
    end
end

function ReaderUI:onCloseWidget()
    if ReaderUI.instance == self then
        logger.dbg("Tearing down ReaderUI", tostring(self))
    else
        logger.warn("ReaderUI instance mismatch! Closed", tostring(self), "while the active one is supposed to be", tostring(ReaderUI.instance))
    end
    ReaderUI.instance = nil
    self._coroutine = nil
end

function ReaderUI:dealWithLoadDocumentFailure()
    -- Sadly, we had to delay loadDocument() to about now, so we only
    -- know now this document is not valid or recognized.
    -- We can't do much more than crash properly here (still better than
    -- going on and segfaulting when calling other methods on unitiliazed
    -- _document)
    -- As we are in a coroutine, we can pause and show an InfoMessage before exiting
    local _coroutine = coroutine.running()
    if coroutine then
        logger.warn("crengine failed recognizing or parsing this file: unsupported or invalid document")
        UIManager:show(InfoMessage:new{
            text = _("Failed recognizing or parsing this file: unsupported or invalid document.\nKOReader will exit now."),
            dismiss_callback = function()
                coroutine.resume(_coroutine, false)
            end,
        })
        -- Restore input, so can catch the InfoMessage dismiss and exit
        Device:setIgnoreInput(false)
        Input:inhibitInputUntil(0.2)
        coroutine.yield() -- pause till InfoMessage is dismissed
    end
    -- We have to error and exit the coroutine anyway to avoid any segfault
    error("crengine failed recognizing or parsing this file: unsupported or invalid document")
end

function ReaderUI:onHome()
    local file = self.document.file
    if file:find("resources/arthur%-conan%-doyle%_the%-hound%-of%-the%-baskervilles.epub") then
        local DataStorage = require("datastorage")
        file = DataStorage:getFullDataDir() .. "/" .. file
        if require("readhistory"):getIndexByFile(file) then
            require("readhistory"):removeItemByPath(file)
            self:onClose()

            local doc_settings = DocSettings:open(file)
            doc_settings:purge()
            local FileManager = require("apps/filemanager/filemanager")
            self:showFileManager()
            FileManager.instance.history:onShowHist()

            -- local DocSettings = require("docsettings")
            -- local has_sidecar_file = DocSettings:hasSidecarFile(fullpath)
            -- if in_history and not has_sidecar_file then
            --     table.insert(files_mbr, FileChooser:getListItem(nil, f, fullpath, attributes, collate))
            -- end
        end
    else

        local MultiConfirmBox = require("ui/widget/multiconfirmbox")

        local multi_box= MultiConfirmBox:new{
            text = "Do you want to put the book to history without configuration?",
            choice1_text = _("Yes"),
            choice1_callback = function()
                UIManager:close(multi_box)

                self:onClose()

                local in_history =  require("readhistory"):getIndexByFile(file)

                if not in_history then
                    require("readhistory"):addItem(file, os.time())
                end

                local doc_settings = DocSettings:open(file)
                doc_settings:purge()
                require("ui/widget/booklist").resetBookInfoCache(file)
                -- require("bookinfomanager"):deleteBookInfo(file)


                if G_reader_settings:isTrue("top_manager_infmandhistory")
                    and util.getFileNameSuffix(file) == "epub"
                    and _G.all_files[file] then
                        _G.all_files[file].status = "mbr"
                        _G.all_files[file].last_modified_year = 0
                        _G.all_files[file].last_modified_month = 0
                        _G.all_files[file].last_modified_day = 0
                        local util = require("util")
                        util.generateStats()
                end

                -- UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", file))
                -- UIManager:broadcastEvent(Event:new("DocSettingsItemsChanged", file))
                -- require("bookinfomanager"):deleteBookInfo(file)
                local FileManager = require("apps/filemanager/filemanager")
                self:showFileManager(file)
                -- local dir = util.splitFilePathName(file)
                -- FileManager:showFiles(dir, file)

                -- If we go to the history straight away, the cover won't be refreshed in the fm after existing
                -- When the history is closed in filemanagerhistory.lua, it will reopen the fm
                -- FileManager.instance.history.send = true
                -- FileManager.instance.history.file = file

                -- If we open the history, the cover browser plugin cover scan will stop
                -- and won't be reactivated after closing the history
                -- We can call require("apps/filemanager/filemanager").instance.file_chooser:refreshPath() when closing the history to reactivate it
                FileManager.instance.history:onShowHist()
                -- self.history:onShowHist()

                return true
            end,
            choice2_text = _("No, just exit"),
            choice2_callback = function()
                self:onClose()
                require("ui/widget/booklist").resetBookInfoCache(file)
                self:showFileManager(file)
                return true
            end,
            cancel_callback = function()
                return true
            end,
            flash_yes = true,
            flash_no = true,
        }
        UIManager:show(multi_box)
    end
    return true
end

function ReaderUI:onScripts()
    self:onClose()
    self:showFileManagerScripts()
    return true
end

function ReaderUI:onReload()
    self:reloadDocument()
end

function ReaderUI:reloadDocument(after_close_callback, seamless)
    local file = self.document.file
    local provider = getmetatable(self.document).__index

    -- Mimic onShowingReader's refresh optimizations
    self.tearing_down = true
    self.dithered = nil
    self.reloading = true

    self:handleEvent(Event:new("CloseReaderMenu"))
    self:handleEvent(Event:new("CloseConfigMenu"))
    self:handleEvent(Event:new("PreserveCurrentSession")) -- don't reset statistics' start_current_period
    self.highlight:onClose() -- close highlight dialog if any
    self:onClose(false)
    if after_close_callback then
        -- allow caller to do stuff between close an re-open
        after_close_callback(file, provider)
    end

    self:showReader(file, provider, seamless)
end

function ReaderUI:switchDocument(new_file, seamless)
    if not new_file then return end

    -- Mimic onShowingReader's refresh optimizations
    self.tearing_down = true
    self.dithered = nil

    self:handleEvent(Event:new("CloseReaderMenu"))
    self:handleEvent(Event:new("CloseConfigMenu"))
    self.highlight:onClose() -- close highlight dialog if any
    self:onClose(false)

    self:showReader(new_file, nil, seamless)
end


function ReaderUI:onOpenLastDoc()
    self:switchDocument(self.menu:getPreviousFile())
end

function ReaderUI:showBookStatus()
    if self.rolling and not self.rolling.rendering_state then
        local OverlapGroup = require("ui/widget/overlapgroup")
        local BookStatusWidget = require("ui/widget/bookstatuswidget")
        local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")


        local doc = self.document
        local doc_settings = self.doc_settings
        local widget = BookStatusWidget:new{
            thumbnail = FileManagerBookInfo:getCoverImage(doc),
            props = self.doc_props,
            document = doc,
            settings = doc_settings,
            ui = self,
            readonly = true,
        }

        local widget = OverlapGroup:new{
            dimen = {
                w = Screen:getWidth(),
                h = Screen:getHeight(),
            },
            widget,
            nil,
        }


        UIManager:show(widget, "full")

        UIManager:scheduleIn(3, function()
            -- Screen:refreshFullImp(0, 0, Screen:getWidth(), Screen:getHeight())
            -- UIManager:setDirty("all", "full")
            UIManager:close(widget)
        end)
    end
end

function ReaderUI:onAdjustMarginsTopbar()
    if util.getFileNameSuffix(self.document.file) ~= "epub" then return end
    local Event = require("ui/event")
    if not self.view.topbar.settings:isTrue("show_top_bar") or self.view.topbar.status_bar == true then
        if self.view.footer_visible then
            -- We want physical pixels because margins are set up like this
            -- so, we can't use self.view.footer:getHeight()
            -- and that's why we get the size of the different components of the status bar separately
            local footer_height = self.view.footer.settings.container_height
            + self.view.footer.settings.progress_style_thick_height
            --local dump = require("dump")
            --print(dump(self.document.configurable))
            if self.view.footer.settings.bar_top == true then
                footer_height = footer_height + self.view.footer.settings.top_padding
                if Device:isAndroid() then
                    if self.document.configurable.t_page_margin ~= footer_height or
                    self.document.configurable.b_page_margin ~= 0 or
                    self.document.configurable.h_page_margins[1] ~= 20 or
                    self.document.configurable.h_page_margins[2] ~= 20 then
                        local margins = { 20, footer_height, 20, 0}
                        self.document.configurable.t_page_margin = footer_height
                        self.document.configurable.b_page_margin = 0
                        self.document.configurable.h_page_margins[1] = 20
                        self.document.configurable.h_page_margins[2] = 20
                        self:handleEvent(Event:new("SetPageMargins", margins))
                    else
                        self:showBookStatus()
                    end
                else
                    if self.document.configurable.t_page_margin ~= footer_height or
                    self.document.configurable.b_page_margin ~= 0 or
                    self.document.configurable.h_page_margins[1] ~= 15 or
                    self.document.configurable.h_page_margins[2] ~= 15 then
                        local margins = { 15, footer_height, 15, 0}
                        self.document.configurable.t_page_margin = footer_height
                        self.document.configurable.b_page_margin = 0
                        self.document.configurable.h_page_margins[1] = 15
                        self.document.configurable.h_page_margins[2] = 15
                        self:handleEvent(Event:new("SetPageMargins", margins))
                    else
                        self:showBookStatus()
                    end
                end
            else
                footer_height = footer_height + self.view.footer.settings.container_bottom_padding
                if Device:isAndroid() then
                    if self.document.configurable.t_page_margin ~= 12 or
                    self.document.configurable.b_page_margin ~= footer_height or
                    self.document.configurable.h_page_margins[1] ~= 20 or
                    self.document.configurable.h_page_margins[2] ~= 20 then
                        local margins = { 20, 12, 20, footer_height}
                        self.document.configurable.t_page_margin = 12
                        self.document.configurable.b_page_margin = footer_height
                        self.document.configurable.h_page_margins[1] = 20
                        self.document.configurable.h_page_margins[2] = 20
                        self:handleEvent(Event:new("SetPageMargins", margins))
                    else
                        self:showBookStatus()
                    end
                else
                    if self.document.configurable.t_page_margin ~= 12 or
                    self.document.configurable.b_page_margin ~= footer_height or
                    self.document.configurable.h_page_margins[1] ~= 15 or
                    self.document.configurable.h_page_margins[2] ~= 15 then
                        local margins = { 15, 12, 15, footer_height}
                        self.document.configurable.t_page_margin = 12
                        self.document.configurable.b_page_margin = footer_height
                        self.document.configurable.h_page_margins[1] = 15
                        self.document.configurable.h_page_margins[2] = 15
                        self:handleEvent(Event:new("SetPageMargins", margins))
                    else
                        self:showBookStatus()
                    end
                end
            end
        else
            -- -- Adjust margin values to the topbar. Values are in pixels
            -- local margins = { 12, 12, 12, 12}
            -- self.document.configurable.t_page_margin = 12
            -- self.document.configurable.b_page_margin = 12
            -- self.document.configurable.h_page_margins[1] = 12
            -- self.document.configurable.h_page_margins[2] = 12
            -- self:handleEvent(Event:new("SetPageMargins", margins))
            -- Height to width ratio to be approximately sqrt(2), 50/35 = 1.43
            if self.document.configurable.b_page_margin ~= 50
                or self.document.configurable.t_page_margin ~= 50
                or self.document.configurable.h_page_margins[1] ~= 35
                or self.document.configurable.h_page_margins[2] ~= 35  then
                local margins = { 35, 50, 35, 50}
                self.document.configurable.b_page_margin = 50
                self.document.configurable.t_page_margin = 50
                self.document.configurable.h_page_margins[1] = 35
                self.document.configurable.h_page_margins[2] = 35
                self:handleEvent(Event:new("SetPageMargins", margins))
            else
                self:showBookStatus()
            end
        end
    end
end

function ReaderUI:getCurrentPage()
    return self.paging and self.paging.current_page or self.document:getCurrentPage()
end

function ReaderUI:onSetSortBy(mode)
    G_reader_settings:saveSetting("collate", mode)
    return true
end

function ReaderUI:onSetReverseSorting(mode)
    G_reader_settings:saveSetting("SetReverseSorting", mode)
    return true
end

return ReaderUI
