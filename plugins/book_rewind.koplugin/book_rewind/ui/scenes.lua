-- The background shapes behind each card, on the 600x800 design space. Layers keep their motion
-- so the browser page can animate them; on a screen or in a saved image they stay still.
local Scenes = {}

local STARS = {
    time = {
        { { 492, 285, 2 }, { 418, 674, 2 }, { 77, 183, 1.5 }, { 449, 424, 3 }, { 228, 668, 2 }, { 102, 372, 1.5 }, { 133, 65, 1.5 }, { 48, 337, 1.5 }, { 483, 552, 3 }, { 32, 405, 2 }, { 297, 775, 3 } },
        { { 208, 754, 3 }, { 249, 670, 2 }, { 320, 51, 2 }, { 149, 394, 1.5 }, { 432, 174, 1.5 }, { 398, 755, 2 }, { 90, 130, 1.5 }, { 584, 125, 2 }, { 545, 330, 2 }, { 73, 668, 2 }, { 34, 623, 1.5 } },
        { { 565, 582, 3 }, { 547, 419, 1.5 }, { 48, 159, 3 }, { 505, 674, 3 }, { 576, 305, 2 }, { 153, 406, 3 }, { 453, 669, 2 }, { 23, 445, 2 }, { 489, 381, 2 }, { 33, 398, 2 } },
    },
    owl = {
        { { 531, 239, 1.5 }, { 576, 454, 1.5 }, { 59, 590, 2 }, { 585, 718, 2 }, { 549, 526, 2 }, { 360, 731, 2 }, { 497, 733, 1.5 } },
        { { 61, 94, 1.5 }, { 520, 716, 3 }, { 196, 735, 2 }, { 512, 451, 1.5 }, { 74, 768, 2 } },
        { { 83, 266, 1.5 }, { 565, 140, 2 }, { 82, 115, 2 }, { 517, 80, 2 } },
    },
    night = {
        { { 475, 593, 3 }, { 259, 634, 1.5 }, { 422, 130, 2 }, { 356, 109, 2 }, { 115, 31, 1.5 }, { 533, 215, 2 }, { 229, 20, 2 }, { 392, 657, 3 } },
        { { 474, 540, 2 }, { 322, 165, 1.5 }, { 27, 561, 1.5 }, { 487, 354, 3 }, { 99, 488, 2 }, { 537, 315, 1.5 }, { 407, 88, 1.5 }, { 352, 35, 3 }, { 488, 518, 2 }, { 441, 679, 3 }, { 323, 40, 2 }, { 464, 284, 1.5 }, { 267, 762, 2 } },
        { { 563, 730, 1.5 }, { 72, 56, 2 }, { 428, 584, 1.5 }, { 83, 596, 1.5 }, { 12, 238, 2 }, { 215, 711, 2 }, { 584, 212, 3 }, { 131, 424, 3 }, { 348, 323, 3 }, { 27, 635, 2 }, { 150, 415, 2 }, { 174, 777, 2 } },
    },
    dawn = {
        { { 277, 317, 2 }, { 471, 587, 2 }, { 157, 529, 3 }, { 51, 387, 2 }, { 551, 23, 2 }, { 493, 554, 2 }, { 585, 565, 3 }, { 525, 751, 2 } },
        { { 248, 702, 2 }, { 313, 50, 3 }, { 462, 713, 3 }, { 575, 261, 2 }, { 255, 760, 3 }, { 198, 322, 2 }, { 451, 678, 1.5 }, { 48, 25, 2 }, { 240, 705, 2 }, { 161, 284, 3 }, { 579, 419, 2 } },
        { { 242, 676, 2 }, { 141, 720, 1.5 }, { 154, 282, 2 }, { 560, 200, 2 }, { 211, 738, 2 }, { 446, 64, 2 }, { 228, 652, 1.5 }, { 180, 720, 1.5 }, { 320, 295, 1.5 }, { 315, 52, 3 }, { 232, 284, 3 }, { 16, 689, 2 }, { 74, 316, 3 }, { 235, 335, 2 } },
    },
}
local SPARKS = { { 271, 370, 2 }, { 435, 550, 3 }, { 122, 128, 2 }, { 441, 622, 3 }, { 90, 287, 3 }, { 313, 236, 2 }, { 298, 279, 2 }, { 296, 338, 3 }, { 198, 377, 3 }, { 411, 148, 3 }, { 427, 578, 3 }, { 212, 313, 4 }, { 316, 151, 3 }, { 37, 358, 3 }, { 550, 259, 4 }, { 463, 673, 3 }, { 471, 522, 3 }, { 268, 372, 3 }, { 74, 143, 2 }, { 503, 701, 3 }, { 561, 607, 4 }, { 381, 208, 3 }, { 98, 482, 3 }, { 481, 342, 3 }, { 394, 506, 3 }, { 233, 391, 2 } }

-- Room above and below the 800 of the card, in the same units: a story needs 134, and a tall phone shows a little more.
local MARGIN = 260

-- The rays of the session art, which continue past the card when there is room.
local RAYS = {
    { 524.8, 390.0, 1199.9, 376.6, 1199.9, 403.4 },
    { 548.7, 417.7, 1196.6, 467.6, 1194.9, 485.7 },
    { 544.6, 437.2, 1189.0, 530.2, 1186.1, 547.7 },
    { 514.4, 444.1, 1182.2, 568.0, 1175.6, 598.0 },
    { 558.0, 476.5, 1168.2, 627.2, 1159.7, 656.3 },
    { 540.0, 491.6, 1148.6, 689.8, 1140.5, 711.7 },
    { 515.5, 513.6, 1113.1, 775.7, 1097.2, 807.6 },
    { 525.3, 562.8, 1053.5, 882.2, 1043.9, 896.6 },
    { 476.9, 545.5, 1021.3, 928.3, 1008.7, 944.7 },
    { 470.2, 562.3, 989.9, 968.0, 960.8, 1001.0 },
    { 460.9, 593.6, 919.2, 1043.1, 891.3, 1068.5 },
    { 429.9, 592.6, 841.3, 1109.0, 826.9, 1119.6 },
    { 432.1, 624.3, 806.0, 1134.3, 773.1, 1155.6 },
    { 414.0, 638.7, 735.6, 1177.6, 703.8, 1194.3 },
    { 401.3, 665.9, 669.9, 1210.5, 630.1, 1227.3 },
    { 375.8, 662.9, 590.7, 1241.7, 556.9, 1252.6 },
    { 344.1, 653.9, 489.8, 1269.7, 449.7, 1277.5 },
    { 314.1, 668.0, 362.3, 1287.8, 342.5, 1289.0 },
    { 291.0, 673.6, 277.6, 1289.7, 256.6, 1289.0 },
    { 276.2, 693.2, 238.3, 1287.9, 199.7, 1284.4 },
    { 254.4, 655.6, 148.1, 1277.1, 103.0, 1268.2 },
    { 221.6, 666.3, 38.1, 1251.0, 3.6, 1239.8 },
    { 189.6, 681.4, -38.7, 1223.8, -79.7, 1206.0 },
    { 191.9, 608.9, -127.5, 1182.0, -161.1, 1162.9 },
    { 135.5, 650.0, -214.0, 1128.8, -244.8, 1106.4 },
    { 136.7, 592.4, -302.7, 1058.4, -321.4, 1041.0 },
    { 116.9, 577.2, -367.0, 994.2, -378.0, 981.9 },
    { 128.6, 546.4, -398.9, 957.0, -411.2, 941.6 },
    { 106.1, 534.6, -449.7, 888.0, -460.6, 871.1 },
    { 106.9, 511.8, -477.9, 842.7, -499.9, 802.5 },
    { 48.7, 510.9, -523.5, 753.2, -536.8, 721.2 },
    { 76.0, 464.3, -558.1, 661.4, -570.7, 617.6 },
    { 31.8, 445.4, -583.2, 563.0, -588.2, 535.4 },
    { 74.0, 406.1, -597.6, 456.1, -598.9, 435.2 },
    { 53.5, 389.1, -600.0, 399.1, -599.9, 375.3 },
    { 85.7, 367.2, -597.2, 319.3, -594.9, 294.6 },
    { 51.9, 340.2, -588.9, 249.4, -584.1, 221.3 },
    { 61.8, 308.6, -568.1, 152.7, -556.9, 114.8 },
    { 98.5, 292.8, -537.2, 59.8, -522.1, 23.8 },
    { 64.4, 234.1, -490.5, -40.2, -469.2, -77.2 },
    { 107.4, 223.5, -428.0, -139.1, -410.4, -162.5 },
    { 134.1, 225.5, -393.9, -183.2, -369.3, -211.7 },
    { 140.5, 206.6, -344.6, -238.0, -328.4, -254.3 },
    { 159.5, 202.8, -294.7, -285.5, -281.4, -297.0 },
    { 154.5, 172.5, -256.4, -317.4, -241.1, -329.1 },
    { 155.0, 148.9, -230.6, -337.0, -192.8, -363.1 },
    { 182.5, 152.5, -155.6, -386.2, -134.4, -398.2 },
    { 184.8, 109.0, -92.8, -419.8, -74.7, -428.3 },
    { 219.8, 122.0, -7.9, -455.7, 22.2, -466.0 },
    { 238.3, 126.5, 56.6, -476.5, 75.2, -481.5 },
    { 255.6, 135.8, 101.2, -487.8, 144.6, -496.5 },
    { 270.3, 105.3, 168.6, -500.4, 216.8, -506.1 },
    { 293.7, 140.8, 256.7, -509.0, 291.2, -510.0 },
    { 318.6, 79.0, 337.0, -509.2, 386.4, -505.8 },
    { 345.8, 120.4, 460.4, -495.6, 484.6, -490.9 },
    { 363.7, 112.5, 509.2, -485.3, 550.2, -474.5 },
    { 385.0, 144.8, 620.7, -450.9, 645.9, -440.9 },
    { 426.2, 115.0, 697.9, -417.2, 741.9, -394.0 },
    { 452.2, 143.2, 802.4, -356.7, 838.3, -331.3 },
    { 454.7, 181.8, 871.7, -305.1, 897.2, -283.3 },
    { 463.0, 198.2, 923.0, -259.5, 935.0, -247.8 },
    { 505.6, 176.2, 954.2, -228.1, 980.7, -198.7 },
    { 524.5, 199.1, 1009.2, -164.1, 1037.8, -125.5 },
    { 501.4, 263.9, 1083.6, -52.7, 1097.1, -27.8 },
    { 507.9, 281.6, 1115.0, 8.1, 1124.3, 28.6 },
    { 554.6, 287.8, 1141.8, 71.5, 1157.2, 115.7 },
    { 560.1, 320.8, 1172.3, 168.6, 1181.0, 205.9 },
    { 571.0, 342.3, 1186.5, 234.8, 1192.4, 272.9 },
    { 545.9, 380.2, 1198.5, 338.0, 1199.9, 379.6 },
}

local function C(x, y, r, color) return { "c", x, y, r, color } end
local function R(x, y, w, h, color) return { "r", x, y, w, h, color } end
local function P(points, color) return { "p", points, color } end

local function layer(anim, dur, shapes, origin, delay)
    return { anim = anim, dur = dur, shapes = shapes, origin = origin, delay = delay or 0 }
end

-- What only matters outside the card: the art already draws it inside, and a device screen ends at the card.
local function beyond_the_card(shapes)
    local l = layer("none", 1, shapes)
    l.beyond_card = true
    return l
end

local function join(...)
    local all = {}
    for _, list in ipairs({ ... }) do
        for _, item in ipairs(list) do
            all[#all + 1] = item
        end
    end
    return all
end

local function tilted(cx, cy, w, h, degrees, color)
    local a = math.rad(degrees)
    local ca, sa = math.cos(a), math.sin(a)
    local points = {}
    for i, corner in ipairs({ { -w / 2, -h / 2 }, { w / 2, -h / 2 }, { w / 2, h / 2 }, { -w / 2, h / 2 } }) do
        points[i] = { cx + corner[1] * ca - corner[2] * sa, cy + corner[1] * sa + corner[2] * ca }
    end
    return P(points, color)
end

local function cloud(x, y, s, color)
    return {
        C(x, y, 24 * s, color), C(x + 32 * s, y - 12 * s, 30 * s, color), C(x + 68 * s, y, 22 * s, color),
        R(x - 2 * s, y - 2 * s, 70 * s, 24 * s, color),
    }
end

local function sun_rays(x, y, r, color)
    local rays = {}
    for i = 0, 11 do
        local a = math.rad(i * 30 + 8)
        local r0, r1 = r + 12, r + (i % 2 == 0 and 38 or 26)
        rays[#rays + 1] = P({
            { x + r0 * math.cos(a - 0.09), y + r0 * math.sin(a - 0.09) },
            { x + r1 * math.cos(a), y + r1 * math.sin(a) },
            { x + r0 * math.cos(a + 0.09), y + r0 * math.sin(a + 0.09) },
        }, color)
    end
    return rays
end

local function star_layers(key, color)
    local layers = {}
    for i, group in ipairs(STARS[key]) do
        local shapes = {}
        for _, star in ipairs(group) do
            shapes[#shapes + 1] = C(star[1], star[2], star[3], color)
            -- The extra height of a story, above and below the card, gets stars too.
            if star[2] < MARGIN then
                shapes[#shapes + 1] = C(star[1], star[2] + 800, star[3], color)
            elseif star[2] > 800 - MARGIN then
                shapes[#shapes + 1] = C(star[1], star[2] - 800, star[3], color)
            end
        end
        layers[i] = layer("twinkle", 4 + (i - 1) * 1.5, shapes, nil, -(i - 1) * 1.3)
    end
    return layers
end

local function bands(color)
    local shapes = {}
    for x = -190, 1140, 190 do
        local top, bottom = -MARGIN, 800 + MARGIN
        shapes[#shapes + 1] = P({ { x - top / 2, top }, { x + 70 - top / 2, top }, { x + 70 - bottom / 2, bottom }, { x - bottom / 2, bottom } }, color)
    end
    return shapes
end

local function heart(x, y, s, color)
    local points = {}
    for degrees = 0, 352, 8 do
        local a = math.rad(degrees)
        points[#points + 1] = {
            x + 16 * s * math.sin(a) ^ 3,
            y - s * (13 * math.cos(a) - 5 * math.cos(2 * a) - 2 * math.cos(3 * a) - math.cos(4 * a)),
        }
    end
    return P(points, color)
end

local Card = {}

function Card.circles(p)
    return { layer("drift-x", 28, { C(100, 690, 230, p.t1) }), layer("drift-x-rev", 34, { C(530, 130, 190, p.t2) }) }
end

function Card.pulse(p)
    return {
        layer("pulse", 7, { C(300, 400, 390, p.t1) }, { 300, 400 }),
        layer("pulse", 5, { C(300, 400, 300, p.t2) }, { 300, 400 }, -2),
    }
end

-- The session art has rays up to its edges, and these go on past them.
function Card.session(p)
    local shapes = {}
    for i, ray in ipairs(RAYS) do
        shapes[i] = P({ { ray[1], ray[2] }, { ray[3], ray[4] }, { ray[5], ray[6] } }, p.ink)
    end
    local layers = Card.pulse(p)
    layers[#layers + 1] = beyond_the_card(shapes)
    return layers
end

-- The dotted art has halftone up to its edges, and these rows go on past them, on the same grid.
function Card.dotted(p)
    local layers = Card.circles(p)
    layers[#layers + 1] = beyond_the_card({ { "d", -31, -1, 11, 1.5, p.ink }, { "d", 84, 112, 11, 1.5, p.ink } })
    return layers
end

function Card.bands(p)
    return { layer("slide", 24, bands(p.t1)), layer("pulse", 8, { C(90, 720, 120, p.t2) }, { 90, 720 }) }
end

function Card.bands_plain(p)
    return { layer("slide", 24, bands(p.t1)) }
end

function Card.hills(p)
    return {
        layer("pulse", 9, { C(470, 190, 84, p.t2) }, { 470, 190 }),
        layer("drift-x", 40, { P({ { -60, 800 }, { 120, 500 }, { 300, 700 }, { 470, 430 }, { 680, 800 }, { 680, 800 + MARGIN }, { -60, 800 + MARGIN } }, p.t1) }),
        layer("drift-x-rev", 22, join(cloud(70, 130, 1, p.t2), cloud(330, 70, 0.7, p.t1))),
    }
end

function Card.streaks(p)
    return {
        layer("drift-x", 9, { R(-40, 110, 300, 10, p.t1), R(280, 170, 420, 10, p.t1), R(-60, 630, 360, 10, p.t1), R(320, 700, 340, 10, p.t1), R(40, 760, 240, 10, p.t1) }),
        layer("drift-x-rev", 6, { R(340, 70, 300, 16, p.t2), R(-60, 250, 180, 16, p.t2), R(420, 600, 240, 16, p.t2) }),
    }
end

function Card.pages(p)
    return {
        layer("rise", 26, { tilted(60, 110, 110, 150, -14, p.t1), tilted(545, 90, 120, 160, 12, p.t1), tilted(40, 660, 100, 140, 10, p.t1), tilted(560, 690, 110, 150, -12, p.t1) }),
        layer("rise-slow", 38, { tilted(140, 40, 90, 120, 20, p.t2), tilted(470, 740, 90, 120, 16, p.t2), tilted(590, 380, 80, 110, -18, p.t2), tilted(5, 390, 80, 110, 14, p.t2) }),
    }
end

function Card.books(p)
    return {
        layer("drift-x", 26, { C(90, 250, 210, p.t1) }),
        layer("drift-y", 32, { C(520, 560, 240, p.t2) }),
        layer("drift-x-rev", 20, { tilted(80, 500, 46, 150, -16, p.t2), tilted(150, 90, 34, 120, 14, p.t1) }),
    }
end

function Card.midnight(p)
    return join({ layer("drift-y", 30, { C(120, 640, 280, p.t1) }) }, star_layers("time", p.t2))
end

function Card.drift(p)
    return { layer("drift-y", 30, { C(120, 640, 280, p.t1) }), layer("drift-x", 36, { C(540, 120, 170, p.t1) }) }
end

function Card.sparks(p)
    local shapes = {}
    for i, spark in ipairs(SPARKS) do
        shapes[i] = C(spark[1], spark[2], spark[3], p.t2)
    end
    for _, spark in ipairs(SPARKS) do
        if spark[2] < MARGIN + 60 then
            shapes[#shapes + 1] = C(spark[1], spark[2] + 800, spark[3], p.t2)
        elseif spark[2] > 800 - MARGIN then
            shapes[#shapes + 1] = C(spark[1], spark[2] - 800, spark[3], p.t2)
        end
    end
    return { layer("drift-y", 30, { C(490, 650, 240, p.t1) }), layer("rise", 6, shapes) }
end

function Card.waves(p)
    local function wave(base, amplitude, color)
        local points = {}
        for x = -210, 830, 20 do
            points[#points + 1] = { x, base + amplitude * math.sin(x / 70) }
        end
        points[#points + 1] = { 830, 800 + MARGIN }
        points[#points + 1] = { -210, 800 + MARGIN }
        return P(points, color)
    end
    return { layer("drift-x", 12, { wave(620, 28, p.t1) }), layer("drift-x-rev", 9, { wave(700, 20, p.t2) }) }
end

function Card.spin(p)
    local near, far = {}, {}
    for a = 0, 315, 45 do
        local angle = math.rad(a)
        near[#near + 1] = tilted(300 + 300 * math.cos(angle), 400 + 300 * math.sin(angle), 74, 104, a + 90, p.t1)
    end
    for a = 20, 320, 60 do
        local angle = math.rad(a)
        far[#far + 1] = tilted(300 + 420 * math.cos(angle), 400 + 420 * math.sin(angle), 60, 84, a, p.t2)
    end
    return { layer("spin", 60, near, { 300, 400 }), layer("spin-rev", 80, far, { 300, 400 }) }
end

function Card.dashes(p)
    local shapes = {}
    for _, y in ipairs({ -90, 40, 720, 860 }) do
        for x = -190, 760, 190 do
            shapes[#shapes + 1] = R(x, y, 70, 12, p.t1)
        end
    end
    return { layer("slide", 7, shapes) }
end

function Card.rays(p)
    local shapes = {}
    for a = 190, 350, 20 do
        local left, right = math.rad(a - 4), math.rad(a + 4)
        shapes[#shapes + 1] = P({ { 300, 870 }, { 300 + 900 * math.cos(left), 870 + 900 * math.sin(left) }, { 300 + 900 * math.cos(right), 870 + 900 * math.sin(right) } }, p.t1)
    end
    return { layer("spin-slow", 70, shapes, { 300, 870 }) }
end

function Card.hearts(p)
    return {
        layer("rise", 9, { heart(60, 120, 3.6, p.t1), heart(530, 700, 4.4, p.t1), heart(40, 720, 2.6, p.t2) }),
        layer("rise-slow", 13, { heart(540, 70, 2.6, p.t2), heart(300, 760, 3, p.t1) }),
    }
end

function Card.compass(p)
    local ticks = {}
    for a = 0, 340, 20 do
        local angle = math.rad(a)
        ticks[#ticks + 1] = tilted(300 + 360 * math.cos(angle), 400 + 360 * math.sin(angle), 10, 58, a + 90, p.t1)
    end
    return {
        layer("spin", 90, ticks, { 300, 400 }),
        layer("twinkle", 6, { C(70, 60, 4, p.t2), C(530, 60, 4, p.t2), C(60, 740, 4, p.t2), C(540, 740, 4, p.t2) }),
    }
end

function Card.lens(p)
    return { layer("drift-x", 20, { C(90, 120, 70, p.t1), C(540, 720, 100, p.t1), C(530, 90, 36, p.t1), C(60, 710, 44, p.t1) }) }
end

function Card.sunny(p)
    return {
        layer("spin", 40, sun_rays(90, 90, 40, p.t2), { 90, 90 }),
        layer("none", 1, { C(90, 90, 40, p.t2) }),
        layer("drift-x", 24, join(cloud(420, 70, 1, p.t1), cloud(60, 720, 1.3, p.t1), cloud(400, 730, 1, p.t1))),
    }
end

function Card.owl(p)
    return join({ layer("drift-y", 28, { C(520, 700, 230, p.t1) }) }, star_layers("owl", p.t2))
end

function Scenes.card(name, palette)
    return Card[name](palette)
end

-- The sky changes with the period of the day when the reader reads the most.
function Scenes.hours(period, h)
    if period == "night" or period == "dawn" then
        local r = 46
        return join(star_layers(period, h.star), {
            layer("float", 9, { C(490, 124, r, h.moon), C(490 - r * 0.42, 124 - r * 0.12, r * 0.92, h.bg) }),
            layer("drift-x", 30, join(cloud(380, 300, 1.3, h.cloud), cloud(30, 690, 1.6, h.cloud))),
        })
    end
    local y, r = 120, 52
    if period == "morning" then
        y, r = 150, 44
    end
    return {
        layer("spin", 40, sun_rays(478, y, r, h.ray), { 478, y }),
        layer("none", 1, { C(478, y, r, h.sun) }),
        layer("drift-x", 22, join(cloud(440, y + 82, 0.72, h.cloud), cloud(26, 268, 0.5, h.cloud))),
        layer("drift-x-rev", 34, join(cloud(40, 700, 1.3, h.cloud2), cloud(370, 740, 1, h.cloud2))),
    }
end

return Scenes
