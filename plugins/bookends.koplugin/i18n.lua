-- i18n.lua — Bookends
-- Translation loader for plugin-specific strings.
-- KOReader's gettext already translates standard strings (Cancel, Save, etc.).
-- This module adds translations for bookends-specific strings.
--
-- HOW TO ADD A LANGUAGE
--   1. Copy locale/bookends.pot -> locale/<lang>.po (e.g. locale/es.po)
--   2. Fill in the msgstr values.
--   3. Done — no code changes needed.

local logger = require("logger")

local _dir = (debug.getinfo(1, "S").source:match("^@(.+/)") or "./")

-- Minimal .po parser
local function parsePO(path)
    local f = io.open(path, "r")
    if not f then return nil end

    local map = {}
    local msgid, msgstr, in_id, in_str = nil, nil, false, false

    local function flush()
        if msgid and msgstr and msgid ~= "" and msgstr ~= "" then
            map[msgid] = msgstr
        end
        msgid, msgstr, in_id, in_str = nil, nil, false, false
    end

    local function unescape(s)
        return s:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub('\\"', '"'):gsub("\\\\", "\\")
    end

    for raw_line in f:lines() do
        local line = raw_line:match("^%s*(.-)%s*$")
        if line:match("^#") or line == "" then
            if line == "" then flush() end
        elseif line:match('^msgid%s+"') then
            flush()
            msgid  = unescape(line:match('^msgid%s+"(.*)"') or "")
            in_id  = true; in_str = false
        elseif line:match('^msgstr%s+"') then
            msgstr = unescape(line:match('^msgstr%s+"(.*)"') or "")
            in_str = true; in_id  = false
        elseif line:match('^"') then
            local cont = unescape(line:match('^"(.*)"') or "")
            if in_id  and msgid  then msgid  = msgid  .. cont end
            if in_str and msgstr then msgstr = msgstr .. cont end
        end
    end
    flush()
    f:close()
    return map
end

local function detectLang()
    local lang = G_reader_settings and G_reader_settings:readSetting("language")
    if type(lang) == "string" and lang ~= "" then return lang end
    local lc = os.getenv("LANG") or os.getenv("LC_ALL") or os.getenv("LC_MESSAGES") or ""
    lang = lc:match("^([a-zA-Z_]+)")
    return lang or "en"
end

local _installed = false

local function install()
    if _installed then return end

    local lang = detectLang()
    if lang == "en" or lang == "en_US" then return end

    -- Try loading translation file
    local translations
    local function try(name)
        local path = _dir .. "locale/" .. name .. ".po"
        local t = parsePO(path)
        if t and next(t) then
            local n = 0; for _ in pairs(t) do n = n + 1 end
            logger.info("bookends i18n: loaded " .. path .. " — " .. n .. " strings")
            return t
        end
    end
    translations = try(lang) or (function()
        local prefix = lang:match("^([a-zA-Z]+)")
        if prefix and prefix ~= lang then return try(prefix) end
    end)()

    if not translations then return end

    local orig_gettext = package.loaded["gettext"]
    if not orig_gettext then return end

    local wrapper
    local mt = getmetatable(orig_gettext)
    if mt and mt.__call then
        wrapper = setmetatable({}, {
            __call = function(_, msgid)
                local t = translations[msgid]
                if t then return t end
                return orig_gettext(msgid)
            end,
            __index = orig_gettext,
        })
    elseif type(orig_gettext) == "function" then
        wrapper = function(msgid)
            local t = translations[msgid]
            if t then return t end
            return orig_gettext(msgid)
        end
    else
        return
    end

    package.loaded["gettext"] = wrapper
    _installed = true
    logger.info("bookends i18n: installed for language: " .. lang)
end

return {
    install = install,
    getLang = detectLang,
}
