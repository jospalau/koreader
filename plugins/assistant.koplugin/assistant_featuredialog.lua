local logger = require("logger")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local TextBoxWidget = require("ui/widget/textboxwidget")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local Event = require("ui/event")
local _ = require("assistant_gettext")
local T = require("ffi/util").template
local Trapper = require("ui/trapper")
local koutil = require("util")
local ChatGPTViewer = require("assistant_viewer")
local assistant_prompts = require("assistant_prompts").assistant_prompts
local NetworkMgr = require("ui/network/manager")
local assistant_utils = require("assistant_utils")
local extractBookTextForAnalysis = assistant_utils.extractBookTextForAnalysis
local extractHighlightsNotesAndNotebook = assistant_utils.extractHighlightsNotesAndNotebook
local normalizeMarkdownHeadings = assistant_utils.normalizeMarkdownHeadings

local function showFeatureDialog(assistant, feature_type, title, author, progress_percent, message_history)
    local CONFIGURATION = assistant.CONFIGURATION
    local Querier = assistant.querier
    local ui = assistant.ui

    -- Check if Querier is initialized
    local ok, err = Querier:load_model(assistant:getModelProvider())
    if not ok then
        UIManager:show(InfoMessage:new{ icon = "notice-warning", text = err })
        return
    end

    local formatted_progress_percent = string.format("%.2f", progress_percent * 100)
    local feature_title, loading_message, system_prompt, user_prompt_template, book_text, highlights_notes

    local language = assistant.settings:readSetting("response_language") or assistant.ui_language

    if type(feature_type) == "table" then
        -- Custom feature from configuration
        local custom_config = feature_type
        feature_title = custom_config.text or _("Custom Prompt")
        loading_message = custom_config.loading_message or _("Loading...")
        system_prompt = custom_config.system_prompt
        user_prompt_template = custom_config.user_prompt

        -- Handle use flags
        book_text = nil
        highlights_notes = nil
        if custom_config.use_book_text and custom_config.use_book_text == true then
            book_text = extractBookTextForAnalysis(CONFIGURATION, ui)
        end
        if custom_config.use_highlight_with_notebook and custom_config.use_highlight_with_notebook == true then
            highlights_notes = extractHighlightsNotesAndNotebook(CONFIGURATION, ui, true)
        elseif custom_config.use_highlight_without_notebook and custom_config.use_highlight_without_notebook == true then
            highlights_notes = extractHighlightsNotesAndNotebook(CONFIGURATION, ui, false)
        end
    else
        -- Original feature type handling
        -- Feature type configurations for easy extension
        local feature_configurations = {
            recap = {
                title = _("Recap"),
                loading_message = _("Loading Recap..."),
                config_key = "recap_config",
                prompts_key = "recap"
            },
            xray = {
                title = _("X‑Ray"),
                loading_message = _("Loading X-Ray..."),
                config_key = "xray_config",
                prompts_key = "xray"
            },
            book_info = {
                title = _("Book Information"),
                loading_message = _("Loading Book Information..."),
                config_key = "book_info_config",
                prompts_key = "book_info"
            },
            annotations = {
                title = _("Highlight & Note Analysis"),
                loading_message = _("Loading Highlight & Note Analysis..."),
                config_key = "annotations_config",
                prompts_key = "annotations"
            },
            summary_using_annotations = {
                title = _("Summary Using Highlights & Notes"),
                loading_message = _("Loading Summary Using Highlights & Notes..."),
                config_key = "summary_using_annotations_config",
                prompts_key = "summary_using_annotations"
            }
        }
        
        -- Get feature configuration
        local feature_config = feature_configurations[feature_type]
        if not feature_config then
            UIManager:show(InfoMessage:new{ 
                icon = "notice-warning", 
                text = string.format(_("Unknown feature type: %s"), feature_type) 
            })
            return
        end
        
        feature_title = feature_config.title
        loading_message = feature_config.loading_message
        local config_key = feature_config.config_key
        local prompts_key = feature_config.prompts_key
        
        -- Get feature CONFIGURATION with fallbacks
        local file_config = koutil.tableGetValue(CONFIGURATION, "features", config_key) or {}
        
        -- Prompts for feature (from config or prompts.lua)
        system_prompt = koutil.tableGetValue(file_config, "system_prompt")
            or koutil.tableGetValue(assistant_prompts, prompts_key, "system_prompt")

        user_prompt_template = koutil.tableGetValue(file_config, "user_prompt")
            or koutil.tableGetValue(assistant_prompts, prompts_key, "user_prompt")

        book_text = nil
        highlights_notes = nil
        if feature_type == "xray" or feature_type == "recap" then
          if assistant.settings:readSetting("use_book_text_for_analysis", false) then
            book_text = extractBookTextForAnalysis(CONFIGURATION, ui)
          end
        elseif feature_type == "annotations" then
          highlights_notes = extractHighlightsNotesAndNotebook(CONFIGURATION, ui,true)
        elseif feature_type == "summary_using_annotations" then
          book_text = extractBookTextForAnalysis(CONFIGURATION, ui)
          highlights_notes = extractHighlightsNotesAndNotebook(CONFIGURATION, ui,false)
        end
    end

    if assistant.settings:readSetting("auto_prompt_suggest", false) then
      local suggestions_prompt = assistant_prompts.suggestions_prompt:gsub("{(%w+)}", {language = language})
      system_prompt = system_prompt .. suggestions_prompt
    end
    
    local book_text_prompt = ""
    if book_text then
        book_text_prompt = string.format("\n\n[! IMPORTANT !] Here is the book text up to my current position, only consider this text for your response:\n [BOOK TEXT BEGIN]\n%s\n[BOOK TEXT END]", book_text)
    end

    local highlights_notes_prompt = ""
    if highlights_notes and highlights_notes ~= "" then
        highlights_notes_prompt = string.format("\n\n[BOOK HIGHLIGHTS, NOTES AND NOTEBOOK CONTENT BEGIN]\n%s\n[BOOK HIGHLIGHTS, NOTES AND NOTEBOOK CONTENT END]", highlights_notes)
    end

    local message_history = message_history or {
        {
            role = "system",
            content = system_prompt,
        },
    }
    
    -- Format the user prompt with variables
    local user_content = user_prompt_template:gsub("{(%w+)}", {
      title = title,
      author = author,
      progress = formatted_progress_percent,
      language = language
    })

    user_content = user_content .. book_text_prompt .. highlights_notes_prompt
    
    local context_message = {
        role = "user",
        content = user_content
    }
    table.insert(message_history, context_message)

    local function createResultText(answer)
      local normalized_answer = normalizeMarkdownHeadings(answer, 2, 6) or answer
      local result_text = 
        TextBoxWidget.PTF_HEADER ..
        TextBoxWidget.PTF_BOLD_START .. title .. TextBoxWidget.PTF_BOLD_END .. " by " .. author .. " is " .. formatted_progress_percent .. "% complete.\n\n" ..  normalized_answer
      return result_text
    end

    local function prepareMessageHistoryForAdditionalQuestion(message_history, user_question, title, author)
      local context = {
        role = "user",
        content = string.format("I'm reading something titled '%s' by %s. Only answer the following question, do not add any additional information or context that is not directly related to the question, the question is: %s", title, author, user_question)
      }
      table.insert(message_history, context)
    end

    local answer, err = Querier:query(message_history, loading_message)
    if err then
      assistant.querier:showError(err)
      return
    end

    table.insert(message_history, {
      role = "assistant",
      content = answer
    })

    local chatgpt_viewer
    chatgpt_viewer = ChatGPTViewer:new {
      assistant = assistant,
      ui = ui,
      title = feature_title,
      text = createResultText(answer),
      disable_add_note = true,
      message_history = message_history,
      onAskQuestion = function(viewer, user_question)
        local viewer_title = ""

        if type(user_question) == "string" then
          prepareMessageHistoryForAdditionalQuestion(message_history, user_question, title, author)
        elseif type(user_question) == "table" then
          viewer_title = user_question.text or "Custom Prompt"
          table.insert(message_history, {
            role = "user",
            content = string.format("I'm reading something titled '%s' by %s. Only answer the following question, do not add any additional information or context that is not directly related to the question, the question is: %s", title, author, user_question.user_prompt or user_question)
          })
        end

        viewer:trimMessageHistory()
        NetworkMgr:runWhenOnline(function()
          Trapper:wrap(function()
            local answer, err = Querier:query(message_history)
            
            if err then
              Querier:showError(err)
              return
            end
            
            table.insert(message_history, {
              role = "assistant",
              content = answer
            })
            local normalized_answer = normalizeMarkdownHeadings(answer, 3, 6) or answer
            local additional_text = "\n\n### ⮞ User: \n" .. (type(user_question) == "string" and user_question or (user_question.text or user_question)) .. "\n\n### ⮞ Assistant:\n" .. normalized_answer
            viewer:update(viewer.text .. additional_text)
            
            if viewer.scroll_text_w then
              viewer.scroll_text_w:resetScroll()
            end
          end)
        end)
      end,
      default_hold_callback = function ()
        chatgpt_viewer:HoldClose()
      end,
    }

    UIManager:show(chatgpt_viewer)
end

return showFeatureDialog
