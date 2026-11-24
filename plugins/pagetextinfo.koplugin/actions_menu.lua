-- actions_menu.lua
-- Menú de acciones para PageTextInfo.
-- Uso:  require("actions_menu")(PageTextInfo)

return function(PageTextInfo)

    -- Modules shared by the helpers below
    local Device = require("device")
    local Font = require("ui/font")
    local UIManager = require("ui/uimanager")
    local Event = require("ui/event")
    local util = require("util")
    local _ = require("gettext")
    local T = require("ffi/util").template
    -- CrashLog is resolved lazily and safely: a missing module must not break loading
    local function getCrashLog()
        for __, name in ipairs({ "crashlog_overlay", "crashlog" }) do
            local ok, mod = pcall(require, name)
            if ok and type(mod) == "table" then return mod end
        end
        return rawget(_G, "CrashLog")
    end
    -- Same for the memory overlay (memory_overlay.lua, next to this file)
    local function getMemoryOverlay()
        local ok, mod = pcall(require, "memory_overlay")
        return ok and mod or nil
    end

    -- Same for the widget time overlay (widget_time_overlay.lua, next to this file)
    local function getWidgetTimeOverlay()
        local ok, mod = pcall(require, "widget_time_overlay")
        return ok and mod or nil
    end
    -- Same for the refresh overlay (refresh_overlay.lua, next to this file)
    local function getRefreshOverlay()
        local ok, mod = pcall(require, "refresh_overlay")
        return ok and mod or nil
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

    -- Show a "Restarting..." message, then restart (or quit) KOReader.
    -- Both arguments are optional so it can also be called without any
    -- (e.g. from the actions menu or after toggling verbose logging).
    local function restartKOReader(paths, widget)
        paths = paths or getPlatformPaths()
        UIManager:nextTick(function()
            if widget then
                UIManager:close(widget, "full")
            end
            showMessage(paths, "Restarting...")
            if Device:canRestart() then
                UIManager:restartKOReader()
            else
                UIManager:quit()
            end
        end)
    end
    PageTextInfo.restartKOReader = restartKOReader

    -- Refresh file list, history and stats after books changed on disk
    -- (used when the user chooses not to restart)
    local function refreshAfterBookSync(paths, skip_stats)
        if not G_reader_settings:isTrue("top_manager_infmandhistory") then
            return
        end
        showFbinkMessage(paths, "Updating...")

        _G.all_files = util.getListAll()
        -- Read the history file again, because it can contain books
        -- that are not physically in the device
        require("readhistory"):reload(true)
        if not skip_stats then util.generateStats() end

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
    -- opts.quiet:         if true, no result / restart dialog: the output is returned to the caller.
    -- Returns true (plus the cleaned output) only if the script ran and succeeded.
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

        -- Part of a longer sequence: the caller shows the final result / restart question
        if opts.quiet then
            return true, clean
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
        return true, clean
    end

    function PageTextInfo:onSynchronizeCode()
        runSyncScript("syncKOReaderCode.sh", { ask_restart = true })
    end

    function PageTextInfo:onPullConfig()
        runSyncScript("pullConfig.sh", { ask_restart = true })
        -- Regenerate stats if enabled (runs regardless of the pull result, as in the original)
        if G_reader_settings:isTrue("top_manager_infmandhistory") then
            util.generateStats()
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

    -- Runs the three sync scripts one after the other: code, pull config and books.
    -- It stops at the first failure (runSyncScript already shows the error) and asks
    -- about the restart only once at the end, instead of once per script.
    function PageTextInfo:onSyncCodeBooksAndPull()
        local ConfirmBox = require("ui/widget/confirmbox")
        local steps = {
            { script = "syncKOReaderCode.sh", label = _("Code"),   progress = _("Synchronizing code...") },
            { script = "pullConfig.sh",       label = _("Config"), progress = _("Pulling config...") },
            { script = "syncBooks.sh",        label = _("Books"),  progress = _("Synchronizing books...") },
        }
        local parts = {}
        for __, step in ipairs(steps) do
            local ok, out = runSyncScript(step.script, {
                quiet = true,
                progress_text = step.progress,
                error_text = T(_("Problem while running %1"), step.script),
            })
            if not ok then return end
            out = (out or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if out ~= "" then
                parts[#parts + 1] = step.label .. ":\n" .. out
            end
        end

        -- Same as the single "Pull conf": regenerate stats if enabled
        if G_reader_settings:isTrue("top_manager_infmandhistory") then
            util.generateStats()
        end

        local paths = getPlatformPaths()
        local confirm_box
        confirm_box = ConfirmBox:new{
            dismissable = false,
            text = table.concat(parts, "\n\n") .. "\n\n" .. _("KOReader needs to be restarted."),
            ok_text = Device:canRestart() and _("Restart") or _("Quit"),
            cancel_text = _("No need to restart"),
            flash_yes = true,
            flash_no = true,
            ok_callback = function()
                restartKOReader(paths, confirm_box)
            end,
            cancel_callback = function()
                -- Books may have changed: refresh the library instead of restarting (stats already done above)
                refreshAfterBookSync(paths, true)
            end,
        }
        UIManager:show(confirm_box)
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
        local text -- Local, so it doesn't leak into the global scope
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

    function PageTextInfo:onCrashLogToggled(enable)
        if enable == nil then
            -- no value given (e.g. from an action): flip the saved flag
            enable = not G_reader_settings:isTrue("crashlog_enabled")
            G_reader_settings:saveSetting("crashlog_enabled", enable)
            G_reader_settings:flush()
        end
        local CrashLog = getCrashLog()
        if CrashLog then
            CrashLog.setEnabled(enable)
        end
        return true
    end

    function PageTextInfo:onMemoryOverlayToggled(enable)
        if enable == nil then
            -- no value given (e.g. from an action): flip the saved flag
            enable = not G_reader_settings:isTrue("memoryoverlay_enabled")
            G_reader_settings:saveSetting("memoryoverlay_enabled", enable)
            G_reader_settings:flush()
        end
        local MemoryOverlay = getMemoryOverlay()
        if MemoryOverlay then
            MemoryOverlay.setEnabled(enable)
        end
        return true
    end

    function PageTextInfo:onWidgetTimeOverlayToggled(enable)
        if enable == nil then
            -- no value given (e.g. from an action): flip the saved flag
            enable = not G_reader_settings:isTrue("widgettimeoverlay_enabled")
            G_reader_settings:saveSetting("widgettimeoverlay_enabled", enable)
            G_reader_settings:flush()
        end
        local WidgetTimeOverlay = getWidgetTimeOverlay()
        if WidgetTimeOverlay then
            WidgetTimeOverlay.setEnabled(enable and true or false)
        end
        return true
    end

    function PageTextInfo:onRefreshOverlayToggled(enable)
        if enable == nil then
            -- no value given (e.g. from an action): flip the saved flag
            enable = not G_reader_settings:isTrue("refreshoverlay_enabled")
            G_reader_settings:saveSetting("refreshoverlay_enabled", enable)
            G_reader_settings:flush()
        end
        local RefreshOverlay = getRefreshOverlay()
        if RefreshOverlay then
            RefreshOverlay.setEnabled(enable and true or false)
        end
        return true
    end

    function PageTextInfo:onExitTimingToggled(enable)
        if enable == nil then
            -- no value given (e.g. from an action): flip the saved flag
            enable = not G_reader_settings:isTrue("exittiming_enabled")
            G_reader_settings:saveSetting("exittiming_enabled", enable)
            G_reader_settings:flush()
        end
        local ok, ExitTiming = pcall(require, "exit_timing")
        if ok and ExitTiming then
            ExitTiming.setEnabled(enable)
        end
        return true
    end

    function PageTextInfo:onToggleDebugVerbose()
        local dbg = require("dbg")
        local DataStorage = require("datastorage")
        local UIManager = require("ui/uimanager")

        -- Delete crash.log before switching the mode so the next run
        -- starts with a clean log.
        os.remove(DataStorage:getDataDir() .. "/crash.log")

        if G_reader_settings:isTrue("debug_verbose") then
            dbg:setVerbose(false)
            dbg:turnOff()
            G_reader_settings:makeFalse("debug_verbose")
            G_reader_settings:makeFalse("debug")
            PageTextInfo.restartKOReader()
        else
            dbg:turnOn()
            dbg:setVerbose(true)
            G_reader_settings:makeTrue("debug")
            G_reader_settings:makeTrue("debug_verbose")
            PageTextInfo.restartKOReader()
        end
    end

    -- Last book read (skips the one currently open)
    function PageTextInfo:getLastBook()
        local ok, ReadHistory = pcall(require, "readhistory")
        if not ok or not ReadHistory or not ReadHistory.hist then return nil end
        local lfs = require("libs/libkoreader-lfs")
        local current = self.ui and self.ui.document and self.ui.document.file
        for _, item in ipairs(ReadHistory.hist) do
            if item.file ~= current and lfs.attributes(item.file, "mode") == "file" then
                local title
                local ok2, DocSettings = pcall(require, "docsettings")
                if ok2 then
                    local ok3, props = pcall(function()
                        return DocSettings:open(item.file):readSetting("doc_props")
                    end)
                    if ok3 and props and props.title and props.title ~= "" then
                        title = props.title
                    end
                end
                title = title or item.file:match("([^/]+)%.[^.]+$") or item.file
                return { file = item.file, title = title }
            end
        end
    end

    -- Menu actions: { label, callback, active }
    function PageTextInfo:getMenuActions()
        local Event = require("ui/event")

        -- Returns true if a process with this name is running
        local function isProcessRunning(name)
            local ok = os.execute("pidof " .. name .. " >/dev/null 2>&1")
            return ok == 0 or ok == true  -- LuaJIT returns 0, Lua 5.2+ returns true
        end

        -- Server shown in the section header (same settings and defaults as readerrsync.lua)
        local rsync_server = G_reader_settings:readSetting("rsync_server", "192.168.50.252")
        local rsync_port = G_reader_settings:readSetting("rsync_port", "873")
        local sync_header = string.format("KOReader sync - %s:%s", tostring(rsync_server), tostring(rsync_port))

        local actions = {
            { header = sync_header, label = "Sync code",  callback = function() self:onSynchronizeCode() end },
            { label = "Sync books", callback = function() self:onSyncBooks() end },
            { label = "Pull conf",  callback = function() self:onPullConfig() end },
            { label = "Push conf",  callback = function() self:onPushConfig() end },
            { label = "Sync code, pull and books", full_width = true, callback = function() self:onSyncCodeBooksAndPull() end },
        }

        table.insert(actions, {
            header = "Toggle services",
            label = "SSH server",
            active = function() return isProcessRunning("dropbear") end,
            callback = function() self.ui:handleEvent(Event:new("ToggleSSHServer")) end,
        })
        table.insert(actions, {
            label = "RSync server",
            active = function() return isProcessRunning("rsync") end,
            callback = function() self.ui:handleEvent(Event:new("ToggleRsyncdService")) end,
        })
        table.insert(actions, {
            label = "Crash log overlay",
            -- Reflects the saved setting
            active = function() return G_reader_settings:isTrue("crashlog_enabled") end,
            callback = function()
                self.ui:handleEvent(Event:new("CrashLogToggled"))
            end,
        })
        table.insert(actions, {
            label = "Memory overlay",
            -- Reflects the saved setting
            active = function() return G_reader_settings:isTrue("memoryoverlay_enabled") end,
            callback = function()
                self.ui:handleEvent(Event:new("MemoryOverlayToggled"))
            end,
        })
        table.insert(actions, {
            label = "Widget time overlay",
            -- Reflects the saved setting
            active = function() return G_reader_settings:isTrue("widgettimeoverlay_enabled") end,
            callback = function()
                self.ui:handleEvent(Event:new("WidgetTimeOverlayToggled"))
            end,
        })
        table.insert(actions, {
            label = "Refresh overlay",
            -- Reflects the saved setting
            active = function() return G_reader_settings:isTrue("refreshoverlay_enabled") end,
            callback = function()
                self.ui:handleEvent(Event:new("RefreshOverlayToggled"))
            end,
        })
        table.insert(actions, {
            label = "Exit timing",
            -- Reflects the saved setting
            active = function() return G_reader_settings:isTrue("exittiming_enabled") end,
            callback = function()
                self.ui:handleEvent(Event:new("ExitTimingToggled"))
            end,
        })
        table.insert(actions, {
            label = "Verbose logging",
            -- Reflects the saved setting (takes effect after a restart)
            active = function() return G_reader_settings:isTrue("debug_verbose") end,
            callback = function() self:onToggleDebugVerbose() end,
        })

        -- "Miscellaneous" section: last book (if any) + top reading sessions.
        -- The header goes on the first entry of the section.
        local misc_header = "Miscellaneous"
        local last = self:getLastBook()
        if last then
            table.insert(actions, {
                header = misc_header,
                label = "Continue reading: " .. last.title,
                full_width = true,
                callback = function()
                    if self.ui and self.ui.switchDocument then
                        self.ui:switchDocument(last.file)
                    else
                        require("apps/reader/readerui"):showReader(last.file)
                    end
                end,
            })
            misc_header = nil
        end

        table.insert(actions, {
            header = misc_header,
            label = "Reading summary",
            full_width = true,
            -- Opens the Reading Summary window (top_reading_sessions.lua registers
            -- the ShowLongestSessions event for both reader and file manager)
            callback = function() self.ui:handleEvent(Event:new("ShowLongestSessions")) end,
        })

        table.insert(actions, { header = "Restart or Exit", label = "Restart", callback = function() PageTextInfo.restartKOReader() end })
        table.insert(actions, { label = "Exit", callback = function() self.ui:handleEvent(Event:new("Exit")) end })
        return actions
    end

    -- Close the menu and repaint the area underneath
    function PageTextInfo:closeActionsMenu()
        local UIManager = require("ui/uimanager")
        local d = self.actions_dialog
        self.actions_dialog = nil
        if d then
            UIManager:close(d, "ui", d.frame_rect)
        end
    end

    -- Face using the font configured in the reader (falls back to the UI font)
    function PageTextInfo:getMenuFace(size)
        local Font = require("ui/font")
        local logger = require("logger")

        -- Current font name, trying the most reliable sources first
        local face_name
        local function try(fn)
            local ok, v = pcall(fn)
            if ok and type(v) == "string" and v ~= "" then return v end
        end
        face_name = try(function() return self.ui.font.font_face end)
            or try(function() return self.ui.document:getFontFace() end)
            or try(function() return self.ui.doc_settings:readSetting("font_face") end)
            -- No book open (file manager): font of the last book read
            or try(function()
                local ReadHistory = require("readhistory")
                local DocSettings = require("docsettings")
                local lfs = require("libs/libkoreader-lfs")
                for _, item in ipairs(ReadHistory.hist or {}) do
                    if lfs.attributes(item.file, "mode") == "file" then
                        local face = DocSettings:open(item.file):readSetting("font_face")
                        if face then return face end
                        break
                    end
                end
            end)
            or try(function() return G_reader_settings:readSetting("cre_font") end)
        logger.dbg("actions_menu: font name =", face_name)
        self._font_debug = "font name: " .. tostring(face_name)
            .. "\nui.font: " .. tostring(self.ui and self.ui.font ~= nil)
            .. "\ndocument: " .. tostring(self.ui and self.ui.document ~= nil)

        if face_name then
            local ok, FontList = pcall(require, "fontlist")
            if ok and FontList then
                -- fontinfo is filled lazily: make sure it is populated
                -- (e.g. when the menu is opened from the file manager)
                pcall(function() FontList:getFontList() end)
                -- Compare ignoring case, spaces and punctuation
                -- ("Tiempos Text" == "TiemposText" == "tiempos-text")
                local function norm(str) return (tostring(str):lower():gsub("[^%w]", "")) end
                local wanted = norm(face_name)
                local best, fallback, loose
                for path, info in pairs(FontList.fontinfo or {}) do
                    local f = info and info[1]
                    if f and f.name and norm(f.name) == wanted then
                        if not f.bold and not f.italic then
                            best = path
                            break
                        end
                        fallback = fallback or path
                    elseif not loose and norm(path:match("([^/]+)$") or ""):find(wanted, 1, true) then
                        -- last resort: the file name contains the font name
                        loose = path
                    end
                end
                fallback = fallback or loose
                local path = best or fallback
                self._font_debug = self._font_debug .. "\nfile: " .. tostring(path)
                if path then
                    local ok2, face = pcall(Font.getFace, Font, path, size)
                    if ok2 and face then
                        -- The file may be missing or unreadable: prove the face
                        -- renders text, otherwise fall back to the system font
                        local TextWidget = require("ui/widget/textwidget")
                        local ok3 = pcall(function()
                            local tw = TextWidget:new{ text = "Ag", face = face }
                            tw:getSize()
                            tw:free()
                        end)
                        if ok3 then return face end
                        self._font_debug = self._font_debug .. "\n(file failed, using system font)"
                    end
                end
                logger.dbg("actions_menu: no font file found for", face_name)
            end
        end
        return Font:getFace("cfont", size)
    end

    function PageTextInfo:onShowActionsMenu()
        local Blitbuffer = require("ffi/blitbuffer")
        local Device = require("device")
        local Geom = require("ui/geometry")
        local GestureRange = require("ui/gesturerange")
        local Size = require("ui/size")
        local UIManager = require("ui/uimanager")
        local TextWidget = require("ui/widget/textwidget")
        local FrameContainer = require("ui/widget/container/framecontainer")
        local CenterContainer = require("ui/widget/container/centercontainer")
        local InputContainer = require("ui/widget/container/inputcontainer")
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local VerticalGroup = require("ui/widget/verticalgroup")
        local Screen = Device.screen

        -- Don't open a second menu
        if self.actions_dialog then return true end

        local COLUMNS = 2
        local FONT_SIZE = 18

        local actions = self:getMenuActions()

        -- Sizes
        local screen = Screen:getSize()
        local dialog_w = math.floor(screen.w * 0.7)
        local cell_w = math.floor(dialog_w / COLUMNS)
        local font_px = Screen:scaleBySize(FONT_SIZE)
        local cell_h = math.floor(font_px * 2.8)
        local text_h = math.floor(font_px * 1.6)
        local baseline = math.floor(font_px * 1.15)
        local thin = Screen:scaleBySize(1)
        local header_h = math.floor(font_px * 2.0)
        local cells = {}  -- { frame, callback }

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
        -- Consume swipe/hold so they don't reach the reader underneath
        function dialog:onSwipe() return true end
        function dialog:onHold() return true end

        -- Grid
        local grid = VerticalGroup:new{ align = "center" }
        local row = HorizontalGroup:new{}

        for _, action in ipairs(actions) do
            -- Section header (full width, above the row that starts here)
            if action.header then
                if #row > 0 then
                    table.insert(grid, row)
                    row = HorizontalGroup:new{}
                end
                table.insert(grid, FrameContainer:new{
                    bordersize = thin,
                    color = Blitbuffer.COLOR_BLACK,
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                    margin = 0,
                    padding = 0,
                    CenterContainer:new{
                        dimen = Geom:new{ w = cell_w * COLUMNS - 2 * thin, h = header_h - 2 * thin },
                        TextWidget:new{
                            text = action.header,
                            face = self:getMenuFace(FONT_SIZE - 3),
                            bold = true,
                            max_width = cell_w * COLUMNS - 2 * Size.padding.small,
                        },
                    },
                })
            end

            if action.full_width and #row > 0 then
                table.insert(grid, row)
                row = HorizontalGroup:new{}
            end
            local this_w = action.full_width and (cell_w * COLUMNS) or cell_w
            -- Active toggles are drawn inverted: white text on black background
            local is_active = action.active and action.active() or false
            local text_widget = TextWidget:new{
                text = action.label,
                face = self:getMenuFace(FONT_SIZE),
                fgcolor = is_active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
                forced_height = text_h,
                forced_baseline = baseline,
                max_width = this_w - 2 * Size.padding.small,
            }
            local cell_frame = FrameContainer:new{
                bordersize = thin,
                color = is_active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
                background = is_active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
                margin = 0,
                padding = 0,
                CenterContainer:new{
                    dimen = Geom:new{ w = this_w - 2 * thin, h = cell_h - 2 * thin },
                    text_widget,
                },
            }
            table.insert(row, cell_frame)
            table.insert(cells, { frame = cell_frame, callback = action.callback,
                action = action, text = text_widget })

            if action.full_width then
                table.insert(grid, row)
                row = HorizontalGroup:new{}
            elseif #row == COLUMNS then
                table.insert(grid, row)
                row = HorizontalGroup:new{}
            end
        end
        -- Odd number of actions
        if #row > 0 then
            table.insert(grid, row)
        end

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
            -- Tap on an option: close the menu, then run the action
            for _, cell in ipairs(cells) do
                if cell.frame.dimen and ges.pos:intersectWith(cell.frame.dimen) then
                    self.plugin:closeActionsMenu()
                    UIManager:nextTick(cell.callback)
                    return true
                end
            end
            -- Tap inside the window but outside any cell: ignore
            if ges.pos:intersectWith(frame_rect) then
                return true
            end
            -- Tap outside the window: close
            self.plugin:closeActionsMenu()
            return true
        end

        function dialog:onClose()
            self.plugin:closeActionsMenu()
            return true
        end

        -- Redraw the inverted state of the toggles from their current values (used when
        -- something changes a flag while the menu is open, e.g. the "×" of an overlay)
        function dialog:updateActive()
            for _, cell in ipairs(cells) do
                if cell.action and cell.action.active then
                    local on = cell.action.active() and true or false
                    cell.text.fgcolor = on and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
                    cell.frame.color = on and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
                    cell.frame.background = on and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
                end
            end
            UIManager:setDirty(self, "ui", self.frame_rect)
        end

        dialog.plugin = self
        dialog.frame_rect = frame_rect
        self.actions_dialog = dialog

        -- The overlays switch their own flag off with the "×": redraw this menu then
        local function onOverlayClosed()
            if self.actions_dialog == dialog then dialog:updateActive() end
        end
        for _, getMod in ipairs({ getCrashLog, getMemoryOverlay, getWidgetTimeOverlay, getRefreshOverlay }) do
            local mod = getMod()
            if mod and mod.setOnClose then mod.setOnClose(onOverlayClosed) end
        end

        UIManager:show(dialog, "ui", frame_rect)
        -- DEBUG: set to false once the font works
        local DEBUG_FONT = false
        if DEBUG_FONT and self._font_debug then
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{ text = self._font_debug, timeout = 8 })
        end
        return true
    end

end
