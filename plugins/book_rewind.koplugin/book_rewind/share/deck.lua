-- The data a browser needs to rebuild each card: colors and shapes of the background, as JSON.
local Themes = require("book_rewind/ui/themes")

local Deck = {}

local function hex(color)
    return string.format("#%02x%02x%02x", color[1], color[2], color[3])
end

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["<"] = "\\u003c", [">"] = "\\u003e", ["&"] = "\\u0026" }

local function quote(text)
    return '"' .. tostring(text):gsub('[%c"\\<>&]', function(char)
        return ESCAPES[char] or string.format("\\u%04x", char:byte())
    end) .. '"'
end

local function number(value)
    return (string.format("%.1f", value):gsub("%.0$", ""))
end

local function shape_json(shape)
    if shape[1] == "c" then
        return string.format('["c",%s,%s,%s,"%s"]', number(shape[2]), number(shape[3]), number(shape[4]), hex(shape[5]))
    elseif shape[1] == "d" then
        return string.format('["d",%d,%d,%s,%s,"%s"]', shape[2], shape[3], number(shape[4]), number(shape[5]), hex(shape[6]))
    elseif shape[1] == "r" then
        return string.format('["r",%s,%s,%s,%s,"%s"]', number(shape[2]), number(shape[3]), number(shape[4]), number(shape[5]), hex(shape[6]))
    end
    local points = {}
    for i, point in ipairs(shape[2]) do
        points[i] = number(point[1]) .. "," .. number(point[2])
    end
    return string.format('["p",[%s],"%s"]', table.concat(points, ","), hex(shape[3]))
end

local function layer_json(layer)
    local shapes = {}
    for i, shape in ipairs(layer.shapes) do
        shapes[i] = shape_json(shape)
    end
    local origin = layer.origin and string.format('"origin":[%s,%s],', number(layer.origin[1]), number(layer.origin[2])) or ""
    return string.format('{"anim":%s,"dur":%s,"delay":%s,%s"shapes":[%s]}', quote(layer.anim), number(layer.dur), number(layer.delay), origin, table.concat(shapes, ","))
end

-- cards: what the screen shows, without what is not shared. Returns JSON text.
function Deck.build(cards, theme_name, year, strings)
    local theme = Themes[theme_name]
    local items = {}
    for index, card in ipairs(cards) do
        local layers = {}
        for i, layer in ipairs(Themes.layers(theme, card)) do
            layers[i] = layer_json(layer)
        end
        items[index] = string.format('{"bg":"%s","layers":[%s]}', hex(Themes.palette(theme, card).bg), table.concat(layers, ","))
    end
    local texts = {}
    for key, value in pairs(strings.page) do
        texts[#texts + 1] = quote(key) .. ":" .. quote(value)
    end
    return string.format('{"year":%d,"theme":%s,"text":{%s},"cards":[%s]}', year, quote(theme_name), table.concat(texts, ","), table.concat(items, ","))
end

return Deck
