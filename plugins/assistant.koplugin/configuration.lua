local CONFIGURATION = {

    provider_settings = {
        gemini = {
            model = "gemini-2.5-flash",
            base_url = "https://generativelanguage.googleapis.com/v1beta/models/",
            api_key = "AIzaSyDuAQTXcBy_VXFS0s3jY7QktIZ0TBI1DII",
        },
        -- You can add other providers here, for example:
        -- openai = {
        --     model = "gpt-4o-mini",
        --     base_url = "https://api.openai.com/v1/chat/completions",
        --     api_key = "your-openai-api-key",
        -- }
    }
}
return CONFIGURATION
