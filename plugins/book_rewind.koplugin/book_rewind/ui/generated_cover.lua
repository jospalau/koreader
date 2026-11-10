local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Cards = require("book_rewind/cards")
local Stats = require("book_rewind/stats")
local TextBoxWidget = require("ui/widget/textboxwidget")

local GeneratedCover = {}

local BASE_W, BASE_H = 300, 440
local MIN_WIDTH_FOR_TEXT = 60
local TITLE_SIZES = { 24, 20, 17, 14 }
local TITLE_ROOM = 190
local LONGEST_TITLE = 70
local LONGEST_AUTHOR = 40

local function style_for(title)
    local sum = 0
    for i = 1, #title do
        sum = (sum * 31 + title:byte(i)) % 1000003
    end
    return sum
end

-- A cloth binding with a hinge, a frame and an ornament, for books with no cover in the cache.
function GeneratedCover.draw(title, authors, max_w, max_h, theme)
    local rgb = theme.rgb
    local function color(c)
        if rgb then
            return Blitbuffer.ColorRGB32(c[1], c[2], c[3], 255)
        end
        return Blitbuffer.Color8(c[1])
    end
    local scale = math.min(max_w / BASE_W, max_h / BASE_H)
    local w, h = math.max(1, math.floor(BASE_W * scale)), math.max(1, math.floor(BASE_H * scale))
    local seed = style_for(title)
    local style = seed % 4
    local pick = theme.covers[seed % #theme.covers + 1]
    local cloth, foil = color(pick[1]), color(pick[2])
    local shade = color({ math.floor(pick[1][1] * 0.72), math.floor(pick[1][2] * 0.72), math.floor(pick[1][3] * 0.72) })
    local cover = Blitbuffer.new(w, h, rgb and Blitbuffer.TYPE_BBRGB32 or Blitbuffer.TYPE_BB8)
    local function rect(x, y, width, height, value)
        if rgb then
            cover:paintRectRGB32(x, y, width, height, value)
        else
            cover:paintRect(x, y, width, height, value)
        end
    end
    local function border(x, y, width, height, thick, value)
        if rgb then
            cover:paintBorderRGB32(x, y, width, height, thick, value)
        else
            cover:paintBorder(x, y, width, height, thick, value)
        end
    end
    local function disc(cx, cy, r, value)
        for dy = -r, r do
            local ox = math.floor(math.sqrt(r * r - dy * dy) + 0.5)
            rect(cx - ox, cy + dy, ox * 2, 1, value)
        end
    end
    local function px(value)
        return math.max(1, math.floor(value * scale + 0.5))
    end
    rect(0, 0, w, h, cloth)
    rect(0, 0, px(20), h, shade)
    rect(px(20), 0, px(2), h, foil)
    local left = px(34)
    border(left, px(14), w - left - px(14), h - px(28), px(3), foil)
    border(left + px(7), px(21), w - left - px(14) - px(14), h - px(42), 1, foil)
    local mid_x = math.floor((left + w - px(14)) / 2)
    if style == 0 then
        rect(left + px(30), px(255), w - left - px(14) - px(60), px(3), foil)
        disc(mid_x, px(290), px(14), foil)
        rect(left + px(30), px(322), w - left - px(14) - px(60), px(3), foil)
    elseif style == 1 then
        for i = 0, 7 do
            local a = math.rad(i * 45)
            disc(mid_x + math.floor(px(36) * math.cos(a)), px(295) + math.floor(px(36) * math.sin(a)), px(7), foil)
        end
        disc(mid_x, px(295), px(16), foil)
    elseif style == 2 then
        disc(mid_x, px(295), px(46), foil)
        disc(mid_x + px(16), px(285), px(38), cloth)
    else
        for i = -2, 2 do
            local half = px(40 - math.abs(i) * 12)
            rect(mid_x - half, px(295 + i * 16), half * 2, px(6), foil)
        end
    end
    if w < MIN_WIDTH_FOR_TEXT then
        return cover, w, h
    end
    local unscale = 1000 / Device.screen:scaleBySize(1000)
    local function text_box(content, face, size)
        return TextBoxWidget:new{
            text = content,
            face = Font:getFace(face, size * scale * unscale),
            width = w - left - px(40),
            alignment = "center",
            fgcolor = foil,
            bgcolor = cloth,
        }
    end
    local short_title = Cards.clip((title:gsub(":.*$", "")), LONGEST_TITLE)
    local box
    for _, size in ipairs(TITLE_SIZES) do
        if box then
            box:free()
        end
        box = text_box(short_title, "noto/NotoSerif-Bold.ttf", size)
        if box:getSize().h <= px(TITLE_ROOM) then
            break
        end
    end
    box:paintTo(cover, left + px(14), px(44))
    box:free()
    -- The same authors the cards accept, so "Windows User" and the like never get printed.
    local author = Stats.split_authors(authors)[1]
    if author then
        local author_box = text_box(Cards.clip(author, LONGEST_AUTHOR), "noto/NotoSerif-Italic.ttf", 15)
        author_box:paintTo(cover, left + px(14), px(372))
        author_box:free()
    end
    return cover, w, h
end

return GeneratedCover
