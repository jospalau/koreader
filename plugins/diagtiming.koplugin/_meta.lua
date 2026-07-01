-- plugins/diagtiming.koplugin/_meta.lua
local _ = require("gettext")
return {
    name = "diagtiming",
    fullname = _("Diagnostic timing (temporary)"),
    description = _("Logs slow require() calls and slow event dispatches. Remove after debugging."),
}
