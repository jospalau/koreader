# Portable Plugin Updater Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the Bookends update system into a standalone, reusable `pluginupdater.lua` module, then refactor Bookends to consume it with no user-facing behavior change.

**Architecture:** Single new file `pluginupdater.lua` encapsulates all update logic. Configured via a constructor table with `repo`, `plugin_dir`, and `display_name`. Bookends `main.lua` deletes its inline update functions and replaces them with a 5-line consumer of the new module.

**Tech Stack:** Lua (KOReader runtime), GitHub REST API v3, KOReader widget APIs

---

### Task 1: Create `pluginupdater.lua` module

**Files:**
- Create: `pluginupdater.lua`

This is the core extraction. The module is a self-contained Lua table with `:new()`, `:check()`, and `:install()` methods, plus private helpers.

- [ ] **Step 1: Create the module file with constructor and helpers**

Create `pluginupdater.lua` with the following content. This is a direct extraction from `main.lua:2996-3231` with hardcoded values replaced by `self.*` config fields:

```lua
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local _ = require("gettext")

local PluginUpdater = {}

--- Create a new PluginUpdater instance.
-- @param config table with required fields:
--   repo         (string) GitHub "owner/repo"
--   plugin_dir   (string) directory name under plugins/, e.g. "myplugin.koplugin"
--   display_name (string) human-readable name for UI strings
function PluginUpdater:new(config)
    assert(config.repo, "PluginUpdater: 'repo' is required")
    assert(config.plugin_dir, "PluginUpdater: 'plugin_dir' is required")
    assert(config.display_name, "PluginUpdater: 'display_name' is required")
    local o = setmetatable({}, { __index = self })
    o.repo = config.repo
    o.plugin_dir = config.plugin_dir
    o.display_name = config.display_name
    return o
end

-- Private: GET a GitHub API endpoint, return decoded JSON or nil.
local function githubGet(url, user_agent)
    local http = require("socket/http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local json = require("json")

    local body = {}
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local code = socket.skip(1, http.request({
        url = url,
        method = "GET",
        headers = {
            ["User-Agent"] = user_agent,
            ["Accept"] = "application/vnd.github.v3+json",
        },
        sink = ltn12.sink.table(body),
        redirect = true,
    }))
    socketutil:reset_timeout()
    if code ~= 200 then return nil end
    local ok, data = pcall(json.decode, table.concat(body))
    return ok and data or nil
end

-- Private: Parse a version string like "v2.5.4" into {2, 5, 4}.
local function parseVersion(v)
    local parts = {}
    for part in tostring(v):gsub("^v", ""):gmatch("([^.]+)") do
        table.insert(parts, tonumber(part) or 0)
    end
    return parts
end

-- Private: Return true if version string v1 is newer than v2.
local function isNewer(v1, v2)
    local a, b = parseVersion(v1), parseVersion(v2)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x > y then return true end
        if x < y then return false end
    end
    return false
end

-- Private: Strip basic Markdown formatting for plain-text display.
local function stripMarkdown(text)
    text = text:gsub("#+%s*", "")
    text = text:gsub("%*%*(.-)%*%*", "%1")
    text = text:gsub("%*(.-)%*", "%1")
    text = text:gsub("`(.-)`", "%1")
    return text
end

--- Check GitHub for updates and show a changelog viewer if one is available.
function PluginUpdater:check()
    local meta = dofile("plugins/" .. self.plugin_dir .. "/_meta.lua")
    local installed_version = meta and meta.version or "unknown"

    local NetworkMgr = require("ui/network/manager")
    if not NetworkMgr:isWifiOn() then
        UIManager:show(InfoMessage:new{
            text = _("Wi-Fi is not enabled."),
            timeout = 3,
        })
        return
    end

    UIManager:show(InfoMessage:new{
        text = _("Checking for updates…"),
        timeout = 1,
    })

    local self_ = self
    local user_agent = "KOReader-" .. self.display_name .. "/" .. installed_version

    UIManager:scheduleIn(0.1, function()
        local releases = githubGet(
            "https://api.github.com/repos/" .. self_.repo .. "/releases",
            user_agent
        )
        if not releases or #releases == 0 then
            UIManager:show(InfoMessage:new{
                text = _("Could not check for updates."),
                timeout = 3,
            })
            return
        end

        local new_releases = {}
        local latest_zip_url
        for _, rel in ipairs(releases) do
            if rel.draft or rel.prerelease then goto continue end
            local ver = rel.tag_name:gsub("^v", "")
            if isNewer(ver, installed_version) then
                table.insert(new_releases, rel)
                if not latest_zip_url and rel.assets then
                    for _, asset in ipairs(rel.assets) do
                        if asset.name:match("%.zip$") then
                            latest_zip_url = asset.browser_download_url
                            break
                        end
                    end
                end
            end
            ::continue::
        end

        if #new_releases == 0 then
            UIManager:show(InfoMessage:new{
                text = self_.display_name .. _(" is up to date.") .. "\n\n" ..
                    _("Version: ") .. "v" .. installed_version,
                timeout = 3,
            })
            return
        end

        local latest_version = new_releases[1].tag_name:gsub("^v", "")
        local notes = {}
        for _, rel in ipairs(new_releases) do
            local header = "v" .. rel.tag_name:gsub("^v", "")
            local body = stripMarkdown(rel.body or "")
            table.insert(notes, header .. "\n" .. body)
        end
        local all_notes = table.concat(notes, "\n\n")

        local TextViewer = require("ui/widget/textviewer")
        local viewer
        local buttons = {
            {
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(viewer)
                    end,
                },
                {
                    text = _("Update and restart"),
                    callback = function()
                        UIManager:close(viewer)
                        if not latest_zip_url then
                            UIManager:show(InfoMessage:new{
                                text = _("No download available for this release."),
                                timeout = 3,
                            })
                            return
                        end
                        self_:install(latest_zip_url, installed_version, latest_version)
                    end,
                },
            },
        }
        viewer = TextViewer:new{
            title = _("Update available!"),
            text = _("Installed: ") .. "v" .. installed_version .. "\n" ..
                _("Latest: ") .. "v" .. latest_version .. "\n\n" ..
                all_notes,
            buttons_table = buttons,
            add_default_buttons = false,
        }
        UIManager:show(viewer)
    end)
end

--- Download a ZIP release asset, extract it over the plugin directory, and offer restart.
function PluginUpdater:install(zip_url, old_version, new_version)
    local DataStorage = require("datastorage")
    local lfs = require("libs/libkoreader-lfs")
    local Device = require("device")

    UIManager:show(InfoMessage:new{
        text = _("Downloading update…"),
        timeout = 1,
    })

    local self_ = self
    local user_agent = "KOReader-" .. self.display_name .. "/" .. old_version

    UIManager:scheduleIn(0.1, function()
        local http = require("socket/http")
        local ltn12 = require("ltn12")
        local socket = require("socket")
        local socketutil = require("socketutil")

        local cache_dir = DataStorage:getSettingsDir() .. "/" .. self_.plugin_dir .. "_cache"
        if lfs.attributes(cache_dir, "mode") ~= "directory" then
            lfs.mkdir(cache_dir)
        end
        local zip_path = cache_dir .. "/" .. self_.plugin_dir .. ".zip"

        local file = io.open(zip_path, "wb")
        if not file then
            UIManager:show(InfoMessage:new{
                text = _("Could not save download."),
                timeout = 3,
            })
            return
        end

        socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
        local code = socket.skip(1, http.request({
            url = zip_url,
            method = "GET",
            headers = {
                ["User-Agent"] = user_agent,
            },
            sink = ltn12.sink.file(file),
            redirect = true,
        }))
        socketutil:reset_timeout()

        if code ~= 200 then
            pcall(os.remove, zip_path)
            UIManager:show(InfoMessage:new{
                text = _("Download failed."),
                timeout = 3,
            })
            return
        end

        local plugin_path = DataStorage:getDataDir() .. "/plugins/" .. self_.plugin_dir
        local ok, err = Device:unpackArchive(zip_path, plugin_path, true)
        pcall(os.remove, zip_path)

        if not ok then
            UIManager:show(InfoMessage:new{
                text = _("Installation failed: ") .. tostring(err),
                timeout = 5,
            })
            return
        end

        UIManager:show(ConfirmBox:new{
            text = self_.display_name .. _(" updated to v") .. new_version .. ".\n\n" ..
                _("Restart KOReader now?"),
            ok_text = _("Restart"),
            ok_callback = function()
                UIManager:restartKOReader()
            end,
        })
    end)
end

return PluginUpdater
```

- [ ] **Step 2: Verify the file loads without syntax errors**

Run:
```bash
luac -p pluginupdater.lua
```

Expected: no output (clean parse).

- [ ] **Step 3: Commit**

```bash
git add pluginupdater.lua
git commit -m "feat: add portable plugin updater module"
```

---

### Task 2: Refactor Bookends to consume `pluginupdater.lua`

**Files:**
- Modify: `main.lua:24-25` (add require after ConfirmBox)
- Modify: `main.lua:1265-1269` (update menu callback)
- Delete: `main.lua:2996-3231` (inline update functions)

- [ ] **Step 1: Add the updater require and instance near the top of `main.lua`**

After the existing requires (around line 25, after the `ConfirmBox` require), add:

```lua
local PluginUpdater = require("pluginupdater")
local updater = PluginUpdater:new{
    repo = "AndyHazz/bookends.koplugin",
    plugin_dir = "bookends.koplugin",
    display_name = "Bookends",
}
```

- [ ] **Step 2: Update the menu callback**

Change the "Check for updates" menu entry at line ~1265 from:

```lua
{
    text = _("Check for updates"),
    keep_menu_open = true,
    callback = function()
        self:checkForUpdates()
    end,
},
```

To:

```lua
{
    text = _("Check for updates"),
    keep_menu_open = true,
    callback = function()
        updater:check()
    end,
},
```

- [ ] **Step 3: Delete `Bookends:checkForUpdates()` and `Bookends:installUpdate()`**

Delete the entire block from line 2996 (`function Bookends:checkForUpdates()`) through line 3231 (end of `function Bookends:installUpdate()`). This is ~235 lines.

- [ ] **Step 4: Verify syntax**

Run:
```bash
luac -p main.lua
```

Expected: no output (clean parse).

- [ ] **Step 5: Commit**

```bash
git add main.lua
git commit -m "refactor: use portable PluginUpdater module in Bookends"
```

---

### Task 3: Handle the `gettext` require difference

**Files:**
- Modify: `pluginupdater.lua:3` (fix gettext require)

The Bookends `main.lua` uses `require("i18n").gettext` (its own local translation wrapper), but a portable module should use KOReader's global `require("gettext")` so it works in any plugin without depending on Bookends' `i18n.lua`.

- [ ] **Step 1: Verify which gettext the module uses**

Check the current require in `pluginupdater.lua` line 3. It should already say:

```lua
local _ = require("gettext")
```

If it says `require("i18n").gettext`, change it to `require("gettext")`. This uses KOReader's global gettext, which is the standard convention for KOReader modules.

- [ ] **Step 2: Verify syntax**

Run:
```bash
luac -p pluginupdater.lua
```

- [ ] **Step 3: Commit if changed**

```bash
git add pluginupdater.lua
git commit -m "fix: use KOReader global gettext in pluginupdater"
```

---

### Task 4: Manual on-device test

**Files:** None (testing only)

- [ ] **Step 1: Push to Kindle**

```bash
scp -r /home/andyhazz/projects/bookends.koplugin/ kindle:/mnt/us/koreader/plugins/bookends.koplugin/
```

- [ ] **Step 2: Open KOReader and test the update check**

1. Open any book
2. Long-press bottom bar → Bookends settings → "Check for updates"
3. Verify it shows the current version as up-to-date (or shows a changelog if there's a newer release)
4. Verify the WiFi-off guard still works (disable WiFi, try again)

- [ ] **Step 3: Commit final state if any fixups were needed**

```bash
git add -A
git commit -m "fix: address on-device testing feedback"
```
