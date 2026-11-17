-- Timing diagnostics: plugin init, reader close, FileManager creation.
-- Everything goes to stdout with print().
local time = require("ui/time")

-- ===== Plugin init timing (FileManager and ReaderUI) =====
local PluginLoader = require("pluginloader")
local orig_create = PluginLoader.createPluginInstance
PluginLoader.createPluginInstance = function(this, plugin, attr)
    local t = time.now()
    local ok, re = orig_create(this, plugin, attr)
    local ms = time.to_ms(time.since(t))
    if ms >= 5 then
        print(string.format("[plugin-init] %-28s %6.0f ms", tostring(plugin.name), ms))
    end
    return ok, re
end

-- ===== Generic wrapper =====
local wrapped = setmetatable({}, { __mode = "k" })   -- wrapper functions already made
local function wrap(obj, name, label, min_ms)
    local orig = obj[name]
    if type(orig) ~= "function" then
        print("[timing] cannot wrap", label)
        return
    end
    if wrapped[orig] then return end                  -- already one of ours
    local f = function(...)
        local t = time.now()
        local r = table.pack(orig(...))
        local ms = time.to_ms(time.since(t))
        if ms >= (min_ms or 10) then
            print(string.format("[timing] %-34s %6.0f ms", label, ms))
        end
        return table.unpack(r, 1, r.n)
    end
    wrapped[f] = true
    obj[name] = f
end

local ReaderUI = require("apps/reader/readerui")
local DocCache = require("document/doccache")
local FileManager = require("apps/filemanager/filemanager")
local FileChooser = require("ui/widget/filechooser")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Event = require("ui/event")
local BookList = require("ui/widget/booklist")

-- ===== Reader close =====
wrap(ReaderUI, "saveSettings", "ReaderUI.saveSettings")
wrap(ReaderUI, "closeDocument", "ReaderUI.closeDocument")
wrap(DocCache, "serialize", "DocCache.serialize")
wrap(PluginLoader, "finalize", "PluginLoader.finalize")
wrap(UIManager, "close", "UIManager.close", 30)
pcall(function()
    wrap(require("readhistory"), "updateLastBookTime", "readhistory.updateLastBookTime")
    wrap(require("readcollection"), "updateLastBookTime", "readcollection.updateLastBookTime")
    wrap(BookList, "setBookInfoCacheProperty", "BookList.setBookInfoCache")
end)

-- Time the onCloseDocument of every child (each plugin / module) of the reader.
-- The handlers are wrapped once, the first time a CloseDocument event is dispatched.
local orig_handle = ReaderUI.handleEvent
ReaderUI.handleEvent = function(self, event, ...)
    if event and event.handler == "onCloseDocument" then
        for _, w in ipairs(self) do
            if type(w) == "table" and type(w.onCloseDocument) == "function" then
                local label = "CloseDocument:" .. tostring(w.name or w.id or "?")
                wrap(w, "onCloseDocument", label, 5)
            end
        end
    end
    return orig_handle(self, event, ...)
end

-- ReaderUI:onClose with checkpoints (same code as this KOReader version).
-- Each [close-cp] line is cumulative since the start of onClose.
ReaderUI.onClose = function(self, full_refresh)
    local t0 = time.now()
    local function cp(label)
        print(string.format("[close-cp] %-26s %6.0f ms", label, time.to_ms(time.since(t0))))
    end
    PluginLoader:finalize();                         cp("finalize")
    Device:notifyBookState(nil, nil);                cp("notifyBookState")
    if self.dialog ~= self then self:saveSettings() end; cp("saveSettings(direct)")
    local file
    if self.document ~= nil then
        file = self.document.file
        require("readhistory"):updateLastBookTime(self.tearing_down)
        require("readcollection"):updateLastBookTime(file); cp("history+collections")
        DocCache:serialize(file);                    cp("DocCache.serialize")
        self:handleEvent(Event:new("CloseDocument")); cp("CloseDocument event")
        if self.document:isEdited() and not self.highlight.highlight_write_into_pdf then
            self.document:discardChange()
        end
        self:closeDocument();                        cp("closeDocument")
    end
    UIManager:close(self.dialog, full_refresh ~= false and "full"); cp("UIManager.close")
    if file then
        BookList.setBookInfoCacheProperty(file, "percent_finished", self.doc_settings:readSetting("percent_finished"))
    end
    cp("end")
end

-- ===== FileManager =====
wrap(FileManager, "init", "FileManager.init")
wrap(FileManager, "setupLayout", "FileManager.setupLayout")
wrap(FileChooser, "genItemTableFromPath", "FileChooser.genItemTable")

-- Menu.init internals (title bar, buttons, icons)
local TitleBar = require("ui/widget/titlebar")
local Button = require("ui/widget/button")
local IconWidget = require("ui/widget/iconwidget")
local RenderImage = require("ui/renderimage")
wrap(Menu, "init", "Menu.init")
wrap(TitleBar, "new", "TitleBar.new", 15)
wrap(Button, "new", "Button.new", 15)
wrap(IconWidget, "new", "IconWidget.new", 15)
wrap(RenderImage, "renderSVGImageFile", "RenderImage.svg", 15)
wrap(RenderImage, "renderImageFile", "RenderImage.file", 15)

-- CoverBrowser replaces some of these when its plugin starts, so they are wrapped
-- every time a FileChooser is created (wrap() skips the ones already wrapped).
-- Menu goes first so FileChooser, which inherits it, is not wrapped twice.
local orig_fc_init = FileChooser.init
FileChooser.init = function(fc, ...)
    for _, obj in ipairs({ Menu, FileChooser }) do
        wrap(obj, "updateItems", "updateItems")
        wrap(obj, "_recalculateDimen", "_recalculateDimen")
        wrap(obj, "switchItemTable", "switchItemTable")
    end
    local t = time.now()
    local r = table.pack(orig_fc_init(fc, ...))
    print(string.format("[timing] %-34s %6.0f ms", "FileChooser.init", time.to_ms(time.since(t))))
    return table.unpack(r, 1, r.n)
end

print("[timing] patch loaded")
