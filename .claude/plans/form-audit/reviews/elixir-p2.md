# Code Review: form-audit Phase 2 (commits cfb3639fc, d852ec7ef, a3f8a7d35)

## Summary
- **Status**: ✅ Approved
- **Issues Found**: 5 (0 blocker, 1 warning, 4 suggestions)

None of the prior-phase (`elixir.md`) findings recur in the diffed files — those
sat in `ops.ex`/`page_vars.ex`, untouched this phase.

## Warnings

1. **`lib/brando/uploads/asset_intent.ex:80` (`get/2`) — `Map.get/3`'s default
   argument is not lazy, so every key conversion attempt runs
   `String.to_existing_atom/1` unconditionally, even when the string key is
   already present.**
   ```elixir
   defp get(params, key), do: Map.get(params, key, Map.get(params, String.to_existing_atom(key)))
   ```
   This is safe today only because `@known_keys` are all atoms that already
   exist elsewhere in the codebase, and the whole `normalize/1` body is wrapped
   in `rescue ArgumentError -> {:error, ...}`, so a future key that has no
   existing atom degrades to a generic error rather than crashing. Still worth
   tightening — `if Map.has_key?(params, key), do: Map.get(params, key), else:
   Map.get(params, String.to_existing_atom(key))` (or `Map.fetch/2` +
   `else`) avoids paying (and risking) the conversion on the common path where
   the string key is already there.

## Suggestions

1. **`form.ex:1163-1166` (`deliver_entry_field_asset/5`) — dynamic atom
   construction from `asset_type` is acceptable here, but borderline.**
   ```elixir
   edit_key = :"edit_#{asset_type}"
   changeset_key = :"#{asset_type}_changeset"
   ```
   `asset_type` is always one of three literal atoms (`:file`/`:image`/`:video`)
   supplied by call sites in the same module, never client input, so this
   isn't the atom-exhaustion class of bug (Iron Law 6) — the resulting atoms
   (`:edit_image`, `:image_changeset`, etc.) already exist as assign keys
   elsewhere in this same file. It collapses three near-identical clauses
   cleanly and the moduledoc-style comment above it explains why galleries
   stay separate. That said, a `case asset_type do :image -> ... end` dispatch
   returning the two keys as a tuple would make the fixed enumeration
   grep-able and would not rely on the reader trusting that every caller is
   constrained to the three known atoms. Not blocking — the closed call-site
   set is real and verified (lines 545, 561, 568).

2. **`lib/brando/galleries.ex:111-127` (`loaded_media?/1`, `same_media?/2`,
   `matches?/3`) — `merge_loaded_media/2`'s helper chain is correct but reads
   awkwardly for what it does.** `matches?/3` special-cases `nil` on either
   side to `false` before falling through to `{same, same} -> true`, which
   already handles the "both nil" case for free were it not excluded first —
   i.e., the `{nil, _}`/`{_, nil}` clauses exist specifically to prevent two
   `image_id: nil` galleries objects from being treated as a match by `video_id`
   comparison. That's correct (an object being matched by neither FK must not
   accidentally match another object with both FKs nil), but it's non-obvious
   from the code alone — a one-line comment on `matches?/3` explaining that nil
   is deliberately never a matching value would save the next reader from
   re-deriving it. No behavior issue.

3. **`lib/brando_admin/components/form/input/gallery/thumb.ex:83-85`
   (`same?/2`) — the guard clause order works but is subtle.** `same?(value, _)
   when value in [nil, ""]` fires before `same?(_, nil)`, so `same?(nil, nil)`
   correctly returns `false` (via the first clause) rather than falling to a
   theoretical "both nil ⇒ true" — this is exactly the D5-adjacent
   empty-string/nil bug the module's moduledoc calls out as the reason for this
   extraction. Confirmed correct; flagging only because the three-clause
   fall-through order is load-bearing and worth a one-line "clause order
   matters" comment given it's the whole point of this module's existence.

4. **`lib/brando/uploads.ex:230-245` (`direct_cdn_config/2`) — the three
   clauses are fine, but the third arm's error string interpolates
   `resolved_target` while the caller (`delete_direct_object/3`) never logs
   which `asset_type` it was for.** Minor: `"#{asset_type} has no
   client-direct transport"` only fires for asset types outside `:file`/
   `:video` (there are none client-direct today), so this is dead code more
   than a bug — same shape as the Phase-0 review's "harmless dead branch"
   note on `ops.ex:742`. Not worth a fix on its own; noting so a future
   third client-direct type doesn't inherit an untested branch silently.

## Verified correct (adversarial checks that did not find a bug)

- **`Gallery.Media`/`Gallery.Thumb` seam**: confirmed each gallery component
  (`gallery.ex`, `gallery_objects.ex`) keeps only its own write
  (`Form.update(%{action: :put_gallery, ...})` vs. direct `put_assoc` on the
  entry changeset it already owns) while sharing lookup/add/remove/sequence/
  notify-picker logic. No behavior drift found between the two call sites;
  `Thumb.find/1`'s empty-string guard is applied uniformly to both now.
- **`Form.deliver_entry_field_asset/5`**: the three collapsed clauses
  (`:file`/`:image`/`:video`) are call-site-constrained atoms, not client
  input — acceptable per Iron Law 6's actual scope (see Suggestion 1).
- **`Galleries.merge_loaded_media/2`**: `Enum.find(previous, &same_media?/2) ||
  object` correctly falls back to the (unmediated) incoming object rather than
  `nil` when no previous match exists — an object newly added by another
  session still renders, just without a locally-cached thumbnail until the
  next reload. `loaded_media?/1`'s `|| false` at the end of the `||` chain is
  redundant (the whole expression is already boolean-normalized by the two
  `&&`s short-circuiting to `nil`/truthy), but harmless.
- **`Form.put_gallery_at/4`**: single write point for both `path == []`
  (entry's own field, `put_assoc`) and nested (`EctoNestedChangeset.update_at`)
  cases; `append_gallery_object/5` refactored onto it correctly slims existing
  objects via the canonical `slim_gallery_object/1` field list before
  appending the new (loaded) object — matches the documented
  duplicate-PK-avoidance pattern from CLAUDE.md.
- **`Uploads.delete_direct_object/3` + `direct_cdn_config/2`**: the `rescue`
  is scoped to exactly the raising call (`CDN.get_s3_config/2` via
  `resolve_*_config`/`Brando.CDN.delete_object/2`), not the whole reaper
  sweep — one misconfigured target's exception can't abort the batch since
  the reaper's `reap/1` calls this per-intent inside `Enum.count/2`, not
  inside a `with`/transaction that a raise would unwind past other intents.
- **The two broad `rescue` clauses called out in scope**
  (`form.ex initiate_provider_upload/5`, `upload_manager.ex finalize_item/2`):
  both are scoped to a single external-call function (not the whole
  `handle_event` body), log the formatted stacktrace before converting to an
  error tuple, and sit in processes holding unsaved work exactly as the
  rationale states. Breadth (bare `exception ->` catching everything) is
  justified by the documented "three provider clients / one CDN client with
  unpredictable failure shapes" reasoning — narrowing to specific exception
  structs would be brittle against upstream libraries the codebase doesn't
  control. No objection to the breadth as shipped.
- **`Gallery.Thumb.find/1` empty-string change**: confirmed this closes a real
  bug (`to_string(nil) == to_string("")` in the old `GalleryObjects` copy)
  rather than introducing a new discrepancy — the guard is now identical in
  both call sites via the shared module.

## Pre-existing issues (not in scope, one-liners)

- `lib/brando_admin/components/form/input/gallery.ex:730` (`entry_form_id/1`
  fallback) — derives from the form-name root, which the moduledoc-adjacent
  comment above it already documents as a fallback-only path for a mounting
  context that doesn't thread `@form_id`; no live call site currently hits it
  as of this diff, so not scored as a new-code issue.
