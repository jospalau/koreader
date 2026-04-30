### New statistics tokens

Seven new tokens that surface the reading data KOReader's statistics plugin already collects:

- `%pages_today` and `%time_today`: pages and reading time today across all books
- `%book_pages_read`: total pages of this book read, lifetime
- `%book_pct_read`: book completion percentage, skip-aware. Complements the existing position-based `%book_pct`
- `%avg_page_time`: average time per page
- `%days_reading_book`: days since first opening this book
- `%pages_per_day`: average pages per day for this book

### Session counters now skip-aware

`%session_pages` and `%session_time` now source from the statistics plugin too. Pages flicked past faster than the dwell threshold (default 5 seconds) no longer inflate the session totals. Counters still reset on book open or wake from suspend, and fall back to the previous behaviour when the statistics plugin is disabled.

### Colour picker fixes

Fixed a lockup on Kobo Libra Colour where typing a custom hex colour trapped users behind the on-screen keyboard. The picker has had a visual polish too: a live preview swatch that updates as you type, a static `#` prefix you can't accidentally delete, and tidier spacing throughout the dialog.
