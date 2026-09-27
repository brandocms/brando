# Shared identifier appearance study

Requested on 27 September 2026. **These are global identifier variants**, not a
special treatment for Related entries. Each appears as a selected, removable
item in a form and as a selected/unselected option in a picker.

- A: compact individual cards.
- B: a joined list with row dividers.
- C: cover rows, with a document icon when the identifier has no
  cover. This preserves visual recognition across identifier contexts.
- D: joined cover rows, combining C's covers with a shared outline and thin
  row dividers. The form actions share a footer inside the same outline.

The same identifier data can supply every variant: title, schema/type, language,
status, cover and URL. The study moves IDs and update dates out of the main row;
they can remain available in identifier details. Publication status has a text
label as well as a color. Sample covers reuse the existing concept assets.

Open `standalone.html` for a portable interactive comparison. Its selection,
removal, filtering and drag reordering are local demonstration state. No content
is saved. **D: joined cover rows is approved and implemented globally.**

Production rendering is shared by `Content.Identifier.content`, called from
`Entries.identifier_content` and `SelectIdentifier`. Its styles live in
`assets/css/components/Content/Identifier.css`. Relation fields, block/datasource
selections, entry/link pickers and alternates use the same rows. The existing
selection, reordering, metadata slots, hidden association inputs and removal
events remain with their respective callers.

The gallery upload-size hint is implemented separately in the real form. It
resolves the gallery's image and video configurations independently and shows
per-file limits. It is not dependent on choosing an identifier style.

To regenerate the standalone file and screenshots:

```sh
cd e2e
source .envrc
node ../docs/admin-ui/identifier-variants/capture.mjs
```

Implementation verification (27 September 2026): the E2E consumer asset build
and eight targeted browser cases pass across relation fields, datasource
selections, entry filtering, navigation links and rich-text links. This includes
cover/fallback rendering, keyboard selection, reorder/remove/save/reopen,
clearing and reselecting, desktop/mobile widths, and Norwegian field/status copy.
Actual application captures:
[relation field](../related-entries-selected-1440.png),
[mobile field](../related-entries-selected-390.png),
[entry picker](../joined-identifiers-picker.png),
[link picker](../link-picker-desktop.png), and
[block selection](../block-identifiers-1440.png).
