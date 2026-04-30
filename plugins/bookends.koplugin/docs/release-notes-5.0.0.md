# Bookends v5.0.0 — release notes

v5 is a big spring-clean of how tokens are named. The tokens you type into a
line now read like English — `%author` instead of `%A`, `%chap_count` instead
of `%J`, `%book_pct` instead of `%p`. Presets you already have keep working:
the old one-letter names still resolve on your device. Open an existing
preset in the line editor and you'll watch the old codes get rewritten to
the new names right in front of you, so you can see what each one means.

## What's new

- **Readable tokens.** All tokens have descriptive names aligned with the
  conditional system, so `%author` and `[if:author]` speak the same
  language. See the README for the full list. Your existing presets are
  untouched on disk — the new names just show up in the editor when you
  open them.

- **Custom date formats.** New `%datetime{…}` token accepts any strftime
  spec.
  - `%datetime{%d %B}` → "23 April"
  - `%datetime{%A, %d %B}` → "Thursday, 23 April"
  - `%datetime{%I:%M %p}` → "7:42 PM"

  If you need a cheatsheet of strftime codes,
  [strftime.net](https://strftime.net/) is a friendly reference. Plain
  `%time`, `%date`, and `%weekday` still give you the familiar defaults.

- **Series split.** `%series` still shows "Foundation #2" combined. New
  `%series_name` and `%series_num` give you the parts separately when you
  want a custom layout.

- **Line editor only shows v5 names while typing.** Mid-word typing like
  `%chap_num` no longer flickers through old meanings when you pass
  through `%c`. Legacy tokens stay literal in live preview; they resolve
  normally once your preset is rendered on the device.

## Compatibility

- Existing presets (yours and gallery) render identically. No action required.
- Conditional predicates: `[if:chapters>10]` still works; `[if:chap_count>10]`
  is the canonical form.
- Presets you edit and save in v5 use the new names in their stored form.
  If you share such a preset file with someone still on Bookends v4, they
  won't recognise the new names — that's a one-way migration. Older plugin
  versions continue to read their own presets fine.
