# Conditional operators, nesting & predicate expansion — design

## Motivation

Three related gaps in the `[if:...]...[/if]` conditional-token feature:

1. **No AND/OR composition.** Expressing "after 18:00 but before 18:30" requires nesting, which doesn't work today — the current parser is a single-pass gsub that mangles nested blocks (the outer opener gets glued to the inner closer). Expressing OR is impossible without duplicating the body.
2. **No way to condition on chapter count.** Requested in issue [#23](https://github.com/AndyHazz/bookends.koplugin/issues/23). The `%J` token exposes chapter count but conditionals can't see it.
3. **No way to condition on text-field emptiness.** A common status-bar design pattern is "show the deepest chapter title you have, falling back to a shallower one if the deepest is empty" — e.g. show `%C2` when in a sub-chapter, `%C1` otherwise. Today there's no predicate that sees the same strings `%T`/`%A`/`%S`/`%C1..3` resolve to.

While extending the grammar, we also clean up three existing predicate names that have aged badly:

- `state.percent` means *book* percent (confusingly vague once a chapter-number predicate exists).
- `state.chapter` means *chapter* percent (actively misleading once `chapter` becomes the chapter-number predicate).
- `state.pages` means *session* pages read (could easily be misread as book-pages or chapter-pages).

A grep of the live gallery (13 presets) finds **zero** uses of `[if:percent...]`, `[if:chapter...]`, or `[if:pages...]`, and the README has only one example referencing `percent`. The rename window is still open.

## Scope

**In scope:**

1. Nested `[if:A][if:B]...[/if][/if]` blocks, any depth, composing with `[else]`.
2. Boolean operators inside the predicate: `not` (prefix), `and`, `or`, with parens for grouping. Standard precedence (`not` tightest, `or` loosest).
3. New numeric predicates: `chapter` (1-indexed current chapter number, matches `%j`), `chapters` (total chapter count, matches `%J`).
4. New string-valued predicates for text-field emptiness/equality checks: `title`, `author`, `series`, `chapter_title`, `chapter_title_1`, `chapter_title_2`, `chapter_title_3` (mirroring `%T`/`%A`/`%S`/`%C`/`%C1`/`%C2`/`%C3`).
5. Renamed predicates: `percent` → `book_pct`; old `chapter` (% through chapter) → `chapter_pct`; `pages` → `session_pages`.
6. Shared helper `Tokens.getChapterTitlesByDepth(ui, pageno)` factored out of `Tokens.expand` — used by both `expand` and `buildConditionState` so `%C2` rendering and `chapter_title_2` predicate evaluation can't drift.
7. README predicate table update and one example update.
8. Release-notes entry flagging the breaking renames.

**Out of scope:**

- Token renaming (`%J` → `%chapters` etc.). Separate future branch, separate decisions.
- **Series-token split** (`%S` → name-only + new index token). The natural letter pairing (`%S`/`%s`) is blocked because `%s` is currently "session pages read" and moving it has no good replacement letter. Deferred to the readable-tokens branch where `%series` / `%series_num` / `%series_name` fit naturally. The new `series` state key (full "Name #N" string) does cover the most useful conditional case — `[if:series]Part of a series[/if]` / `[if:not series]Standalone[/if]` — so the feature need is largely addressed at the conditional level without a token split.
- `elif` or multi-branch conditionals. The existing `[if:A][else][if:B][else]...[/if][/if]` idiom now works (post-nesting) and is sufficient.
- Error surfacing for malformed predicates. Silent-fail matches current behaviour and the plugin's low-ceremony style.
- Backward-compatibility aliases for renamed predicates. Clean break, noted in release notes.

## Architecture

Single file: **`bookends_tokens.lua`**.

Four logical pieces change:

| Area | Change |
|------|--------|
| `processConditionals` (line 106–119) | Replaces the one-shot gsub with an **innermost-peel loop** that resolves nested blocks inside-out. |
| `evaluateCondition` (line 78–103) | Becomes the atom evaluator (unchanged semantics). A new `evaluateExpression` wraps it as a recursive-descent expression parser supporting `not`/`and`/`or`/parens. |
| `buildConditionState` (line 124–228) | Adds numeric predicates (`chapter`, `chapters`), string predicates (`title`, `author`, `series`, `chapter_title`, `chapter_title_1..3`), renames `percent` → `book_pct`, old `chapter` → `chapter_pct`, `pages` → `session_pages`. |
| New helper `Tokens.getChapterTitlesByDepth` | Factored out of the inline TOC-walk inside `expand`. Called by both `expand` (for `%C`/`%C1..3` rendering) and `buildConditionState` (for `chapter_title*` predicates). Single source of truth. |

No other files changed except:

- `README.md` — conditional-predicate table gains new rows, removes old names, updates the `[if:percent>90]` example.
- `CHANGELOG.md` (or wherever release notes live) — breaking-rename entry.

## Components

### Predicate state table — final shape

**Numeric predicates:**

| Key           | Meaning                                 | Source                         | Status |
|---------------|------------------------------------------|--------------------------------|--------|
| `chapter`     | current chapter number (1-indexed)       | flat TOC walk, matches `%j`    | **new** |
| `chapters`    | total chapter count                      | `#ui.toc.toc`, matches `%J`    | **new** |
| `chapter_pct` | % through current chapter (0–100)        | (unchanged math)               | **rename** of `chapter` |
| `book_pct`    | % through book (0–100)                   | (unchanged math)               | **rename** of `percent` |
| `session_pages` | pages read in current session          | (unchanged math)               | **rename** of `pages` |
| `batt`, `charging`, `light`, `connected`, `invert`, `page`, `format`, `time`, `day`, `session`, `speed`, `wifi` | existing | unchanged | unchanged |

**String predicates** (new — enable emptiness / string-equality checks):

| Key                 | Source (matches token) | Example use |
|---------------------|------------------------|-------------|
| `title`             | `%T` — book title                  | `[if:title]%T[else]%N[/if]` (fall back to filename) |
| `author`            | `%A` — author                      | `[if:not author]Unknown[/if]` |
| `series`            | `%S` — series (with index)         | `[if:series]Part of a series[/if]` |
| `chapter_title`     | `%C` — current chapter title (same source as `%C`) | `[if:chapter_title=Introduction]Welcome[/if]` |
| `chapter_title_1`   | `%C1` — chapter title at depth 1   | `[if:chapter_title_1]%C1[/if]` |
| `chapter_title_2`   | `%C2` — chapter title at depth 2   | `[if:chapter_title_2]%C2[else]%C1[/if]` (user's example) |
| `chapter_title_3`   | `%C3` — chapter title at depth 3   | `[if:chapter_title_3]%C3[/if]` |

String predicates evaluate via existing grammar — no syntax additions. Empty string is falsy (via the `evaluateCondition` truthy fallback), so `[if:not chapter_title_2]` = "chapter title at depth 2 is empty". `=` comparison works for string equality. No operator for substring/regex match — YAGNI.

The `chapter` / `chapters` derivation mirrors `%j` / `%J` exactly — walks `ui.toc.toc` counting entries with `page <= pageno`. Reuses the existing lookup, no new `ui.toc` API calls. String predicates are sourced from the shared `Tokens.getChapterTitlesByDepth` helper and the same book-metadata fields `expand` reads for `%T`/`%A`/`%S`, so the predicate and the token *cannot* drift.

### Grammar

```
expr   := or_expr
or_expr  := and_expr ("or" and_expr)*
and_expr := not_expr ("and" not_expr)*
not_expr := "not" not_expr | primary
primary  := "(" expr ")" | atom
atom     := key (op value)?          -- single whitespace-delimited token, no internal whitespace
op       := "=" | "<" | ">"
key      := [A-Za-z_][A-Za-z0-9_]*
value    := characters after `op` up to the next whitespace or `)`
```

**Precedence**: `not` tightest, then `and`, then `or`.

**Whitespace** separates tokens. A key / value may not contain whitespace. This matches every existing predicate (`day=Sun`, `batt<20`, `time>=18:30`) — no gallery preset or README example uses spaces inside a predicate value. Safe rule.

**Backward compatibility**: a bare atom (the only form that exists today) parses as `or_expr → and_expr → not_expr → primary → atom` with zero operators — the new grammar trivially subsumes the old.

### Nesting — peel-innermost algorithm

```
function processConditionals(format_str, state):
    loop:
        find the first "[/if]" in format_str
        if none: break
        find the last "[if:...]" that appears BEFORE that "[/if]"
        if none: break (malformed — leave as-is)
        extract the block [if:cond]body[/if]
        split body on first [else] (if any)
        if evaluateExpression(cond, state): replace block with if_part
        else:                                replace block with else_part
    return format_str
```

Each iteration resolves exactly one innermost block — by construction it contains no nested `[if:]` because we took the `[if:]` closest to the first `[/if]`. After substitution, an outer block's body is now "flat" relative to whatever's left, so the next iteration peels it.

**Complexity**: O(n) per iteration × O(depth) iterations = O(n·d). For a status-bar string (≤200 chars, nesting depth ≤3 in realistic cases), negligible — the current single-pass gsub isn't meaningfully faster.

**Edge cases:**

- Unbalanced tags (`[if:x]foo` with no closer): innermost scan finds no `[/if]`, loop exits, string left as-is. Matches current behaviour.
- Orphan `[/if]` with no preceding `[if:`: scan finds the closer but no matching opener before it, loop exits, string left as-is.
- Empty condition (`[if:]foo[/if]`): evaluateExpression returns false, if_part discarded, else_part (empty) substituted.
- Literal `[if:` in text content with no `[/if]`: harmless — just text.
- Literal `[/if]` in text preceded by an unrelated `[if:`: this is the one theoretical false-positive. Users don't write literal `[/if]` in status bars in practice; accepting this matches the current parser's already-greedy behaviour.

### Expression evaluator

A recursive-descent parser over a whitespace-tokenised cond string. Roughly:

```
function evaluateExpression(cond_str, state):
    tokens = tokenise(cond_str)      -- keywords "and"/"or"/"not"/"("/")" + atoms
    pos = 1
    return parseOr(tokens, state)    -- pos captured in closure / table
```

Tokenisation walks the string char-by-char, emitting:
- `(` / `)` as single-char tokens
- Runs of non-whitespace / non-paren chars as atom tokens
- Whitespace skipped
- Keywords `and`/`or`/`not` recognised after tokenisation (case-sensitive, lowercase)

`parseAtom` delegates to the existing `evaluateCondition` — all legacy atom logic (numeric comparison, HH:MM parsing, truthiness fallback) is preserved verbatim.

~40 lines of Lua. No deps.

### Preview mode interaction

`Tokens.expand` has a preview-mode branch (used by the token picker to show label strings). Preview mode currently **skips conditional processing entirely** (line 239: `if not preview_mode and format_str:find("%[if:")`). Unchanged. Conditionals render their raw `[if:...]` / `[else]` / `[/if]` markers in preview, as today.

## Migration

**Breaking renames** (three predicate names):

| Old                    | New                  | Risk |
|------------------------|----------------------|------|
| `[if:percent>N]`       | `[if:book_pct>N]`    | Low — unknown key evaluates false, user notices and fixes. |
| `[if:chapter>N]`       | `[if:chapter_pct>N]` | **Silent**: the name `chapter` gets reclaimed for the new chapter-index predicate, so old usage would silently start comparing numbers instead of percentages. Called out in release notes; gallery has zero affected presets. |
| `[if:pages>N]`         | `[if:session_pages>N]` | Low — unknown key evaluates false. |

**Files to update:**

- `README.md` — line 170 (`[if:percent>90]` example) → `[if:book_pct>90]`, plus the predicate table (add new rows, remove old names).
- Release notes / CHANGELOG — entry under "Breaking changes" listing the three renames.

**No gallery migration needed** — zero presets use any of the old names.

**No token-picker UI changes** — the picker doesn't expose a conditional builder today; conditionals are typed by hand in the line editor.

## Testing

A new `tests/conditionals_spec.lua` (if the test harness exists) or a `_test_conditionals.lua` scratch script covering:

### Nesting

- `[if:a=1][if:b=2]inner[/if][/if]` with both true → `inner`.
- Same with outer true / inner false → `""`.
- Same with outer false → `""` regardless of inner.
- Three-deep: `[if:a=1][if:b=2][if:c=3]x[/if][/if][/if]` with all true → `x`.
- Nested with `[else]` on outer: `[if:a=1][if:b=2]bb[/if][else]A-else[/if]`.
- Nested with `[else]` on inner: `[if:a=1][if:b=2]bb[else]b-else[/if][/if]`.
- Both: `[if:a=1][if:b=2]bb[else]b-else[/if][else]A-else[/if]`.

### Operators

- `[if:batt<50 and charging=yes]` — true only when both.
- `[if:day=Sat or day=Sun]` — true on either.
- `[if:not charging=yes]` — true when not charging.
- `[if:(a=1 or b=2) and c=3]` — grouping works.
- `[if:a=1 and b=2 or c=3]` — `and` binds tighter: evaluates as `(a and b) or c`.
- `[if:a=1 or b=2 and c=3]` — evaluates as `a or (b and c)`.
- `[if:not a=1 and b=2]` — `not` binds tightest: `(not a) and b`.

### New numeric predicates

- `[if:chapters>20]Long book[/if]` — true when TOC has >20 entries.
- `[if:chapter=1]Foreword[/if]` — true in first chapter.
- `[if:chapter_pct>50]past half of chapter[/if]` — true when halfway through current chapter.
- `[if:book_pct>90]Almost done[/if]` — true when past 90% of book.
- `[if:session_pages>10]`, renamed from `[if:pages>10]`.

### New string predicates

- `[if:not series]Standalone[else]%S[/if]` — empty series falls to true on negation.
- `[if:chapter_title_2]%C2[else]%C1[/if]` — user's motivating example; show depth-2 title if non-empty, depth-1 otherwise.
- `[if:author=Anonymous]` — string equality.
- `[if:not title]` — empty title (rare but handled for symmetry).
- Combined with operators: `[if:series and not chapter_title_2]%S · %C1[/if]`.

### Regression (backward compat)

Every existing gallery conditional continues to render correctly:
- `[if:connected=yes]%W[/if]`, `[if:batt<20]`, `[if:charging=yes]`, `[if:light=off]%f[else]...[/if]`, `[if:format=EPUB]...`.

### Edge cases

- Unbalanced: `[if:a=1]foo` → passes through unchanged.
- Orphan closer: `foo[/if]bar` → passes through unchanged.
- Unknown key: `[if:nonsense=yes]x[/if]` → false, `x` stripped.
- Empty predicate: `[if:]x[/if]` → false, `x` stripped.

## Release notes entry (draft)

> **Breaking**: conditional predicate renames.
>
> - `[if:percent>N]` → `[if:book_pct>N]` (percent through book)
> - `[if:chapter>N]` → `[if:chapter_pct>N]` (percent through current chapter)
> - `[if:pages>N]` → `[if:session_pages>N]` (pages read in current session)
>
> The name `chapter` now means the *current chapter number* (matching the `%j` token), and a new `chapters` predicate exposes the total chapter count (matching `%J`). If you'd built a preset around `[if:chapter>50]`, update it to `[if:chapter_pct>50]` — otherwise it will silently start comparing chapter numbers.
>
> **New**: nested conditionals, boolean operators, and string/chapter-title predicates.
>
> - Nesting: `[if:time<18:30][if:time>=18:00]between 6 and 6:30[/if][/if]`
> - Operators: `[if:time>=18:00 and time<18:30]...[/if]`, `[if:day=Sat or day=Sun]weekend[/if]`, `[if:not charging=yes]running on battery[/if]`
> - Grouping: `[if:(day=Sat or day=Sun) and batt<50]...[/if]`
> - Chapter number / count: `[if:chapters>20]Long read[/if]`, `[if:chapter=1]Foreword[/if]`
> - Text-field emptiness: `[if:chapter_title_2]%C2[else]%C1[/if]` (show sub-chapter title when present, otherwise fall back to the parent chapter), `[if:not series]Standalone[/if]`, `[if:author=Anonymous]`.

## Work breakdown estimate

Ballpark for the implementation phase (separate from this design):

- `processConditionals` peel loop: ~20 lines.
- Expression parser + tokeniser: ~40 lines.
- `Tokens.getChapterTitlesByDepth` helper + extraction from `expand`: ~25 lines (about half is moved code).
- State-table additions/renames (numeric + string predicates): ~25 lines.
- README updates: ~25 lines across the predicate table + one example.
- Release notes entry: ~20 lines.
- Test script: ~80 lines covering the cases above.

Total: ~235 lines across 2–3 files. Two development sessions.
