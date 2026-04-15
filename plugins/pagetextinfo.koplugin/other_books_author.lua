local logger = require("logger")
logger.info("Applying reading hours patch")

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local ReaderUI = require("apps/reader/readerui")
local Screen = Device.screen
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local ShowOtherBooksAuthorWindow = InputContainer:extend({
	modal = true,
	name = "show_other_books_author_window",
})

function ShowOtherBooksAuthorWindow:init()
	self.show_all_days = G_reader_settings:readSetting("reading_hours_show_all_days") or false
	local screen_width = Screen:getWidth()
	local screen_height = Screen:getHeight()
	local w_width = math.floor(screen_width * 0.7)
	if screen_width > screen_height then
		w_width = math.floor(w_width * screen_height / screen_width)
	end

	local w_font = {
		face = "cfont",
		size = { big = 22, med = 18, small = 15 },
		color = {
			black = Blitbuffer.COLOR_BLACK,
			gray = Blitbuffer.COLOR_GRAY_4,
		},
	}

	local w_padding = {
		internal = Screen:scaleBySize(10),
		external = Screen:scaleBySize(10),
	}

	local function vertical_spacing(h)
		h = h or 1
		return VerticalSpan:new({ width = math.floor(w_padding.internal * h) })
	end


	local function buildWindow()
		local scrollbar_width = ScrollableContainer:getScrollbarWidth()
		local content_width = w_width - scrollbar_width
		local scrollbar_width = ScrollableContainer:getScrollbarWidth()
        local padding = w_padding.external * 2
        local bar_max_width = w_width - scrollbar_width - padding
		local rows = VerticalGroup:new({})

        local ui = require("apps/reader/readerui").instance
        local current_author = ui.document._document:getDocumentProps().authors

        if current_author and current_author:match("%.$") then
            current_author = current_author:sub(1, -2) .. "_"
        end

        local lfs = require("libs/libkoreader-lfs")

        local books_dir = G_reader_settings:readSetting("home_dir") .. "/" .. current_author

        local files = {}
        for file in lfs.dir(books_dir) do
            if file and file:match("%.epub$") then
                table.insert(files, file)
            end
        end

        table.sort(files, function(a, b)
            return a:lower() < b:lower()
        end)
		for _, file in ipairs(files) do
			local txt = file:match("^(.-)%s*%-") or file
            txt = txt:gsub("%.epub$", "")


            local text_widget = TextWidget:new({
                text = txt,
                face = Font:getFace(w_font.face, w_font.size.small),
                max_width = bar_max_width,
                ellipsis = true,
            })

            local row = HorizontalGroup:new({
                align = "center",

                LeftContainer:new({
                    dimen = Geom:new({ w = bar_max_width, h = Screen:scaleBySize(20) }),
                    text_widget,
                }),

                HorizontalSpan:new({ width = Screen:scaleBySize(10) }),

            })

			table.insert(rows, row)
			table.insert(rows, vertical_spacing(0.5))
		end

        local datetime = require("datetime")
        local read_book = ""
        local ui = require("apps/reader/readerui").instance
        local user_duration_format = "modern"
        read_book = ui.view.topbar.initial_total_time_book + (os.time() - ui.view.topbar.start_session_time)

        local percentage_read = ui.view.footer.pageno / ui.view.footer.pages
        local Math = require("optmath")
        local words_read = Math.round(ui.view.topbar.total_words * percentage_read)
        local wpm =  math.floor(words_read / (read_book/60))
        read_book = read_book > 86400 and math.floor(read_book/60/60/24 * 100)/100 .. "d" or datetime.secondsToClockDuration(user_duration_format, read_book, false)

        current_author = current_author and current_author:gsub("^%s*(.-),%s*(.+)%s*$", "%2 %1") or current_author
        local title_widget = TextWidget:new{
            text = current_author .. " other books",
            face = Font:getFace("cfont", 18),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
            align = "center",
        }

		local title = FrameContainer:new({
            dimen = Geom:new({
                w = w_width,
                h = title_widget:getSize().h,
            }),
            bordersize = 0,
            padding = 0,
            title_widget,
        })

		local row_height = Screen:scaleBySize(20) + math.floor(w_padding.internal * 0.5)
		local num_items = #files
		local scrollable_height
		if num_items <= 10 then
			scrollable_height = num_items * row_height
		else
			scrollable_height = 10 * row_height
		end

		local scrollable = ScrollableContainer:new({
			dimen = Geom:new({
				w = w_width,
				h = scrollable_height,
			}),
			show_parent = self,
			rows,
		})

        local info = HorizontalGroup:new({
            align = "center",
            LeftContainer:new({
                dimen = Geom:new({ w = scrollable:getSize().w, h = Screen:scaleBySize(20) }),
                TextWidget:new{
                    text = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")) .. " - " .. read_book .. " - " .. wpm .. "wpm",
                    face = Font:getFace("cfont", 16),
                    bold = false,
                },
                -- HorizontalSpan:new({ width = scrollable:getSize().w }),
            }),
        })

		return VerticalGroup:new({
			title,
            -- info,
			vertical_spacing(),
			scrollable,
		})
	end

	local content, error_msg = buildWindow()

	if not content then
		UIManager:show(InfoMessage:new({ text = _(error_msg or "Unknown error") }))
		return
	end

	local frame = FrameContainer:new({
		radius = Screen:scaleBySize(22),
		bordersize = Screen:scaleBySize(2),
		padding = w_padding.external,
		background = Blitbuffer.COLOR_WHITE,
		content,
	})

	self[1] = CenterContainer:new({
		dimen = Screen:getSize(),
		frame,
	})

	self.dimen = Geom:new({
		x = 0,
		y = 0,
		w = screen_width,
		h = screen_height,
	})

	local frame_dimen = frame:getSize()
	local toggle_size = Screen:scaleBySize(30)
	local toggle_padding = w_padding.external
	self.toggle_area = Geom:new({
		x = (screen_width - frame_dimen.w) / 2 + frame_dimen.w - toggle_size - toggle_padding,
		y = (screen_height - frame_dimen.h) / 2 + toggle_padding,
		w = toggle_size + toggle_padding,
		h = toggle_size + toggle_padding,
	})

	if Device:hasDPad() then
		self.key_events.Close = { { Device.input.group.Back } }
	end
	if Device:isTouchDevice() then
		self.ges_events.TapClose = {
			GestureRange:new({
				ges = "tap",
				range = self.dimen,
			}),
		}
	end
end

function ShowOtherBooksAuthorWindow:onShow()
	UIManager:setDirty(self, function()
		return "ui", self[1][1].dimen
	end)
	return true
end

function ShowOtherBooksAuthorWindow:onClose()
	UIManager:close(self)
	return true
end

function ShowOtherBooksAuthorWindow:onToggle()
	local new_state = not self.show_all_days
	G_reader_settings:saveSetting("reading_hours_show_all_days", new_state)
	UIManager:close(self)
	UIManager:show(ShowOtherBooksAuthorWindow:new(), "ui")
end

function ShowOtherBooksAuthorWindow:onTapClose(arg, ges_ev)
	if ges_ev and ges_ev.pos and self.toggle_area:contains(ges_ev.pos) then
		self:onToggle()
	else
		self:onClose()
	end
	return true
end

Dispatcher:registerAction("show_other_books_author", {
	category = "none",
	event = "ShowOtherBooksAuthor",
	title = _("Show other books author"),
	general = true,
})

function ReaderUI:onShowOtherBooksAuthor()
	if self.statistics then
		self.statistics:insertDB()
	end
	local widget = ShowOtherBooksAuthorWindow:new()
	UIManager:show(widget, "ui", widget.dimen)
end

logger.info("Other books author patch applied")
