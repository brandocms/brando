# Footnotes and block regions: internals

Site-facing behaviour is in `guides/footnotes.md`. This file is what changing
the code needs on top of it.

## Data model

- Both features store content in a **slot**: a `Block` with `type: :slot`,
  `slot_kind` (`:region` | `:footnote`), `slot_name` and `slot_module_set`
  (columns from upgrade migration `brando_169_add_block_slots`). Slots are
  children of their owner in the ordinary block tree.
- Module-owned slots hang under the module block. `slot_name` is the ref name;
  a footnote slot's `uid` is the note UID.
- Blueprint rich-text notes are root blocks of the field's `footnotes: [blocks:]`
  relation, with `slot_name` = the field name. A relation that stores notes
  accepts only slots (`BlockSlots.validate_entry_slot/3`).
- Ref rows address slots by name; they do not own them. Replacing a ref row
  must never delete or re-home its slot.
- Tiptap stores only `data-footnote-uid` on the marker. Numbers are never
  persisted: the editor renumbers in the DOM (`renumberFootnotes` in
  `assets/src/components/TipTap/extensions/Footnote/index.js`, on TipTap mount
  and update, BlockField hook updates and SortableBlocks moves, scoped to
  `.blocks-wrapper`); the site renumbers in `Brando.Villain.Footnotes.render/2`.

## Policy is server-owned

- `BlockSlots.validate/2` (run by `recursive_block_changeset/4`) →
  `keep_slot_identity`: for persisted slots, `type`, `slot_kind`, `slot_name`
  and `slot_module_set` are reset from `changeset.data` unless a valid remap
  token is present (see Remap). Posted hidden fields cannot rename or re-home
  a slot.
- A new slot under a module block must be enabled by the module's current refs
  (`allowed_for_refs?/2`: a text ref with `footnotes: true` and matching
  `footnote_module_set`, or a `blocks` ref with matching `module_set`).
  A slot's children must be in its module set (`validate_slot_children`);
  retained children of a now-disallowed module may stay.
- `create_footnote` (`Form.Block` for text refs, `BlockField` for Blueprint
  fields) reads the module definition or the compiled form config, never the
  event params, so posted input cannot enable footnotes or pick a set.
- `BlockSlots.suitable_module?/1` keeps palettes one level deep: no multi
  modules, child modules (`parent_id` set), `blocks` refs, or text refs with footnotes on.

## Remap

`Lifecycle.remap/4` re-checks targets (`remap_targets/3`: unmatched region,
empty destination, all children allowed) and returns a `Phoenix.Token`
(salt `"brando-region-remap"`) in the virtual `slot_remap` field. The token
travels with DOM recovery, drafts (`Brando.Drafts.Params`) and op snapshots
(`BlockField.Ops`); at save, `keep_slot_identity` verifies the claim and
`Lifecycle.validate_remaps/1` re-checks the destination against the current
definition. Entry-level slots cannot be remapped.

## Rendering

- `Parser.render_block_slot/2` renders a region's active children without a
  wrapper; `process_refs` puts it in the `blocks` ref's `rendered_html`.
- For text refs, `Footnotes.attach/3` appends each active note as
  `<template data-brando-footnote="uid">…</template>` after the owner's HTML.
  `Footnotes.render/2` (called at the end of `Villain.parse/3` unless
  `footnotes: false`, then `to_html/1` adds the endnote list) extracts templates
  and existing endnote sections, numbers markers in document order and drops
  unreferenced definitions. It returns `%{html:, notes:}`.
  A block rendered alone still has raw markers: when `Footnotes.unresolved?/1`
  is true, `Form` re-renders the whole preview instead of patching the block.
- `Footnotes.render_field/3` renders a rich-text field's note slots the same way.
  It raises if `entry_<blocks relation>` is not preloaded.

## Copies and transfers

- Whole-block copies go through `Blocks.duplicate_block/2` (duplicate, paste,
  proposals, which pass their own `:uid_mapping`). It builds a full UID map with
  `BlockSlots.uid_mapping/1` and rewrites markers in text refs and vars with
  `remap_markers/2`. The edit session's rescue copy (`<uid>-kept`) renames by
  suffix and remaps the same way in `BlockField`'s `rename_copy/2`. Any new copy
  path must do the same, or copied markers point at the original's notes.
- Content transfer rewrites `data-footnote-uid` in `Transfer.Portable` and
  `Transfer.Recovery`; retained slot UIDs pass to validation through the
  server-only `:retained_slot_uids` option.

## Unused detection

`Lifecycle.unused?/3`: a region is unused when no `blocks` ref has its name; a
note is unused when its text ref is gone or the text has no marker with its
UID (`marker_uids/1`). Rich-text fields use `Lifecycle.unused_notes/3`.
