-- Display the book cover while opening and closing documents.
-- Place this file in koreader/patches/.

local logger = require("logger")
local UIManager = require("ui/uimanager")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local CenterContainer = require("ui/widget/container/centercontainer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local DataStorage = require("datastorage")
local FrameContainer = require("ui/widget/container/framecontainer")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Screen = Device.screen
local lfs = require("libs/libkoreader-lfs")
local DocumentRegistry = require("document/documentregistry")
local _ = require("gettext")

local PLUGIN_NAME = "BookLoadCover Plus"
local LOG_PREFIX = PLUGIN_NAME .. " patch:"
local PATCH_VERSION = "v1.6.8"

local function pluginName()
	return _("BookLoadCover Plus")
end

local function info(...)
	logger.info(LOG_PREFIX, ...)
end

local function warn(...)
	logger.warn(LOG_PREFIX, ...)
end

local ReaderUI

local State = {
	cover_widget = nil,
	owned_cover_bb = nil,
	stretched_bb = nil,
	book_info_manager = nil,
	file_manager_book_info = nil,
	coverbrowser_path_added = false,
	suppress_closing_notice = false,
	reload_pending = false,
}

local Settings = {
	open_mode = "bookloadcover_open_mode",
	close_mode = "bookloadcover_close_mode",
	close_enabled_legacy = "bookloadcover_close_enabled",
	extract_enabled = "bookloadcover_extract_enabled",
	cover_source = "bookloadcover_cover_source",
	cover_layout = "bookloadcover_cover_layout",
	card_size_percent = "bookloadcover_card_size_percent",
	card_rounded_corners = "bookloadcover_card_rounded_corners",
	close_on_teardown = "bookloadcover_close_on_teardown",
	status_label = "bookloadcover_status_label", -- legacy: applied to both
	status_label_open = "bookloadcover_status_label_open",
	status_label_close = "bookloadcover_status_label_close",
	status_icon = "bookloadcover_status_icon",
	refresh_mode = "bookloadcover_refresh_mode",
	suppress_closing_notice = "bookloadcover_suppress_closing_notice",
	open_close_delay = "bookloadcover_close_delay",
	after_close_delay = "bookloadcover_after_close_delay",
	closing_notice_suppress_delay = "bookloadcover_closing_notice_suppress_delay",
}

local Mode = {
	off = "off",
	no_transition_widgets = "no_transition_widgets",
	cover_with_widgets = "cover_with_widgets",
	cover_only = "cover_only",
}

local SourceMode = {
	balanced = "balanced",
	best_quality = "best_quality",
}

local LayoutMode = {
	stretch = "stretch",
	fit_black = "fit_black",
	fit_white = "fit_white",
	fill_zoom = "fill_zoom",
	centered_card = "centered_card",
}

local DEFAULT_OPEN_MODE = Mode.cover_only
local DEFAULT_CLOSE_MODE = Mode.cover_only
local DEFAULT_SOURCE_MODE = SourceMode.balanced
local DEFAULT_LAYOUT_MODE = LayoutMode.stretch
local DEFAULT_CARD_SIZE_PERCENT = 70

local MODE_ORDER = {
	Mode.off,
	Mode.no_transition_widgets,
	Mode.cover_with_widgets,
	Mode.cover_only,
}

local VALID_MODES = {
	[Mode.off] = true,
	[Mode.no_transition_widgets] = true,
	[Mode.cover_with_widgets] = true,
	[Mode.cover_only] = true,
}

local SOURCE_MODE_ORDER = {
	SourceMode.balanced,
	SourceMode.best_quality,
}

local VALID_SOURCE_MODES = {
	[SourceMode.balanced] = true,
	[SourceMode.best_quality] = true,
}

local LAYOUT_MODE_ORDER = {
	LayoutMode.stretch,
	LayoutMode.fit_black,
	LayoutMode.fit_white,
	LayoutMode.fill_zoom,
	LayoutMode.centered_card,
}

local VALID_LAYOUT_MODES = {
	[LayoutMode.stretch] = true,
	[LayoutMode.fit_black] = true,
	[LayoutMode.fit_white] = true,
	[LayoutMode.fill_zoom] = true,
	[LayoutMode.centered_card] = true,
}

local function modeLabel(mode)
	local labels = {
		[Mode.off] = _("Default widgets only"),
		[Mode.no_transition_widgets] = _("No cover or default widgets"),
		[Mode.cover_with_widgets] = _("Cover + default widgets"),
		[Mode.cover_only] = _("Cover only"),
	}
	return labels[mode] or labels[Mode.cover_only]
end

local function sourceModeLabel(mode)
	local labels = {
		[SourceMode.balanced] = _("Balanced (faster)"),
		[SourceMode.best_quality] = _("Best quality"),
	}
	return labels[mode] or labels[SourceMode.balanced]
end

local function layoutModeLabel(mode)
	local labels = {
		[LayoutMode.stretch] = _("Stretch to screen"),
		[LayoutMode.fit_black] = _("Fit to screen (black background)"),
		[LayoutMode.fit_white] = _("Fit to screen (white background)"),
		[LayoutMode.fill_zoom] = _("Fill screen (zoom/crop)"),
		[LayoutMode.centered_card] = _("Centered card"),
	}
	return labels[mode] or labels[LayoutMode.stretch]
end

local function readMode(key, default_mode)
	local mode = G_reader_settings:readSetting(key, default_mode)
	return VALID_MODES[mode] and mode or default_mode
end

local function getCoverSourceMode()
	local mode = G_reader_settings:readSetting(Settings.cover_source, DEFAULT_SOURCE_MODE)
	return VALID_SOURCE_MODES[mode] and mode or DEFAULT_SOURCE_MODE
end

local function getCoverLayoutMode()
	local mode = G_reader_settings:readSetting(Settings.cover_layout, DEFAULT_LAYOUT_MODE)
	return VALID_LAYOUT_MODES[mode] and mode or DEFAULT_LAYOUT_MODE
end

local function getCardSizePercent()
	local percent = tonumber(G_reader_settings:readSetting(Settings.card_size_percent, DEFAULT_CARD_SIZE_PERCENT))
	if not percent then
		return DEFAULT_CARD_SIZE_PERCENT
	end
	return math.max(30, math.min(95, math.floor(percent)))
end

local function useRoundedCardCorners()
	return G_reader_settings:nilOrTrue(Settings.card_rounded_corners)
end

local function getOpenMode()
	return readMode(Settings.open_mode, DEFAULT_OPEN_MODE)
end

local function getCloseMode()
	if
		G_reader_settings:hasNot(Settings.close_mode)
		and G_reader_settings:has(Settings.close_enabled_legacy)
		and not G_reader_settings:nilOrTrue(Settings.close_enabled_legacy)
	then
		return Mode.off
	end

	return readMode(Settings.close_mode, DEFAULT_CLOSE_MODE)
end

local function modeShowsCover(mode)
	return mode == Mode.cover_with_widgets or mode == Mode.cover_only
end

local function modeSuppressesDefaultWidgets(mode)
	return mode == Mode.cover_only or mode == Mode.no_transition_widgets
end

local function shouldShowOpeningCover()
	return modeShowsCover(getOpenMode())
end

local function shouldShowClosingCoverMode()
	return modeShowsCover(getCloseMode())
end

local function shouldUseSeamlessOpening()
	return modeSuppressesDefaultWidgets(getOpenMode())
end

local function shouldSuppressClosingNotice()
	local close_mode = getCloseMode()
	if close_mode == Mode.no_transition_widgets then
		return true
	end

	return close_mode == Mode.cover_only and G_reader_settings:nilOrTrue(Settings.suppress_closing_notice)
end

local function shouldPreferBestQualityCover()
	return getCoverSourceMode() == SourceMode.best_quality
end

local function shouldExtractFromDocument()
	return G_reader_settings:nilOrTrue(Settings.extract_enabled)
end

local function shouldShowStatusLabel(reason)
	local key = reason == "close" and Settings.status_label_close or Settings.status_label_open
	if G_reader_settings:has(key) then
		return G_reader_settings:isTrue(key)
	end
	return G_reader_settings:nilOrTrue(Settings.status_label)
end

local function shouldShowStatusIcon()
	return G_reader_settings:nilOrTrue(Settings.status_icon)
end

local function getRefreshMode()
	local mode = G_reader_settings:readSetting(Settings.refresh_mode, "full")
	return mode == "partial" and "partial" or "full"
end

local function shouldShowOnTeardown()
	return G_reader_settings:isTrue(Settings.close_on_teardown)
end

local function getOpenCloseDelay()
	return G_reader_settings:readSetting(Settings.open_close_delay, 0.1)
end

local function getAfterCloseDelay()
	return G_reader_settings:readSetting(Settings.after_close_delay, 0.5)
end

local function getClosingNoticeSuppressDelay()
	return G_reader_settings:readSetting(Settings.closing_notice_suppress_delay, getAfterCloseDelay() + 0.3)
end

local function flushSettings()
	if UIManager.flushSettings then
		pcall(function()
			UIManager:flushSettings()
		end)
	end
end

local function saveSetting(key, value)
	G_reader_settings:saveSetting(key, value)
	flushSettings()
end

local function joinPath(base, name)
	if not base or base == "" then
		return name
	end
	return base:sub(-1) == "/" and base .. name or base .. "/" .. name
end

local function safeRequire(module_name)
	local ok, module = pcall(require, module_name)
	if ok then
		return module
	end

	warn("failed to load module", module_name, module)
	return nil
end

local function addCoverBrowserToPackagePath(plugin_path)
	if State.coverbrowser_path_added then
		return
	end

	package.path = plugin_path .. "/?.lua;" .. package.path
	State.coverbrowser_path_added = true
end

local function getBookInfoManager()
	if State.book_info_manager then
		return State.book_info_manager
	end

	local plugin_path = "plugins/coverbrowser.koplugin"
	if lfs.attributes(plugin_path, "mode") ~= "directory" then
		warn("CoverBrowser plugin directory not found")
		return nil
	end

	addCoverBrowserToPackagePath(plugin_path)
	State.book_info_manager = safeRequire("bookinfomanager")
	return State.book_info_manager
end

local function getFileManagerBookInfo()
	if State.file_manager_book_info then
		return State.file_manager_book_info
	end

	State.file_manager_book_info = safeRequire("apps/filemanager/filemanagerbookinfo")
	return State.file_manager_book_info
end

local function freeOwnedCover()
	if State.stretched_bb then
		pcall(function()
			State.stretched_bb:free()
		end)
		State.stretched_bb = nil
	end

	if not State.owned_cover_bb then
		return
	end

	local ok, err = pcall(function()
		State.owned_cover_bb:free()
	end)

	if not ok then
		warn("failed to free owned cover blitbuffer", err)
	end

	State.owned_cover_bb = nil
end

local function closeBookInfoDbIfLoaded()
	local BIM = State.book_info_manager
	if not BIM or not BIM.closeDbConnection then
		return
	end

	local ok, err = pcall(function()
		BIM:closeDbConnection()
	end)

	if not ok then
		warn("failed to close BookInfoManager DB connection", err)
	end
end

local function closeCover()
	if State.notice_widget then
		pcall(function()
			UIManager:close(State.notice_widget)
		end)
		State.notice_widget = nil
	end

	if State.cover_widget then
		local ok, err = pcall(function()
			UIManager:close(State.cover_widget)
		end)
		if not ok then
			warn("failed to close cover widget", err)
		end
		State.cover_widget = nil
	end

	freeOwnedCover()
	closeBookInfoDbIfLoaded()
end

-- Widgets created with timeout == 0.0 are third-party "Closing book…" notices
-- (e.g. Bookshelf). They are left alone: not suppressed and not closed.
local function isForeignClosingNotice(widget)
	return type(widget) == "table" and widget.timeout == 0.0
end

local function closeOverlayWidgets()
	local kept = {}
	local stack = UIManager._window_stack
	if not stack or #stack == 0 then
		return kept
	end

	local widgets = {}
	for i = #stack, 1, -1 do
		local entry = stack[i]
		if entry and entry.widget then
			table.insert(widgets, entry.widget)
		end
	end

	local closed_any = false
	for _i, widget in ipairs(widgets) do
		if widget ~= State.cover_widget then
			local name = type(widget.name) == "string" and widget.name:lower() or nil
			if name == "readerui" or name == "filemanager" or name == "bookshelf" then
				break
			end
			if isForeignClosingNotice(widget) then
				table.insert(kept, widget)
			else
				closed_any = true
				local ok, err = pcall(function()
					UIManager:close(widget)
				end)
				if not ok then
					warn("failed to close overlay widget before showing cover", err)
				end
			end
		end
	end
	-- Only repaint if something was actually closed: an extra repaint is a visible flicker.
	if closed_any then
		UIManager:forceRePaint()
	end
	return kept
end

local function scheduleCloseCover(delay)
	UIManager:scheduleIn(delay, closeCover)
end

local function stopSuppressingClosingNotice()
	State.suppress_closing_notice = false
end

local function startSuppressingClosingNotice()
	if shouldSuppressClosingNotice() then
		State.suppress_closing_notice = true
	end
end

local function scheduleStopSuppressingClosingNotice(delay)
	if State.suppress_closing_notice then
		UIManager:scheduleIn(delay, stopSuppressingClosingNotice)
	end
end

local function setMode(key, mode)
	if VALID_MODES[mode] then
		saveSetting(key, mode)
	end
end

local function setCoverSourceMode(mode)
	if VALID_SOURCE_MODES[mode] then
		saveSetting(Settings.cover_source, mode)
	end
end

local function setCoverLayoutMode(mode)
	if VALID_LAYOUT_MODES[mode] then
		saveSetting(Settings.cover_layout, mode)
	end
end

local function setCardSizePercent(percent)
	percent = tonumber(percent)
	if percent then
		saveSetting(Settings.card_size_percent, math.max(30, math.min(95, math.floor(percent))))
	end
end

local function getWidgetText(widget)
	if type(widget) ~= "table" then
		return nil
	end

	local candidates = {
		widget.text,
		widget.message,
		widget.title,
		widget.info_text,
		widget.content,
		widget.label,
	}

	for _i, value in ipairs(candidates) do
		if type(value) == "string" and value ~= "" then
			return value
		end
	end

	return nil
end

local function textHasAllWords(text, words)
	for _i, word in ipairs(words) do
		if not text:find(word, 1, true) then
			return false
		end
	end
	return true
end

local function textLooksLikeClosingBookNotice(text)
	if type(text) ~= "string" then
		return false
	end

	-- The real notice is a short "Closing book…"; longer texts (like menu help messages that
	-- merely contain those words) must never be swallowed.
	if #text > 60 then
		return false
	end

	local normalized = text:lower()
	local localized = {
		_("Closing book…"),
		_("Closing book..."),
		_("Closing book"),
	}

	for _i, candidate in ipairs(localized) do
		if type(candidate) == "string" and candidate ~= "" and normalized:find(candidate:lower(), 1, true) then
			return true
		end
	end

	local word_sets = {
		{ "closing", "book" }, -- English
		{ "fechando", "livro" }, -- Portuguese
		{ "chiusura", "libro" }, -- Italian
		{ "chiudendo", "libro" }, -- Italian alternative
		{ "fermeture", "livre" }, -- French
		{ "cerrando", "libro" }, -- Spanish
		{ "schließen", "buch" }, -- German
		{ "schlies", "buch" }, -- German fallback without ß
		{ "закры", "кни" }, -- Russian stem fallback
		{ "Закры", "кни" }, -- Russian, capitalized (lower() is ASCII-only)
	}

	for _i, words in ipairs(word_sets) do
		if textHasAllWords(normalized, words) or textHasAllWords(text, words) then
			return true
		end
	end

	return false
end

local function widgetLooksLikeClosingBookNotice(widget)
	if type(widget) == "string" then
		return textLooksLikeClosingBookNotice(widget)
	end

	return textLooksLikeClosingBookNotice(getWidgetText(widget))
end

local function getCoverFromCoverImageCache(filepath)
	local cache_path = G_reader_settings:readSetting("cover_image_cache_path")
	if not cache_path or lfs.attributes(cache_path, "mode") ~= "directory" then
		return nil
	end

	local util = safeRequire("util")
	local sha2 = safeRequire("ffi/sha2")
	local RenderImage = safeRequire("ui/renderimage")
	if not util or not sha2 or not sha2.md5 or not RenderImage then
		return nil
	end

	local _dir, document_name = util.splitFilePathName(filepath)
	if not document_name then
		return nil
	end

	local quality = G_reader_settings:readSetting("cover_image_quality", 75)
	local stretch_limit = G_reader_settings:readSetting("cover_image_stretch_limit", 8)
	local background = G_reader_settings:readSetting("cover_image_background", "black")
	local format = G_reader_settings:readSetting("cover_image_format", "auto")
	local grayscale = G_reader_settings:isTrue("cover_image_grayscale")
	local rotate = G_reader_settings:readSetting("cover_image_rotate", true)
	local rotated = rotate and "_rotated_" or ""

	local key = document_name
		.. quality
		.. stretch_limit
		.. background
		.. format
		.. tostring(grayscale)
		.. Screen:getRotationMode()
		.. rotated

	local ext = "jpg"
	local cover_path = G_reader_settings:readSetting("cover_image_path")
	if cover_path then
		local suffix = util.getFileNameSuffix(cover_path)
		if suffix and suffix ~= "" then
			ext = suffix:lower()
		end
	end

	local cache_file = joinPath(cache_path, "cover_" .. sha2.md5(key) .. "." .. ext)
	if lfs.attributes(cache_file, "mode") ~= "file" then
		return nil
	end

	local ok, cover_bb = pcall(function()
		return RenderImage:renderImageFile(cache_file)
	end)

	if ok and cover_bb then
		return cover_bb, true
	end

	warn("failed to load CoverImage cache file", cover_bb)
	return nil
end

local function getCoverFromDB(filepath)
	local BIM = getBookInfoManager()
	if not BIM then
		return nil
	end

	local ok, bookinfo = pcall(function()
		return BIM:getBookInfo(filepath, true)
	end)

	if not ok then
		warn("failed to read book info from DB", bookinfo)
		return nil
	end

	if not bookinfo or not bookinfo.has_cover or bookinfo.ignore_cover or not bookinfo.cover_bb then
		return nil
	end

	return bookinfo.cover_bb, false
end

local function closeDocument(document)
	if not document then
		return
	end

	local ok, err = pcall(function()
		document:close()
	end)

	if not ok then
		warn("failed to close temporary document", err)
	end
end

local function getCoverFromOpenDocument(document)
	if not document then
		return nil
	end

	local FMBI = getFileManagerBookInfo()
	if not FMBI then
		return nil
	end

	local ok, cover_bb = pcall(function()
		return FMBI:getCoverImage(document)
	end)

	if ok and cover_bb then
		return cover_bb, true
	end

	if not ok then
		warn("failed to get cover from open document", cover_bb)
	end

	return nil
end

local function extractCoverFromDocument(filepath, force_extract)
	if not force_extract and not shouldExtractFromDocument() then
		return nil
	end

	if not DocumentRegistry:hasProvider(filepath) then
		return nil
	end

	local FMBI = getFileManagerBookInfo()
	if not FMBI then
		return nil
	end

	local document
	local ok, cover_bb = pcall(function()
		local provider = ReaderUI:extendProvider(filepath, DocumentRegistry:getProvider(filepath))
		document = DocumentRegistry:openDocument(filepath, provider)
		if not document then
			return nil
		end

		if document.loadDocument and not document:loadDocument(false) then
			return nil
		end

		return FMBI:getCoverImage(document)
	end)

	closeDocument(document)

	if ok and cover_bb then
		return cover_bb, true
	end

	if not ok then
		warn("failed to extract cover from document", cover_bb)
	end

	return nil
end

local function findCover(filepath, options)
	options = options or {}

	local sources = {}

	if shouldPreferBestQualityCover() then
		if options.open_document then
			table.insert(sources, function()
				return getCoverFromOpenDocument(options.open_document)
			end)
		end

		if options.allow_direct_extract ~= false then
			table.insert(sources, function()
				return extractCoverFromDocument(filepath, true)
			end)
		end

		table.insert(sources, getCoverFromDB)
		table.insert(sources, getCoverFromCoverImageCache)
	else
		table.insert(sources, getCoverFromDB)

		if options.open_document then
			table.insert(sources, function()
				return getCoverFromOpenDocument(options.open_document)
			end)
		end

		if options.allow_direct_extract ~= false then
			table.insert(sources, extractCoverFromDocument)
		end

		-- Last resort: the CoverImage cache is already rendered at screen size with its own
		-- letterboxing/cropping baked in, so stretching it cannot fix that.
		table.insert(sources, getCoverFromCoverImageCache)
	end

	for _i, source in ipairs(sources) do
		local ok, cover_bb, needs_free = pcall(source, filepath)
		if ok and cover_bb then
			return cover_bb, needs_free
		end
		if not ok then
			warn("cover source failed", cover_bb)
		end
	end

	return nil
end

local function getCoverSize(cover_bb)
	if not cover_bb or not cover_bb.getWidth or not cover_bb.getHeight then
		return nil, nil
	end

	local ok, w, h = pcall(function()
		return cover_bb:getWidth(), cover_bb:getHeight()
	end)

	if ok and w and h and w > 0 and h > 0 then
		return w, h
	end

	return nil, nil
end

local function getDitheredOption()
	return Screen.hw_dithering or nil
end

-- Full-screen opaque frame, so nothing underneath can ever show through.
local function wrapFullScreen(child, screen_w, screen_h, background)
	return FrameContainer:new({
		width = screen_w,
		height = screen_h,
		padding = 0,
		margin = 0,
		bordersize = 0,
		background = background or Blitbuffer.COLOR_BLACK,
		CenterContainer:new({
			dimen = { w = screen_w, h = screen_h },
			child,
		}),
	})
end

local function makeStretchCoverWidget(cover_bb, screen_w, screen_h)
	-- Scale the image to EXACTLY the screen size ourselves, instead of relying on
	-- ImageWidget's scale_factor=0 (which may keep the aspect ratio / crop).
	local image = cover_bb
	local RenderImage = safeRequire("ui/renderimage")
	if RenderImage and RenderImage.scaleBlitBuffer then
		local ok, scaled = pcall(RenderImage.scaleBlitBuffer, RenderImage, cover_bb, screen_w, screen_h, false)
		if ok and scaled then
			State.stretched_bb = scaled
			image = scaled
		else
			warn("failed to pre-scale cover, using ImageWidget scaling", scaled)
		end
	end

	return wrapFullScreen(
		ImageWidget:new({
			image = image,
			width = screen_w,
			height = screen_h,
			scale_factor = State.stretched_bb and 1 or 0,
			alpha = true,
			dithered = getDitheredOption(),
			image_disposable = false,
		}),
		screen_w,
		screen_h
	)
end

local function makeCenteredCardCoverWidget(cover_bb, cover_w, cover_h, screen_w, screen_h)
	local percent = getCardSizePercent() / 100
	local card_w = math.max(1, math.floor(screen_w * percent))
	local card_h = math.max(1, math.floor(screen_h * percent))
	local border_size = Screen:scaleBySize(2)
	local padding = Screen:scaleBySize(10)
	local inner_w = math.max(1, card_w - (padding + border_size) * 2)
	local inner_h = math.max(1, card_h - (padding + border_size) * 2)
	local scale_factor = math.min(inner_w / cover_w, inner_h / cover_h)

	local image = ImageWidget:new({
		image = cover_bb,
		scale_factor = scale_factor,
		alpha = true,
		image_disposable = false,
	})

	local card = FrameContainer:new({
		dimen = { w = card_w, h = card_h },
		padding = padding,
		bordersize = border_size,
		radius = useRoundedCardCorners() and Screen:scaleBySize(18) or 0,
		background = Blitbuffer.COLOR_WHITE,
		color = Blitbuffer.COLOR_BLACK,
		CenterContainer:new({
			dimen = { w = inner_w, h = inner_h },
			image,
		}),
	})

	return CenterContainer:new({
		dimen = { w = screen_w, h = screen_h },
		card,
	})
end

local function makeCoverImageWidget(cover_bb)
	local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
	local layout_mode = getCoverLayoutMode()

	if layout_mode == LayoutMode.stretch then
		return makeStretchCoverWidget(cover_bb, screen_w, screen_h)
	end

	local cover_w, cover_h = getCoverSize(cover_bb)
	if not cover_w or not cover_h then
		warn("failed to read cover size, falling back to stretch layout")
		return makeStretchCoverWidget(cover_bb, screen_w, screen_h)
	end

	if layout_mode == LayoutMode.centered_card then
		return makeCenteredCardCoverWidget(cover_bb, cover_w, cover_h, screen_w, screen_h)
	end

	local scale_factor
	if layout_mode == LayoutMode.fill_zoom then
		scale_factor = math.max(screen_w / cover_w, screen_h / cover_h)
		return wrapFullScreen(
			ImageWidget:new({
				image = cover_bb,
				width = screen_w,
				height = screen_h,
				scale_factor = scale_factor,
				alpha = true,
				dithered = getDitheredOption(),
				image_disposable = false,
			}),
			screen_w,
			screen_h
		)
	end

	scale_factor = math.min(screen_w / cover_w, screen_h / cover_h)
	local image = ImageWidget:new({
		image = cover_bb,
		scale_factor = scale_factor,
		alpha = true,
		image_disposable = false,
	})

	local background = layout_mode == LayoutMode.fit_white and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK

	return FrameContainer:new({
		width = screen_w,
		height = screen_h,
		padding = 0,
		margin = 0,
		bordersize = 0,
		background = background,
		CenterContainer:new({
			dimen = { w = screen_w, h = screen_h },
			image,
		}),
	})
end

-- Small PNG icons (open book with sparkles / sleeping closed book), embedded as base64
-- and written once to KOReader's cache dir so ImageWidget can load them from a file.
local ICONS_B64 = {
	open = "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",
	close = "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",
}

local function getIconPath(reason)
	local key = reason == "close" and "close" or "open"
	local ok, path = pcall(function()
		local dir = DataStorage:getDataDir() .. "/cache"
		local file = dir .. "/bookloadcover_" .. key .. ".png"
		if lfs.attributes(file, "mode") == "file" then
			return file
		end
		local sha2 = require("ffi/sha2")
		if not sha2.base64_to_bin then
			return nil
		end
		if lfs.attributes(dir, "mode") ~= "directory" then
			lfs.mkdir(dir)
		end
		local data = sha2.base64_to_bin(ICONS_B64[key])
		local f = io.open(file, "wb")
		if not f then
			return nil
		end
		f:write(data)
		f:close()
		return file
	end)
	return ok and path or nil
end

local FUN_TEXTS = {
	open = {
		_("Opening book…"),
		_("Cracking it open…"),
		_("Dusting off the cover…"),
		_("Turning to your page…"),
		_("Chapter loading…"),
	},
	reload = {
		_("Reflowing the pages…"),
		_("Rearranging the words…"),
		_("Giving the text a new look…"),
		_("Shuffling the paragraphs…"),
		_("Re-shelving the letters…"),
		_("Fresh coat of layout…"),
	},
	close = {
		_("Closing book…"),
		_("Saving your spot…"),
		_("Tucking in the bookmark…"),
		_("Shutting it softly…"),
		_("Until next chapter…"),
	},
}

-- Font of the book being opened/closed, resolved to a font file; nil -> keep the UI font.
-- Closing: the live font face from the reader. Opening: the book's own sidecar setting,
-- then KOReader's default book font.
local function getBookFontFace(reason, filepath, options)
	local ok, face = pcall(function()
		local face_name = options and options.font_face
		if not face_name and reason ~= "close" and filepath then
			local DocSettings = require("docsettings")
			local doc_settings = DocSettings:open(filepath)
			face_name = doc_settings and doc_settings:readSetting("font_face")
		end
		if not face_name then
			face_name = G_reader_settings:readSetting("cre_font")
		end
		if type(face_name) ~= "string" or face_name == "" then
			return nil
		end

		local cre = require("libs/libkoreader-cre")
		if type(cre) ~= "table" or type(cre.getFontFaceFilenameAndFaceIndex) ~= "function" then
			return nil
		end
		local filename = cre.getFontFaceFilenameAndFaceIndex(face_name)
		if type(filename) ~= "string" or filename == "" then
			return nil
		end

		return Font:getFace(filename, 20)
	end)

	if ok and face then
		return face
	end
	return nil
end

local function pickFunText(reason, is_reload)
	local list = FUN_TEXTS[is_reload and "reload" or (reason == "close" and "close" or "open")]
	return list[math.random(#list)]
end

-- Rounded "pill" at the bottom of the cover: icon + a playful opening/closing phrase.
local function makeStatusLabelWidget(reason, screen_w, screen_h, filepath, options)
	local text_widget = TextWidget:new({
		text = pickFunText(reason, options and options.reload),
		face = getBookFontFace(reason, filepath, options) or Font:getFace("cfont", 20),
		bold = true,
		fgcolor = Blitbuffer.COLOR_BLACK,
	})

	local content = text_widget
	local icon_path = shouldShowStatusIcon() and getIconPath(reason) or nil
	if icon_path then
		local ok, group = pcall(function()
			local icon_size = Screen:scaleBySize(36)
			local text_size = text_widget:getSize()
			-- Both the icon and the text sit in boxes of the same height with their content
			-- centred vertically, so they always line up with each other and with the pill.
			local row_h = math.max(icon_size, text_size.h)
			return HorizontalGroup:new({
				align = "center",
				CenterContainer:new({
					dimen = Geom:new({ w = icon_size, h = row_h }),
					ImageWidget:new({
						file = icon_path,
						width = icon_size,
						height = icon_size,
						scale_factor = 0,
						alpha = true,
					}),
				}),
				HorizontalSpan:new({ width = Screen:scaleBySize(10) }),
				CenterContainer:new({
					dimen = Geom:new({ w = text_size.w, h = row_h }),
					text_widget,
				}),
			})
		end)
		if ok and group then
			content = group
		else
			warn("failed to build label icon", group)
		end
	end

	local pill = FrameContainer:new({
		background = Blitbuffer.COLOR_WHITE,
		color = Blitbuffer.COLOR_BLACK,
		bordersize = Screen:scaleBySize(2),
		radius = Screen:scaleBySize(26),
		padding = Screen:scaleBySize(8),
		padding_left = Screen:scaleBySize(16),
		padding_right = Screen:scaleBySize(20),
		margin = 0,
		content,
	})

	return BottomContainer:new({
		dimen = Geom:new({ w = screen_w, h = screen_h - Screen:scaleBySize(48) }),
		pill,
	})
end

local function addStatusLabel(cover_widget, reason, filepath, options)
	local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
	local ok, result = pcall(function()
		return OverlapGroup:new({
			dimen = Geom:new({ w = screen_w, h = screen_h }),
			allow_mirroring = false,
			cover_widget,
			makeStatusLabelWidget(reason, screen_w, screen_h, filepath, options),
		})
	end)

	if ok and result then
		return result
	end

	warn("failed to build status label, showing plain cover", result)
	return cover_widget
end

local function showCover(filepath, options)
	if not filepath or filepath == "" then
		return false
	end

	options = options or {}
	-- cancel stale close timers so they can't remove this new cover early
	UIManager:unschedule(closeCover)
	closeCover()
	local kept_notices = closeOverlayWidgets()

	local cover_bb, needs_free = findCover(filepath, options)
	if not cover_bb then
		return false
	end

	if needs_free then
		State.owned_cover_bb = cover_bb
	end

	local cover_widget = makeCoverImageWidget(cover_bb)
	local label_shown = false
	if shouldShowStatusLabel(options.reason) then
		local with_label = addStatusLabel(cover_widget, options.reason, filepath, options)
		label_shown = with_label ~= cover_widget
		cover_widget = with_label
	end

	if Device:isKobo() and Device.model == "Kobo_io" then
		require("ffi/util").usleep(250 * 1000)
	end

	local ok, err = pcall(function()
		-- Reloads happen while reading: a "ui" refresh avoids the full-screen flash.
		UIManager:show(cover_widget, options.reload and "ui" or getRefreshMode())
		if options.reason == "close" then
			UIManager:forceRePaint()
		end
	end)

	if not ok then
		warn("failed to display cover", err)
		freeOwnedCover()
		return false
	end

	-- "Cover + default widgets": put the third-party "Closing book…" notice back on top of the cover.
	if options.reason == "close" and getCloseMode() == Mode.cover_with_widgets then
		-- The third-party notice may already be gone (or hidden under the cover), so drop it
		-- and show our own persistent notice above the cover instead.
		for _i, notice in ipairs(kept_notices) do
			pcall(function()
				UIManager:close(notice)
			end)
		end
		pcall(function()
			local notice = InfoMessage:new({ text = _("Closing book…") })
			State.notice_widget = notice
			UIManager:show(notice)
			UIManager:setDirty(notice, function()
				return "partial", notice.dimen
			end)
		end)
		UIManager:forceRePaint()
	end

	State.cover_widget = cover_widget
	return true
end

local function shouldShowClosingCover(ui, full_refresh)
	if not shouldShowClosingCoverMode() then
		return false
	end

	if not ui or not ui.document or not ui.document.file then
		return false
	end

	if full_refresh == false and ui.tearing_down and not shouldShowOnTeardown() then
		return false
	end

	return true
end

local function makeModeMenu(setting_key, default_mode, get_current_mode)
	local items = {}

	for _i, mode in ipairs(MODE_ORDER) do
		table.insert(items, {
			text = modeLabel(mode),
			radio = true,
			keep_menu_open = true,
			checked_func = function()
				local current_mode = get_current_mode and get_current_mode() or readMode(setting_key, default_mode)
				return current_mode == mode
			end,
			callback = function(touchmenu_instance)
				setMode(setting_key, mode)
				if mode == Mode.off or mode == Mode.no_transition_widgets then
					stopSuppressingClosingNotice()
					closeCover()
				end
				if touchmenu_instance then
					touchmenu_instance:updateItems()
				end
			end,
		})
	end

	return items
end

local function makeSourceModeMenu()
	local items = {}

	for _i, mode in ipairs(SOURCE_MODE_ORDER) do
		table.insert(items, {
			text = sourceModeLabel(mode),
			radio = true,
			keep_menu_open = true,
			checked_func = function()
				return getCoverSourceMode() == mode
			end,
			callback = function(touchmenu_instance)
				setCoverSourceMode(mode)
				if touchmenu_instance then
					touchmenu_instance:updateItems()
				end
			end,
		})
	end

	return items
end

local function makeLayoutModeMenu()
	local items = {}

	for _i, mode in ipairs(LAYOUT_MODE_ORDER) do
		table.insert(items, {
			text = layoutModeLabel(mode),
			radio = true,
			keep_menu_open = true,
			checked_func = function()
				return getCoverLayoutMode() == mode
			end,
			callback = function(touchmenu_instance)
				setCoverLayoutMode(mode)
				if touchmenu_instance then
					touchmenu_instance:updateItems()
				end
			end,
		})
	end

	return items
end

local function makeCardSizeMenu()
	local items = {}
	local options = { 40, 50, 60, 70, 80, 90 }

	for _i, percent in ipairs(options) do
		table.insert(items, {
			text = percent .. "%",
			radio = true,
			keep_menu_open = true,
			checked_func = function()
				return getCardSizePercent() == percent
			end,
			callback = function(touchmenu_instance)
				setCardSizePercent(percent)
				if touchmenu_instance then
					touchmenu_instance:updateItems()
				end
			end,
		})
	end

	return items
end

local function makeRefreshModeMenu()
	local items = {}
	local modes = {
		{ id = "full", label = _("Full (clean, flashes)") },
		{ id = "partial", label = _("Partial (no flash, may ghost)") },
	}

	for _i, entry in ipairs(modes) do
		table.insert(items, {
			text = entry.label,
			radio = true,
			keep_menu_open = true,
			checked_func = function()
				return getRefreshMode() == entry.id
			end,
			callback = function(touchmenu_instance)
				saveSetting(Settings.refresh_mode, entry.id)
				if touchmenu_instance then
					touchmenu_instance:updateItems()
				end
			end,
		})
	end

	return items
end

local function showVersionInfo()
	UIManager:show(InfoMessage:new({
		text = pluginName() .. "\n" .. _("Version") .. ": " .. PATCH_VERSION,
		timeout = 3,
	}))
end

local BookLoadCoverMenu = {
	name = "bookloadcover",
}

function BookLoadCoverMenu:addToMainMenu(menu_items)
	menu_items.bookloadcover = {
		text = pluginName(),
		sorting_hint = "setting",
		keep_menu_open = true,
		sub_item_table = {
			{
				text = _("Transition behavior"),
				keep_menu_open = true,
				sub_item_table = {
					{
						text_func = function()
							return _("Opening") .. ": " .. modeLabel(getOpenMode())
						end,
						keep_menu_open = true,
						sub_item_table = makeModeMenu(Settings.open_mode, DEFAULT_OPEN_MODE, getOpenMode),
					},
					{
						text_func = function()
							return _("Closing") .. ": " .. modeLabel(getCloseMode())
						end,
						keep_menu_open = true,
						sub_item_table = makeModeMenu(Settings.close_mode, DEFAULT_CLOSE_MODE, getCloseMode),
					},
				},
			},
			{
				text = _("Cover display"),
				keep_menu_open = true,
				sub_item_table = {
					{
						text_func = function()
							return _("Cover source") .. ": " .. sourceModeLabel(getCoverSourceMode())
						end,
						keep_menu_open = true,
						sub_item_table = makeSourceModeMenu(),
					},
					{
						text_func = function()
							return _("Cover layout") .. ": " .. layoutModeLabel(getCoverLayoutMode())
						end,
						keep_menu_open = true,
						sub_item_table = makeLayoutModeMenu(),
					},
					{
						text_func = function()
							return _("Refresh when showing cover") .. ": " .. (getRefreshMode() == "partial" and _("Partial") or _("Full"))
						end,
						keep_menu_open = true,
						hold_callback = function()
							UIManager:show(InfoMessage:new({
								text = _("Used when entering or leaving a book.\nInternal reloads (changing document settings) always use the non-flashing \"ui\" refresh."),
							}))
						end,
						sub_item_table = makeRefreshModeMenu(),
					},
					{
						text = _("Show label on cover"),
						keep_menu_open = true,
						sub_item_table = {
							{
								text = _("When opening"),
								checked_func = function()
									return shouldShowStatusLabel("open")
								end,
								keep_menu_open = true,
								callback = function(touchmenu_instance)
									saveSetting(Settings.status_label_open, not shouldShowStatusLabel("open"))
									if touchmenu_instance then
										touchmenu_instance:updateItems()
									end
								end,
							},
							{
								text = _("When closing"),
								checked_func = function()
									return shouldShowStatusLabel("close")
								end,
								keep_menu_open = true,
								callback = function(touchmenu_instance)
									saveSetting(Settings.status_label_close, not shouldShowStatusLabel("close"))
									if touchmenu_instance then
										touchmenu_instance:updateItems()
									end
								end,
								separator = true,
							},
							{
								text = _("Show book icon"),
								checked_func = shouldShowStatusIcon,
								keep_menu_open = true,
								callback = function(touchmenu_instance)
									saveSetting(Settings.status_icon, not shouldShowStatusIcon())
									if touchmenu_instance then
										touchmenu_instance:updateItems()
									end
								end,
							},
						},
					},
					{
						text = _("Centered card"),
						enabled_func = function()
							return getCoverLayoutMode() == LayoutMode.centered_card
						end,
						keep_menu_open = true,
						sub_item_table = {
							{
								text_func = function()
									return _("Size") .. ": " .. getCardSizePercent() .. "%"
								end,
								keep_menu_open = true,
								sub_item_table = makeCardSizeMenu(),
							},
							{
								text = _("Rounded corners"),
								checked_func = useRoundedCardCorners,
								keep_menu_open = true,
								callback = function(touchmenu_instance)
									saveSetting(Settings.card_rounded_corners, not useRoundedCardCorners())
									if touchmenu_instance then
										touchmenu_instance:updateItems()
									end
								end,
							},
						},
					},
				},
			},
			{
				text = _("Advanced"),
				keep_menu_open = true,
				sub_item_table = {
					{
						text = _("Extract cover directly from document when needed"),
						checked_func = shouldExtractFromDocument,
						keep_menu_open = true,
						callback = function(touchmenu_instance)
							saveSetting(Settings.extract_enabled, not shouldExtractFromDocument())
							if touchmenu_instance then
								touchmenu_instance:updateItems()
							end
						end,
					},
					{
						text = _("Show cover on internal reload/document switch"),
						checked_func = shouldShowOnTeardown,
						keep_menu_open = true,
						callback = function(touchmenu_instance)
							saveSetting(Settings.close_on_teardown, not shouldShowOnTeardown())
							if touchmenu_instance then
								touchmenu_instance:updateItems()
							end
						end,
					},
				},
			},
			{
				text_func = function()
					return _("Patch version") .. ": " .. PATCH_VERSION
				end,
				keep_menu_open = false,
				callback = showVersionInfo,
			},
		},
	}
end

local function registerMenuToMainMenu(menu)
	if not menu or not menu.registerToMainMenu or menu._bookloadcover_menu_registered then
		return
	end

	menu:registerToMainMenu(BookLoadCoverMenu)
	menu._bookloadcover_menu_registered = true
	menu.tab_item_table = nil
end

local function patchFileManagerMenu()
	local FileManagerMenu = safeRequire("apps/filemanager/filemanagermenu")
	if not FileManagerMenu or FileManagerMenu._original_init_bookloadcover then
		return
	end

	FileManagerMenu._original_init_bookloadcover = FileManagerMenu.init
	FileManagerMenu.init = function(self, ...)
		local ret = FileManagerMenu._original_init_bookloadcover(self, ...)
		registerMenuToMainMenu(self)
		return ret
	end
end

local function patchUIManagerShow()
	if UIManager._original_show_bookloadcover then
		return
	end

	UIManager._original_show_bookloadcover = UIManager.show

	UIManager.show = function(self, widget, ...)
		if
			not (isForeignClosingNotice(widget) and not shouldSuppressClosingNotice())
			and widgetLooksLikeClosingBookNotice(widget)
			and (State.suppress_closing_notice or shouldSuppressClosingNotice())
		then
			startSuppressingClosingNotice()
			return widget
		end

		return UIManager._original_show_bookloadcover(self, widget, ...)
	end
end

-- KOReader shows its own "Opening file…" notice (with a repaint) in showReader() BEFORE
-- showReaderCoroutine runs, so forcing seamless later is too late: that notice flashes
-- just before our cover appears. Force seamless here, at the entry point.
local function patchShowReader()
	if not ReaderUI.showReader or ReaderUI._original_showReader_bookloadcover then
		return
	end

	ReaderUI._original_showReader_bookloadcover = ReaderUI.showReader

	ReaderUI.showReader = function(self, file, provider, seamless, ...)
		if shouldUseSeamlessOpening() then
			seamless = true
		end
		return ReaderUI._original_showReader_bookloadcover(self, file, provider, seamless, ...)
	end
end

local function patchShowReaderCoroutine()
	if ReaderUI._original_showReaderCoroutine_bookloadcover then
		return
	end

	ReaderUI._original_showReaderCoroutine_bookloadcover = ReaderUI.showReaderCoroutine

	ReaderUI.showReaderCoroutine = function(self, file, provider, seamless)
		-- KOReader flags a document reload (e.g. triggered by changing a book
		-- setting like font, margins, etc.) by setting self.reloading = true
		-- on the new ReaderUI instance. Without this check, the opening cover
		-- would be shown on every such reload regardless of the
		-- "Show cover on internal reload/document switch" setting, since that
		-- setting was previously only honored on the closing side.
		local is_internal_reload = (self.reloading or self.tearing_down or State.reload_pending) and true or false
		State.reload_pending = false

		local cover_shown_on_open = false
		if shouldShowOpeningCover() and not (is_internal_reload and not shouldShowOnTeardown()) then
			local ok, result = pcall(showCover, file, {
				reason = "open",
				reload = is_internal_reload,
				allow_direct_extract = true,
			})
			if ok then
				cover_shown_on_open = result and true or false
			else
				warn("showCover failed", result)
			end
		end

		local final_seamless = seamless
		if shouldUseSeamlessOpening() then
			final_seamless = true
		end
		-- On an internal reload our cover + label is the only message: don't let KOReader
		-- add its own "Opening book…" notice on top.
		if is_internal_reload and cover_shown_on_open then
			final_seamless = true
		end

		return ReaderUI._original_showReaderCoroutine_bookloadcover(self, file, provider, final_seamless)
	end
end

-- Mark the whole close+reopen sequence of ReaderUI:reloadDocument() as an internal reload,
-- so onClose and showReaderCoroutine agree on it and only one cover/message is shown.
local function patchReloadDocument()
	if not ReaderUI.reloadDocument or ReaderUI._original_reloadDocument_bookloadcover then
		return
	end

	ReaderUI._original_reloadDocument_bookloadcover = ReaderUI.reloadDocument

	ReaderUI.reloadDocument = function(self, ...)
		State.reload_pending = true
		UIManager:scheduleIn(10, function()
			State.reload_pending = false
		end)
		return ReaderUI._original_reloadDocument_bookloadcover(self, ...)
	end
end

local function patchReaderInit()
	if ReaderUI._original_init_bookloadcover then
		return
	end

	ReaderUI._original_init_bookloadcover = ReaderUI.init

	ReaderUI.init = function(self, ...)
		local ret = ReaderUI._original_init_bookloadcover(self, ...)
		registerMenuToMainMenu(self.menu)
		scheduleCloseCover(getOpenCloseDelay())
		return ret
	end
end

local function patchReaderOnClose()
	if ReaderUI._original_onClose_bookloadcover then
		return
	end

	ReaderUI._original_onClose_bookloadcover = ReaderUI.onClose

	ReaderUI.onClose = function(self, full_refresh)
		local cover_shown = false
		local suppress_started = false

		-- Internal reload / document switch: onClose(false) or a tearing-down reader.
		-- reloadDocument() sets self.reloading. Do NOT use full_refresh == false here:
		-- Bookshelf also closes books with onClose(false).
		-- (also set by the reloadDocument wrapper below, in case self.reloading is not set)
		local is_reload = (self.reloading or State.reload_pending) and true or false
		if is_reload then
			State.reload_pending = true
			-- safety net: never let the flag leak into a later, unrelated opening
			UIManager:scheduleIn(10, function()
				State.reload_pending = false
			end)
		end

		if shouldSuppressClosingNotice() then
			startSuppressingClosingNotice()
			suppress_started = State.suppress_closing_notice
		end

		-- On a reload the cover is shown once, on the opening side (the end of the reload),
		-- instead of twice (close + open).
		if not is_reload and shouldShowClosingCover(self, full_refresh) then
			local ok, result = pcall(showCover, self.document.file, {
				reason = "close",
				reload = is_reload,
				open_document = self.document,
				font_face = self.font and self.font.font_face or nil,
				allow_direct_extract = false,
			})

			if ok then
				cover_shown = result
				if not cover_shown and not suppress_started then
					stopSuppressingClosingNotice()
				end
			else
				warn("showCover on close failed", result)
				if not suppress_started then
					stopSuppressingClosingNotice()
				end
			end
		end

		local ok, ret = pcall(function()
			return ReaderUI._original_onClose_bookloadcover(self, full_refresh)
		end)

		if cover_shown then
			scheduleCloseCover(getAfterCloseDelay())
		end

		if suppress_started or State.suppress_closing_notice then
			scheduleStopSuppressingClosingNotice(getClosingNoticeSuppressDelay())
		end

		if not ok then
			error(ret)
		end

		return ret
	end
end

ReaderUI = require("apps/reader/readerui")
patchUIManagerShow()
patchFileManagerMenu()
patchShowReader()
patchShowReaderCoroutine()
patchReloadDocument()
patchReaderInit()
patchReaderOnClose()

info("initialized successfully")
