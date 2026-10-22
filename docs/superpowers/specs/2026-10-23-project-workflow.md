# Project-centered learning workflow

User approved implementation after iterative discussion and visual mockups.
Keep the existing Today time-period layout. Add a plain Project planning view,
grouped by long-term goal and DIVE/TODO/HOLD, with source navigation, folding,
start scheduling and state controls. Show current phase/next action without
commitment glyphs. DONE is available but collapsed. No duplicated plan storage.

Explicit goal/project properties identify boundaries: existing DIVE chapter groups
must not silently become projects. Register existing headings interactively; never
migrate personal files automatically. Sources remain ordinary agenda Org files.

TODO projects start on SCHEDULED date; DIVE generates one daily commitment without
requiring a project schedule. First executable unfinished leaf in current active
branch is selected. Never count QA/LAB/HW as execution leaves, nested project roots,
habits, HOLD/DONE branches or future-scheduled steps. Missing next action is visible.
Commitments freeze for the day; finishing one never automatically adds another.
Across dates the unfinished step receives today's responsibility without stacking
old project responsibilities. No retroactive success or invented offline duties.

Pause immediately withdraws unfinished daily commitments, preserving completed
facts and all clocks. Same-day resume reuses the same record. Goal pause records
only its DIVE projects; goal resume restores only those still paused by that batch.
Manual intervening edits override batch restoration. No missed-day debt on resume.

Task commitment satisfaction requires completion. A configurable whole-day minimum
investment is an alternative daily floor, not task completion. Empty/withdrawn sets
are not automatically successful. Preserve historical snapshots and record a dated
semantics boundary. Persist per-day threshold when first used, so changing settings
does not rewrite prior floors. Use existing coordinated Org/SQLite transactions.

Approaches: time-first Today redesign was deferred by user; retain current Today
and add separate project view. Prefer native text/Org navigation over web/cards.
User authorized independent implementation without further design approval.
