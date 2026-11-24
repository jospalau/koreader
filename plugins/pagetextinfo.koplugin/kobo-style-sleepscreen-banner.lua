--[[ 2-kobo-style-sleepscreen-banner.lua ]]
--redesigns the inbuilt 'banner' type sleep screen message to
--make it look like the kobo lockscreen tag.

--[ v2.2.0 ]
--the banner no longer depends on the inbuilt sleep screen message being enabled.
--new menu items under Settings > Screen > Sleep screen > Wallpaper:
--  'Kobo style sleep screen'  : on/off. when on, the banner is always drawn on top of the
--                               wallpaper (cover / random image / document cover), whether
--                               or not the inbuilt sleep screen message is enabled.
--  'Kobo style banner position': % of the screen height, measured from the bottom.
--the values in BANNER SETTINGS below are only the defaults of these two menu settings.

--[ v2.1.0 ]
--bookshelf integration: when bookshelf.koplugin is installed, the title line of the
--banner is replaced by bookshelf's own top panel (the "currently reading" card:
--cover, title, author, progress...), rendered with bookshelf's own code and settings.
--without bookshelf (or if the panel cannot be built) the banner is exactly as before.

--[ v2.0.2 ]
--crash guard when uiman:show() called w/o widget

--CREDITS
--this version was written in collab with discord user @sandcastles.
--i've also borrowed some design cues from a similar patch written by reddit user u/juancoquet.

local B_SETT = {	--BANNER SETTINGS
					kobo_style_sleepscreen = true,	-- default of the menu toggle 'Kobo style sleep screen'. true = banner
										-- always drawn on the sleep screen, whether or not the inbuilt sleep
										-- screen message is enabled. false = patch does nothing.
					vertical_position = 50,	-- default of the menu setting 'Kobo style banner position': % of the
										-- screen height measured from the bottom (0 = bottom, 100 = top).
					stats_text_fallback = "page %c of %t",	-- stats line text, only used when the inbuilt sleep
										-- screen message is not in use. same tokens as title_text.
										-- "" = no stats line.
					title_text = "%T", 	--configure title_text like you'd configure the inbuilt
										--sleep screen message. for eg, "%T" shows book title,
										--"page %c of %t" shows 'page 1 of 400' etc.
					title_fontFace = "cfont",
					title_fontSize = 30,
					stats_fontFace = "cfont",
					stats_fontSize = 17,
					border_size = 1,
					border_color = 1,	-- 0 = white, 1 = black
					background = 0,		-- 0 = white, 1 = black
					margin = 10,
					padding = 15,
					max_height = 50,		-- percentage of screen height
					max_width_hl_off = 40,	-- width when highlight off, min: 20
					max_width_hl_on = 60,  	-- width when highlight on, min: 20
}
local PANEL_SETT = {	--BOOKSHELF TOP PANEL SETTINGS
					enabled = true,		-- false = always the plain banner
					only_in_reader = false,	-- true = only when a book is open (not in the file manager / shelf)
					width_pct = 60,		-- banner width (% of screen) when the panel is shown
					height_pct = 12,	-- panel height (% of screen height)
					hide_regions = { "status", "rating", "metadata", "description", "tags" },	-- regions of bookshelf's card to hide in the banner, e.g.
										-- { "status", "description", "tags" }
										-- options: status (time / battery / wifi / light),
										-- rating, title, author, metadata (series),
										-- description, tags
										-- (only changes the banner, not your shelf settings)
					show_progress = true,	-- force the progress bar region on
					keep_stats = false,	-- true = also show the original banner lines below the
										-- panel (page x of y, read today, ΔL...)
					show_highlight = false,	-- true = also show the random highlight below the panel
}
local HL_SETT = {	--HIGHLIGHT SETTINGS
					showRandomHighlight = true,
					highlight_fontFace = "NotoSerif-Italic.ttf",
					highlight_fontSize = 16,
					justify = true,
					add_quotations = true,
					show_accent_line = true,
					showHighlightFooter = true,
					hl_footer_fontFace = "NotoSerif-Regular.ttf",
					hl_footer_fontSize = 15,
					hl_footer_text = "saved on %DT at %HM",
										-- %DT = date,
										-- %HM = time,
										-- %PG = page,
										-- %C = chapter,
										-- %A = author,
										-- %T = title,
										-- \n = line break

					allowed_hl_styles = { 	-- only 'true' styles will be shown
									lighten = true,
									underscore = true,
									strikethrough = false,
									invert = false,
					}
}

local Bb = require("ffi/blitbuffer")
local _ = require("gettext")
local BookInfo = require("apps/filemanager/filemanagerbookinfo")
local BookList = require("ui/widget/booklist")
local CenterContainer = require("ui/widget/container/centercontainer")
local datetime = require("datetime")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local logger = require("logger")
local OverlapGroup = require("ui/widget/overlapgroup")
local Screen = Device.screen
local Size = require("ui/size")
local SpinWidget = require("ui/widget/spinwidget")
local T = require("ffi/util").template
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local util = require("util")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
local cached_random_highlight_index  = 1
local Sidecar

-- Current values of the two menu settings. The menu (Sleep screen > Wallpaper) saves them in
-- G_reader_settings; until the user touches them the defaults from B_SETT apply.
local function isKoboStyleOn()
	local saved = G_reader_settings:readSetting("kobo_style_sleepscreen")
	if saved == nil then
		return B_SETT.kobo_style_sleepscreen and true or false
	end
	return saved and true or false
end

-- banner position, % of the screen height measured from the bottom
local function getBannerPosition()
	local saved = tonumber(G_reader_settings:readSetting("kobo_style_sleepscreen_position"))
	return math.min(math.max(saved or tonumber(B_SETT.vertical_position) or 50, 0), 100)
end

-- Expands tokens like "%T" / "%c" / "%t" the same way the inbuilt sleep screen message does.
local function expandTokens(ui, text, file)
	if ui and ui.document and ui.toc and ui.bookinfo then
		return ui.bookinfo:expandString(text, file) or "N/A"
	end
	return BookInfo:expandString(text, file) or "N/A"
end

local function buildTextField(
								text,
								font_face,
								max_height,
								max_wid,
								ignoreLineBreaks,
								isHighlight,
								text_color
							)
	local wgt_grp = VerticalGroup:new{align = "left"}
	text = text:gsub("\\n", "\n")
	local segments = ignoreLineBreaks and {text} or util.splitToArray(text, "\n")
	for idx, item in ipairs(segments) do
		local wgt = TextWidget:new{
						padding = 0,
						text = item,
						face = font_face,
						alignment = "left",
						fgcolor = text_color and text_color or
									B_SETT.background == 1 and Bb.COLOR_WHITE or
									Bb.COLOR_BLACK,
						bgcolor = B_SETT.background == 0 and Bb.COLOR_WHITE or
									Bb.COLOR_BLACK,
		}
		if wgt:getSize().w > max_wid then
			wgt:free()
			wgt = TextBoxWidget:new{
						text = item,
						face = font_face,
						width = max_wid,
						alignment = "left",
						height = max_height,
						height_adjust = true,
						height_overflow_show_ellipsis = true,
						justified = isHighlight and HL_SETT.justify,
						fgcolor = text_color and text_color or
									B_SETT.background == 1 and Bb.COLOR_WHITE or
									Bb.COLOR_BLACK,
						bgcolor = B_SETT.background == 0 and Bb.COLOR_WHITE or
									Bb.COLOR_BLACK,
			}
		end
		table.insert(wgt_grp, wgt)
	end
	return wgt_grp
end

local function addQuotesIfReq(text)
	if not text or text == "" then
		return text
	end
	local chars = util.splitToChars(text)
	local first_char = chars[1]
	local last_char = chars[#chars]
	local control = { {"'", "'"}, {"\"", "\""}, {"“", "”"},
						{"‘", "’"}, {"«", "»"}, {"„", "“"} }
	local quotesFound = false
	for _, quotes in ipairs(control) do
		if first_char == quotes[1] and last_char == quotes[2] then
			quotesFound = true
			break
		end
	end
	if not quotesFound then
		return "“" .. text .. "”"
	end
	return text
end

local function parseFooterText(hl_array, text, index)
	if not text or not index or text == "" then
		return text, index
	end

	local hl_time, hl_date, hl_chapter = "", "", ""
	local hl_pageno, bk_author, bk_title = 0, "", ""

    -- local hl_array = Sidecar and Sidecar:readSetting("annotations")
	hl_array = hl_array and hl_array[index] or {}
	hl_chapter = hl_array.chapter or "N/A"
	hl_pageno = Sidecar:isTrue("pagemap_use_page_labels") and hl_array.pageref or
				hl_array.pageno or "N/A"

	local doc_props = Sidecar and Sidecar:readSetting("doc_props") or {}
	bk_author = doc_props.authors or "N/A"
	bk_title = doc_props.title or "N/A"

	--date and time
	local yr, mth, dy
	local date_and_time = hl_array.datetime and
							util.splitToArray(hl_array.datetime, "%s+", false) or {}

	hl_date = date_and_time and date_and_time[1] or ""
	yr, mth, dy = hl_date:match("(%d+)-(%d+)-(%d+)")
	local month_abbr = yr and mth and dy and
						os.date("%b", os.time{year=yr, month=mth, day=dy}) or ""
	local short_month = datetime.shortMonthTranslation[month_abbr]  or ""
	hl_date = yr and mth and dy and short_month and
				string.format("%s %s '%02d", dy, short_month, tonumber(yr) % 100) or "N/A"

	local timesplit = date_and_time and date_and_time[2] and
					  util.splitToArray(date_and_time[2], ":") or {}
	hl_time = timesplit and timesplit[1] and timesplit[2] and
			  timesplit[1]..":"..timesplit[2] or "N/A"

	local sub_table = {
		["%%HM"] = hl_time,
		["%%DT"] = hl_date,
		["%%PG"] = hl_pageno,
		["%%C"] = hl_chapter,
		["%%A"] = bk_author,
		["%%T"] = bk_title
	}
	for pattern, replacement in pairs(sub_table) do
		if replacement then
			text = string.gsub(text, pattern, replacement)
		end
	end
	return text
end

-- Progress line in bookshelf's own style: "42%   [bar]   2h left".
-- The bar is bookshelf's own widget (lib/bookshelf_hero_bar), with the bar style and
-- colours chosen in bookshelf's settings.
local function buildProgressRow(width, pct, book, device_state, progress_cfg)
	local HeroBar = require("lib/bookshelf_hero_bar")
	local fg = B_SETT.background == 1 and Bb.COLOR_WHITE or Bb.COLOR_BLACK
	local bg = B_SETT.background == 0 and Bb.COLOR_WHITE or Bb.COLOR_BLACK
	local face = Font:getFace(B_SETT.stats_fontFace, B_SETT.stats_fontSize) or Font:getFace("cfont", 17)
	local gap = Screen:scaleBySize(8)

	local pct_widget = TextWidget:new{
		text = string.format("%d%%", math.floor(math.max(0, math.min(1, pct)) * 100 + 0.5)),
		face = face, bold = false, padding = 0, fgcolor = fg, bgcolor = bg,
	}

	-- time left, as bookshelf words it (empty when unknown)
	local left_text = ""
	pcall(function()
		local Tokens = require("lib/bookshelf_tokens")
		left_text = util.trim(tostring(Tokens.expand("%book_time_left", book, device_state) or ""))
	end)
	local left_widget
	if left_text ~= "" then
		left_widget = TextWidget:new{
			text = left_text, face = face, padding = 0, fgcolor = fg, bgcolor = bg,
		}
	end

	local used = pct_widget:getSize().w + gap * 2 + (left_widget and left_widget:getSize().w or 0)
	local bar_colors
	if progress_cfg.bar_style ~= "pacman" then
		local ok_cp, CP = pcall(require, "lib/bookshelf_cover_progress")
		if ok_cp and CP and CP.pickedBarColors then
			bar_colors = CP.pickedBarColors()
		end
	end
	local bar = HeroBar:new{
		width = math.max(10, width - used),
		height = Screen:scaleBySize(8),
		percentage = pct,
		style = progress_cfg.bar_style or "bordered",
		colors = bar_colors,
	}

	local row = HorizontalGroup:new{align = "center", pct_widget, HorizontalSpan:new{width = gap}, bar}
	if left_widget then
		table.insert(row, HorizontalSpan:new{width = gap})
		table.insert(row, left_widget)
	end
	return row
end

-- Builds bookshelf's top panel (the "currently reading" hero card) for the book
-- that is open / was read last. Returns the widget, or nil when bookshelf is not
-- installed or anything fails (the caller then falls back to the plain banner).
local function buildBookshelfPanel(width, height)
	local ok, card = pcall(function()
		local HeroCard = require("lib/bookshelf_hero_card")
		local Repo = require("lib/bookshelf_book_repository")
		local Space = require("lib/bookshelf_space")
		local BookshelfWidget = require("lib/bookshelf_widget")

		-- The card reads progress (%) from the book's saved data on disk. While reading,
		-- that is not always written yet, and bookshelf drops the progress bar for a book
		-- with no saved progress. So save the open book first, and clear the caches.
		local rui = require("apps/reader/readerui").instance
		if rui and rui.document then
			pcall(function() rui:saveSettings() end)
			local file = rui.document.file
			if Repo.invalidateProgressCache then pcall(Repo.invalidateProgressCache, file) end
			if Repo.invalidateStatsCache then pcall(Repo.invalidateStatsCache, file) end
		end

		local book = Repo.getCurrent()
		if not book then
			return nil
		end
		-- still nothing on disk: take the live value of the open book
		if not book.book_pct and rui and rui.doc_settings then
			book.book_pct = rui.doc_settings:readSetting("percent_finished")
		end
		if Repo.enrichStats then
			Repo.enrichStats(book)
		end
		-- clock / battery / wifi etc. (does not use the widget instance)
		local device_state = BookshelfWidget._buildDeviceState({})

		-- same proportions bookshelf uses: 2:3 cover, capped so the text column keeps room
		local pad = math.min(math.floor(Space.padding.fullscreen * 2 * 0.8),
								math.floor(screen_w * 0.03))
		local cover_h = math.max(1, height)
		local cover_w = math.max(1, math.floor(cover_h / 1.5))
		local max_cover_w = math.max(1, math.floor(width * 0.58))
		if cover_w > max_cover_w then
			cover_w = max_cover_w
			cover_h = math.max(1, math.floor(cover_w * 1.5))
		end

		-- Choose which regions of the card are drawn, for this build only: Regions.read()
		-- is swapped for a patched copy while the card is built and then restored,
		-- so the settings of the real shelf are never touched.
		local Regions = require("lib/bookshelf_hero_regions")
		local original_read = Regions.read
		local progress_cfg = original_read().progress or {}
		Regions.read = function(...)
			local base = original_read(...)
			local patched = {}
			for key, region in pairs(base) do
				patched[key] = region
			end
			local function withDisabled(key, disabled)
				if type(patched[key]) == "table" then
					local copy = {}
					for k, v in pairs(patched[key]) do copy[k] = v end
					copy.disabled = disabled
					patched[key] = copy
				end
			end
			for _, key in ipairs(PANEL_SETT.hide_regions or {}) do
				withDisabled(key, true)
			end
			-- the progress bar is drawn below the card by buildProgressRow (the card drops its
			-- own progress line when it is short), so switch the card's own one off
			if PANEL_SETT.show_progress then
				withDisabled("progress", true)
			end
			return patched
		end

		local ok_card, card_or_err = pcall(HeroCard.new, HeroCard, {
			book = book,
			has_wallpaper = false,
			width = width,
			height = height,
			cover_w = cover_w,
			cover_h = cover_h,
			pad = pad,
			device_state = device_state,
		})
		Regions.read = original_read	-- always restore
		if not ok_card then
			error(card_or_err)
		end
		if not PANEL_SETT.show_progress then
			return card_or_err
		end

		-- progress: saved value, else the live position in the open book
		local pct = tonumber(book.book_pct)
		if not pct and rui and rui.doc_settings then
			pct = tonumber(rui.doc_settings:readSetting("percent_finished"))
		end
		if not pct and rui and rui.document then
			local ok_pg, v = pcall(function()
				return rui.document:getCurrentPage() / rui.document:getPageCount()
			end)
			pct = ok_pg and v or nil
		end
		local row = buildProgressRow(width, pct or 0, book, device_state, progress_cfg)
		return VerticalGroup:new{
			align = "left",
			card_or_err,
			VerticalSpan:new{width = Screen:scaleBySize(6)},
			row,
		}
	end)
	if not ok then
		logger.warn("[banner-bookshelf] could not build the bookshelf panel:", card)
		return nil
	end
	return card
end

-- Draws the banner on top of the sleep screen wallpaper, at the left edge. If the inbuilt
-- sleep screen message is enabled (any container), it is dropped so it doesn't show twice.
local function attachBanner(ss_widget, banner, message_enabled)
	local main_frame = ss_widget[1]
	local base = main_frame and main_frame[1]
	if not base then
		return false
	end

	-- position = % of the free height, measured from the bottom (0 = bottom, 100 = top)
	local free_h = math.max(0, screen_h - banner:getSize().h)
	banner.overlap_offset = {0, math.floor(free_h * (100 - getBannerPosition()) / 100)}

	if message_enabled and #base >= 2 then
		-- inbuilt message layout: overlap group of {wallpaper, message}
		table.remove(base, 2)
		table.insert(base, banner)
	else
		main_frame[1] = OverlapGroup:new{
			dimen = Geom:new{w = screen_w, h = screen_h},
			CenterContainer:new{
				dimen = Geom:new{w = screen_w, h = screen_h},
				base,
			},
			banner,
		}
	end
	return true
end

local og_uiMan_show = UIManager.show

function UIManager:show(widget, ...)
	-- if widget isn't 'screensaver' or if wallpaper type
	-- isn't 'book cover' or 'custom image' or if sleep screen message type
	-- isn't 'banner', we do not intercept.

	if not widget or widget.name ~= "ScreenSaver" or not isKoboStyleOn() then
		return og_uiMan_show(self, widget, ...)
	end

	local screensaver_type = G_reader_settings:readSetting("screensaver_type")
	local message_container_enabled = G_reader_settings:isTrue("screensaver_show_message")
	local message_container_type = G_reader_settings:readSetting("screensaver_message_container")

	if screensaver_type ~= "cover" and
			screensaver_type ~= "random_image" and
			screensaver_type ~= "document_cover" then
		return og_uiMan_show(self, widget, ...)
	end

	local txtBoxWgtFound = message_container_enabled and
								message_container_type == "banner" and
								widget and
								widget[1] and  --screensaver wgt
								widget[1][1] and  -- overlap group
								widget[1][1][2] and --custom pos. container
								widget[1][1][2].widget and --textbox widget
								widget[1][1][2].widget.text
	-- txtBoxWgtFound: the inbuilt message is enabled with the 'banner' container, so its
	-- text is reused for the stats line. in any case the banner is built from scratch and
	-- placed by attachBanner() at the position set in the menu.
	--=================================

	local last_file = G_reader_settings:readSetting("lastfile")
	Sidecar = BookList.getDocSettings(last_file)
	self.ui = require("apps/reader/readerui").instance or
				require("apps/filemanager/filemanager").instance
	Sidecar:flush()

	--dimen roundup
	local dimen_ = {
			padding = B_SETT.padding and
						Screen:scaleBySize(B_SETT.padding) or
						Screen:scaleBySize(15),
			margin = B_SETT.margin and
						Screen:scaleBySize(B_SETT.margin) or
						Screen:scaleBySize(10),
			border_size = B_SETT.border_size and
						Screen:scaleBySize(B_SETT.border_size) or
						Screen:scaleBySize(1),
			line_width = Screen:scaleBySize(1),
			line_clearance = Size.padding.large,
			hl_wgt_clearance = Screen:scaleBySize(15),
			footer_clearance = Screen:scaleBySize(5),
	}

	local overflow_h = (dimen_.padding + dimen_.margin + dimen_.border_size) * 2 +
							dimen_.hl_wgt_clearance
	local overflow_w = (dimen_.padding + dimen_.margin + dimen_.border_size) * 2
	local overflow_w_hl = HL_SETT.show_accent_line and
							(overflow_w + dimen_.line_clearance + dimen_.line_width) or
							overflow_w

	--font roundup
	local font_ = {
		title_font = Font:getFace(
						B_SETT.title_fontFace,
						B_SETT.title_fontSize) or
						Font:getFace("cfont", 30),
		stats_font = Font:getFace(
						B_SETT.stats_fontFace,
						B_SETT.stats_fontSize) or
						Font:getFace("cfont", 17),
		footer_font = Font:getFace(
						HL_SETT.hl_footer_fontFace,
						HL_SETT.hl_footer_fontSize) or
						Font:getFace("NotoSerif-Regular.ttf", 15),
		highlight_font = Font:getFace(
						HL_SETT.highlight_fontFace,
						HL_SETT.highlight_fontSize) or
						Font:getFace("NotoSerif-Italic.ttf", 16)
	}

	--intercept the custom position container and child.

	local cus_pos_container, orig_sleep_widget, content_widget

	local orig_sleep_text
	if txtBoxWgtFound then
		cus_pos_container = widget[1][1][2]
		orig_sleep_widget = widget[1][1][2].widget
		orig_sleep_text = orig_sleep_widget.text
		orig_sleep_widget:free()
	else
		-- no inbuilt message: the stats line comes from 'stats_text_fallback'
		local fallback = B_SETT.stats_text_fallback
		orig_sleep_text = fallback and util.trim(fallback) ~= "" and
							expandTokens(self.ui, fallback, last_file) or ""
	end

	local highlightCount, highlightEnabled, highlights_list

	if HL_SETT.showRandomHighlight then
		local all_annotations = (self.ui.annotation and self.ui.annotation.annotations)
            or Sidecar:readSetting("annotations")
            or {}
		highlights_list = {}

		local allowed = HL_SETT.allowed_hl_styles

		for _, item in ipairs(all_annotations) do
			if item.text
			   and item.drawer
			   and allowed[item.drawer] then
				local trimmed = util.trim(item.text)
				if trimmed ~= "" then
					table.insert(highlights_list, item)
				end
			end
		end

		highlightCount = #highlights_list
		highlightEnabled = highlightCount > 0
	end

	local hl_footer_enabled = highlightEnabled and
								HL_SETT.showHighlightFooter and
								HL_SETT.hl_footer_text and
								util.trim(HL_SETT.hl_footer_text) ~= ""

	local max_wid
	if not highlightEnabled then
		max_wid = B_SETT.max_width_hl_off and
					B_SETT.max_width_hl_off >= 20 and
					B_SETT.max_width_hl_off <= 100 and
					(B_SETT.max_width_hl_off/100 * screen_w) or
					screen_w * 0.4
		max_wid = max_wid - overflow_w
	else
		max_wid = B_SETT.max_width_hl_on and
					B_SETT.max_width_hl_on >= 20 and
					B_SETT.max_width_hl_on <= 100 and
					(B_SETT.max_width_hl_on/100 * screen_w) or
					screen_w * 0.6
		max_wid = max_wid - overflow_w_hl
	end
	local max_height = B_SETT.max_height >= 20 and
						B_SETT.max_height <= 100 and
						(B_SETT.max_height/100 * screen_h) or
						screen_h * 0.5
	max_height = max_height - overflow_h

	--BOOKSHELF TOP PANEL (replaces the title line when bookshelf is installed)
	local panel_widget
	-- "reader mode" = a book is open AND it is what is on screen. With bookshelf's hot
	-- parking the book stays open (parked) underneath the shelf, so it must not count.
	local in_reader = self.ui and self.ui.document and true or false
	if in_reader then
		local ok_park, Park = pcall(require, "lib/bookshelf_reader_park")
		if ok_park and type(Park) == "table" and Park.isParked and Park.isParked() then
			in_reader = false
		end
	end
	if PANEL_SETT.enabled and (in_reader or not PANEL_SETT.only_in_reader) then
		local panel_overflow = highlightEnabled and overflow_w_hl or overflow_w
		local panel_max_wid = screen_w * math.min(math.max(PANEL_SETT.width_pct, 20), 100) / 100
								- panel_overflow
		local panel_h = math.min(
							math.floor(screen_h * math.min(math.max(PANEL_SETT.height_pct, 5), 100) / 100),
							math.floor(max_height))
		-- the highlight row is drawn wider than max_wid by its accent line:
		-- make the panel as wide as the widest row so the banner has no gap
		panel_widget = buildBookshelfPanel(
							math.floor(panel_max_wid + (panel_overflow - overflow_w)),
							panel_h)
		if panel_widget then
			max_wid = panel_max_wid
		end
	end

	--TITLE WIDGET
	local title_text

	if self.ui and self.ui.document and self.ui.toc and self.ui.bookinfo then
		title_text = self.ui and self.ui.bookinfo:expandString(B_SETT.title_text, last_file) or "N/A"
	else
		title_text = BookInfo:expandString(B_SETT.title_text, last_file) or "N/A"
	end

	local title_widget = panel_widget or buildTextField(
							title_text,
							font_.title_font,
							max_height,
							max_wid,
							true
	)
	local title_dimen = title_widget:getSize()

	--STATS WIDGET
	local stats_widget
	if (panel_widget and not PANEL_SETT.keep_stats) or orig_sleep_text == "" then
		stats_widget = VerticalSpan:new{width = 0}
	else
		stats_widget = buildTextField(
							orig_sleep_text,
							font_.stats_font,
							max_height - title_dimen.h,
							max_wid
		)
	end
	local stats_dimen = stats_widget:getSize()

	--HIGHLIGHTS WIDGET
	local highlight_widget

	if highlightEnabled then
		local random_highlight, random_highlight_index

		if highlightCount == 1 then
			random_highlight = highlights_list and highlights_list[1] and
								highlights_list[1].text or ""
			random_highlight_index = 1
		else
			random_highlight_index = math.random(highlightCount)

			--get a diff random highlight from prev time.
			while random_highlight_index == cached_random_highlight_index do
				random_highlight_index = math.random(highlightCount)
			end
			cached_random_highlight_index = random_highlight_index
			random_highlight = highlights_list[random_highlight_index] and
								highlights_list[random_highlight_index].text or ""
		end

		random_highlight = util.trim(random_highlight)
		random_highlight = HL_SETT.add_quotations and addQuotesIfReq(random_highlight) or
							random_highlight

		local hl_footer_widget
		local footer_color = B_SETT.background == 0 and
								Bb.COLOR_GRAY_4 or
								Bb.COLOR_GRAY_9

		if hl_footer_enabled then
			local hyphen_wid = buildTextField(
									"— ",
									font_.footer_font,
									max_height,
									max_wid,
									true,
									false,
									footer_color
			)
			hl_footer_widget = buildTextField(
									parseFooterText(highlights_list, HL_SETT.hl_footer_text , random_highlight_index),
									font_.footer_font,
									max_height - title_dimen.h - stats_dimen.h,
									max_wid - hyphen_wid:getSize().w,
									false,
									false,
									footer_color
			)
			hl_footer_widget = HorizontalGroup:new{
									align = "top",
									hyphen_wid,
									hl_footer_widget
			}
			hl_footer_widget = VerticalGroup:new{
								VerticalSpan:new{width = dimen_.footer_clearance},
								hl_footer_widget,
			}
		end

		local hl_wgt_max_h = hl_footer_enabled and
						(max_height - title_dimen.h - stats_dimen.h - hl_footer_widget:getSize().h) or
						(max_height - title_dimen.h - stats_dimen.h)
		highlight_widget = buildTextField(
								random_highlight,
								font_.highlight_font,
								hl_wgt_max_h,
								max_wid,
								true,
								true
		)
		local accent_height = highlight_widget:getSize().h

		-- if hl_footer_enabled and hl_footer_widget then
			-- highlight_widget = VerticalGroup:new{
					-- align = "left",
					-- highlight_widget,
					-- hl_footer_widget,
			-- }
		-- end

		if HL_SETT.show_accent_line then
			local highlight_accent = LineWidget:new{
									background = footer_color,
									dimen =  Geom:new{
										w = dimen_.line_width,
										h = accent_height,
									},
			}
			highlight_widget = HorizontalGroup:new{
				align = "top",
				highlight_accent,
				HorizontalSpan:new{width = dimen_.line_clearance},
				highlight_widget,
			}
		end

		if hl_footer_enabled and hl_footer_widget then
			highlight_widget = VerticalGroup:new{
					align = "left",
					highlight_widget,
					hl_footer_widget,
			}
		end
	end

    local time_today_widget
    local progress_year_widget
    local time_widget
    local Topbar = require("apps/reader/modules/topbar")
    local topbar = Topbar:new{
        view = nil,
        ui = nil,
        fm = true,
    }
    if topbar then
        self.ui.statistics:insertDB()
        self.ui.statistics:insertDBSessionStats()
        local doc_props = Sidecar and Sidecar:readSetting("doc_props") or {}
        local read_today = select(1, topbar:getReadTodayThisMonth(doc_props.title or "")) or 0

        read_today = read_today > 86400
        and (math.floor(read_today / 60 / 60 / 24 * 100) / 100 .. "d")
        or datetime.secondsToClockDuration("modern", read_today, false)
        time_widget = buildTextField(
            "Total time read today: " .. tostring(read_today),
            font_.stats_font,
            max_height - title_dimen.h - stats_dimen.h,
            max_wid
        )
        local year_read = topbar:getReadThisYearSoFar() or 0
        progress_year_widget = buildTextField(
            "ΔL:" .. tostring(year_read) .. "h",
            font_.stats_font,
            max_height - title_dimen.h - stats_dimen.h,
            max_wid
        )
    end
	if panel_widget and not PANEL_SETT.keep_stats then
		time_widget = nil
		progress_year_widget = nil
	end
	content_widget = VerticalGroup:new{
		align = "left",
		title_widget,
		stats_widget,
        time_widget or VerticalSpan:new{width = 0},
        progress_year_widget or VerticalSpan:new{width = 0},
	}

	if highlightEnabled and highlight_widget and
			(not panel_widget or PANEL_SETT.show_highlight) then
		table.insert(content_widget, VerticalSpan:new{width = dimen_.hl_wgt_clearance})
		table.insert(content_widget, highlight_widget)
	end

	content_widget = FrameContainer:new{
		background = B_SETT.background == 0 and Bb.COLOR_WHITE or
					 Bb.COLOR_BLACK,
		color = B_SETT.border_color == 0 and Bb.COLOR_WHITE or
				Bb.COLOR_BLACK,
		margin = dimen_.margin,
		bordersize = dimen_.border_size,
		padding = dimen_.padding,
		content_widget,
	}

	-- put the banner at the left edge (replacing the inbuilt message, if any)
	if not attachBanner(widget, content_widget, message_container_enabled) then
		-- unexpected sleep screen layout: leave it untouched
		return og_uiMan_show(self, widget, ...)
	end

	return og_uiMan_show(self, widget, ...)
end

--MENU INTEGRATION (Settings > Screen > Sleep screen > Wallpaper)
local function addWallpaperItems(ss_items)
	if type(ss_items) ~= "table" then
		return
	end

	local wallpaper
	for i, item in ipairs(ss_items) do
		if item.text == _("Wallpaper") then
			wallpaper = item
			break
		end
	end
	wallpaper = wallpaper or (ss_items[1] and ss_items[1].sub_item_table and ss_items[1])
	if not wallpaper or wallpaper.kobo_style_items_added then
		return
	end
	wallpaper.kobo_style_items_added = true

	local wp_items = wallpaper.sub_item_table
	if #wp_items > 0 then
		wp_items[#wp_items].separator = true
	end
	table.insert(wp_items, {
		text = _("Kobo style sleep screen"),
		help_text = _("Draw the Kobo style banner on top of the sleep screen wallpaper, whether or not the sleep screen message is enabled."),
		checked_func = isKoboStyleOn,
		callback = function()
			G_reader_settings:saveSetting("kobo_style_sleepscreen", not isKoboStyleOn())
		end,
	})
	table.insert(wp_items, {
		text_func = function()
			return T(_("Kobo style banner position: %1 %"), getBannerPosition())
		end,
		help_text = _("Vertical position of the banner, as a percentage of the screen height measured from the bottom (0 = bottom, 100 = top)."),
		enabled_func = isKoboStyleOn,
		keep_menu_open = true,
		callback = function(touchmenu_instance)
			UIManager:show(SpinWidget:new{
				title_text = _("Banner position"),
				info_text = _("Percentage of the screen height, measured from the bottom.\n0 = bottom, 100 = top."),
				value = getBannerPosition(),
				value_min = 0,
				value_max = 100,
				value_step = 1,
				value_hold_step = 10,
				default_value = math.min(math.max(tonumber(B_SETT.vertical_position) or 50, 0), 100),
				unit = "%",
				callback = function(spin)
					G_reader_settings:saveSetting("kobo_style_sleepscreen_position", spin.value)
					if touchmenu_instance then
						touchmenu_instance:updateItems()
					end
				end,
			})
		end,
	})
end

local function safely(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		logger.warn("[kobo-style-sleepscreen] could not add the menu items:", err)
	end
end

local function addMenuItems(menu_items)
	local ss_menu = menu_items and menu_items.screensaver
	addWallpaperItems(ss_menu and ss_menu.sub_item_table)
end

-- koreader builds the sleep screen menu with dofile("frontend/ui/elements/screensaver_menu.lua")
-- every time the menus are (re)built. catch that table as soon as it is created.
local og_dofile = dofile
dofile = function(path, ...)
	local res = og_dofile(path, ...)
	if type(path) == "string" and path:find("screensaver_menu%.lua$") then
		safely(addWallpaperItems, res)
	end
	return res
end

-- as a second way in, also add the items right after the menus are (re)built
local function hookMenu(module_path)
	local ok, Menu = pcall(require, module_path)
	if not ok or type(Menu) ~= "table" or not Menu.setUpdateItemTable then
		return
	end
	local og_setUpdateItemTable = Menu.setUpdateItemTable
	function Menu:setUpdateItemTable(...)
		local res = og_setUpdateItemTable(self, ...)
		safely(addMenuItems, self.menu_items)
		return res
	end
end
hookMenu("apps/filemanager/filemanagermenu")
hookMenu("apps/reader/modules/readermenu")

-- menus that already exist when this patch runs
for i, module_path in ipairs{"apps/filemanager/filemanager", "apps/reader/readerui"} do
	local ok, class = pcall(require, module_path)
	local instance = ok and type(class) == "table" and class.instance
	if instance and instance.menu then
		safely(addMenuItems, instance.menu.menu_items)
	end
end
