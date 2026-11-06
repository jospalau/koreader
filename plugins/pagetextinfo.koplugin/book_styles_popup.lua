--[[
Book Styles (plain text, scrollable)
Standalone version of PageTextInfo:onGetStyles. Shows the classed elements of
the text at the start of the current page and the CSS rules of those classes,
as monospaced text in a TextViewer (scroll, search and close come for free).

Output:
  Source: <stylesheet path>

  Elements
  <p class="tx">  x12
  ...

  Classes
  tx, para, ...

  CSS
  .tx {
      text-indent: 1.2em;
      margin: 0;
  }

  Not in stylesheet
  .foo, .bar

Action: GetStyles
]]--

local Device     = require("device")
local Dispatcher = require("dispatcher")
local Font       = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local UIManager  = require("ui/uimanager")
local util       = require("util")
local Screen     = Device.screen

-- true  = rebuild every rule with one declaration per line (4 spaces)
-- false = keep each rule exactly as written in the stylesheet
local PRETTY_CSS = true

-- Stylesheet locations to try, in order.
local CSS_PATHS = {
    "OPS/styles/stylesheet.css",
    "stylesheet.css",
    "epub/css/core.css",   -- resources/arthur-conan-doyle_the-hound-of-the-baskervilles.epub
    "OEBPS/styles/stylesheet.css",
    "OEBPS/stylesheet.css",
}

local TRACKED_TAGS = {
    body = true, p = true, div = true, span = true, blockquote = true,
    h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true,
}

-- ── Parsing ───────────────────────────────────────────────────────────────────

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Opening tags with a class attribute → ordered elements {tag, class, count}
-- plus an ordered list of unique class names.
local function collectElements(html)
    local elements, by_key = {}, {}
    local classes, seen_class = {}, {}

    for tag, attrs in html:gmatch("<(%a[%w]*)([^>]*)>") do
        tag = tag:lower()
        if TRACKED_TAGS[tag] then
            local cls = attrs:match('class%s*=%s*"(.-)"') or attrs:match("class%s*=%s*'(.-)'")
            if cls and cls ~= "" then
                cls = trim(cls):gsub("%s+", " ")
                local key = tag .. "\0" .. cls
                if by_key[key] then
                    by_key[key].count = by_key[key].count + 1
                else
                    local e = { tag = tag, class = cls, count = 1 }
                    by_key[key] = e
                    table.insert(elements, e)
                end
                for c in cls:gmatch("%S+") do
                    if not seen_class[c] then
                        seen_class[c] = true
                        table.insert(classes, c)
                    end
                end
            end
        end
    end
    return elements, classes
end

-- True if `selector` contains `.cls` as a whole class name (.tx does not match .tx2).
local function selectorHasClass(selector, cls)
    local needle, start = "." .. cls, 1
    while true do
        local s, e = selector:find(needle, start, true)
        if not s then return false end
        local nextc = selector:sub(e + 1, e + 1)
        if nextc == "" or not nextc:match("[%w_%-]") then return true end
        start = e + 1
    end
end

-- Flat stylesheet → { {selector=, body=, raw=}, ... }.
-- Rules inside @media are read too (without their condition).
local function parseCSS(css_text)
    local rules = {}
    css_text = css_text:gsub("/%*.-%*/", "")
    for selector, body in css_text:gmatch("([^{}]+)%{([^{}]*)%}") do
        selector = trim(selector)
        table.insert(rules, {
            selector = selector,
            body     = body,
            raw      = selector .. " {" .. body .. "}",
        })
    end
    return rules
end

-- "a: b; c: url(x;y)" → { "a: b", "c: url(x;y)" }  (respects parentheses and quotes)
local function splitDeclarations(body)
    local decls, buf, depth, quote = {}, {}, 0, nil

    local function flush()
        local s = trim((table.concat(buf):gsub("%s+", " ")))
        buf = {}
        if s ~= "" then table.insert(decls, s) end
    end

    for i = 1, #body do
        local c = body:sub(i, i)
        if quote then
            table.insert(buf, c)
            if c == quote then quote = nil end
        elseif c == '"' or c == "'" then
            quote = c
            table.insert(buf, c)
        elseif c == "(" then
            depth = depth + 1
            table.insert(buf, c)
        elseif c == ")" then
            depth = math.max(0, depth - 1)
            table.insert(buf, c)
        elseif c == ";" and depth == 0 then
            flush()
        else
            table.insert(buf, c)
        end
    end
    flush()
    return decls
end

local function formatRule(rule)
    if not PRETTY_CSS then return trim(rule.raw) end

    local sels = {}
    for sel in rule.selector:gmatch("[^,]+") do
        table.insert(sels, trim((sel:gsub("%s+", " "))))
    end
    local lines = { table.concat(sels, ",\n") .. " {" }
    for _, d in ipairs(splitDeclarations(rule.body)) do
        local prop, value = d:match("^([^:]+):%s*(.*)$")
        if prop then
            table.insert(lines, "    " .. trim(prop) .. ": " .. value .. ";")
        else
            table.insert(lines, "    " .. d .. ";")
        end
    end
    table.insert(lines, "}")
    return table.concat(lines, "\n")
end

local function rulesForClass(rules, cls)
    local out = {}
    for _, r in ipairs(rules) do
        for sel in r.selector:gmatch("[^,]+") do
            if selectorHasClass(sel, cls) then
                table.insert(out, r)
                break
            end
        end
    end
    return out
end

-- ── Build text ────────────────────────────────────────────────────────────────

local function buildText(ui)
    local doc = ui.document

    local css_text, css_path
    for _, path in ipairs(CSS_PATHS) do
        local content = doc:getDocumentFileContent(path)
        if content then
            css_text, css_path = content, path
            break
        end
    end

    local first = doc._document:getTextFromPositions(0, 0, 10, Screen:getHeight(), false, false)
    if not first or not first.pos0 or not first.pos1 then return nil end
    local html = doc._document:getHTMLFromXPointers(first.pos0, first.pos1, 0xE830, true)
    if html == nil then return nil end

    local elements, classes = collectElements(html)
    local all_rules = css_text and parseCSS(css_text) or {}

    local shown, blocks, missing = {}, {}, {}
    for _, cls in ipairs(classes) do
        local matched = rulesForClass(all_rules, cls)
        if #matched == 0 then
            table.insert(missing, "." .. cls)
        end
        for _, r in ipairs(matched) do
            local key = r.selector .. "\0" .. r.body
            if not shown[key] then   -- each rule once, even if several classes match it
                shown[key] = true
                table.insert(blocks, formatRule(r))
            end
        end
    end

    local out = {}
    table.insert(out, "Source: " .. (css_path or "stylesheet not found"))

    table.insert(out, "")
    table.insert(out, "Elements")
    if #elements == 0 then
        table.insert(out, "(none with class)")
    end
    for _, e in ipairs(elements) do
        local line = string.format('<%s class="%s">', e.tag, e.class)
        if e.count > 1 then line = line .. "  x" .. e.count end
        table.insert(out, line)
    end

    table.insert(out, "")
    table.insert(out, "Classes")
    table.insert(out, #classes > 0 and table.concat(classes, ", ") or "(none)")

    table.insert(out, "")
    table.insert(out, "CSS")
    if #blocks == 0 then
        table.insert(out, "(no matching rules)")
    else
        table.insert(out, table.concat(blocks, "\n\n"))
    end

    if #missing > 0 then
        table.insert(out, "")
        table.insert(out, "Not in stylesheet")
        table.insert(out, table.concat(missing, ", "))
    end

    return table.concat(out, "\n")
end

-- ── Registration ──────────────────────────────────────────────────────────────

Dispatcher:registerAction("get_styles", {
    category  = "none",
    event     = "GetStyles",
    title     = "Get book styles",
    general   = true,
    separator = true,
})

local function showMessage(text)
    UIManager:show(InfoMessage:new{
        text  = text,
        face  = Font:getFace("myfont3"),
        width = math.floor(Screen:getWidth() * 0.85),
    })
end

local ReaderUI = require("apps/reader/readerui")
local _orig    = ReaderUI.registerKeyEvents

ReaderUI.registerKeyEvents = function(self)
    if _orig then _orig(self) end
    if not self.document then return end
    if util.getFileNameSuffix(self.document.file) ~= "epub" then return end

    self.onGetStyles = function(this)
        local text = buildText(this)
        if not text then
            showMessage("Could not retrieve styles")
            return true
        end
        UIManager:show(TextViewer:new{
            title            = "Book styles",
            title_multilines = true,
            text             = text,
            text_type        = "file_content",
        })
        return true
    end
end
