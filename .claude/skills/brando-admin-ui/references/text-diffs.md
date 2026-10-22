# Shared text diffs

Use `BrandoAdmin.Components.TextDiff.diff/1` for line-by-line text comparisons.
Content transfer, module-file import review, recovery-copy previews and revision
comparisons (`Activity.comparison/1`: Activity and an entry's History) use this component. Its shared
styles live in `assets/css/components/TextDiff.css`, and its English/Norwegian
labels use the `admin_diff` Gettext domain.

```heex
<TextDiff.diff
  id={"template-diff-#{@module.uid}"}
  label={gettext("Template")}
  before={@saved_template || ""}
  after={@incoming_template || ""}
  description={gettext("Current → imported")}
  monospace
/>
```

Supply a stable ID and plain strings, or a list of `%{text: text, key: identity}` lines.
Optional `type: :heading | :media | :detail` provides restrained hierarchy.
Keys distinguish different assets with the same filename and different placements;
they are never rendered. Keep keys stable across the two sides, including any
source-to-destination asset mappings. Serialize structured values at the caller;
use an empty string for an absent side so it does not appear as removed text.
The panel escapes content, marks additions/removals, retains unchanged context,
and includes line numbers, translated counts and a keyboard-scrollable viewport.
`description`, `empty_text` and `note` provide context-specific copy; `monospace`
is useful for code and JSON. The parent layout owns the surrounding spacing.

Previews are bounded to 12,000 characters and 400 lines per side and explicitly
label truncation. For block comparisons, `BrandoAdmin.ContentPreview.lines/2`
projects loaded blocks
or portable blocks with an asset index into readable text and media references.
It includes image/file/video filenames, gallery order and selected authored metadata.
It preserves placement context, so moved media appears as removal and addition.
Explain that rendered layout and other settings still need their own review.
Recovery previews compare readable payload sections against a freshly loaded
saved entry, retaining field identities and omitting editor capability settings.
Show only changed sections and lines by default, retaining their field labels.
The “Show unchanged content” checkbox reveals the full preview and persists
through LiveView patches. Keep truncation notices visible in both modes.
Copy text includes the recovery side; JSON export keeps the original payload.
Keep one recovery comparison, without a duplicate scalar summary. Resolve media
and related-entry references in batches for both sides; keep their identity in
line keys and show thumbnails, filenames and entry titles. Optional line
`preview` metadata supplies the kind, thumbnail and details to the shared viewer.
Image thumbnails use fixed width and automatic height. Missing records remain
visible as unavailable references. Recovery capture timestamps must not advance
when a copy is dismissed, reviewed or renewed without content changes.
Match recovery blocks (including children) by UID and gallery placements by
identity before comparing their content. Show reordering in a separate compact
movement list with names/thumbnails and old → new positions; keep edits to those
same items in the text diff. Inserting or deleting an item must not turn every
shifted neighbour into a move. Gallery objects and their overrides should produce
one movement summary. The expanded recovery diff uses page scrolling: reset both
internal overflow and scroll containment so mouse-wheel input reaches the page.
Shared-library template overrides are another suitable use; permission sets and
record relationships need their structured comparisons.
