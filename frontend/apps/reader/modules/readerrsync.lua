local Widget = require("ui/widget/widget")
local LineWidget = require("ui/widget/linewidget")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local T = require("ffi/util").template
local _ = require("gettext")
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local Blitbuffer = require("ffi/blitbuffer")
local left_container = require("ui/widget/container/leftcontainer")
local right_container = require("ui/widget/container/rightcontainer")
local center_container = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local datetime = require("datetime")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local SQ3 = require("lua-ljsqlite3/init")
local ProgressWidget = require("ui/widget/progresswidget")
local Device = require("device")
local Size = require("ui/size")
local logger = require("logger")

local RSync = WidgetContainer:extend{
    name = "RSync",
    server = G_reader_settings:readSetting("rsync_server", "192.168.50.252"),
    port = G_reader_settings:readSetting("rsync_port", ""),
}


function RSync:init()
    self.ui.menu:registerToMainMenu(RSync)
end

function RSync:addToMainMenu(menu_items)

    menu_items.rsync_configuration = {
        text = _("Rsync server configuration"),
        sorting_hint = ("more_tools"),
        sub_item_table = {
            {
                text_func = function()
                    return T(_("Server: %1"), self.server)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local InputDialog = require("ui/widget/inputdialog")
                    local server_dialog
                    server_dialog = InputDialog:new{
                        title = _("Set server"),
                        input = self.server,
                        input_type = "string",
                        input_hint = _("Server (default is 192.168.50.252)"),
                        buttons =  {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(server_dialog)
                                    end,
                                },
                                {
                                    text = _("OK"),
                                    -- keep_menu_open = true,
                                    callback = function()
                                        local server = server_dialog:getInputValue()
                                        self.server = server
                                        G_reader_settings:saveSetting("rsync_server", server)

                                        UIManager:close(server_dialog)
                                        touchmenu_instance:updateItems()
                                    end,
                                },
                            },
                        },
                    }
                    UIManager:show(server_dialog)
                    server_dialog:onShowKeyboard()
                end,
            },
            {
                text_func = function()
                    return T(_("Port: %1"), self.port)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local InputDialog = require("ui/widget/inputdialog")
                    local port_dialog
                    port_dialog = InputDialog:new{
                        title = _("Set custom port"),
                        input = self.port,
                        input_type = "number",
                        input_hint = _("Port number (default is no port)"),
                        buttons =  {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(port_dialog)
                                    end,
                                },
                                {
                                    text = _("OK"),
                                    -- keep_menu_open = true,
                                    callback = function()
                                        local port = port_dialog:getInputValue()
                                        logger.warn("port", port)
                                        if port and port >= 1 and port <= 65535 then
                                            self.port = port
                                            G_reader_settings:saveSetting("rsync_port", port)
                                        end
                                        if not port then
                                            self.port = ""
                                            G_reader_settings:saveSetting("rsync_port", port)
                                        end
                                        UIManager:close(port_dialog)
                                        touchmenu_instance:updateItems()
                                    end,
                                },
                            },
                        },
                    }
                    UIManager:show(port_dialog)
                    port_dialog:onShowKeyboard()
                end,
            }
        },
    }
end


return RSync
