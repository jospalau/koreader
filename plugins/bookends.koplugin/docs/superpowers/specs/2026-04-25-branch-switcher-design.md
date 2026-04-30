# Development branch switcher — design

## Motivation

Bookends ships via tagged GitHub releases through the existing in-plugin updater (`bookends_updater.lua`). When testing fixes / features that aren't yet ready for a release, today's options are:

1. SSH into the Kindle and `tar`-pipe a working tree across (the maintainer's dev loop, only viable on home network).
2. Cut a release candidate tag and ask testers to install it via the regular update flow (visible in the public release history forever, even when the work doesn't pan out).
3. Ask testers to clone the repo and copy files manually (out of reach for most users).

None of these scale to "I have an idea on a branch, would a couple of testers try it?" — which is the practical case the maintainer keeps hitting (e.g. paradox460 testing list-token features on his Boox; the maintainer testing presets while away from home network).

The existing updater already does the hard work: HTTP fetch (LuaSocket with curl SSL fallback), zip download, archive unpack with strip-root, restart prompt. The branch switcher is a thin layer that lets the same install pipeline pull from a non-default URL.

## Scope

**In scope:**

1. A persisted "Development branch" setting (string, empty by default) tucked under a new **Settings → Advanced** submenu.
2. URL composition: empty setting → existing latest-release flow unchanged; non-empty → `https://github.com/AndyHazz/bookends.koplugin/archive/refs/heads/<branch>.zip` via the existing `Updater.install` pipeline.
3. A "Reset to latest stable release" entry in the Advanced submenu — fail-safe rollback that always installs the most recent release zip regardless of `_meta.lua`'s reported version (so it works correctly when a branch's `_meta.lua` reports a higher version than stable).
4. A status line in the Advanced submenu showing the installed source — `Installed: v5.1.0 (release)` or `Installed: v5.2.0-dev (branch: feature/v5.2-test)` — derived from `_meta.lua` and a new `last_install_source` setting written on successful install.
5. Tracking via `last_install_source` so the status line stays accurate after a restart.

**Out of scope:**

- Branch list / autocomplete (text entry only — branch names spread by word-of-mouth in PR threads / Reddit posts; deliberately not casually discoverable in the UI).
- Tag picker (release candidates would clutter the public release history; ephemeral branches better fit the use case).
- Automatic backups / "reset to last working" beyond the explicit Reset entry above.
- Changes to the existing hourly background release-poll. It continues regardless of branch state — opting into a branch doesn't suppress release-update notifications.
- Updatesmanager (third-party) integration. If a user has updatesmanager installed, it'll offer the latest release independently — we don't try to coordinate.
- Hot-swapping plugin code without a KOReader restart. Restart prompt matches the existing updater behaviour.

## Architecture

Three files touched:

| File | Change |
|------|--------|
| `bookends_updater.lua` | Two new module functions: `Updater.composeBranchUrl(branch)` and `Updater.installBranch(branch)`. One new helper: `Updater.installLatestStable()`. Existing `check()` and `install()` unchanged. |
| `main.lua` | One-line dispatch added to `Bookends:checkForUpdates()` (release vs branch). |
| `menu/main_menu.lua` | New "Advanced" entry appended to `buildBookendsSettingsMenu()`'s returned table, with a `sub_item_table` containing three rows (Development branch, Reset to latest stable release, status line). |

No new files. No new external dependencies. Existing settings infrastructure (`self.settings:saveSetting` / `:readSetting`) holds the two new keys. The hourly background release-poll (`Updater.checkBackground`, gated by the existing opt-in `check_updates` setting) is unchanged.

## Components

### Settings

Persisted in the existing bookends settings file:

| Key | Type | Default | Notes |
|-----|------|---------|-------|
| `dev_branch` | string | `""` | Branch name to install from. Empty = stable. Trimmed and URL-encoded at compose time. |
| `last_install_source` | string | `"release"` | Set after a successful install. Either `"release"` or `"branch:<name>"`. Used purely for the status-line display. |

### Updater additions

```lua
-- bookends_updater.lua additions

function Updater.composeBranchUrl(branch)
    -- URL-encode the branch path segment; leave / unescaped so feature/foo works
    local encoded = branch:gsub("[^%w%-_/.~]", function(c)
        return string.format("%%%02X", c:byte())
    end)
    return string.format(
        "https://github.com/AndyHazz/bookends.koplugin/archive/refs/heads/%s.zip",
        encoded)
end

function Updater.installBranch(branch)
    -- Same Wi-Fi guard as Updater.check()
    -- Compose URL, hand to existing install() with version label "branch:<name>"
    -- On success, caller should set last_install_source = "branch:<name>"
end

function Updater.installLatestStable()
    -- Fetch /releases/latest, find the zip asset, hand to install()
    -- Skips the version-comparison check that check() does — always proceeds
    -- On success, caller should set last_install_source = "release"
end
```

The existing `Updater.install(zip_url, old_version, new_version)` is unchanged. It does the download → `Device:unpackArchive(zip_path, plugin_path, true)` → restart prompt. The strip-root flag handles GitHub's `<repo>-<branch>/` archive prefix natively (verified on the v5.0.1 release zip and a sample branch zip).

### Menu — Settings → Advanced

A new submenu rendered as three rows:

```
Settings → Advanced
├─ Development branch:                    feature/v5.2-test  (tap to edit)
├─ Reset to latest stable release         ▶
└─ Installed: v5.2.0-dev (branch: feature/v5.2-test)   [info, non-tappable]
```

- **Development branch** — tapping opens an `InputDialog` pre-filled with the current `dev_branch`. Save persists; Cancel discards. Empty submission clears the field. Whitespace trimmed before save; reject empty-after-trim by treating as cleared.
- **Reset to latest stable release** — tapping opens a `ConfirmBox`: *"This will clear the development branch setting and install the latest stable release of Bookends, then restart KOReader. Continue?"*. On confirm: `dev_branch = ""`, then `Updater.installLatestStable()`.
- **Status line** — non-tappable info row. Reads `last_install_source` and `_meta.lua`'s version; renders one of:
  - `Installed: v5.1.0 (release)` — when `last_install_source == "release"`.
  - `Installed: <version> (branch: <name>)` — when `last_install_source == "branch:<name>"`.

The Advanced submenu lives at the bottom of the bookends settings menu so it's never the first thing a casual user sees.

### Update entry-point dispatch

The existing version row in `Bookends:buildBookendsSettingsMenu()` (`menu/main_menu.lua:382-394`) has a dynamic `text_func` label — `"Installed version: vX.Y.Z"` or `"Update available: vX.Y.Z → vA.B.C"` — and a callback that calls `self:checkForUpdates()`. Both stay; only the body of `Bookends:checkForUpdates()` (`main.lua:2324`) grows a one-line dispatch:

```lua
function Bookends:checkForUpdates()
    local dev_branch = self.settings:readSetting("dev_branch", "")
    if dev_branch ~= "" then
        Updater.installBranch(dev_branch, self.settings)
    else
        Updater.check()
    end
end
```

Branch flow skips the release-notes preview that `check()` shows — branches don't have release notes; the confirmation comes purely from "Install branch <name>?" → restart prompt.

### Persisting `last_install_source`

`Updater.install` currently takes `(zip_url, old_version, new_version)` and ends with the restart `ConfirmBox`. It needs one extra optional parameter — an `on_success` callback that fires after `Device:unpackArchive` returns true but before the restart prompt — so the wrapping function can stamp `last_install_source` while the new code is on disk but the old code is still running:

```lua
function Updater.install(zip_url, old_version, new_version, on_success)
    -- ... existing download + unpack ...
    if not ok then
        UIManager:show(InfoMessage:new{ text = _("Installation failed: ") .. tostring(err) })
        return
    end
    if on_success then on_success() end  -- new: stamp source before restart prompt
    UIManager:show(ConfirmBox:new{ ... existing restart prompt ... })
end
```

`installBranch(branch, settings)` and `installLatestStable(settings)` pass an `on_success` that calls `settings:saveSetting("last_install_source", "branch:" .. branch)` or `"release"` respectively. KOReader autosaves settings on flush; the value persists across the restart and is what the status line reads on next entry to the Advanced submenu.

Existing call sites of `Updater.install` (release flow inside `Updater.check`) pass no `on_success` and behave unchanged — but ALSO need a stamp so the status line is accurate after a vanilla release update too. Easiest fix: have `Updater.check` itself pass an `on_success` that stamps `"release"`. That way every path through the updater leaves `last_install_source` accurate.

## Data flow

### Switching to a branch

1. User → Settings → Advanced → Development branch.
2. `InputDialog` opens. User types `feature/v5.2-test`. Save.
3. `dev_branch = "feature/v5.2-test"` persisted. No install yet.
4. User → Bookends → Check for updates.
5. Dispatch sees non-empty `dev_branch`, calls `Updater.installBranch("feature/v5.2-test")`.
6. Wi-Fi guard, URL composition, download, unpack, restart prompt — all reusing existing infrastructure.
7. On confirmed install + restart: `last_install_source = "branch:feature/v5.2-test"`.
8. Next visit to Settings → Advanced shows `Installed: v5.2.0-dev (branch: feature/v5.2-test)` in the status row.

### Rollback (deliberate)

1. User → Settings → Advanced → Reset to latest stable release.
2. `ConfirmBox` shows. User confirms.
3. `dev_branch = ""`, `Updater.installLatestStable()` called.
4. Latest release fetched, downloaded, unpacked, restart prompt.
5. On confirmed install: `last_install_source = "release"`.

### Rollback (fall-through via updatesmanager)

If a user has updatesmanager installed and runs its scan: it offers the latest bookends release. Installing via that path overwrites the plugin directory with release contents. `last_install_source` is not updated by this path (we don't hook updatesmanager), so the bookends status line will show stale info — known limitation; the user can run "Reset to latest stable release" inside bookends to refresh both.

## Error handling

- **Wi-Fi off** → `NetworkMgr:isWifiOn()` check in `installBranch` and `installLatestStable` shows `_("Wi-Fi is not enabled.")` `InfoMessage`, no state change. Mirrors `Updater.check()`.
- **Branch not found** → GitHub returns 404 → existing `Updater.install` failure path fires `_("Download failed.")` (with offer to open releases page). `dev_branch` and `last_install_source` unchanged.
- **Network error / SSL / timeout** → existing curl fallback in `Updater.install`'s download path. If both fail, same "Download failed" treatment.
- **Malformed zip / unpack failure** → existing `Device:unpackArchive` returns false → existing `_("Installation failed: ")` `InfoMessage`. Plugin directory may be in a half-unpacked state in the most pathological case; user recovers via Reset or updatesmanager.
- **Whitespace / unicode / `..` in branch name** → trim leading/trailing whitespace; URL-encode all chars except `%w%-_/.~` (so `feature/foo` keeps its slash but a literal `;` or `?` is encoded). Empty after trim → treat as cleared. No special validation against malicious branch names — the URL goes to `github.com`, which validates server-side and returns 404 for non-existent refs.

## Testing

No new automated tests. The change is UI + URL composition + reuse of an already-tested install pipeline. Smoke tests on Kindle:

1. **Stable round trip.** Empty `dev_branch`, Check for updates → existing flow, install completes, status line reads `Installed: vX.Y.Z (release)`.
2. **Branch round trip.** Set `dev_branch=feature/v5.2-test`, Check for updates → branch flow, download / unpack / restart, status line reads `Installed: <version> (branch: feature/v5.2-test)`.
3. **Reset.** From a branch state, tap Reset to latest stable release → confirm → release reinstall, status line reverts to `(release)`, `dev_branch` cleared.
4. **404 path.** Set `dev_branch=this-does-not-exist`, Check for updates → "Download failed", `last_install_source` unchanged.
5. **Whitespace input.** Type `  feature/v5.2-test  ` → trim before save, install works.
6. **Wi-Fi off path.** Disable Wi-Fi, Check for updates with non-empty `dev_branch` → "Wi-Fi is not enabled" message, no install.

## Future work (not in this design)

- Adding a `dev_branch` field to the existing background release-check could let bookends warn "you've been on this branch for 30+ days, the latest release is vX.Y.Z" — useful for testers who forget they're on a branch. Defer until there's evidence anyone actually leaves a branch installed long-term.
- A "share installed source" command that copies the current branch / version label to the clipboard — useful for bug reports. Trivial to add later if it becomes a pattern.
