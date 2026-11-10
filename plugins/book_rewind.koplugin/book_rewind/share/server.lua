local socket = require("socket")

local Access = require("book_rewind/share/access")

-- KOReader's logger writes to crash.log. Outside KOReader, as in the tests, print stands in for it.
local has_logger, logger = pcall(require, "logger")
local function warn(...)
    if has_logger then
        logger.warn(...)
    else
        print(...)
    end
end

local Server = {}
Server.__index = Server

local CHUNK = 65536
-- How long one tick may work on transfers before giving the interface its turn again.
local TICK_BUDGET = 0.03
local MAX_ACCEPTS = 4
local MAX_PASSES = 256
local MAX_CONNECTIONS = 12
local MAX_CLIENT_CONNECTIONS = 6
local MAX_OTHER_CONNECTIONS = 2
local REQUEST_TIMEOUT = 10
local TRANSFER_TIMEOUT = 30

-- opts: access, ip (the address to listen on), port, and optionally log(...), for errors in requests.
function Server.new(opts)
    return setmetatable({
        access = opts.access,
        ip = opts.ip,
        port = opts.port,
        log = opts.log or warn,
        connections = {},
        last_activity = os.time(),
    }, Server)
end

function Server:start()
    local listener, err = socket.bind(self.ip, self.port)
    if not listener then
        return false, err
    end
    listener:settimeout(0)
    self.listener = listener
    return true
end

function Server:close_connection(conn)
    if conn.file then
        conn.file:close()
    end
    conn.client:close()
end

function Server:stop()
    for _, conn in ipairs(self.connections) do
        self:close_connection(conn)
    end
    self.connections = {}
    if self.listener then
        self.listener:close()
        self.listener = nil
    end
end

-- Only the approved device keeps the session alive, so a stranger or an unanswered request cannot stop the
-- idle limit, which is what lets the Kindle sleep again.
function Server:touch(conn)
    conn.deadline = os.time() + TRANSFER_TIMEOUT
    if conn.ip == self.access.client_ip then
        self.last_activity = os.time()
    end
end

function Server:reply(conn, result)
    conn.body = nil
    if result.path then
        -- The length comes from the open file, so the head always tells the truth about the body.
        local file = io.open(result.path, "rb")
        local size = file and file:seek("end")
        if not size or not file:seek("set", 0) then
            if file then
                file:close()
            end
            result = { status = 500, body = "", content_type = "text/plain" }
        else
            conn.file, conn.file_left = file, size
            conn.outgoing = Access.response_head(result, size)
        end
    end
    if not conn.file then
        conn.outgoing = Access.response_head(result, #result.body)
        conn.body = result.body
    end
    conn.sent = 0
    conn.state = "sending"
    self:touch(conn)
end

function Server:prepare_response(conn, head)
    local result = self.access:handle(head, conn.ip)
    if result.close_only then
        conn.done = true
        return
    end
    self:reply(conn, result)
end

function Server:read_request(conn)
    local data, err, partial = conn.client:receive(1024)
    local received = data or partial
    if received and #received > 0 then
        conn.buffer = conn.buffer .. received
    end
    local _, head_end = conn.buffer:find("\r?\n\r?\n")
    if head_end then
        self:prepare_response(conn, conn.buffer:sub(1, head_end))
    elseif #conn.buffer > Access.MAX_REQUEST_BYTES then
        self:prepare_response(conn, conn.buffer)
    elseif err == "closed" then
        conn.done = true
    end
    return received ~= nil and #received > 0
end

function Server:send_response(conn)
    if conn.sent >= #conn.outgoing then
        local chunk
        if conn.body then
            chunk, conn.body = conn.body, nil
        elseif conn.file and conn.file_left > 0 then
            chunk = conn.file:read(math.min(CHUNK, conn.file_left))
            conn.file_left = conn.file_left - (chunk and #chunk or 0)
        end
        if not chunk then
            conn.done = true
            return false
        end
        conn.outgoing, conn.sent = chunk, 0
        if chunk == "" then
            return true
        end
    end
    local before = conn.sent
    local last, err, partial = conn.client:send(conn.outgoing, conn.sent + 1)
    local position = last or partial or conn.sent
    -- Only real progress extends the deadline, so a stalled client cannot hold the connection.
    if position > conn.sent then
        conn.sent = position
        self:touch(conn)
    end
    if err == "closed" then
        conn.done = true
    end
    return conn.sent > before
end

-- The device the person is using has its own places, so other addresses on the network can never take them,
-- however many they are. The others share what is left.
function Server:has_room(ip)
    local preferred = self.access:preferred_ip()
    local from_ip, others = 0, 0
    for _, conn in ipairs(self.connections) do
        if conn.ip == ip then
            from_ip = from_ip + 1
        end
        if conn.ip ~= preferred then
            others = others + 1
        end
    end
    if ip == preferred then
        return from_ip < MAX_CLIENT_CONNECTIONS
    end
    return from_ip < MAX_OTHER_CONNECTIONS and others < MAX_CONNECTIONS - MAX_CLIENT_CONNECTIONS
end

function Server:step(conn)
    if conn.done then
        return false
    end
    if conn.state == "reading" then
        return self:read_request(conn)
    end
    return self:send_response(conn)
end

function Server:accept()
    for _ = 1, MAX_ACCEPTS do
        local client = self.listener:accept()
        if not client then
            return
        end
        client:settimeout(0)
        local ip = client:getpeername()
        -- A blocked address is dropped at once, so it cannot hold a place until its request times out.
        if not self.access:is_denied(ip) and self:has_room(ip) then
            table.insert(self.connections, { client = client, ip = ip, buffer = "", state = "reading", deadline = os.time() + REQUEST_TIMEOUT })
        else
            client:close()
        end
    end
end

-- Called repeatedly by the screen. Never waits on the network, so the interface stays responsive.
function Server:tick()
    if not self.listener then
        return false
    end
    self:accept()
    local stop_at = socket.gettime() + TICK_BUDGET
    for _ = 1, MAX_PASSES do
        local moved = false
        for _, conn in ipairs(self.connections) do
            -- An error in one request ends that connection, never the reader the person is using.
            local ok, progress = pcall(self.step, self, conn)
            if not ok then
                conn.done = true
                -- Only the error itself: never the request, which carries the code of the address.
                self.log("Book Rewind: a request failed:", tostring(progress))
            elseif progress then
                moved = true
            end
        end
        if not moved or socket.gettime() >= stop_at then
            break
        end
    end
    local now = os.time()
    for index = #self.connections, 1, -1 do
        local conn = self.connections[index]
        -- Drawing an image can hold this loop for seconds, and that time is not the fault of the connections waiting.
        if conn.done or (now > conn.deadline and now - (self.last_tick or now) < REQUEST_TIMEOUT) then
            self:close_connection(conn)
            table.remove(self.connections, index)
        end
    end
    self.last_tick = now
    return #self.connections > 0
end

return Server
