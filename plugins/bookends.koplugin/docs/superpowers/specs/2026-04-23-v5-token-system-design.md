# v5 token system overhaul — design

## Motivation

`bookends_tokens.lua` speaks two vocabularies at once. The conditional-state builder (`buildConditionState`, from the v4.1 predicate work) already exposes descriptive names — `state.author`, `state.chap_count`, `state.book_pct`, `state.batt`. Meanwhile the token-replacement pipeline stays on single-letter codes — `%A`, `%J`, `%p`, `%b`. Writing `[if:chapters>10]Chapter %J of %J[/if]` is two languages in one string: one descriptive, one cryptic.

v5 collapses those two vocabularies into one. Tokens get the same readable names as conditional predicates. Single-letter codes remain functional forever as compatibility aliases (the `bookends-presets` remote gallery has 13+ presets baked with old syntax), but the documented, picker-offered, line-editor-shown surface is the new vocabulary.

Two secondary goals ride along:

1. **`%datetime{…}` escape hatch.** The forcing function is a Reddit request for "21 April" (day + full month, no year). Rather than adding a one-off `%M` token, v5 exposes a single parameterised token whose brace content is passed straight to `os.date` — users get the full strftime grammar. Plain `%time`, `%date`, and `%weekday` keep their familiar fixed-format outputs; the escape hatch is a separate, explicitly-named token.
2. **Unified brace grammar.** Three disjoint mini-parsers currently handle `%bar{100v10}`, `%C<d>{N}`, and `(%%%a){N}`. Multi-character descriptive tokens don't fit any of them (`%chap_title{200}` would need a fourth). One outer pattern + per-token dispatch replaces all three in one pass.

Paradox460's PRs [#26](https://github.com/AndyHazz/bookends.koplugin/pull/26) (`!=` / `@ref`) and [#28](https://github.com/AndyHazz/bookends.koplugin/pull/28) (index filter + list conditionals) remain deferred — they are treated as design input, not patches to rebase. The unified brace grammar leaves a clean extension slot for the `{1i40}` index-filter shape; the conditional evaluator is unchanged in v5.0 and can pick up `!=`/`@ref` in a later cycle.

## Scope

**In scope — v5.0.0:**

1. Descriptive multi-character token vocabulary aligned to conditional-state keys.
2. Legacy single-letter tokens remain functional via a compile-time alias table (gallery compatibility, forever).
3. `%datetime{strftime}` escape hatch for custom date/time formatting.
4. Series-token split: `%series` (combined, unchanged semantics), plus new `%series_name` and `%series_num`.
5. Unified brace grammar: one outer `%%name{content}` parser, per-token dispatch of brace content.
6. Line-editor behaviour: canonicalise legacy tokens to new vocabulary on open; live-preview only resolves new tokens while typing (legacy tokens stay literal).
7. State-key aliases inside `[if:…]` predicates, so gallery presets using `chapters`, `chapter`, etc. still evaluate.
8. Token picker (`menu/token_picker.lua`) rewritten to the new vocabulary.
9. README rewritten to use only the new vocabulary; legacy syntax undocumented. README's `%datetime` section links to [strftime.net](https://strftime.net/) as a user-friendly reference cheatsheet.
10. Release notes covering the rename + migration story.
11. Tests covering `canonicaliseLegacy()` idempotency, alias-pass correctness, `%datetime` strftime expansion, bare-`%datetime` literal fall-through, state-key alias resolution.

**Out of scope (explicit):**

- **Conditional evaluator rewrite.** Recursive-descent parser from v4.1 works fine. `!=` and `@ref` (paradox460's #26) deferred.
- **Sentinel-byte pipeline replacement.** `\x01N\x02val\x03` for pixel truncation stays. PR #7's flag-of-fragility deferred.
- **Per-token character limits / auto-hide icons.** Issue #6 concept, stays parked.
- **Bulk "Modernise my presets" UI.** Rely on migrate-on-edit. Ship as v5.1+ if anyone asks.
- **Subtle editor hint for unresolved legacy tokens.** Literal fall-through is self-diagnosing enough.
- **`%A{1i40}` index-filter grammar.** The unified brace grammar leaves a clean extension slot; the grammar itself is not landed in v5.0.
- **Peer-to-peer preset compatibility with pre-v5 users.** Once edited-and-saved in v5, strings emit new names. One-way migration cliff, flagged in release notes.

## Architecture

Work concentrates in three files, with ripple into picker, README, locales, and tests.

| Area | File | Change shape |
|------|------|--------------|
| Core expander | `bookends_tokens.lua` | Add `TOKEN_ALIAS` + `STATE_ALIAS` tables; add one-shot alias-rewrite pass at top of `expand()`; replace three brace mini-parsers with one outer `%%name%b{}` pass + per-token dispatcher; extend state-key lookup in `evaluateCondition` to honour `STATE_ALIAS`; add `Tokens.canonicaliseLegacy()` pure function; rename state-key builders to new vocabulary; add `%datetime{…}` handler. |
| Line editor | `bookends_line_editor.lua` | Call `Tokens.canonicaliseLegacy()` when opening a line for editing. Pass `legacy_literal = true` flag into `Tokens.expandPreview()` so the alias-rewrite step is skipped in editor live preview. |
| Token picker | `menu/token_picker.lua` | Rewrite token list: new names, category reordering if needed. Descriptions mostly survive verbatim (already semantic, not name-referencing). |
| Documentation | `README.md` | Rewrite token tables using new vocabulary. Legacy syntax undocumented. |
| Release notes | `docs/release-notes-5.0.0.md` | New file. Rename summary, migration story, strftime angle. |
| i18n | `locale/*.po`, `locale/bookends.pot` | 5–10 new strings (`%datetime`, `%series_name`, `%series_num`, strftime teaching blurb). Existing description strings reused verbatim under renamed associations. |
| Tests | `_test_tokens.lua` (new), `_test_conditionals.lua` (extend) | See Testing section. |

No architectural reshuffles. No new modules. No changes to `main.lua`, `bookends_overlay_widget.lua`, `preset_manager.lua`, `preset_gallery.lua`.

## Token inventory

Full rename table. Convention: where a common abbreviation exists and reads cleanly, it's applied (`chap`, `batt`, `light`, `lang`, `mem`). Where it doesn't, the full word stays.

### Page / progress

| Legacy | v5 | Notes |
|---|---|---|
| `%c` | `%page_num` | `state.page` stays "odd"/"even"; explicit suffix avoids clash. |
| `%t` | `%page_count` | |
| `%p` | `%book_pct` | Matches `state.book_pct`. |
| `%P` | `%chap_pct` | Matches `state.chap_pct`. |
| `%g` | `%chap_read` | Pages read in chapter. |
| `%G` | `%chap_pages` | Total pages in chapter. |
| `%l` | `%chap_pages_left` | |
| `%L` | `%pages_left` | Pages left in book. |
| `%j` | `%chap_num` | |
| `%J` | `%chap_count` | |

### Chapter titles

| Legacy | v5 |
|---|---|
| `%C` | `%chap_title` |
| `%C1` / `%C2` / `%C3` | `%chap_title_1` / `%chap_title_2` / `%chap_title_3` |

### Book metadata

| Legacy | v5 | Notes |
|---|---|---|
| `%T` | `%title` | |
| `%A` | `%author` | |
| `%S` | `%series` | Combined "Foundation #2", unchanged semantics. |
| — | `%series_name` | **New.** Series name alone. |
| — | `%series_num` | **New.** Series index alone. |
| `%N` | `%filename` | |
| `%i` | `%lang` | |
| `%o` | `%format` | |

### Annotations

| Legacy | v5 |
|---|---|
| `%q` | `%highlights` |
| `%Q` | `%notes` |
| `%x` | `%bookmarks` |
| `%X` | `%annotations` |

### Time / date / session

| Legacy | v5 | Notes |
|---|---|---|
| `%k` | `%time_12h` | |
| `%K` | `%time_24h` | |
| — | `%time` | **New.** Alias for `%time_24h`. |
| `%d` | `%date` | Short "23 Apr". |
| `%D` | `%date_long` | "23 April 2026". |
| `%n` | `%date_numeric` | "23/04/2026". |
| `%w` | `%weekday` | "Thursday". |
| `%a` | `%weekday_short` | "Thu". |
| — | `%datetime{spec}` | **New.** Strftime escape hatch. Bare form falls through as literal. |
| `%R` | `%session_time` | |
| `%s` | `%session_pages` | Matches `state.session_pages`. |
| `%h` | `%chap_time_left` | |
| `%H` | `%book_time_left` | |
| `%r` | `%speed` | Matches `state.speed`. |
| `%E` | `%book_read_time` | Matches `ui.statistics.book_read_time`. |

### Device

| Legacy | v5 |
|---|---|
| `%b` | `%batt` |
| `%B` | `%batt_icon` |
| `%W` | `%wifi` |
| `%V` | `%invert` |
| `%f` | `%light` |
| `%F` | `%warmth` |
| `%m` | `%mem` |
| `%M` | `%ram` |
| `%v` | `%disk` |

### Structural

`%bar` and its brace-modifier forms (`%bar{100}`, `%bar{v10}`, `%bar{100v10}`) are unchanged. Already multi-character and readable.

## Grammar

### Outer pattern

One Lua-pattern capture handles every token site:

```lua
format_str:gsub("%%([%a_][%w_]*)(%b{})", function(name, brace)
    local content = brace:sub(2, -2)  -- strip { and }
    return dispatchBraceModifier(name, content)
end)
-- Second pass for bare %name (no braces)
format_str:gsub("%%([%a_][%w_]*)", function(name)
    return replaceTable[name] or "%" .. name  -- unknown = literal
end)
```

`%b{}` matches balanced braces, so `%datetime{some {nested} spec}` works for free (edge case, unlikely in practice).

### Per-token brace dispatch

```lua
local BRACE_HANDLERS = {
    bar      = parseBarBrace,         -- (\d+)?(v\d+)?
    datetime = parseStrftimeBrace,    -- pass to os.date
    -- default: pixel-width cap (digits only)
}
```

The default handler accepts digit-only content and treats it as a pixel-width cap (emitting the existing `\x01 N \x02 val \x03` sentinel pair). Non-digit content on tokens without a registered handler leaves the brace group intact as literal text: `%author{foo}` expands the `%author` portion to the author name and leaves `{foo}` as visible text afterward (matching today's behaviour for unparsed braces — `%A{foo}` already works this way).

The `BRACE_HANDLERS` table is also the natural extension slot for paradox460's `{1i40}` index-filter: extending the default handler to also accept `\d+i\d+` is a two-line addition whose grammar lives in one place.

### Replace-table keying

After the alias pass runs, every token in the expander's working string is in the new vocabulary. The `replace` table is keyed by bareword:

```lua
local replace = {
    author     = tostring(authors),
    title      = tostring(title),
    chap_num   = tostring(chapter_num),
    chap_count = tostring(chapter_count),
    -- ...
}
```

Single source of truth for token→value mapping. No dual legacy+new keys.

## Alias mechanism

Two surgical pieces. Different mechanisms because legacy token names appear as literal bytes in the format string, while legacy state keys appear only as parsed identifiers inside predicate atoms.

### Token aliases (string-level rewrite)

One-shot rewrite at the top of `Tokens.expand()`, after the conditional-fast-path check but before brace-modifier extraction:

```lua
local TOKEN_ALIAS = {
    A = "author", T = "title", S = "series", C = "chap_title",
    J = "chap_count", j = "chap_num",
    p = "book_pct", P = "chap_pct",
    c = "page_num", t = "page_count", L = "pages_left", l = "chap_pages_left",
    g = "chap_read", G = "chap_pages",
    k = "time_12h", K = "time_24h",
    d = "date", D = "date_long", n = "date_numeric",
    w = "weekday", a = "weekday_short",
    R = "session_time", s = "session_pages",
    r = "speed", E = "book_read_time",
    h = "chap_time_left", H = "book_time_left",
    b = "batt", B = "batt_icon",
    W = "wifi", V = "invert",
    f = "light", F = "warmth",
    m = "mem", M = "ram", v = "disk",
    N = "filename", i = "lang", o = "format",
    q = "highlights", Q = "notes", x = "bookmarks", X = "annotations",
}

-- Unless caller requested legacy_literal, rewrite legacy tokens in-place.
-- Single pass: greedy-match the full identifier after %, then decide.
-- Any following {…} is left untouched by this pass and handled later by
-- the brace-grammar pass — the gsub only consumes %<identifier>, not {...}.
if not legacy_literal then
    format_str = format_str:gsub("%%([%a_][%w_]*)", function(ident)
        -- Legacy single-letter token: %A, %T, %J, etc.
        if #ident == 1 and TOKEN_ALIAS[ident] then
            return "%" .. TOKEN_ALIAS[ident]
        end
        -- Legacy depth-specific chapter title: %C1, %C2, %C3.
        local depth = ident:match("^C(%d)$")
        if depth then
            return "%chap_title_" .. depth
        end
        -- New token or unknown identifier: leave as-is.
        return nil
    end)
end
```

Why one pass is enough: the greedy `[%a_][%w_]*` captures the *full* identifier after `%`. So `%author` captures `"author"` (length > 1, not in `TOKEN_ALIAS`, untouched), `%A` captures `"A"` (length 1, in `TOKEN_ALIAS`, rewritten), `%C1` captures `"C1"` (matches `^C(%d)$`, rewritten). Any `{…}` following the token is preserved verbatim by the gsub — the next pipeline stage (brace-grammar dispatch) sees `%author{200}` with `author` as the identifier and `{200}` intact.

### State-key aliases (lookup-level redirect)

Inside `evaluateCondition`, when the predicate has been split into `key / op / value`:

```lua
local STATE_ALIAS = {
    chapters    = "chap_count",
    chapter     = "chap_num",       -- renamed from ambiguous "chapter pct" in v4.1
    chapter_pct = "chap_pct",
    chapter_title   = "chap_title",
    chapter_title_1 = "chap_title_1",
    chapter_title_2 = "chap_title_2",
    chapter_title_3 = "chap_title_3",
    pages       = "session_pages",  -- pre-v4.1 name, still in some gallery presets
    percent     = "book_pct",       -- pre-v4.1 name
    -- Unchanged (already on the new vocabulary or have no legacy form):
    --   batt, title, author, series, format, speed, session, session_pages,
    --   book_pct, wifi, connected, charging, light, invert, time, day, page.
    -- Note: state.session (minutes since start) pairs with token %session_time
    -- (formatted duration). Different types, different names — display tokens
    -- and numeric predicates don't have to share a name. Same pattern for
    -- state.time (minutes since midnight) vs %time (formatted clock).
}

local resolved_key = STATE_ALIAS[key] or key
local state_val = state[resolved_key]
```

No string rewriting of predicates — safer, because predicate values may themselves contain legacy names literally (`[if:title=chapters]` comparing the book's title to the word "chapters" must compare to the literal string "chapters", not have the right-hand side rewritten).

The `buildConditionState` function is updated to populate state keys under the **new** names (`state.chap_count`, `state.chap_num`, etc.); `STATE_ALIAS` directs legacy predicates to those new keys at lookup time.

## `canonicaliseLegacy()` and migration UX

A pure string → string utility exported from `bookends_tokens.lua`:

```lua
function Tokens.canonicaliseLegacy(format_str)
    -- 1. Rewrite legacy token identifiers (single-letter and %C<d>) using the
    --    same single-pass greedy-identifier approach as the in-expand alias pass.
    local s = format_str:gsub("%%([%a_][%w_]*)", function(ident)
        if #ident == 1 and TOKEN_ALIAS[ident] then
            return "%" .. TOKEN_ALIAS[ident]
        end
        local depth = ident:match("^C(%d)$")
        if depth then return "%chap_title_" .. depth end
        return nil
    end)

    -- 2. Rewrite legacy state keys inside [if:...] predicates.
    --    Only the KEY portion of each atom (split on operators) is rewritten.
    --    Literal string values containing legacy-looking words are untouched.
    s = rewriteConditionalKeys(s, STATE_ALIAS)

    return s
end
```

`rewriteConditionalKeys` walks every `[if:…]` opener, tokenises the predicate with the existing `tokeniseExpression`, rewrites the key portion of each atom (key is the run of `[%w_]+` before any operator), rejoins, and substitutes back.

**Idempotency.** Applying `canonicaliseLegacy` to an already-canonical string is a no-op. Because the gsub greedy-captures the full identifier after `%`, `%author` produces the capture `"author"` (length 6) — `TOKEN_ALIAS` only has single-letter keys, so the lookup returns nil and the string is untouched. Similarly `%chap_title_1` captures `"chap_title_1"`, neither single-letter nor matching `^C(%d)$`, so it passes through unchanged. State-key rewrite is also idempotent: `chap_count` isn't in `STATE_ALIAS` as a key (only the legacy names are), so re-running the predicate walk doesn't re-rewrite.

**Hook points:**

| Hook | Mechanism |
|------|-----------|
| Line editor opens a line for editing | `bookends_line_editor.lua` calls `Tokens.canonicaliseLegacy(stored_line)` and displays the result. |
| Line editor live preview while typing | `Tokens.expandPreview(line, ui, …, {legacy_literal = true})` — the alias-rewrite step is skipped, so typing `%A` mid-edit stays literal `%A`. |
| Final render on device | `Tokens.expand(line, ui, …)` unchanged. Alias rewrite always active. Gallery presets using `%A` render correctly. |

### Trade-offs acknowledged

1. **Open-in-editor silently rewrites user's stored string.** A user who wrote `%A` and reopens sees `%author`. On save, the new form is persisted. This is deliberate: the editor becomes a teaching surface for the v5 vocabulary. No mid-typing autocorrect; the rewrite is single-shot on open.
2. **Typing `%A` in the editor shows literal `%A` in preview.** User learns the name is now `%author`. Self-diagnosing; no hint UI required for v5.0.
3. **Peer-to-peer sharing.** An edited-in-v5 preset string uses new names. Pre-v5 receivers wouldn't recognise them. Called out in release notes.

## `%datetime{…}` semantics

```lua
-- Handler in BRACE_HANDLERS.datetime:
local function parseStrftimeBrace(content)
    -- Pass content straight to os.date; respect locale if available.
    local loc = getDateLocale()  -- existing helper
    local saved_locale
    if loc then
        saved_locale = os.setlocale(nil, "time")
        os.setlocale(loc, "time")
    end
    local result = os.date(content)
    if saved_locale then os.setlocale(saved_locale, "time") end
    return result or ""
end
```

**Bare `%datetime` (no braces):** falls through as literal `%datetime`. Not registered in the bareword `replace` table. Rationale: `%datetime` is the explicit escape hatch — meaningless without a format spec. Users who want "23 Apr 19:42" write `%date %time` or `%datetime{%d %b %H:%M}`.

**Token-picker entry:** the picker inserts `%datetime{}` with cursor positioned inside the braces, so users never trip over bare form.

## Testing

### New `_test_tokens.lua`

Standalone test file following the `_test_conditionals.lua` pattern (no KOReader runtime required; stub `ui`/`doc`/etc. as needed).

Assertions cover:

1. **Alias-pass correctness.** For every entry in `TOKEN_ALIAS`, `canonicaliseLegacy("%X")` → `"%" .. new_name`. Same for brace-bearing forms (`%X{200}`, `%C1{300}`).
2. **Idempotency.** `canonicaliseLegacy(canonicaliseLegacy(s)) == canonicaliseLegacy(s)` across a fixture set.
3. **Mixed strings.** Strings containing both legacy and new tokens canonicalise cleanly (new tokens untouched, legacy rewritten).
4. **`%datetime{…}` expansion.** Various strftime specs return expected values against a fixed mock `os.date`. Bare `%datetime` returns literal `%datetime`.
5. **Unknown token fall-through.** `%nonexistent` stays as `%nonexistent` in output.
6. **Brace-handler dispatch.** `%bar{100v10}` → bar dims; `%author{200}` → pixel cap; `%author{foo}` → literal (no digit-only match, no handler).
7. **Live-preview legacy-literal flag.** `Tokens.expandPreview(str, ui, …, {legacy_literal = true})` leaves `%A` as `%A`; without the flag, `%A` resolves.

### Extended `_test_conditionals.lua`

1. **State-key alias resolution.** `[if:chapters>10]` against a state with `chap_count = 15` evaluates true. `[if:percent>50]` against `state.book_pct = 60` evaluates true.
2. **Mixed legacy/new keys in one predicate.** `[if:chapters>10 and chap_pct>50]` evaluates correctly.
3. **Predicate value preservation.** `[if:title=chapters]` against `state.title = "chapters"` evaluates true (value "chapters" not rewritten).

## Files touched

| File | Approximate LoC delta |
|------|----------------------|
| `bookends_tokens.lua` | +300 / −200 (net +100). New `TOKEN_ALIAS`, `STATE_ALIAS`, `canonicaliseLegacy`, unified brace parser, `%datetime` handler; removed three mini-parsers; renamed state keys; new replace-table keys. |
| `bookends_line_editor.lua` | +15. Call `canonicaliseLegacy` on open; pass `legacy_literal` flag to preview. |
| `menu/token_picker.lua` | ~60 lines rewritten (in place; file size similar). |
| `README.md` | ~100 lines rewritten (token table + examples). |
| `docs/release-notes-5.0.0.md` | New, ~60 lines. |
| `_test_tokens.lua` | New, ~200 lines. |
| `_test_conditionals.lua` | +30. |
| `locale/bookends.pot` | 5–10 new msgids. |
| `locale/*.po` (6 files) | 5–10 new entries per file; existing entries reused verbatim under renamed Lua-side associations. |

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Alias rewrite accidentally mangles user text containing `%A` as literal content | Low — `%X` in format strings is always token-intended | Single-letter regex only rewrites known `TOKEN_ALIAS` entries; unknown letters fall through untouched. Tested with mixed-content fixtures. |
| `canonicaliseLegacy` non-idempotency creeps in | Low — regex is single-letter-targeted | Idempotency test in `_test_tokens.lua`. Specifically cover strings containing both `%A` and `%author` (rewrite-collision edge). |
| State-key rewrite touches literal values inside predicates | Low — rewrite walks tokenised predicate, not raw string | Test: `[if:title=chapters]` keeps "chapters" as literal value. |
| Preview-mode label tables drift from new vocabulary | Medium — 45 entries to update | Preview labels live in `preview` table inside `Tokens.expand`. Rewrite the whole table in one edit; verify by snapshot test. |
| Token picker descriptions reference old letter codes in user-visible text | Low — inspected, descriptions are semantic ("Author(s)"), not syntactic | Quick grep for `"%"` in `_()` call arguments; fix any leakage. |
| Translation coverage slips during rollout | Medium | Existing parallel-agent dispatch workflow (per `reference_translation.md`). All 6 .po files updated before release tag. |
| Peer-to-peer preset sharing pre-v5 → v5 users breaks | Certain, by design | Documented in release notes; one-way migration. |
| Gallery-preset compatibility regresses | Low — aliases active on device | Install a current-gallery preset end-to-end and verify render on device before release. |

## Release notes bullets (draft)

- **Readable tokens.** `%A` is now `%author`, `%T` is `%title`, `%J` is `%chap_count` — all 45 tokens have descriptive names. Full rename table in the docs. Your existing presets keep working: the old one-letter names still resolve on device. Open any preset in the line editor and you'll see it automatically converted to the new vocabulary.
- **Custom date formats.** New `%datetime{…}` token accepts any strftime spec — e.g. `%datetime{%d %B}` for "23 April", `%datetime{%A, %d %B}` for "Thursday, 23 April", `%datetime{%I:%M %p}` for "7:42 PM". Plain `%time`, `%date`, and `%weekday` still give the familiar defaults you know. If you need a cheatsheet of strftime codes, [strftime.net](https://strftime.net/) is the friendliest one out there.
- **Series split.** `%series` still shows "Foundation #2" combined. New `%series_name` and `%series_num` give you the parts separately when you want custom layout.
- **Conditional names match tokens.** `[if:chap_count>10]` is the canonical form; `[if:chapters>10]` still works. Same vocabulary, one set of words.
- **Line editor teaches the new names.** When you open an existing preset, legacy token codes are rewritten to readable names in place. Type `%chap_num` and it resolves; typing the old `%j` shows literal `%j` while you're mid-edit, so you know which names are current.
- **Known limitation.** Presets edited in v5 use the new names in their stored form. If you share such a preset file with someone still on a pre-v5 Bookends build, they won't recognise the new names. One-way migration.

## Open questions for writing-plans

None as of spec finalisation. All shape decisions locked through the brainstorming Q&A on 2026-04-23.
