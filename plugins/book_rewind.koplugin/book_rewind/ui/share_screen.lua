local bit = require("bit")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local PluginShare = require("pluginshare")
local Png = require("ffi/png")
local QRWidget = require("ui/widget/qrwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local ffi = require("ffi")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local socket = require("socket")
local util = require("util")

local Access = require("book_rewind/share/access")
local CardView = require("book_rewind/ui/card_view")
local Deck = require("book_rewind/share/deck")
local Server = require("book_rewind/share/server")
local Strings = require("book_rewind/share/strings")

local Device_screen = Device.screen

local PORT = 8643
local TICK_ACTIVE = 0.02
local TICK_IDLE = 0.25
local IDLE_LIMIT = 600
local PARTIAL_REFRESHES = 8
local TOKEN_ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789"
local TOKEN_LENGTH = 16
local SERIF = "noto/NotoSerif-Regular.ttf"
local SERIF_BOLD = "noto/NotoSerif-Bold.ttf"
-- The design is 600x800; a story of 1080x1920 keeps it whole in the middle, with room above and below.
local LAYER_SIZES = { preview = { 600, 800 }, story = { 1080, 1440 } }
-- The cache shares its partition with KOReader's settings, which must still have room to be saved.
local FREE_MARGIN_BYTES = 50 * 1024 * 1024

local ShareScreen = InputContainer:extend{
    name = "book_rewind_share_screen",
    covers_fullscreen = true,
    stop_events_propagation = true,
    cards = nil,
    year = nil,
    language = nil,
    card_strings = nil,
    plugin_dir = nil,
    cover = nil,
    after_layer = nil,
    local_ip = nil,
    port = PORT,
    open_firewall = nil,
    close_firewall = nil,
}

local function random_token()
    local source = io.open("/dev/urandom", "rb")
    if not source then
        return nil
    end
    local bytes = source:read(TOKEN_LENGTH)
    source:close()
    if not bytes or #bytes < TOKEN_LENGTH then
        return nil
    end
    local out = {}
    for i = 1, TOKEN_LENGTH do
        local index = bytes:byte(i) % #TOKEN_ALPHABET + 1
        out[i] = TOKEN_ALPHABET:sub(index, index)
    end
    return table.concat(out)
end

-- Connecting a UDP socket picks the outgoing interface without sending any packet.
local function detect_local_ip()
    local udp = socket.udp()
    if not udp then
        return nil
    end
    udp:setpeername("10.255.255.255", 9)
    local ip = udp:getsockname()
    udp:close()
    return ip
end

local function firewall(action)
    if not Device:isKindle() then
        return
    end
    os.execute(string.format("iptables -%s INPUT -p tcp --dport %d -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null", action, PORT))
    os.execute(string.format("iptables -%s OUTPUT -p tcp --sport %d -m conntrack --ctstate ESTABLISHED -j ACCEPT 2>/dev/null", action, PORT))
end

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local data = file:read("*a")
    file:close()
    return data
end

function ShareScreen.cache_dir()
    return DataStorage:getDataDir() .. "/cache/book_rewind_share"
end

function ShareScreen.marker_path()
    return DataStorage:getDataDir() .. "/cache/book_rewind_share.active"
end

local function remove_cache()
    local dir = ShareScreen.cache_dir()
    if lfs.attributes(dir, "mode") == "directory" then
        for name in lfs.dir(dir) do
            if name:match("^[%w_]+%.png$") then
                os.remove(dir .. "/" .. name)
            end
        end
        lfs.rmdir(dir)
    end
end

-- A crash or a forced quit skips onCloseWidget, which would leave the port open and the Kindle awake.
function ShareScreen.recover()
    if lfs.attributes(ShareScreen.marker_path(), "mode") ~= "file" then
        return
    end
    firewall("D")
    if Device:isKindle() and not PluginShare.keepalive then
        os.execute("lipc-set-prop com.lab126.powerd preventScreenSaver 0")
    end
    remove_cache()
    os.remove(ShareScreen.marker_path())
end

function ShareScreen:init()
    local rotation = Device_screen:getRotationMode()
    if bit.band(rotation, 1) == 1 then
        self.restore_rotation = rotation
        Device_screen:setRotationMode(Device_screen.DEVICE_ROTATED_UPRIGHT)
    end
    self.dimen = Geom:new{ x = 0, y = 0, w = Device_screen:getWidth(), h = Device_screen:getHeight() }
    self.width, self.height = self.dimen.w, self.dimen.h
    self.text_width = self.width - 2 * Device_screen:scaleBySize(30)
    self.strings = Strings[self.language] or Strings.en
    self.tick_callback = function() self:tick() end
    self.decks = {}
    self.shared = {}
    for _, card in ipairs(self.cards) do
        if not card.not_shared then
            self.shared[#self.shared + 1] = card
        end
    end
    self:start_sharing()
end

function ShareScreen:deck(theme)
    if not self.decks[theme] then
        self.decks[theme] = Deck.build(self.shared, theme, self.year, self.strings)
    end
    return self.decks[theme]
end

-- Drawn when the browser first asks, and kept, because the same card is asked for again when saving.
function ShareScreen:layer(theme, index, size)
    local card = self.shared[index]
    if not card then
        return nil
    end
    local path = string.format("%s/%s_%d_%s.png", ShareScreen.cache_dir(), theme, index, size)
    if lfs.attributes(path, "mode") == "file" then
        return { path = path }
    end
    local w, h = LAYER_SIZES[size][1], LAYER_SIZES[size][2]
    util.makePath(ShareScreen.cache_dir())
    local available = util.diskUsage(ShareScreen.cache_dir()).available
    if available and available < w * h * 4 + FREE_MARGIN_BYTES then
        return nil, "space"
    end
    local bb = Blitbuffer.new(w, h, Blitbuffer.TYPE_BBRGB32)
    local ok, err = pcall(function()
        CardView.paint_layer(bb, card, { width = w, height = h, strings = self.card_strings, plugin_dir = self.plugin_dir, cover = self.cover, theme = theme })
        local written, problem = Png.encodeToFile(path, ffi.cast("const unsigned char*", bb.data), w, h, 4)
        if not written then
            error(problem)
        end
    end)
    bb:free()
    if self.after_layer then
        self.after_layer()
    end
    if not ok then
        logger.warn("Book Rewind: could not draw a shared image", card.id, err)
        os.remove(path)
        return nil, "failed"
    end
    return { path = path }
end

function ShareScreen:keep_awake(on)
    if (self.awake or false) == on then
        return
    end
    self.awake = on
    if on then
        self.previous_pause = PluginShare.pause_auto_suspend
        PluginShare.pause_auto_suspend = true
    else
        PluginShare.pause_auto_suspend = self.previous_pause
    end
    if Device:isKindle() and not PluginShare.keepalive then
        os.execute(string.format("lipc-set-prop com.lab126.powerd preventScreenSaver %d", on and 1 or 0))
    end
end

function ShareScreen:start_sharing()
    local ip = self.local_ip or detect_local_ip()
    if not ip or not Access.is_private_ip(ip) then
        self:show_message(self.strings.no_network_title, self.strings.no_network_text)
        return
    end
    local token = random_token()
    if not token then
        self:show_message(self.strings.start_failed_title, self.strings.token_failed)
        return
    end
    local script = read_file(self.plugin_dir .. "/assets/share/app.js")
    local style = read_file(self.plugin_dir .. "/assets/share/style.css")
    if not script or not style then
        self:show_message(self.strings.start_failed_title, self.strings.render_failed)
        return
    end
    self.ip = ip
    self.url = string.format("http://%s:%d/%s/", ip, self.port, token)
    self.access = Access.new{
        token = token,
        host = string.format("%s:%d", ip, self.port),
        strings = self.strings,
        assets = { script = script, style = style },
        deck = function(theme) return self:deck(theme) end,
        layer = function(theme, index, size) return self:layer(theme, index, size) end,
        on_new_client = function(client_ip) self:ask_permission(client_ip) end,
    }
    remove_cache()
    self.server = Server.new{ access = self.access, ip = ip, port = self.port }
    local close_firewall = self.close_firewall or function() firewall("D") end
    local open_firewall = self.open_firewall or function() firewall("A") end
    close_firewall()
    local ok, err = self.server:start()
    if not ok then
        self.server = nil
        self:show_message(self.strings.start_failed_title, tostring(err))
        return
    end
    local marker = io.open(ShareScreen.marker_path(), "w")
    if marker then
        marker:close()
    end
    open_firewall()
    self.close_firewall_now = close_firewall
    self.state = "waiting"
    self:keep_awake(true)
    self:show_sharing()
    UIManager:scheduleIn(TICK_IDLE, self.tick_callback)
end

-- The answer only counts while this session is running: the question may outlive it by sleep or the idle limit.
function ShareScreen:ask_permission(client_ip)
    local access = self.access
    self.confirm = ConfirmBox:new{
        text = string.format(self.strings.allow_question, client_ip),
        ok_text = self.strings.allow_button,
        cancel_text = self.strings.deny_button,
        -- A tap outside the box would count as Deny, and a denied device stays out for the whole session.
        dismissable = false,
        ok_callback = function()
            self.confirm = nil
            if not self.server or self.access ~= access then
                return
            end
            access:approve(client_ip)
            self.state = "connected"
            self:show_sharing()
        end,
        cancel_callback = function()
            self.confirm = nil
            if not self.server or self.access ~= access then
                return
            end
            access:deny(client_ip)
        end,
    }
    UIManager:show(self.confirm)
end

function ShareScreen:close_confirm()
    if self.confirm then
        UIManager:close(self.confirm)
        self.confirm = nil
    end
end

function ShareScreen:tick()
    if not self.server then
        return
    end
    local busy = self.server:tick()
    if os.time() - self.server.last_activity > IDLE_LIMIT then
        self:stop_sharing(self.strings.idle_stop)
        return
    end
    UIManager:scheduleIn(busy and TICK_ACTIVE or TICK_IDLE, self.tick_callback)
end

function ShareScreen:stop_sharing(message)
    UIManager:unschedule(self.tick_callback)
    self:close_confirm()
    if self.server then
        self.server:stop()
        self.server = nil
    end
    if self.close_firewall_now then
        self.close_firewall_now()
        self.close_firewall_now = nil
    end
    self:keep_awake(false)
    remove_cache()
    os.remove(ShareScreen.marker_path())
    if message then
        self:show_message(self.strings.ended_title, message)
    end
end

function ShareScreen:paragraph(text, face, size)
    return TextBoxWidget:new{ text = text, face = Font:getFace(face, size), width = self.text_width, alignment = "center" }
end

function ShareScreen:button(text, callback)
    return Button:new{
        text = text,
        width = self.text_width,
        padding_v = Device_screen:scaleBySize(10),
        radius = Device_screen:scaleBySize(8),
        bordersize = Device_screen:scaleBySize(2),
        text_font_face = "cfont",
        text_font_size = 19,
        callback = callback,
    }
end

function ShareScreen:set_group(kind, group)
    if self[1] then
        self[1]:free()
    end
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        width = self.width,
        height = self.height,
        CenterContainer:new{ dimen = Geom:new{ w = self.width, h = self.height }, group },
    }
    local mode = "full"
    if kind == self.shown_kind and (self.partial_refreshes or 0) < PARTIAL_REFRESHES then
        mode = "ui"
        self.partial_refreshes = (self.partial_refreshes or 0) + 1
    else
        self.partial_refreshes = 0
    end
    self.shown_kind = kind
    UIManager:setDirty(self, function()
        return mode, self.dimen
    end)
end

function ShareScreen:show_message(title, message)
    local gap = Device_screen:scaleBySize(16)
    self.state = "message"
    self:set_group("message", VerticalGroup:new{
        align = "center",
        self:paragraph(title, SERIF_BOLD, 28),
        VerticalSpan:new{ width = gap },
        self:paragraph(message, SERIF, 18),
        VerticalSpan:new{ width = gap * 2 },
        self:button(self.strings.close_button, function() UIManager:close(self) end),
    })
end

function ShareScreen:show_sharing()
    if self.state == "connected" then
        self:show_connected()
    else
        self:show_waiting()
    end
end

function ShareScreen:show_waiting()
    local s = self.strings
    local gap = Device_screen:scaleBySize(12)
    local qr_size = math.floor(math.min(self.width, self.height) * 0.62)
    self:set_group("waiting", VerticalGroup:new{
        align = "center",
        self:paragraph(s.title, SERIF_BOLD, 28),
        VerticalSpan:new{ width = gap },
        self:paragraph(s.scan_hint, SERIF, 17),
        VerticalSpan:new{ width = gap },
        QRWidget:new{ text = self.url, width = qr_size, height = qr_size },
        VerticalSpan:new{ width = gap },
        self:paragraph(self.url, SERIF, 14),
        VerticalSpan:new{ width = gap },
        self:paragraph(s.waiting, SERIF_BOLD, 17),
        VerticalSpan:new{ width = gap },
        self:paragraph(s.privacy_note, SERIF, 14),
        VerticalSpan:new{ width = gap },
        self:button(s.stop_button, function() UIManager:close(self) end),
    })
end

function ShareScreen:show_connected()
    local s = self.strings
    local gap = Device_screen:scaleBySize(16)
    self:set_group("connected", VerticalGroup:new{
        align = "center",
        self:paragraph(s.title, SERIF, 20),
        VerticalSpan:new{ width = gap * 2 },
        self:paragraph(s.connected, SERIF_BOLD, 40),
        VerticalSpan:new{ width = gap },
        self:paragraph(string.format(s.connected_ip, self.access.client_ip), SERIF, 19),
        VerticalSpan:new{ width = gap * 2 },
        self:paragraph(s.connected_hint, SERIF, 18),
        VerticalSpan:new{ width = gap * 2 },
        self:paragraph(s.reopen_hint, SERIF, 14),
        self:paragraph(self.url, SERIF, 14),
        VerticalSpan:new{ width = gap },
        self:paragraph(s.privacy_note, SERIF, 14),
        VerticalSpan:new{ width = gap * 2 },
        self:button(s.stop_button, function() UIManager:close(self) end),
    })
end

function ShareScreen:onSuspend()
    self:stop_sharing(self.strings.slept)
end

function ShareScreen:onSetRotationMode()
    return true
end

function ShareScreen:onCloseWidget()
    self:stop_sharing()
    if self.restore_rotation then
        Device_screen:setRotationMode(self.restore_rotation)
    end
    UIManager:setDirty(nil, "full")
end

return ShareScreen
