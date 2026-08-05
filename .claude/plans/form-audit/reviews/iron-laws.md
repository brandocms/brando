# Iron Law Violations Report — commit 2c26cb31b

## Summary
- Files scanned (lib/ + test/, added lines only): `lib/brando_admin/components/form/block/render.ex`, `lib/brando/content/block.ex`, `test/brando/content/conditional_refs_test.exs`
- Iron Laws checked: 8 of 26 (relevant subset: raw/inline-style, HOF/loops, aliases, template constants, Ecto changeset patterns, comments-as-commit-messages)
- Violations found: 0 blocker/warning; 2 suggestions (LOW, comment style)

## Pre-Existing (not introduced by this commit, do not attribute)

- `lib/brando_admin/components/form/block/render.ex:907` — `{raw(split)}` (Law #12, `raw/1` with untrusted content). Introduced in commit `ad47cd205`. This commit's only addition in that region is line 910, `<.carried_refs refs_field={@block_form[:refs]} liquid_splits={@liquid_splits} />`, which is clean (no `raw`, no interpolation).

## Clean — verified against project conventions

- `lib/brando_admin/components/form/block/render.ex:1225-1241` (`carried_refs/1`): uses `hidden` boolean attribute (`<div class="block-carried-refs" hidden>`), not an inline `style`. Complies with "never use inline styles" convention.
- Same function uses a `for {:ref, name} <- assigns.liquid_splits, do: name` comprehension (HOF-idiomatic), no manual accumulator loop.
- `lib/brando/content/block.ex` `ref_changeset/3` (block.ex:281-303): adds `:gallery_id` to the cast list alongside `cast_assoc(:gallery, ...)`. Correctly relies on `on_replace: :nilify` for the `gallery` belongs_to and does not mix `put_change(:gallery_id, nil)` with `put_assoc(:gallery, ...)` — matches the documented Ecto changeset pattern.
- `finalize_new_block/2` (block.ex:182-202): strips `:replace` ref/var changesets and forces `action: :insert` for pk-less blocks — correct handling of the "marking structs as new" gotcha (avoids `NoPrimaryKeyValueError`).
- `test/brando/content/conditional_refs_test.exs`: no factory/schema mismatches, no `Process.sleep`, async correctly disabled (`async: false`, uses `Brando.ConnCase`/Repo). No violations.

## Low / Suggestion — Comments Convention (Law #19)

### [#19] Comments aren't commit messages
- **File**: `test/brando/content/conditional_refs_test.exs:1-8`
- **Code**: `# B5 verification — are refs inside \`{% if %}\` / \`{% for %}\` regions deleted\n# on the first keystroke?`
- **Confidence**: REVIEW
- **Fix**: `B5` reads as a plan/ticket-step reference. Keep the durable behavioral explanation (what `liquid_strip_logic/1` does, why `on_replace: :delete_if_exists` matters) but drop the "B5 verification" framing — that traceability belongs in the commit/PR, not the test file docstring.

### [#19] Comments aren't commit messages
- **File**: `lib/brando/content/block.ex:290-294`
- **Code**: `# ... :gallery_id was missing, so a gallery picked on a ref was dropped by the cast — the same omission as the var list above. Casting the FK alongside cast_assoc(:gallery, ...) is safe: params carry one or the other, and the relation is on_replace: :nilify.`
- **Confidence**: REVIEW
- **Fix**: The `on_replace: :nilify` invariant explanation is durable and worth keeping. The "was missing, so ... was dropped" clause narrates the historical bug/fix — that belongs in the commit message, not inline. Trim to the invariant only, e.g.: "All four media FKs must be cast alongside their assoc (`cast_assoc(:gallery, ...)`); relation is `on_replace: :nilify` so casting both FK and assoc is safe."

No violations found for: floats-for-money, query pinning, has_many joins, String.to_atom, mount/PubSub Iron Laws, Oban patterns, GenServer justification, @external_resource, alias-vs-import, or constant-options-in-template — none of these patterns appear in the lines added by this commit.
