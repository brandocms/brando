# Shared dropdowns and entry panels

The approved identifier appearance is **D: joined cover rows**, selected on
27 September 2026. Apply it globally to relation fields, block/datasource
selections, entry/link pickers and alternates. See the shipped
[relation field](../../../../docs/admin-ui/related-entries-selected-1440.png),
[mobile field](../../../../docs/admin-ui/related-entries-selected-390.png) and
[entry picker](../../../../docs/admin-ui/joined-identifiers-picker.png).

Use one outline around adjacent rows, thin dividers, small rectangular covers
and the content type's icon when no cover exists. Titles lead, with the status
dot before them (its localized name is there for screen readers and on hover);
type and language sit below. Show a grip only for sortable rows, a checkbox
for picker choices, and a small remove button where removal is supported.
Relation-field actions share a footer inside the outline. Link-picker results
also retain their destination URL.

`Content.Identifier.content` owns the shared row contents and `Identifier.css`
owns their appearance. Keep selection, sorting, hidden association inputs and
metadata slots with their existing callers. Do not add per-field overrides that
make Related entries look different from the other identifier contexts.

Action, sort, bulk-selection and block menus share `%admin_dropdown_panel` in
`FloatingDropdown.css`: white surface, muted border, light shadow. Their rows are
[menu items](buttons-badges-menus.md#menu-items). Keep only positioning and trigger styling in the
component.
An action menu on the `Brando.FloatingDropdown` hook (the entry toolbar's More,
the media Replace and More menus) takes a menu button's keys: opening it
focuses its first action (ArrowUp on the trigger, the last), ArrowDown and
ArrowUp move and wrap, Home and End jump, Enter and Space choose, Escape closes
and returns the focus, and Tab leaves. Its items stay buttons, with the
`.menu-item` class.
Bulk selection uses a light fixed bar above presence avatars, with a count and
an explicit Actions button. Listing title links reveal an arrow on hover/focus.
Shortcuts are a `.menu-item-hint`, muted, with a shared right edge inside each menu.
Badges (`.badge`, see [Buttons and badges](buttons-badges-menus.md)) have no
border: a sage fill (`--brando-badge-bg`) and muted ink (`--brando-badge-ink`)
on a 4px corner. Keep the hard 1px border
for controls with a selected state, such as the status radios.

Meta, revisions and scheduled publishing use the media browser's workspace
shell, with entry-specific contents in `EditorWorkspace.css`. Keep the header
visible while the body scrolls. Formatting toolbars inherit
`--form-toolbar-offset`, measured by the Form hook from the actual toolbar
height plus an 8px gap; independent dialogs reset this offset.
Keep the measured value in a form-scoped stylesheet rule outside LiveView's
patched attributes. Revisions show explicit active/inactive, scheduled and protected
labels, with schema metadata below the revision number. Authors use the shared
`Content.modal_person` component with preloaded avatars and an initial fallback.
Use its `compact` option in revision rows: 26px avatar, 11px text and an 8px gap.
Narrow layouts stack the same information without horizontal scrolling.

Related-entry pickers reuse `Entries.entry_picker` and `Brando.SelectFilter`.
The filter control is client-owned; selection patches must retain its query
and reapply it to the updated results. The multi-select dialog lists its
options and its selection in the same joined rows, without covers: an option
is a checkbox (`role="checkbox"`, toggled by a click, Space or Enter) with the
status dot when it has one and its language below; a selected one has the
square remove button, in the order chosen. The two columns stack on a phone.
Selected rows share the available options' height, and only their remove
control responds to hover.
Search fields with a custom clear control suppress the browser's native clear
button. Image refs use a fixed thumbnail width (180px on desktop, 96px on mobile)
and automatic height to preserve the loaded image's proportions. Keep metadata
beside the thumbnail and actions below the row; the image does not fill the card.
While an uploaded image is processing, reserve that same height from its known
width/height ratio. Keep the dimensions visible and show one translated status
with a small spinner beside the filename. Hide the duplicate upload-manager
projection in the field, while keeping errors visible. Respect reduced-motion
preferences. See the [portrait](../../../../docs/admin-ui/image-ref-processing-portrait.png) and
[landscape](../../../../docs/admin-ui/image-ref-processing-landscape.png) processing examples.
