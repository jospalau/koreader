---
name: review-preset-submission
description: Review an incoming Bookends preset PR on AndyHazz/bookends-presets. Validates syntax, metadata, flags hidden conditional tokens that can hide content from quick previews, checks device-specific fonts, detects disabled regions, suggests naming improvements, installs on the Kindle for preview, and carries out merge (with optional tweaks) when approved.
---

# Reviewing a Bookends preset submission

Invoke as: "Review PR #N" (or any request where the user references a PR number on `AndyHazz/bookends-presets`).

## Goal

Turn a raw preset PR into a short, actionable report so the maintainer can decide merge / modify-and-merge / reject without having to read 250 lines of autosaved Lua table or rely solely on a single-moment on-device preview.

The maintainer **will preview on-device** for aesthetic review. Your job is the **mechanical review** — everything that's easy to miss in a quick visual check.

**Important context:** PRs are opened by the maintainer's own PAT (via the Cloudflare submission Worker), so the real submitter (whose name lives only inside the preset's `author` field) has no GitHub identity on the PR — there is no way to comment back at them or ask them to revise. The three real options are:

1. **MERGE** — file is fine as-is.
2. **MODIFY AND MERGE** — rename / strip disabled flags / fix description in place on the PR branch, then merge. This is the main recourse for anything the submitter "should have done differently".
3. **REJECT** — close the PR without merging. Only for genuinely unsafe or broken submissions.

## Process

### 1. Fetch PR metadata and content

```bash
gh pr view <N> --repo AndyHazz/bookends-presets --json title,author,body,headRefName,mergeable,files
gh pr diff <N> --repo AndyHazz/bookends-presets > /tmp/diff_<N>.patch
awk '/^\+\+\+/{getline; next} /^\+/{print substr($0,2)}' /tmp/diff_<N>.patch > /tmp/<slug>.lua
luac -p /tmp/<slug>.lua
```

Check `mergeable: "MERGEABLE"` — if not, report to user and stop.

### 2. Run the checks below on the extracted `.lua` file

Report findings grouped by check. Use ✓ for passes, ⚠ for soft concerns, ❌ for hard blockers.

### 3. Install on Kindle for preview

```bash
scp /tmp/<slug>.lua kindle:/mnt/us/koreader/settings/bookends_presets/
```

If the Kindle is unreachable (`No route to host`), note the file is staged in `/tmp/` and can be pushed when wifi is back.

### 4. Report

Format:

- **Preset**: name (author) — one-line description.
- **Syntax**: ✓ or ❌ details.
- **Metadata**: ✓ / ⚠ with specifics.
- **Fonts**: ✓ or ❌ (device-specific → hard reject).
- **Conditional tokens**: itemised list of every `[if:...]` with what condition triggers it (CRITICAL — see below).
- **Disabled regions**: itemised list of any region with `disabled = true` plus whatever tokens it contains that won't render.
- **Naming**: ✓ / ⚠ vs. existing gallery entries.
- **Recommendation**: MERGE / MODIFY AND MERGE / REJECT — with the specific diff if modifying.

### 5. On approval, carry out the merge

**Merge as-is**:
```bash
gh pr merge <N> --repo AndyHazz/bookends-presets --squash --delete-branch
```

**Reject** (only for genuinely unsafe / broken submissions — the submitter won't see any feedback):
```bash
gh pr close <N> --repo AndyHazz/bookends-presets --delete-branch
```

**Modify and merge**: edit file in-place, PUT to the PR branch, then merge. Example rename:
```bash
# fetch current file from branch
gh api "repos/AndyHazz/bookends-presets/contents/presets/<slug>.lua?ref=<branch>" --jq '.content' | base64 -d > /tmp/<slug>.lua
# sed in the rename (watch for apostrophes — use different sed delimiters if needed)
sed -i '1s/^-- Bookends preset: .*$/-- Bookends preset: <new name>/; s/^    name = ".*",$/    name = "<new name>",/' /tmp/<slug>.lua
luac -p /tmp/<slug>.lua
# push back
FILE_SHA=$(gh api "repos/AndyHazz/bookends-presets/contents/presets/<slug>.lua?ref=<branch>" --jq '.sha')
gh api --method PUT repos/AndyHazz/bookends-presets/contents/presets/<slug>.lua \
  -f message="<why>" \
  -f content="$(base64 -w0 /tmp/<slug>.lua)" \
  -f sha="$FILE_SHA" \
  -f branch="<branch>" \
  --jq '.commit.html_url'
# merge
gh pr merge <N> --repo AndyHazz/bookends-presets --squash --delete-branch
```

After merge, the `Regenerate index.json` Action fires (serialised via a concurrency group — safe even for burst merges) and updates the gallery within ~30s.

---

## Checks in detail

### Metadata sanity

- **`name` field**
  - Not empty.
  - Capitalised reasonably (leading uppercase for English names; respect native capitalisation for non-English).
  - Not generic/reserved: `"Default"`, `"Basic"`, `"Basic bookends"`, `"Test"`, `"Untitled"`, or single-word names that describe nothing about the preset → rename via modify-and-merge.
  - Not already in use — compare (case-insensitive) against the live gallery:
    ```bash
    gh api repos/AndyHazz/bookends-presets/contents/index.json --jq '.content' | base64 -d | grep '"name"'
    ```
- **`author`**: non-empty, not just a placeholder like `"me"` or `"user"`.
- **`description`**: non-empty, ≤120 chars (Worker already enforces, but re-check), matches the actual content of the preset. A "Simple books" description on a preset showing clock, battery, memory, frontlight, and chapter title is a mismatch worth flagging.

### Font portability (HARD BLOCKER if violated)

The Worker strips device-specific fonts automatically and warns the submitter. If any slip through, the preset won't render the same on other devices.

Scan every `line_font_face` array. Allowed entries:
- empty string/slot (nothing set)
- `@family:serif` / `@family:sans-serif` / `@family:monospace` / `@family:cursive` / `@family:fantasy` / `@family:ui` — these are the portable sentinels.

Anything else (e.g. `"/mnt/us/fonts/FooBar.ttf"`, `"Caecilia.ttf"`, `"Bookerly Regular"`) means the Worker failed to strip something. Two options: modify-and-merge by clearing the offending `line_font_face` entries (they fall back to the user's default font), or reject as fundamentally broken. Prefer modify-and-merge — the submitter can't fix it themselves.

Also check `defaults.font_face` for the same.

### Conditional tokens (CRITICAL — the reviewer's blind spot)

The on-device preview shows ONE state at one moment. Conditional tokens wrap content that only renders under specific conditions — they will be invisible in the preview if the condition isn't currently true.

Regex scan: `grep -oE '\[if:[^\]]+\]' /tmp/<slug>.lua`

Common conditions (all supported as of v4.0.x):
| Condition | Example | Triggers when |
|---|---|---|
| `time>=HH`, `time<HH`, `time=HH` | `[if:time>=23]` | After 11pm |
| `day=<weekday>` | `[if:day=Sun]` | Specific weekday |
| `batt<N`, `batt>N` | `[if:batt<20]` | Battery level threshold |
| `charging=yes` / `charging=no` | `[if:charging=yes]` | Charging state |
| `light=on` / `light=off` | `[if:light=off]` | Frontlight state |
| `connected=yes` / `connected=no` | `[if:connected=no]` | Wi-Fi state |
| `format=EPUB` etc. | `[if:format=PDF]` | Document type |
| `invert=yes` | `[if:invert=yes]` | Page-turn direction flipped |
| `page=odd` / `page=even` | `[if:page=odd]` | Page parity |
| Custom `[else]` branches | `[if:X=Y]A[else]B[/if]` | Both sides — check both |

For each conditional in the preset, explicitly report:
> Line `<region>[<idx>]` shows `<branch-content>` only when `<condition>`.

**Why this matters:** A preset could show a friendly "Good night!" message every evening, or "Happy Birthday!" on a specific date, or a hidden "Unauthorised" message that fires after `11pm on Sundays` — and none of that would be visible in a normal daytime preview. The reviewer needs a complete catalogue.

Also note: if a preset uses `[else]` branches, both sides are behavior — report the else content too.

### Disabled regions

Grep for `disabled = true` in each position block. If a region has both `disabled = true` and non-empty `lines`, that content won't render when installed — almost always an accidental capture of the submitter's local state.

> `bl` region has `disabled = true` but contains `"%W %B%b"` — probably unintentional. Remove the `disabled = true,` line before merging (modify-and-merge path).

### Colour usage (soft check)

v4.3 presets may contain hex colour values that only render faithfully on colour-capable e-ink devices (Kindle Colorsoft, Kobo Libra Colour, Boox Go Color). On greyscale devices hex values fall back to Rec.601 luminance — still legible, but the aesthetic flattens.

Scan for hex colours in the submitted preset:

```bash
# {hex="#RRGGBB"} or {hex="#RGB"} in stored settings (bar_colors, text_color, symbol_color)
grep -nE 'hex = "#[0-9A-Fa-f]{3,6}"' /tmp/<slug>.lua
# Inline [c=#hex] tags in line text (format-string colouring)
grep -nE '\[c=#[0-9A-Fa-f]{3,6}\]' /tmp/<slug>.lua
```

Neutral-equivalent hex (all channels equal, e.g. `#404040`, `#222`, `#FFF`) collapses to greyscale at paint time — those don't count as "uses colour" for the gallery flag, but still worth reporting as greyscale intent.

Format in the report:

> **Colour usage**: ⚠ preset uses 3 hex colour values — `#7F08FF` at `bar_colors.fill`, `#FFB58C` at `progress_bars[1].colors.bg`, `[c=#F0A]` inline in `positions.bc.lines[2]`. (Or: ✓ no hex colour values.)

No reject gate — this is purely informational so the maintainer knows whether the preset targets colour hardware. The gallery glyph (🎨 equivalent — actually a small coloured-stripe flag) fires automatically based on index.json metadata; no reviewer action needed unless the preset has been mis-authored (e.g. a single stray hex tag the author forgot to remove).

### Margin and layout sanity

Check `progress_bars[i]` entries that are `enabled = true`:
- If `margin_left + margin_right > 1000`, the bar width assumes a wide device. On narrower devices (older Kindles, 6" Kobos) it could become ≤0 px wide or off-screen. Flag if seen.
- If `height > 40`, visually dominant — worth a maintainer's eye.
- If `chapter_ticks = "all"` on a thick bar with lots of chapters, can look noisy. Not a blocker.

### Naming overlap with gallery

```bash
gh api repos/AndyHazz/bookends-presets/contents/index.json --jq '.content' | base64 -d | grep '"name"' | sed 's/.*"name": "//; s/",.*//' | sort -f
```

If the new `name` matches an existing entry (case-insensitive, trimmed) or is 1 character off, rename it during modify-and-merge (e.g. `"Default"` → `"<author>'s Default"`, or append a differentiator based on what the preset actually does).

---

## What this skill can and can't catch

**Catches reliably** (the mechanical layer):
- Syntax errors, non-portable fonts, disabled regions with content.
- Every conditional token and its triggering condition — closes the biggest blind spot in quick on-device previews.
- Name collisions against live gallery.
- Metadata mismatches (description vs. content).
- Obviously generic or placeholder names.
- Colour-value usage (`hex = "#…"` in settings or `[c=#…]` inline tags) reported in the mechanical output.

**Can't catch** (still needs the maintainer's eye):
- Aesthetic taste — does the layout actually look good? Is the font pairing awkward?
- Cultural appropriateness of non-English content.
- Subtle rendering bugs only visible on a specific device/rotation/font size.
- Performance issues from unusual token combinations.
- Whether the preset's *point* is communicated clearly by the name+description.

So the skill does the thorough-but-mechanical first pass; the maintainer previews on-device for the bits that need human judgment.

---

## Concurrency note

`regenerate-index.yml` has a `concurrency: { group: regenerate-index, cancel-in-progress: false }` block, so merging several PRs in quick succession queues the index regens instead of racing them. Safe to merge back-to-back.
