local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local I18n = require("book_rewind/i18n")
local PluginScreensaver = require("book_rewind/screensaver")
local Screen = require("book_rewind/ui/screen")
local ShareScreen = require("book_rewind/ui/share_screen")

PluginScreensaver.install(debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*)/") or ".")

local function strings()
    return I18n[I18n.language_from(G_reader_settings:readSetting("language"))]
end

local BookRewind = WidgetContainer:extend{
    name = "book_rewind",
    is_doc_only = false,
}

local recovered = false

function BookRewind:init()
    self.ui.menu:registerToMainMenu(self)
    if not recovered then
        recovered = true
        ShareScreen.recover()
    end
end

function BookRewind:addToMainMenu(menu_items)
    menu_items.book_rewind = {
        text = strings().menu,
        sorting_hint = "tools",
        callback = function()
            -- The statistics plugin keeps the open book's pages in memory until it writes them.
            local statistics = self.ui.statistics
            if statistics and statistics.isEnabled and statistics:isEnabled() then
                pcall(statistics.insertDB, statistics)
            end
            local ok, screen = pcall(Screen.new, Screen, {})
            if ok then
                UIManager:show(screen)
            else
                logger.warn("Book Rewind: could not open", screen)
                UIManager:show(InfoMessage:new{ text = strings().open_failed })
            end
        end,
    }
end

return BookRewind
