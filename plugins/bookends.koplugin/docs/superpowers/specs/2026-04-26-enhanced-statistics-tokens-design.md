# Enhanced statistics tokens — design

## Motivation

A user reported that the existing `session_pages` token has two surprises:

1. It resets when the book is closed and re-opened (this is by design — "session" means a contiguous reading session — but combined with the next point it's a bigger problem in practice).
2. It counts pages skipped over. Opening a New Yorker issue at page 1 and jumping to an article on page 25 reports "24 pages read this session" with zero dwell time.

The same user asked for "Total pages read today".

KOReader's stock `ReaderStatistics` plugin already solves all of these. It persists per-page reading data in `statistics.sqlite3`, applies a minimum-dwell-time threshold (`settings.min_sec`, default ~5 s) to filter out skipped pages, and exposes session and today aggregates via `getCurrentBookStats()` / `getTodayBookStats()`. Bookends already integrates with `ui.statistics` for `book_time_left`, `chap_time_left`, and `book_read_time`, so this is an extension of an existing pattern, not new infrastructure.

The principle is the same as the chapter-title decision earlier this session: when KOReader has the canonical data, read from it instead of inventing a parallel store.

## Scope

**In scope:**

1. Silent upgrade of `session_pages` and `session_time` to source from `ui.statistics:getCurrentBookStats()`. Skip-aware. Falls back to current max-page / wall-clock behaviour when statistics is unavailable or disabled.
2. Seven new tokens, all sourced from `ui.statistics`:
   - `pages_today` — pages read today across all books (skip-aware).
   - `time_today` — minutes read today across all books.
   - `book_pages_read` — lifetime skip-aware pages read of the current book.
   - `avg_page_time` — average seconds per page on the current book.
   - `book_pct_read` — `book_read_pages / page_count * 100`. Complements existing position-based `book_pct`.
   - `days_reading_book` — days since first open of the current book.
   - `pages_per_day` — `book_read_pages / days_reading_book`, rounded to integer.
3. Token-picker entries and translatable labels for each new token.
4. Test coverage in `_test_tokens.lua` covering: stats-available paths, stats-disabled fallback, skip-aware deltas, zero-day handling for `pages_per_day`.

**Out of scope:**

- Cross-book aggregates beyond today (`pages_this_month`, `pages_this_year`, reading streak). The today aggregate covers the asked-for case; longer windows would need custom SQL, not just method calls. Park unless requested.
- Per-book percentile / percentage-of-readers stats. Not in the API.
- Reading-streak token. Not directly available; would need custom SQL date-grouping.
- Changes to existing time tokens beyond the silent upgrade (e.g. `book_read_time`, `chap_time_left` keep their current implementations).
- `_clock` formatted variants of time tokens. The dual-form pattern in `bookends_tokens.lua` (integer minutes in `buildConditionState` for `[if:...]`, formatted clock duration via `secondsToClockDuration` for display) already respects the user's `duration_format` preference. New time tokens follow the same pattern; no extra surface area needed.

## Architecture

Three files touched. No new files.

| File | Change |
|------|--------|
| `bookends_tokens.lua` | Update `session_pages` / `session_time` rendering to call `ui.statistics:getCurrentBookStats()` with current-behaviour fallback. Add seven new token cases in the existing rendering and condition-state code paths. Register the seven new names in the `Tokens.aliases` map. |
| `menu/token_picker.lua` | Add picker entries for each new token with translatable labels. |
| `_test_tokens.lua` | New tests for each of the seven tokens plus regression coverage for the silent-upgrade case (skip-aware vs fallback behaviour). |

No new external dependencies. No new persisted settings. No new event handlers (existing `onPageUpdate` / paint cycle covers when these are recomputed).

## Components

### Stats access helper

A single helper inside `bookends_tokens.lua`:

```
local function readStatsBookSession(ui)
    if not ui or not ui.statistics or not ui.statistics.getCurrentBookStats then
        return nil
    end
    local ok, dur, pages = pcall(function()
        return ui.statistics:getCurrentBookStats()
    end)
    if not ok then return nil end
    return { duration = dur or 0, pages = pages or 0 }
end
```

A parallel `readStatsToday(ui)` for `getTodayBookStats()`. Both return `nil` on any failure (statistics disabled, plugin missing, SQL error). Callers fall back accordingly.

`pcall` is defensive — `getCurrentBookStats` opens a SQLite connection and could in principle fail (locked DB, missing file). Today bookends already calls `ui.statistics:getTimeForPages(...)` without `pcall` (bookends_tokens.lua:1206); stats failures there cause render glitches. Worth wrapping in `pcall` here even though the existing code doesn't.

### Silent upgrade — `session_pages` / `session_time`

Today (main.lua:1078-1079):

```
function Bookends:getSessionPages()
    return math.max(0, (self.session_max_page or 0) - (self.session_start_page or 0))
end
```

This stays — it's the fallback. In `bookends_tokens.lua`, where these values are turned into rendered strings and condition-state entries, prefer the stats-backed value when available:

- `session_pages` value path: try `readStatsBookSession(ui).pages`; if nil, use the current `session_pages_read` arg passed in by `Tokens.expand`.
- `session_time` value path: try `readStatsBookSession(ui).duration`; if nil, use the current `session_elapsed` arg.

Both arguments are still threaded through `Tokens.expand` / `Tokens.buildConditionState` unchanged — they're now the fallback, not the primary source. No call-site changes required.

### New tokens — value computation

| Token | Source | Conditional value | Render path |
|---|---|---|---|
| `pages_today` | `getTodayBookStats().pages` | int | `tostring(int)` |
| `time_today` | `getTodayBookStats().duration` | `floor(secs/60)` (int min) | `secondsToClockDuration(format, secs, true)` |
| `book_pages_read` | `ui.statistics.book_read_pages or 0` | int | `tostring(int)` |
| `avg_page_time` | `ui.statistics.avg_time or 0` | `floor(secs)` (int sec) | `secondsToClockDuration(format, secs, true)` |
| `book_pct_read` | `(book_read_pages / page_count) * 100` when `page_count > 0`, else `0` | int 0-100 | `tostring(int)` |
| `days_reading_book` | `floor((now - first_open) / 86400)` | int | `tostring(int)` |
| `pages_per_day` | `book_read_pages / max(days_reading_book, 1)` | int | `tostring(int)` |

`days_reading_book` requires `first_open`, which isn't a stats instance field. The value is queried inside `getBookStat(id_book)` (statistics line 1718). Rather than calling that heavy method, we issue a direct SQL query mirroring its shape — `SELECT min(start_time) FROM page_stat WHERE id_book = ?` — gated and `pcall`-wrapped. One query per render at most, only when a needs-line uses the token.

### Fallback behaviour

When `ui.statistics` is unavailable, disabled, or any read fails:

| Token | Fallback |
|---|---|
| `session_pages` | Existing `session_pages_read` arg (max-page minus start-page) |
| `session_time` | Existing `session_elapsed` arg (wall-clock since session start) |
| `pages_today`, `time_today`, `book_pages_read`, `book_pct_read`, `days_reading_book`, `pages_per_day` | `0` |
| `avg_page_time` | `0` |

`0` triggers the existing auto-hide-zero behaviour on lines that contain only the token. Documented in `feedback_auto_hide_zero.md`.

### Token registration

The `Tokens.aliases` table at bookends_tokens.lua:107 maps user-facing names to canonical state-keys. Each new token gets an entry there so `[if:...]` resolution finds it. Token-picker entries in `menu/token_picker.lua` add the user-facing line + label for each.

### Performance

- Two `needs(...)` gates added: one for the `getCurrentBookStats` call (covers `session_pages`, `session_time` and any token that reads from the same payload), one for `getTodayBookStats` (covers `pages_today`, `time_today`).
- Each gated call hits SQLite once per render. Render cadence is page-turn driven (typically 5–30 s between renders), and the queries are sub-millisecond against a warm DB. Same cost shape as existing `getTimeForPages` calls.
- Within a single render, results are cached in local variables so multiple tokens reading from the same payload (e.g. `pages_today` and `time_today`) issue at most one query.

## Testing

Add cases to `_test_tokens.lua`:

1. Stats available — each new token returns the expected derived value.
2. Stats unavailable (`ui.statistics = nil`) — each new token falls back to 0; `session_pages` / `session_time` fall back to the legacy max-page / wall-clock values.
3. Skip-aware regression — given mock stats where session pages = 5 but session_pages_read arg = 24 (simulating the New Yorker jump), token resolves to 5.
4. Zero-day handling — when `days_reading_book = 0` (book opened today), `pages_per_day` returns `book_pages_read` rather than NaN/error.
5. Conditional state — `[if:pages_today>10]X[/if]` evaluates correctly with mock state.

The existing test infrastructure already mocks `ui.statistics` with stub methods (search shows `secondsToClockDuration = function() return "" end` at `_test_tokens.lua:13`). Extending the mock is minimal.

## Migration

No data migration. Users who use `%session_pages` in a preset will see lower numbers if they skip-flip pages, but the change is a strict improvement — the new value reflects pages they actually dwelled on. Users who read linearly see no change. Users with the statistics plugin disabled see no change at all.

Release notes call this out under a "Stats integration" line, framed as "session pages now ignores pages you skip over" rather than as a behaviour-change warning.

## Open questions

None. Naming, fallback semantics, and the silent-upgrade vs new-token decision were settled in the brainstorm.
