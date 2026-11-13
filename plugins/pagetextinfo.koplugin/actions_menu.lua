-- actions_menu.lua
-- Menú de acciones para PageTextInfo.
-- Uso:  require("actions_menu")(PageTextInfo)

return function(PageTextInfo)

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

        local actions = {
            { header = "KOReader sync", label = "Sync code",  callback = function() self:onSynchronizeCode() end },
            { label = "Sync books", callback = function() self:onSyncBooks() end },
            { label = "Pull conf",  callback = function() self:onPullConfig() end },
            { label = "Push conf",  callback = function() self:onPushConfig() end },
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
            full_width = true,
            -- Tracks the overlay state locally
            active = function() return self.crash_log_overlay_on == true end,
            callback = function()
                self.crash_log_overlay_on = not self.crash_log_overlay_on
                self.ui:handleEvent(Event:new("CrashLogToggled"))
            end,
        })

        local last = self:getLastBook()
        if last then
            table.insert(actions, {
                header = "Continue reading...",
                label = last.title,
                full_width = true,
                callback = function()
                    if self.ui and self.ui.switchDocument then
                        self.ui:switchDocument(last.file)
                    else
                        require("apps/reader/readerui"):showReader(last.file)
                    end
                end,
            })
        end

        table.insert(actions, { header = "Restart or Exit", label = "Restart", callback = function() restartKOReader() end })
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
        local face_name = self.ui and self.ui.font and self.ui.font.font_face
        if not face_name then
            face_name = G_reader_settings and G_reader_settings:readSetting("cre_font")
        end
        if face_name then
            local ok, FontList = pcall(require, "fontlist")
            if ok and FontList and FontList.fontinfo then
                for path, info in pairs(FontList.fontinfo) do
                    local f = info and info[1]
                    if f and f.name == face_name and not f.bold and not f.italic then
                        local ok2, face = pcall(Font.getFace, Font, path, size)
                        if ok2 and face then return face end
                    end
                end
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
        local FONT_SIZE = 22

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
            table.insert(cells, { frame = cell_frame, callback = action.callback })

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

        dialog.plugin = self
        dialog.frame_rect = frame_rect
        self.actions_dialog = dialog

        UIManager:show(dialog, "ui", frame_rect)
        return true
    end

end
