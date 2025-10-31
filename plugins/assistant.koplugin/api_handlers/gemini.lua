local BaseHandler = require("api_handlers.base")
local json = require("json")
local koutil = require("util")
local logger = require("logger")

local GeminiHandler = BaseHandler:new()

function GeminiHandler:query(message_history, gemini_settings)

    if not gemini_settings or not gemini_settings.api_key then
        return "Error: Missing API key in configuration"
    end

    -- Gemini API requires messages with explicit roles
    local contents = {}
    local system_content = ""
    local generationConfig = nil

    for i, msg in ipairs(message_history) do
        if msg.role == "system" then
            system_content = system_content .. msg.content .. "\n"
        elseif msg.role == "user" then
            table.insert(contents, { role = "user", parts = {{ text = msg.content }} })
        elseif msg.role == "assistant" then
            table.insert(contents, { role = "model", parts = {{ text = msg.content }} })
        else
            -- Fallback for any other roles, mapping to 'user'
            table.insert(contents, { role = "user", parts = {{ text = msg.content }} })
        end
    end

    local system_instruction = nil
    if system_content ~= "" then
        system_instruction = { parts = {{ text = system_content:gsub("\n$", "") }} }
    end

    local thinking_budget = koutil.tableGetValue(gemini_settings, "additional_parameters", "thinking_budget")
    if thinking_budget ~= nil then
        generationConfig = generationConfig or {}
        generationConfig.thinking_config = { thinking_budget = thinking_budget }
    end

    local stream = koutil.tableGetValue(gemini_settings, "additional_parameters", "stream") or false

    local requestBodyTable = {
        contents = contents,
        system_instruction = system_instruction,
        safetySettings = {
            { category = "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_HATE_SPEECH", threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_HARASSMENT", threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_DANGEROUS_CONTENT", threshold = "BLOCK_NONE" }
        },
        generationConfig = generationConfig
    }
    -- a few more snake_case fields
    if gemini_settings.additional_parameters then
        for _, option in ipairs({"maxOutputTokens", "temperature", "topP", "topK"}) do
            if gemini_settings.additional_parameters[option] then
                generationConfig = generationConfig or {}
                generationConfig[option] = gemini_settings.additional_parameters[option]
            end
        end
    end

    local requestBody = json.encode(requestBodyTable)
    
    local headers = {
        ["Content-Type"] = "application/json",
        ["x-goog-api-key"] = gemini_settings.api_key,
    }

    local model = gemini_settings.model or "gemini-2.0-flash"
    local base_url = gemini_settings.base_url or "https://generativelanguage.googleapis.com/v1beta/models/"
    
    local url = string.format(stream and "%s%s:streamGenerateContent?alt=sse" or "%s%s:generateContent",
                base_url, model)
    logger.dbg("Making Gemini API request to model:", model)

    if stream then
        -- For streaming responses, we need to handle the response differently
        headers["Accept"] = "text/event-stream"
        return self:backgroundRequest(url, headers, requestBody)
    end
    
    local success, code, response = self:makeRequest(url, headers, requestBody)
    if not success then
        -- Handle user abort case
        if code == BaseHandler.CODE_CANCELLED then
            return nil, response
        end

        logger.warn("Gemini API request failed:", {
            error = response,
            model = model,
            base_url = base_url:gsub(gemini_settings.api_key, "***"), -- Hide API key in logs
            request_size = #requestBody,
            message_count = #message_history
        })
        return nil,"Error: Failed to connect to Gemini API - " .. tostring(response)
    end

    local success, parsed = pcall(json.decode, response)
    if not success then
        logger.warn("JSON Decode Error:", parsed)
        return nil,"Error: Failed to parse Gemini API response"
    end
    
    local content = koutil.tableGetValue(parsed, "candidates", 1, "content", "parts", 1, "text")
    if content then return content end

    local err_msg = koutil.tableGetValue(parsed, "error", "message")
    if err_msg then
        return nil, err_msg
    else
        return nil,"Error: Unexpected response format from Gemini API"
    end
end

return GeminiHandler