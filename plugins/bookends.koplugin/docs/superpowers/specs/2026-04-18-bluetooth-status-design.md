# Bluetooth Status Token

**Date:** 2026-04-18
**Origin:** Reddit feature request — user wants Bookends to show a Bluetooth indicator equivalent to the one [kobo.koplugin](https://github.com/OGKevin/kobo.koplugin) injects into KOReader's stock status bar. With Bookends' "Disable stock status bar" setting enabled, that indicator disappears.

## Overview

Add a single new token `%X` and a single new conditional state `bluetooth=on/off` that pass through kobo.koplugin's authoritative Bluetooth state.

Scope is deliberately narrow:

- Passthrough only. No independent Bluetooth detection (no `rfkill`, no DBus, no `bluetoothctl`).
- Adapter power state only. No "remote connected" / "auto-connect active" / "auto-detect active" sub-states.
- No new plugin-level settings. Works identically to `%W` (Wi-Fi): on = icon, off = hidden.

## Rationale

### Why passthrough, not independent detection

KOReader core has no Bluetooth API. The entire KOReader source mentions "bluetooth" only in `platform/kobo/koreader.sh:220`, where it `killall`s `bluetoothd` on startup. `Device:getPowerDevice()` covers battery + frontlight only; `ui/network/manager` covers Wi-Fi only.

kobo.koplugin (`src/kobo_bluetooth.lua:165`) provides `isBluetoothEnabled()` which wraps a DBus call to BlueZ / MTK bluedroid, depending on hardware. It's the canonical source of truth on Kobo devices and already handles unsupported-hardware detection via `isDeviceSupported()`.

An rfkill-based fallback was considered (option C during brainstorming) but rejected:

- The cohort it would serve — Kobo users with Bluetooth hardware but *without* kobo.koplugin installed — is tiny. Anyone wanting to use Bluetooth in KOReader installs kobo.koplugin to get a pairing UI.
- rfkill only reports adapter power, not connected-device state. Doesn't meaningfully improve on the passthrough.
- Adds shell-out code and OS-specific paths to maintain.

If that cohort surfaces later, an rfkill fallback can be added alongside the passthrough without breaking existing behaviour.

### Why one glyph, not three

kobo.koplugin renders three different glyphs in the stock footer based on its internal polling mode:

- `󰂯` U+F00AF — adapter on (baseline)
- `󰂎` U+F06E — adapter on + auto-connect polling active
- `󰑈` U+F0208 — adapter on + auto-detect polling active

Bookends exposes only the baseline state. Users who care about the polling sub-states can read them from kobo.koplugin's own UI. Users who want a visible "off" state can write:

```
[if:bluetooth=on]󰂯[else]󰂲[/if]
```

This mirrors how `%W` works (on = icon, off = hidden string) and keeps the feature small.

## User-facing surface

### New token

| Token | Expands to |
|---|---|
| `%X` | `󰂯` (U+F00AF, Material `mdi-bluetooth`) when adapter is on, empty string otherwise |

Empty string means the containing line auto-hides if `%X` was the only content, matching the existing all-empty behaviour in `tokens.lua`.

### New conditional state

| Condition | Values | Meaning |
|---|---|---|
| `bluetooth` | `on` / `off` | Adapter power state from kobo.koplugin |

When kobo.koplugin is not loaded (or is loaded on a non-Kobo device), `state.bluetooth` is **nil** rather than `"off"`. This means:

- `[if:bluetooth=on]...[/if]` — false, `[/if]` branch silently fires `[else]` content if present.
- `[if:bluetooth=off]...[/if]` — also false, since nil doesn't equal the string `"off"`.

That's the correct semantic: "we don't know the state" should not make either affirmative branch match. Users wanting graceful degradation on non-Kobo devices can just use `[if:bluetooth=on]...[/if]` without an `[else]` — the whole block vanishes when the plugin isn't present.

### Usage examples

```
%W %X                               → wifi and bluetooth icons side by side
[if:bluetooth=on]󰂯[/if]            → show only when BT on
[if:bluetooth=on]BT[else]-[/if]    → explicit on/off labels
```

## Implementation

Three files, ~15 lines of logic plus picker entries and README rows.

### tokens.lua

**Condition state** — in `buildConditionState` (currently `tokens.lua:119-214`), alongside the Wi-Fi block (~line 127):

```lua
-- Bluetooth (via kobo.koplugin if present)
local kp = ui.kobo_plugin
if kp and kp.kobo_bluetooth then
    state.bluetooth = kp.kobo_bluetooth:isBluetoothEnabled() and "on" or "off"
end
```

Intentionally nil when the plugin isn't loaded — see "New conditional state" above.

**Token resolution** — in `Tokens.expand` (currently `tokens.lua:659-670` for the Wi-Fi block), add a parallel block just after Wi-Fi:

```lua
local bt_symbol = ""
if needs("X") then
    local kp = ui.kobo_plugin
    if kp and kp.kobo_bluetooth and kp.kobo_bluetooth:isBluetoothEnabled() then
        bt_symbol = "\xF3\xB0\x82\xAF"  -- U+F00AF mdi-bluetooth
    end
end
```

UTF-8 encoding of U+F00AF: codepoint is in SMP (above 0xFFFF) so it's a 4-byte sequence: `F3 B0 82 AF`.

**Replace table** — one entry added to the `replace` table (currently `tokens.lua:742`):

```lua
["%X"] = bt_symbol,
```

**Preview mode** — one entry in the preview mapping (currently `tokens.lua:283`):

```lua
["%X"] = "[bt]",
```

No change to `needs()`, no change to the main gsub loop, no change to auto-hide logic — all pre-existing machinery handles the new token by inheritance.

### menu/token_picker.lua

Add `%X` to the Device section with label "Bluetooth icon (dynamic)" and a help note that it requires kobo.koplugin.

### icon_picker.lua

Add two glyphs to the Device category so users can type static BT icons inside `[if:]` blocks:

- `󰂯` U+F00AF — bluetooth on
- `󰂲` U+F00B2 — bluetooth off / disabled

(The dynamic `%X` token is separate from these static icons — the icons are for use inside conditional branches.)

### README.md

Three surgical additions, no restructuring:

**Device tokens table** — one row:

```
| `%X` | Bluetooth icon (dynamic) | Hidden when off or kobo.koplugin not loaded |
```

**Conditional tokens table** — one row:

```
| `bluetooth` | on / off | Bluetooth adapter state (requires kobo.koplugin) |
```

**Requirements note** under the Device tokens section:

> `%X` and the `bluetooth` condition require [kobo.koplugin](https://github.com/OGKevin/kobo.koplugin) to be installed on a supported Kobo device. They expand to empty / never match otherwise.

## Edge cases

- **kobo.koplugin not installed** — `ui.kobo_plugin` is nil; `%X` → empty; `state.bluetooth` stays nil. Lines auto-hide cleanly.
- **kobo.koplugin installed but running on a non-Kobo device** — `kobo_bluetooth:isBluetoothEnabled()` returns false via `isDeviceSupported()` check. `%X` → empty; `state.bluetooth = "off"`. Slightly different from "not loaded" in that `[if:bluetooth=off]` now matches; arguably still correct behaviour ("we can tell the adapter is off, it's just always off").
- **kobo.koplugin installed but fails to init** — `ui.kobo_plugin` exists but `kobo_bluetooth` might be nil. Guarded by the `kp.kobo_bluetooth and` check. Degrades to nil state.
- **Rapid BT toggles during a paint cycle** — same refresh cadence as `%W`; no special handling. The existing paint-cycle condition-state cache (`tokens.lua:119-122`) means `state.bluetooth` is computed once per paint, consistent across all lines in that frame.
- **`isBluetoothEnabled()` signature or name changes upstream** — `pcall` not added because an error here would indicate a real integration break worth surfacing. If upstream churn becomes an issue, wrap the method call.

## Testing & delivery

The primary author does not have a Bluetooth-capable device and cannot verify end-to-end behaviour. Delivery strategy:

1. **Implement on a feature branch** — `feature/bluetooth-status` or similar.
2. **Cut a GitHub prerelease.** The in-app updater (`updater.lua:138` and `updater.lua:196`) explicitly skips `rel.draft or rel.prerelease`, so existing users are not auto-notified. Tag as `vX.Y.Z-rc1`.
3. **Attach the `.zip` asset** — same packaging as a stable release, so the tester extracts it into their plugins folder without the `bookends.koplugin-branchname/` folder-rename footgun of a raw branch download.
4. **Command:**
   ```sh
   gh release create vX.Y.Z-rc1 \
     --prerelease \
     --title "Bluetooth status — preview" \
     --notes "Requires kobo.koplugin installed on a Kobo device." \
     bookends.koplugin.zip
   ```
5. **Reply to the Reddit thread** with:
   - Direct URL to the prerelease page
   - Install instructions (unzip into `/mnt/onboard/.adds/koreader/plugins/`, restart KOReader)
   - Usage hint: type `%X` into any line, or use the Tokens picker → Device → Bluetooth
   - Specific asks: confirm the icon appears/disappears when toggling BT via kobo.koplugin, and screenshot any oddities
6. **Open a GitHub issue first** and link the prerelease to it — gives the tester a natural reporting channel and gives future users searching "bluetooth" something to find.
7. **Iterate as `-rc2`, `-rc3`** if fixes are needed, then promote to a stable release once validated.

## Non-goals

- No rfkill / sysfs / `bluetoothctl` fallback.
- No UI for "show remote-connected state" or similar enhanced indicators.
- No plugin-level setting for Bluetooth — it's always available; users who don't want the icon simply don't use the token.
- No gesture / dispatcher action for toggling Bluetooth — that belongs in kobo.koplugin.
