-- Decides what each request gets. It never touches the network or the disk, so every rule can be tested alone.
-- Everything here only reads: there is no way to send anything to the device.
local Access = {}
Access.__index = Access

Access.MAX_BAD_REQUESTS = 20
Access.MAX_REQUEST_BYTES = 8192
Access.THEMES = { vibrant = true, eink = true, gray = true }
Access.SIZES = { preview = true, story = true }

local function escape_html(text)
    return (tostring(text):gsub("[&<>\"']", {
        ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;",
    }))
end

function Access.is_private_ip(ip)
    local a, b = tostring(ip):match("^(%d+)%.(%d+)%.%d+%.%d+$")
    a, b = tonumber(a), tonumber(b)
    if not a then
        return false
    end
    return a == 10 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168)
end

-- opts: token, host (the "ip:port" this server answers to), strings, deck(theme) returning JSON text,
-- layer(theme, index, size) returning { path } or nil, or nil and "space", assets { script, style },
-- on_new_client(ip).
function Access.new(opts)
    return setmetatable({
        token = opts.token,
        host = opts.host,
        strings = opts.strings,
        deck = opts.deck,
        layer = opts.layer,
        assets = opts.assets,
        on_new_client = opts.on_new_client,
        client_ip = nil,
        pending_ip = nil,
        denied = {},
        strikes = {},
    }, Access)
end

function Access:approve(ip)
    if self.pending_ip == ip then
        self.client_ip = ip
        self.pending_ip = nil
    end
end

function Access:deny(ip)
    self.denied[ip] = true
    if self.pending_ip == ip then
        self.pending_ip = nil
    end
end

function Access:is_denied(ip)
    return self.denied[ip] == true
end

-- The device that is approved, or waiting for approval: the one the person is using.
function Access:preferred_ip()
    return self.client_ip or self.pending_ip
end

local function html(status, body)
    return { status = status, body = body, content_type = "text/html; charset=utf-8" }
end

local function plain(status, body)
    return { status = status, body = body, content_type = "text/plain; charset=utf-8" }
end

-- Strikes are per address, so someone else on the network can only lock themselves out. The approved
-- device is never locked out: its browser asks for things like /favicon.ico by itself.
function Access:reject(ip)
    if ip ~= self.client_ip then
        self.strikes[ip] = (self.strikes[ip] or 0) + 1
        if self.strikes[ip] >= Access.MAX_BAD_REQUESTS then
            self.denied[ip] = true
        end
    end
    -- The same answer for everything unknown, so nothing reveals what exists.
    return plain(404, self.strings.not_found)
end

function Access:head_tags(title, extra)
    return table.concat{
        string.format('<!doctype html><html lang="%s"><head><meta charset="utf-8">', self.strings.html_lang),
        '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">',
        extra or "",
        '<link rel="icon" href="data:,">',
        string.format('<link rel="stylesheet" href="/%s/style.css">', self.token),
        "<title>", escape_html(title), "</title></head>",
    }
end

function Access:waiting_page()
    local s = self.strings
    return html(200, table.concat{
        self:head_tags(s.page_title, '<meta http-equiv="refresh" content="2">'),
        '<body class="notice"><h1>', escape_html(s.confirm_heading), "</h1><p>", escape_html(s.confirm_text), "</p></body></html>",
    })
end

function Access:app_page()
    local s = self.strings
    return html(200, table.concat{
        self:head_tags(s.page_title),
        '<body><div id="app"></div><noscript><p>', escape_html(s.no_script), "</p></noscript>",
        string.format('<script src="/%s/app.js"></script>', self.token),
        "</body></html>",
    })
end

function Access:layer_response(theme, index, size, ip)
    local file, problem = self.layer(theme, tonumber(index), size)
    if file then
        return { status = 200, path = file.path, content_type = "image/png", cacheable = true }
    end
    if problem == "space" then
        return plain(507, self.strings.no_space)
    end
    if problem == "failed" then
        return plain(500, self.strings.render_failed)
    end
    return self:reject(ip)
end

-- request: the raw request head. ip: the address of the connection.
function Access:handle(request, ip)
    if self.denied[ip] then
        return { status = 503, body = "", content_type = "text/plain", close_only = true }
    end
    if #request > Access.MAX_REQUEST_BYTES or not Access.is_private_ip(ip) then
        return self:reject(ip)
    end
    local method, target = request:match("^(%u+) ([^%s]+) HTTP/1%.[01]\r?\n")
    if method ~= "GET" then
        return self:reject(ip)
    end
    -- A request for another name is a page trying to reach this server through the browser.
    local host = request:match("\n[Hh][Oo][Ss][Tt]:[ \t]*([^\r\n]+)")
    if host ~= self.host then
        return self:reject(ip)
    end
    local token, rest = target:match("^/([%w]+)(/?.*)$")
    if token ~= self.token then
        return self:reject(ip)
    end
    -- The style is the only thing the waiting page needs, and it says nothing about the reader.
    if rest == "/style.css" then
        return { status = 200, body = self.assets.style, content_type = "text/css; charset=utf-8" }
    end
    if not self.client_ip then
        if not self.pending_ip then
            self.pending_ip = ip
            self.on_new_client(ip)
        end
        if self.pending_ip ~= ip then
            return self:reject(ip)
        end
        return self:waiting_page()
    end
    if ip ~= self.client_ip then
        return self:reject(ip)
    end
    if rest == "" or rest == "/" then
        return self:app_page()
    end
    if rest == "/app.js" then
        return { status = 200, body = self.assets.script, content_type = "text/javascript; charset=utf-8" }
    end
    local deck_theme = rest:match("^/deck/(%l+)$")
    if deck_theme and Access.THEMES[deck_theme] then
        return { status = 200, body = self.deck(deck_theme), content_type = "application/json; charset=utf-8" }
    end
    local theme, index, size = rest:match("^/layer/(%l+)/(%d+)/(%l+)$")
    if theme and Access.THEMES[theme] and Access.SIZES[size] and #index <= 3 then
        return self:layer_response(theme, index, size, ip)
    end
    return self:reject(ip)
end

local STATUS_TEXT = {
    [200] = "OK", [404] = "Not Found", [500] = "Internal Server Error", [503] = "Service Unavailable", [507] = "Insufficient Storage",
}

function Access.response_head(result, size)
    return table.concat({
        string.format("HTTP/1.1 %d %s", result.status, STATUS_TEXT[result.status] or "Error"),
        "Content-Type: " .. result.content_type,
        "Content-Length: " .. size,
        "Connection: close",
        result.cacheable and "Cache-Control: private, max-age=3600" or "Cache-Control: no-store",
        "Referrer-Policy: no-referrer",
        "X-Content-Type-Options: nosniff",
        "X-Frame-Options: DENY",
        "Content-Security-Policy: default-src 'none'; img-src 'self' blob: data:; style-src 'self'; script-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'",
    }, "\r\n") .. "\r\n\r\n"
end

return Access
