local Screen = require("device").screen
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local ButtonTable = require("ui/widget/buttontable")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local Assets = require("wordreference_assets")
local Event = require("ui/event")
local Translator = require("ui/translator")
local _ = require("gettext")

local Dialog = {}

function Dialog:makeSettings(ui, items)
	local centered_container

	local hasProjectTitlePlugin = ui["coverbrowser"] ~= nil and ui["coverbrowser"].fullname:find("Project")

	local menu = Menu:new{
		title = _("WordReference"),
		item_table = items,
		width = Screen:getWidth(), -- hasProjectTitlePlugin and Screen:getWidth() or math.min(Screen:getWidth() * 0.6, Screen:scaleBySize(400)),
		height = Screen:getHeight(), -- hasProjectTitlePlugin and Screen:getHeight() or Screen:getHeight() * 0.9,
		is_popout = false,
		close_callback = function()
			UIManager:close(centered_container)
		end
	}

	centered_container = CenterContainer:new{
		dimen = {
			x = 0,
			y = 0,
			w = Screen:getWidth(),
			h = Screen:getHeight()
		},
		menu,
	}

	menu.show_parent = centered_container

	return centered_container
end

function Dialog:makeDefinition(ui, phrase, html_content, copyright, close_callback)
    local definition_dialog

    local window_w = math.floor(Screen:getWidth() * 0.8)
    local window_h = math.floor(Screen:getHeight() * 0.8)

    local titlebar = TitleBar:new {
        title = copyright,
        width = window_w,
        align = "left",
        with_bottom_line = true,
        title_shrink_font_to_fit = true,
        close_callback = function()
            UIManager:close(definition_dialog)
            if close_callback then
                close_callback()
            end
        end,
        left_icon = "appbar.settings",
        left_icon_tap_callback = function()
            local WordReference = require("wordreference")
            WordReference:showLanguageSettings(ui, function()
                UIManager:close(definition_dialog)
                if close_callback then
                    close_callback()
                end
            end)
        end,
        show_parent = self,
    }

    local available_height = window_h
    local tb_size = titlebar:getSize() or { h = 0 }
    if tb_size and tb_size.h then
        available_height = math.max(0, available_height - tb_size.h)
    end

    local html_widget = ScrollHtmlWidget:new{
        html_body = string.format('<div class="wr">%s</div>', html_content),
        css = Assets:getDefinitionTablesStylesheet(),
        default_font_size = Screen:scaleBySize(14),
        width = window_w,
        height = available_height,
    }

    local bottom_buttons = {}
    local VocabBuilder = ui["vocabbuilder"]
    if VocabBuilder then
        VocabBuilder:onDictButtonsReady(ui, bottom_buttons)
    end
    table.insert(bottom_buttons, {
        {
            id = "wikipedia",
            text = _("Wikipedia"),
            callback = function()
                UIManager:nextTick(function()
                    UIManager:close(definition_dialog)
                    if close_callback then close_callback() end
                    UIManager:setDirty("widget", "ui")
                    ui:handleEvent(Event:new("LookupWikipedia", phrase))
                end)
            end
        },
        {
            id = "dictionary",
            text = _("Dictionary"),
            callback = function()
                UIManager:nextTick(function()
                    UIManager:close(definition_dialog)
                    if close_callback then close_callback() end
                    UIManager:setDirty("widget", "ui")
                    ui.dictionary:onLookupWord(phrase, false, nil)
                end)
            end
        },
        {
            id = "translate",
            text = _("Translate"),
            callback = function()
                UIManager:nextTick(function()
                    UIManager:close(definition_dialog)
                    if close_callback then close_callback() end
                    UIManager:setDirty("widget", "ui")
                    Translator:showTranslation(phrase, true, nil, nil, true, nil)
                end)
            end
        },
    })
    ui:handleEvent(Event:new("WordReferenceDefinitionButtonsReady", ui, bottom_buttons))

    local button_table = ButtonTable:new{
        width = window_w,
        buttons = bottom_buttons,
        zero_sep = true,
        show_parent = self,
    }

    local WidgetContainer = require("ui/widget/container/widgetcontainer")

    local content_container = FrameContainer:new {
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new {
            titlebar,
            html_widget,
            #bottom_buttons > 0 and button_table or nil,
        }
    }

    local MovableContainer = require("ui/widget/container/movablecontainer")
    local movable = MovableContainer:new {
        --ignore_events = { "swipe","hold","hold_release","hold_pan","touch","pan","pan_release" },
        is_movable_with_keys = false,
        content_container,
    }

    local positioned_container = WidgetContainer:new {
        align = "center",
        dimen = { x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
        movable,
    }

    definition_dialog = InputContainer:new {
        dimen = { x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
        positioned_container,
    }

    local function point_inside_rect(x, y, rect)
        return x >= rect.x and x < (rect.x + rect.w)
        and y >= rect.y and y < (rect.y + rect.h)
    end

    definition_dialog:registerTouchZones({
        {
            id = "wordreference_tap_outside",
            ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges)
                if not point_inside_rect(ges.pos.x, ges.pos.y, content_container.dimen) then
                    UIManager:close(definition_dialog)
                    return true
                end
                return false
            end,
        },
    })

    html_widget.dialog = definition_dialog
    if VocabBuilder then
        ui.ui = ui
        ui.button_table = button_table
        ui.lookupword = phrase
    end

    return definition_dialog
end

return Dialog
