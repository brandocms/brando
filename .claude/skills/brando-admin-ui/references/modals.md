# Approved modal direction

The modal study approved on 8 September 2026 uses **B (Section rail)** as the
shared direction for the variable editor, block configuration, and transfer &
delete user. Show section navigation when the task has distinct sections; simple
confirmations and transfer dialogs do not need a rail merely for consistency.
Use **C (Split workspace)** for link picking: content types and search on the
left, results in the center, selected destination and link behavior on the right.
The shared shell is implemented in `Content.modal`; `Content.modal_sections`
provides the section rail and `SelectIdentifier` provides the link workspace.
Their styling lives in `assets/css/components/ModalWorkspace.css`.

Keep the title and context line in one compact stack centered beside the heading
icon. Treat creator name and role the same way beside an avatar. Trim the text
boxes to the font's capital height before setting the gap; centering oversized
line boxes leaves the visible text looking displaced. Modal titles use 22px text.
Heading and person text stacks both use an 8px gap, including equivalent creator
and recipient details. Keep these proportions on mobile and check wrapped titles.

Adjacent metadata values must share their type size and alignment row, including
values containing badges or status dots. The link sidebar uses 13px values inside
24px rows with centered contents. Keep status dots at least 1em. Verify the visible
text positions with the actual consumer font, not only the surrounding boxes.

Use subtle surface colors to distinguish context from editable content. The
approved transfer summary has a near-white sage surface (`#fbfff7`). Keep
headers and action rows outside the scrolling body, preserve input through nested
selection, and return to the original editor and section after choosing a link.
Block and variable settings currently update the parent form, so their completion
action remains Done. Apply/Cancel requires an actual isolated draft; do not imply
cancellation semantics with styling alone.

Section changes keep inputs mounted so LiveView validation retains edits. Escape
closes only the active dialog and returns focus to its opener; link openers must
be real buttons. Show and hide commands target direct dialog children to avoid
revealing nested dialogs. Cover these interactions with
`e2e/playwright/tests/modal-design.spec.js`, alongside the existing form,
block persistence, upload and accessibility tests.

## Compare implementation against the approved sketch

Use the actual approved render and its measurements as the reference; matching
only the broad layout is insufficient. Compare at 1440px with the consumer's
real font files. Review each context separately: a link variable inside a menu,
a nested variable dialog, and the rich-text dialog have different ancestors.

For the C sidebar, use a 21px/28px destination title, a 4px title-to-URL gap,
16px before metadata, 20px from creator to link fields, and 14px between the
link field and toggle. Keep field labels at 13px, the sidebar at 306px, and
its background at `#f4f7f9`. Heading/person stacks retain the approved 8px gap.

Align the C header icon, mode switch, and content-type heading text to the same
20px desktop inset. Use a shared 18px inset for the header and switch on mobile.
The selected entry's update timestamp includes the time in the configured site
timezone, alongside its localized date.

Form rules can override more than paragraph margins: definition-list margins,
subform label spacing, old dialog-specific tab margins, and uppercase toggle
styles also cross into nested dialogs. Inspect the winning rule and use a
scoped layout owner for gaps. Check visible alignment after scrolling, too:
a sticky search field must not cover mobile content navigation.

Keep deliberate adaptations explicit. Real content-type names may need a
slightly wider navigation column. Use the shared identifier status treatment in
results, including draft and published labels. Use the existing icon family,
actual counts and creator photos, and truthful completion actions for the
form's state model.
