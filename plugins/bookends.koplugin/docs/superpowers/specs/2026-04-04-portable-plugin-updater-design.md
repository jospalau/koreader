# Portable KOReader Plugin Updater

**Date:** 2026-04-04
**Status:** Approved

## Overview

Extract the Bookends update system (`checkForUpdates` + `installUpdate`, ~235 lines in `main.lua`) into a standalone, reusable Lua module that any KOReader plugin can drop in and configure with three fields.

## Motivation

KOReader has no built-in plugin update mechanism. Plugins that want self-update must implement GitHub API calls, version comparison, download, extraction, and UI from scratch. The Bookends implementation is proven and well-structured — making it portable lets other plugin authors reuse it.

## Design

### File

`pluginupdater.lua` at the root of `bookends.koplugin/`. Plugin authors copy this single file into their own `.koplugin` directory.

### Consumer API

```lua
local PluginUpdater = require("pluginupdater")

local updater = PluginUpdater:new{
    repo = "AndyHazz/bookends.koplugin",  -- GitHub owner/repo (required)
    plugin_dir = "bookends.koplugin",      -- directory name under plugins/ (required)
    display_name = "Bookends",             -- human-readable name for UI (required)
}

-- Menu entry:
{ text = _("Check for updates"), callback = function() updater:check() end }
```

### Public Methods

| Method | Description |
|---|---|
| `PluginUpdater:new(config)` | Validates required fields (`repo`, `plugin_dir`, `display_name`), stores config, returns instance |
| `updater:check()` | Full update check flow: WiFi guard → toast → GitHub API → version compare → changelog viewer with "Update and restart" button |
| `updater:install(zip_url, old_ver, new_ver)` | Download ZIP → extract with strip-root → restart prompt. Called internally by the changelog viewer's update button; exposed for flexibility but not expected to be called directly. |

### Private Helpers

- `githubGet(url, user_agent)` — GitHub API GET with socketutil timeouts, returns decoded JSON or nil
- `parseVersion(v)` — strips leading `v`, splits on `.`, returns table of integers
- `isNewer(v1, v2)` — component-by-component numeric comparison
- `stripMarkdown(text)` — removes `#` headings, `**bold**`, `*italic*`, `` `code` ``

### Derived Paths

All paths are derived from the `plugin_dir` config field:

| Value | Derivation |
|---|---|
| Meta path | `"plugins/" .. plugin_dir .. "/_meta.lua"` |
| Cache dir | `DataStorage:getSettingsDir() .. "/" .. plugin_dir .. "_cache"` |
| Install path | `DataStorage:getDataDir() .. "/plugins/" .. plugin_dir` |
| User-Agent | `"KOReader-" .. display_name .. "/" .. version` |

### Consumer Convention

Plugins must have a `_meta.lua` at their root returning a table with a `version` field (semver string, e.g. `"2.5.4"`). This is already the Bookends pattern.

### KOReader API Dependencies

| API | Module | Used For |
|---|---|---|
| `UIManager:show/close/scheduleIn/restartKOReader` | `ui/uimanager` | Widget display, deferred execution, restart |
| `NetworkMgr:isWifiOn()` | `ui/network/manager` | WiFi guard |
| `DataStorage:getSettingsDir/getDataDir` | `datastorage` | Path resolution |
| `Device:unpackArchive()` | global | ZIP extraction |
| `InfoMessage`, `ConfirmBox`, `TextViewer` | `ui/widget/*` | UI dialogs |
| `socket/http`, `ltn12`, `socket`, `socketutil` | KOReader bundled | HTTP requests |
| `json` | KOReader bundled | Response parsing |
| `libs/libkoreader-lfs` | KOReader bundled | Directory creation |

## Changes to Bookends

- **New file:** `pluginupdater.lua` — the portable module
- **Modified:** `main.lua` — delete `checkForUpdates()` (lines 2973–3129) and `installUpdate()` (lines 3131–3208), replace with:
  - A `require("pluginupdater")` call and `PluginUpdater:new{...}` in init or at module scope
  - The existing menu entry's callback changes from `self:checkForUpdates()` to `updater:check()`

No behavior change for end users.

## Out of Scope

- Auto-check on startup or periodic background checks
- Update frequency tracking / "last checked" timestamp
- Pre-release channel support
- Post-update migration hooks / callbacks
- Pagination of GitHub releases API (stays at default 30)

These can be added in future versions if real usage demands them.
