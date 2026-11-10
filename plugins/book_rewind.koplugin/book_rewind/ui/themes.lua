-- Colors of each theme. Gray is for black and white screens, eink for color e-ink, and vibrant for phones.
local function g(v) return { v, v, v } end

local Themes = {}

Themes.gray = {
    name = "gray",
    rgb = false,
    spines = { g(0), g(40), g(0), g(68) },
    band = g(255),
    covers = {
        { g(34), g(255) },
        { g(68), g(255) },
        { g(238), g(0) },
        { g(204), g(0) },
    },
    families = {
        indigo = { bg = g(34), ink = g(187), second = g(136), text = g(255), inner = g(255), t1 = g(51), t2 = g(85) },
        midnight = { bg = g(0), ink = g(0), second = g(136), text = g(255), inner = g(255), t1 = g(34), t2 = g(204) },
        navy = { bg = g(0), ink = g(0), second = g(136), text = g(255), inner = g(255), t1 = g(34), t2 = g(204) },
        pine = { bg = g(0), ink = g(0), second = g(136), text = g(255), inner = g(255), t1 = g(34), t2 = g(204) },
        ember = { bg = g(17), ink = g(17), second = g(136), text = g(255), inner = g(255), t1 = g(34), t2 = g(204) },
        teal = { bg = g(68), ink = g(255), second = g(187), text = g(255), inner = g(255), t1 = g(85), t2 = g(102) },
        violet = { bg = g(68), ink = g(255), second = g(187), text = g(255), inner = g(34), t1 = g(85), t2 = g(102) },
        crimson = { bg = g(85), ink = g(255), second = g(187), text = g(255), inner = g(34), t1 = g(102), t2 = g(119) },
        peach = { bg = g(238), ink = g(0), second = g(119), text = g(0), inner = g(255), t1 = g(221), t2 = g(204) },
        lemon = { bg = g(238), ink = g(0), second = g(119), text = g(0), inner = g(255), t1 = g(221), t2 = g(204) },
        pink = { bg = g(187), ink = g(0), second = g(102), text = g(0), inner = g(255), t1 = g(204), t2 = g(221) },
        orange = { bg = g(221), ink = g(0), second = g(136), text = g(0), inner = g(255), t1 = g(204), t2 = g(187) },
        sky = { bg = g(221), ink = g(0), second = g(119), text = g(0), inner = g(255), t1 = g(204), t2 = g(238) },
        mint = { bg = g(238), ink = g(0), second = g(119), text = g(0), inner = g(255), t1 = g(221), t2 = g(204) },
        lilac = { bg = g(221), ink = g(0), second = g(119), text = g(0), inner = g(255), t1 = g(204), t2 = g(187) },
        p_marathoner = { bg = g(51), ink = g(0), second = g(136), text = g(255), inner = g(255), t1 = g(85), t2 = g(204) },
        p_owl = { bg = g(34), ink = g(0), second = g(136), text = g(255), inner = g(255), t1 = g(68), t2 = g(221) },
        p_bird = { bg = g(102), ink = g(0), second = g(136), text = g(255), inner = g(255), t1 = g(119), t2 = g(204) },
        p_steady = { bg = g(51), ink = g(0), second = g(136), text = g(255), inner = g(255), t1 = g(68), t2 = g(204) },
        p_loyal = { bg = g(68), ink = g(0), second = g(136), text = g(255), inner = g(255), t1 = g(85), t2 = g(119) },
        p_weekend = { bg = g(85), ink = g(0), second = g(136), text = g(255), inner = g(255), t1 = g(102), t2 = g(204) },
        p_explorer = { bg = g(51), ink = g(0), second = g(136), text = g(255), inner = g(255), t1 = g(68), t2 = g(204) },
        p_curious = { bg = g(68), ink = g(0), second = g(136), text = g(255), inner = g(255), t1 = g(85), t2 = g(204) },
    },
    hours = {
        dawn = { bg = g(34), text = g(255), bar = g(170), best = g(255), ring = g(255), star = g(221), moon = g(255), cloud = g(51) },
        morning = { bg = g(238), text = g(0), bar = g(102), best = g(0), ring = g(0), cloud = g(255), sun = g(68), ray = g(119), cloud2 = g(204) },
        afternoon = { bg = g(204), text = g(0), bar = g(85), best = g(0), ring = g(0), cloud = g(255), sun = g(51), ray = g(85), cloud2 = g(187) },
        night = { bg = g(0), text = g(255), bar = g(170), best = g(255), ring = g(255), star = g(221), moon = g(255), cloud = g(51) },
    },
}

Themes.eink = {
    name = "eink",
    rgb = true,
    spines = { { 27, 20, 100 }, { 0, 120, 130 }, { 190, 24, 110 }, { 232, 120, 20 }, { 92, 40, 170 }, { 216, 50, 60 } },
    band = { 255, 225, 150 },
    covers = {
        { { 27, 20, 100 }, { 245, 200, 90 } },
        { { 150, 20, 70 }, { 255, 225, 170 } },
        { { 0, 105, 110 }, { 250, 235, 190 } },
        { { 90, 40, 170 }, { 250, 205, 120 } },
        { { 200, 60, 40 }, { 255, 235, 190 } },
    },
    families = {
        indigo = { bg = { 70, 50, 190 }, ink = { 255, 105, 140 }, second = { 255, 190, 0 }, text = { 255, 255, 255 }, inner = { 255, 255, 255 }, t1 = { 86, 68, 208 }, t2 = { 102, 86, 222 } },
        midnight = { bg = { 45, 40, 190 }, ink = { 45, 40, 190 }, second = { 255, 190, 0 }, text = { 255, 255, 255 }, inner = { 255, 255, 255 }, t1 = { 70, 70, 225 }, t2 = { 255, 235, 120 } },
        navy = { bg = { 20, 70, 200 }, ink = { 20, 70, 200 }, second = { 255, 190, 0 }, text = { 255, 255, 255 }, inner = { 255, 255, 255 }, t1 = { 45, 95, 225 }, t2 = { 255, 235, 120 } },
        pine = { bg = { 0, 130, 120 }, ink = { 0, 130, 120 }, second = { 255, 190, 0 }, text = { 255, 255, 255 }, inner = { 255, 255, 255 }, t1 = { 0, 152, 140 }, t2 = { 255, 235, 120 } },
        ember = { bg = { 170, 30, 100 }, ink = { 170, 30, 100 }, second = { 255, 190, 0 }, text = { 255, 255, 255 }, inner = { 255, 255, 255 }, t1 = { 195, 50, 120 }, t2 = { 255, 225, 130 } },
        teal = { bg = { 40, 205, 190 }, ink = { 5, 45, 90 }, second = { 240, 80, 30 }, text = { 5, 45, 90 }, inner = { 255, 255, 255 }, t1 = { 0, 180, 170 }, t2 = { 90, 225, 210 } },
        violet = { bg = { 165, 120, 255 }, ink = { 40, 5, 120 }, second = { 255, 110, 0 }, text = { 40, 5, 120 }, inner = { 255, 255, 255 }, t1 = { 145, 95, 250 }, t2 = { 190, 155, 255 } },
        crimson = { bg = { 255, 105, 100 }, ink = { 70, 0, 40 }, second = { 255, 225, 90 }, text = { 70, 0, 40 }, inner = { 255, 255, 255 }, t1 = { 255, 85, 85 }, t2 = { 255, 130, 120 } },
        peach = { bg = { 255, 170, 110 }, ink = { 25, 20, 120 }, second = { 225, 40, 40 }, text = { 25, 20, 120 }, inner = { 255, 255, 255 }, t1 = { 255, 145, 80 }, t2 = { 255, 125, 60 } },
        lemon = { bg = { 255, 225, 0 }, ink = { 90, 10, 170 }, second = { 235, 20, 90 }, text = { 70, 10, 130 }, inner = { 255, 255, 255 }, t1 = { 255, 195, 0 }, t2 = { 255, 170, 0 } },
        pink = { bg = { 255, 80, 165 }, ink = { 70, 0, 90 }, second = { 255, 200, 0 }, text = { 70, 0, 90 }, inner = { 255, 255, 255 }, t1 = { 255, 110, 185 }, t2 = { 255, 140, 200 } },
        orange = { bg = { 255, 140, 0 }, ink = { 70, 10, 150 }, second = { 255, 235, 90 }, text = { 60, 10, 130 }, inner = { 255, 255, 255 }, t1 = { 255, 165, 30 }, t2 = { 255, 195, 70 } },
        sky = { bg = { 90, 200, 255 }, ink = { 5, 35, 90 }, second = { 240, 90, 0 }, text = { 5, 35, 90 }, inner = { 255, 255, 255 }, t1 = { 60, 180, 245 }, t2 = { 150, 220, 255 } },
        mint = { bg = { 60, 225, 165 }, ink = { 0, 60, 70 }, second = { 240, 60, 40 }, text = { 0, 60, 70 }, inner = { 255, 255, 255 }, t1 = { 30, 205, 145 }, t2 = { 100, 235, 185 } },
        lilac = { bg = { 190, 150, 255 }, ink = { 45, 5, 120 }, second = { 255, 110, 0 }, text = { 45, 5, 120 }, inner = { 255, 255, 255 }, t1 = { 170, 125, 250 }, t2 = { 205, 175, 255 } },
        p_marathoner = { bg = { 0, 185, 170 }, ink = { 5, 45, 90 }, second = { 255, 190, 0 }, text = { 5, 35, 70 }, inner = { 255, 255, 255 }, t1 = { 0, 155, 150 }, t2 = { 255, 190, 0 } },
        p_owl = { bg = { 110, 60, 235 }, ink = { 40, 10, 120 }, second = { 255, 190, 0 }, text = { 255, 255, 255 }, inner = { 255, 255, 255 }, t1 = { 135, 90, 250 }, t2 = { 255, 235, 120 } },
        p_bird = { bg = { 255, 140, 0 }, ink = { 90, 20, 40 }, second = { 255, 235, 90 }, text = { 70, 15, 30 }, inner = { 255, 255, 255 }, t1 = { 255, 165, 30 }, t2 = { 255, 235, 90 } },
        p_steady = { bg = { 0, 190, 130 }, ink = { 0, 50, 50 }, second = { 255, 190, 0 }, text = { 0, 50, 45 }, inner = { 255, 255, 255 }, t1 = { 0, 165, 115 }, t2 = { 255, 190, 0 } },
        p_loyal = { bg = { 255, 80, 160 }, ink = { 70, 0, 60 }, second = { 255, 200, 0 }, text = { 70, 0, 60 }, inner = { 255, 255, 255 }, t1 = { 255, 110, 180 }, t2 = { 255, 145, 200 } },
        p_weekend = { bg = { 60, 170, 255 }, ink = { 5, 30, 80 }, second = { 255, 170, 0 }, text = { 5, 30, 80 }, inner = { 255, 255, 255 }, t1 = { 35, 150, 245 }, t2 = { 255, 235, 120 } },
        p_explorer = { bg = { 0, 210, 190 }, ink = { 0, 50, 60 }, second = { 255, 190, 0 }, text = { 0, 50, 60 }, inner = { 255, 255, 255 }, t1 = { 0, 185, 170 }, t2 = { 255, 235, 120 } },
        p_curious = { bg = { 255, 90, 80 }, ink = { 70, 0, 30 }, second = { 255, 215, 0 }, text = { 70, 0, 30 }, inner = { 255, 255, 255 }, t1 = { 255, 115, 105 }, t2 = { 255, 215, 0 } },
    },
    hours = {
        dawn = { bg = { 90, 50, 200 }, text = { 255, 255, 255 }, bar = { 200, 170, 255 }, best = { 255, 255, 255 }, ring = { 255, 255, 255 }, star = { 255, 255, 255 }, moon = { 240, 235, 255 }, cloud = { 115, 80, 220 } },
        morning = { bg = { 90, 200, 255 }, text = { 5, 35, 90 }, bar = { 240, 90, 0 }, best = { 5, 35, 90 }, ring = { 5, 35, 90 }, cloud = { 255, 255, 255 }, sun = { 255, 160, 0 }, ray = { 255, 190, 0 }, cloud2 = { 150, 220, 255 } },
        afternoon = { bg = { 18, 118, 215 }, text = { 255, 255, 255 }, bar = { 255, 215, 0 }, best = { 255, 255, 255 }, ring = { 255, 255, 255 }, cloud = { 255, 255, 255 }, sun = { 255, 225, 0 }, ray = { 255, 235, 90 }, cloud2 = { 60, 165, 250 } },
        night = { bg = { 45, 40, 190 }, text = { 255, 255, 255 }, bar = { 255, 190, 0 }, best = { 255, 255, 255 }, ring = { 255, 255, 255 }, star = { 255, 235, 120 }, moon = { 255, 240, 150 }, cloud = { 70, 70, 225 } },
    },
}

Themes.vibrant = {
    name = "vibrant",
    rgb = true,
    spines = { { 27, 20, 100 }, { 0, 120, 130 }, { 190, 24, 110 }, { 232, 120, 20 }, { 92, 40, 170 }, { 216, 50, 60 } },
    band = { 255, 225, 150 },
    covers = {
        { { 27, 20, 100 }, { 245, 200, 90 } },
        { { 150, 20, 70 }, { 255, 225, 170 } },
        { { 0, 105, 110 }, { 250, 235, 190 } },
        { { 90, 40, 170 }, { 250, 205, 120 } },
        { { 200, 60, 40 }, { 255, 235, 190 } },
    },
    families = {
        indigo = { bg = { 36, 26, 120 }, ink = { 255, 92, 120 }, second = { 255, 196, 61 }, text = { 255, 243, 214 }, inner = { 255, 243, 214 }, t1 = { 48, 36, 150 }, t2 = { 64, 50, 180 } },
        midnight = { bg = { 18, 16, 64 }, ink = { 18, 16, 64 }, second = { 255, 183, 77 }, text = { 255, 243, 214 }, inner = { 255, 243, 214 }, t1 = { 30, 26, 92 }, t2 = { 255, 220, 150 } },
        navy = { bg = { 10, 30, 90 }, ink = { 10, 30, 90 }, second = { 255, 190, 70 }, text = { 255, 255, 255 }, inner = { 235, 245, 255 }, t1 = { 20, 46, 118 }, t2 = { 255, 235, 190 } },
        pine = { bg = { 8, 60, 60 }, ink = { 8, 60, 60 }, second = { 255, 205, 90 }, text = { 255, 255, 255 }, inner = { 250, 245, 215 }, t1 = { 14, 82, 78 }, t2 = { 255, 225, 160 } },
        ember = { bg = { 70, 15, 50 }, ink = { 70, 15, 50 }, second = { 255, 160, 40 }, text = { 255, 243, 214 }, inner = { 255, 243, 214 }, t1 = { 95, 25, 65 }, t2 = { 255, 200, 120 } },
        teal = { bg = { 8, 112, 122 }, ink = { 255, 243, 214 }, second = { 255, 200, 87 }, text = { 255, 243, 214 }, inner = { 255, 243, 214 }, t1 = { 14, 130, 140 }, t2 = { 24, 150, 158 } },
        violet = { bg = { 110, 62, 235 }, ink = { 255, 243, 214 }, second = { 255, 196, 61 }, text = { 255, 243, 214 }, inner = { 60, 20, 140 }, t1 = { 126, 82, 245 }, t2 = { 146, 106, 250 } },
        crimson = { bg = { 205, 50, 65 }, ink = { 255, 243, 214 }, second = { 255, 205, 90 }, text = { 255, 243, 214 }, inner = { 90, 10, 40 }, t1 = { 222, 70, 85 }, t2 = { 235, 95, 100 } },
        peach = { bg = { 255, 214, 186 }, ink = { 36, 26, 120 }, second = { 240, 84, 60 }, text = { 36, 26, 120 }, inner = { 255, 250, 240 }, t1 = { 255, 198, 162 }, t2 = { 255, 180, 142 } },
        lemon = { bg = { 255, 209, 63 }, ink = { 74, 20, 140 }, second = { 233, 30, 99 }, text = { 74, 20, 140 }, inner = { 255, 250, 225 }, t1 = { 255, 194, 25 }, t2 = { 255, 178, 0 } },
        pink = { bg = { 240, 60, 130 }, ink = { 48, 0, 58 }, second = { 255, 196, 61 }, text = { 48, 0, 58 }, inner = { 255, 243, 225 }, t1 = { 250, 84, 150 }, t2 = { 255, 112, 170 } },
        orange = { bg = { 255, 150, 40 }, ink = { 60, 10, 130 }, second = { 255, 235, 150 }, text = { 60, 10, 130 }, inner = { 255, 245, 205 }, t1 = { 255, 172, 74 }, t2 = { 255, 194, 110 } },
        sky = { bg = { 150, 216, 245 }, ink = { 16, 44, 92 }, second = { 240, 90, 40 }, text = { 16, 44, 92 }, inner = { 255, 250, 240 }, t1 = { 125, 200, 240 }, t2 = { 190, 232, 250 } },
        mint = { bg = { 170, 240, 205 }, ink = { 5, 70, 75 }, second = { 255, 90, 80 }, text = { 5, 70, 75 }, inner = { 255, 255, 245 }, t1 = { 140, 228, 190 }, t2 = { 115, 215, 175 } },
        lilac = { bg = { 215, 195, 255 }, ink = { 60, 15, 120 }, second = { 255, 120, 40 }, text = { 60, 15, 120 }, inner = { 255, 250, 255 }, t1 = { 198, 172, 250 }, t2 = { 180, 150, 245 } },
        p_marathoner = { bg = { 8, 100, 110 }, ink = { 8, 40, 70 }, second = { 255, 200, 60 }, text = { 255, 255, 255 }, inner = { 255, 243, 214 }, t1 = { 14, 120, 130 }, t2 = { 255, 200, 60 } },
        p_owl = { bg = { 60, 20, 130 }, ink = { 30, 10, 75 }, second = { 255, 190, 70 }, text = { 255, 255, 255 }, inner = { 255, 243, 214 }, t1 = { 82, 38, 160 }, t2 = { 255, 225, 160 } },
        p_bird = { bg = { 240, 120, 30 }, ink = { 90, 20, 40 }, second = { 255, 225, 120 }, text = { 70, 15, 30 }, inner = { 255, 245, 220 }, t1 = { 250, 142, 58 }, t2 = { 255, 225, 120 } },
        p_steady = { bg = { 15, 125, 90 }, ink = { 5, 50, 50 }, second = { 255, 205, 90 }, text = { 255, 255, 255 }, inner = { 250, 245, 215 }, t1 = { 26, 145, 106 }, t2 = { 255, 205, 90 } },
        p_loyal = { bg = { 210, 40, 115 }, ink = { 70, 10, 65 }, second = { 255, 210, 110 }, text = { 255, 255, 255 }, inner = { 255, 240, 235 }, t1 = { 230, 65, 135 }, t2 = { 255, 150, 190 } },
        p_weekend = { bg = { 20, 120, 200 }, ink = { 8, 36, 90 }, second = { 255, 170, 80 }, text = { 255, 255, 255 }, inner = { 235, 245, 255 }, t1 = { 45, 140, 215 }, t2 = { 255, 225, 120 } },
        p_explorer = { bg = { 8, 128, 120 }, ink = { 5, 60, 75 }, second = { 255, 215, 110 }, text = { 255, 255, 255 }, inner = { 235, 255, 245 }, t1 = { 26, 170, 156 }, t2 = { 255, 215, 110 } },
        p_curious = { bg = { 200, 60, 60 }, ink = { 60, 12, 50 }, second = { 255, 205, 90 }, text = { 255, 255, 255 }, inner = { 255, 240, 220 }, t1 = { 218, 80, 75 }, t2 = { 255, 205, 90 } },
    },
    hours = {
        dawn = { bg = { 44, 22, 110 }, text = { 255, 255, 255 }, bar = { 190, 160, 255 }, best = { 255, 255, 255 }, ring = { 255, 255, 255 }, star = { 255, 255, 255 }, moon = { 240, 235, 255 }, cloud = { 62, 36, 134 } },
        morning = { bg = { 150, 216, 245 }, text = { 16, 44, 92 }, bar = { 240, 120, 40 }, best = { 16, 44, 92 }, ring = { 16, 44, 92 }, cloud = { 255, 255, 255 }, sun = { 255, 170, 40 }, ray = { 255, 200, 90 }, cloud2 = { 190, 232, 250 } },
        afternoon = { bg = { 24, 112, 205 }, text = { 255, 255, 255 }, bar = { 255, 205, 60 }, best = { 255, 255, 255 }, ring = { 255, 255, 255 }, cloud = { 255, 255, 255 }, sun = { 255, 215, 70 }, ray = { 255, 235, 150 }, cloud2 = { 60, 150, 235 } },
        night = { bg = { 20, 18, 84 }, text = { 255, 255, 255 }, bar = { 255, 190, 60 }, best = { 255, 255, 255 }, ring = { 255, 255, 255 }, star = { 255, 240, 190 }, moon = { 255, 245, 215 }, cloud = { 36, 32, 118 } },
    },
}

Themes.cards = {
    cover = { family = "indigo", scene = "books" },
    time = { family = "midnight", scene = "midnight" },
    pages = { family = "teal", scene = "pages" },
    books = { family = "peach", scene = "circles" },
    timeline = { family = "mint", scene = "circles" },
    devoured = { family = "crimson", scene = "pulse" },
    author = { family = "lilac", scene = "circles" },
    streak = { family = "lemon", scene = "bands" },
    best_day = { family = "sky", scene = "dotted" },
    session = { family = "pink", scene = "session" },
    weekdays = { family = "mint", scene = "bands" },
    months = { family = "orange", scene = "hills" },
    speed = { family = "violet", scene = "streaks" },
    previous = { family = "sky", scene = "pages" },
    summary = { family = "lemon", scene = "dotted" },
    about = { family = "lilac", scene = "circles" },
    profile_night_owl = { family = "p_owl", scene = "owl" },
    profile_early_bird = { family = "p_bird", scene = "rays" },
    profile_steady = { family = "p_steady", scene = "bands_plain" },
    profile_marathoner = { family = "p_marathoner", scene = "dashes" },
    profile_loyal = { family = "p_loyal", scene = "hearts" },
    profile_weekender = { family = "p_weekend", scene = "sunny" },
    profile_explorer = { family = "p_explorer", scene = "compass" },
    profile_curious = { family = "p_curious", scene = "lens" },
    almost_there = { family = "peach", scene = "hills" },
    back_after_years = { family = "navy", scene = "drift" },
    book_waited = { family = "lilac", scene = "pages" },
    bookends = { family = "sky", scene = "circles" },
    comeback = { family = "mint", scene = "hills" },
    extremes = { family = "orange", scene = "circles" },
    juggler = { family = "pink", scene = "spin" },
    memorable_day = { family = "lemon", scene = "pulse" },
    most_marked = { family = "lilac", scene = "pages" },
    one_sitting = { family = "pine", scene = "drift" },
    pace_change = { family = "sky", scene = "streaks" },
    past_midnight = { family = "midnight", scene = "drift" },
    reread = { family = "mint", scene = "spin" },
    ritual = { family = "peach", scene = "pulse" },
    series_run = { family = "lilac", scene = "books" },
    slow_burn = { family = "ember", scene = "sparks" },
    waves = { family = "sky", scene = "waves" },
}

local FALLBACK = { family = "peach", scene = "circles" }

function Themes.period(hour)
    if hour < 5 then return "dawn" end
    if hour < 12 then return "morning" end
    if hour < 18 then return "afternoon" end
    return "night"
end

function Themes.device_theme(screen)
    return screen:isColorEnabled() and "eink" or "gray"
end

local function card_key(card)
    return card.id == "archetype" and card.art or card.id
end

function Themes.palette(theme, card)
    if card.id == "hours" then
        local h = theme.hours[Themes.period(card.best_hour)]
        local midnight = theme.families.midnight
        return { bg = h.bg, ink = midnight.ink, second = midnight.second, text = h.text, inner = midnight.inner }
    end
    return theme.families[(Themes.cards[card_key(card)] or FALLBACK).family]
end

function Themes.layers(theme, card)
    local Scenes = require("book_rewind/ui/scenes")
    if card.id == "hours" then
        local period = Themes.period(card.best_hour)
        return Scenes.hours(period, theme.hours[period])
    end
    return Scenes.card((Themes.cards[card_key(card)] or FALLBACK).scene, Themes.palette(theme, card))
end

return Themes
