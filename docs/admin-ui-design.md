# Admin UI design guide

Use this guide when creating or refining Brando admin screens. It records the
design direction approved during issue #2788 on 7 September 2026: restrained
colors, clear grouping, compact controls, deliberate spacing, and factual copy.
Apply it alongside existing components and the screen's functional requirements.
The measurements below are starting points from Utilities, not a mandate to
restyle every existing screen.

## Reference

The Utilities page is a worked example. Its main content shows the approved
spacing, action placement, maintenance rows, and system-information grouping.
The surrounding sidebar and avatar images come from the E2E fixture application.

![Approved Utilities layout](admin-ui/utilities-reference.png)

The import preview shows how the same hierarchy extends to expanded details,
permission changes, and the final apply action.

![Utilities import preview](admin-ui/import-preview.png)

Implementation references:

- [Utilities styles](../assets/css/views/config/Utils.css)
- [Authorization tools component](../lib/brando_admin/components/authorization_tools.ex)
- [Utilities LiveView](../lib/brando_admin/live/config/utils_live.ex)

## Start with the task and hierarchy

Give each section a clear purpose and place its actions next to the relevant
content. Use one page title, section headings, and smaller item titles. Make
related items share alignment, spacing, and control treatment.

Choose a bounded width for settings and configuration. Utilities uses a 1120px
maximum; dense tables and editors may need more. A wide monitor should not pull
short descriptions, actions, and metadata to opposite edges of the screen.

Use numbered steps for an actual sequence. Use cards to group distinct workflows
such as import and export. Use a single bordered list with dividers for simple
maintenance actions: description on the left, action on the right. Let content
determine row height. Oversized cards with one short sentence create unnecessary
empty space.

## Make spacing a system

Start with a small spacing scale: 4, 8, 12, 16, 24, and 32px. Adjust deliberately
for the existing layout and actual text wrapping.

| Relationship | Starting point |
| --- | --- |
| Item title to description | 4–8px |
| Description to action below it | At least 16px |
| Related actions | 8–12px |
| Card or settings-row padding | 20–24px |
| Major sections | 24–32px |
| Metadata label to value | 4px |

Separate button padding from the space around the button. Increasing button
height does not solve a button touching the paragraph above it.

### Let the layout own the gap

Brando's [global stylesheet](../assets/css/app.css) includes:

```css
p:last-of-type {
  margin-bottom: 0 !important;
}
```

This cancelled the intended paragraph margins in the first Utilities design.
Several buttons had a measured gap of zero despite apparently correct local CSS.
Use parent `gap` or padding on an action wrapper so spacing survives the reset:

```css
.screen-actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 12px;
  padding-top: 16px;
}

/* Within a column of related steps, align actions while retaining the gap. */
.screen-step .screen-actions {
  margin-top: auto;
}
```

Inspect computed styles before adding specificity or another `!important`.
Keep fixes scoped to the screen; changing a global reset needs a separate review
of the screens it affects. Measure the rendered gap after the longest description
wraps, as well as with shorter text.

## Keep controls compact and predictable

Utilities uses 30px desktop buttons: 12px text, 18px line height, 5px vertical
padding, 12px horizontal padding, a 1px border, and a 5px radius. These proportions
are a useful starting point for secondary admin actions. Coarse-pointer controls
use a minimum height of 40px; check touch usability in context.

Align equivalent actions consistently. In a settings list, use a shared right
edge and consistent widths where the labels allow it. In parallel workflow
cards, align actions at the bottom while preserving a minimum gap from content.
On narrow screens, stack the action under its description with a 16px gap.

Give the main consequential action stronger emphasis. Keep navigation and
secondary actions quieter. Use verbs that describe the result: “Run migration
report”, “Sync identifiers”, “Preview import”, “Apply configuration”.

Use consistent icons from the existing icon system. A disclosure chevron should
have a consistent size, stroke, alignment, and open state. Omit decorative arrows
that add no information. Keep visible keyboard focus, accessible names for
icon-only controls, and understandable loading and disabled states.

## Use typography and color to establish hierarchy

Retain Brando's existing typefaces. The Utilities scale is approximately 30px for
the page title, 18–22px for section headings, 13–14px for item titles, and 12–13px
for descriptions. Small metadata is subordinate, but it still needs to be readable
at normal zoom. Do not shrink essential instructions to make a layout fit.

Use regular or medium weights, restrained borders, and minimal shadows. Sentence
case suits headings and actions. Reserve small uppercase labels for short context
labels, and use monospace for keys, configuration, and technical values.

The approved palette uses these roles:

| Role | Utilities reference |
| --- | --- |
| Main text | `#272b2a` |
| Secondary text | `#626b66` |
| Borders | `#dce2dc` |
| Main accent | `#254e3f` |
| Authorization header | `#f1f5ef` |
| Export surface | `#f8f9f5` |
| Import surface | `#f8f8fc` |

Prefer existing design tokens where they serve the same purpose. Keep tinted
surfaces subtle, and check text and control contrast in the rendered interface.
Status needs a textual label as well as color.

## Write factual, useful copy

Use the language of the task. Explain the action, relevant consequences, and the
next step when needed. Avoid cute catchphrases, promotional headings, and invented
personality. “Import / export” is a useful heading on an administrative screen.

Describe empty states naturally: “Not generated” for an absent sitemap, followed
by “Last generated: …” when a timestamp exists. Keep descriptions concise, but
preserve facts the user needs to act safely, such as whether an import affects
existing members.

## Present metadata as information

Use a semantic description list (`dl`, `dt`, `dd`) with labels above values and
consistent column spacing. Bound its width and reduce the column count on narrow
screens. Avoid distributing a handful of tiny label/value pairs across the full
viewport with `justify-content: space-between`.

Show effective configuration values. The initial Image jobs field was blank
because the setting was unset, although the application uses a default of 1.
Resolve the same default as the consuming code. If a value cannot be determined,
display a meaningful unknown state instead of inventing a value.

## Verify the rendered result

CSS that looks right in a diff is insufficient evidence of a finished layout.

Before editing, search the existing E2E tests for the page's route, labels, and
selectors. Include those tests in local validation alongside new tests. A new
workflow test does not replace existing coverage of the page's other actions.
Update assertions affected by an intentional redesign while preserving their
behavioral coverage. When fixing a failing test, rerun that specific test first.

1. Build changed JS/CSS through the E2E consumer, following [AGENTS.md](../AGENTS.md).
   Source `e2e/.envrc` first. Do not use a standalone root asset build as a gate.
2. Inspect the actual page with its real styles and fonts. Reload after rebuilding
   when hot reload is unavailable. Check computed styles when spacing disagrees
   with the source.
3. Check the normal desktop layout and narrow widths, including 390px. Look for
   overflow, awkward wrapping, missing values, crowded actions, and inconsistent
   alignment. Allow resize transitions to settle before taking screenshots.
4. Inspect relevant states: empty, loading, disabled, error, populated, and
   expanded details. Check keyboard focus and long labels or filenames where
   they occur. Run focused behavioral tests appropriate to the changes.
5. Take and inspect fresh screenshots. When presenting UI work, show the user a
   screenshot of the actual implementation. Keep saved reference images current
   when the approved design changes.

## External references

These sources informed the Utilities refinement. Use their underlying principles
while retaining Brando's visual identity:

- [Stripe: styling](https://docs.stripe.com/stripe-apps/style) — reusable spacing
  values and consistent component styling.
- [Stripe: action buttons](https://docs.stripe.com/stripe-apps/patterns/action-buttons)
  — predictable action placement.
- [Supabase: layout](https://supabase.com/design-system/docs/ui-patterns/layout)
  — content-appropriate widths, grouped settings, and actions placed with their
  relevant content.

## Shared workspaces and form sections

Use `Workspace.header` and the opt-in `admin-workspace` styles for list and
settings screens. Existing generated listing LiveViews also inherit these styles
when `Content.List` is rendered directly inside the main content article. This
compatibility scope includes `Content.header` and its actions, so applications
do not need to regenerate their listings. Explicit workspace wrappers retain
their own layout without a second surrounding workspace. Keep regression
coverage for the old generated markup alongside Pages and the new generator.

Custom listing rows using `update_link` get the title treatment automatically;
they do not require the Pages-specific `listing-title` class. Preserve custom
cells, cover images, checklists, and creator metadata at desktop and mobile sizes.
Keep the original vertical checklist pills and application-defined category
typography. Give metadata columns consistent widths so shorter category lists
share the same left edge as longer ones.
Keep media folder navigation shared between images, files,
and videos. Show the current folder's count using the same scope as the list.
Keep item titles primary; formats, dimensions, file sizes, authors, and timestamps
are secondary information. Avoid exposing URL query strings as video metadata.

Blueprint fieldsets accept `label t("Section name")` for a translated legend.
A read-only `component &Module.preview/1` can render from the current `form`
assigns without maintaining a separate copy of pending values. Keep form IDs,
input names, component IDs, upload targets, and save ownership stable.

Constrain avatar photos and their image wrappers to their container. Source
`width`/`height` attributes and a non-shrinking image wrapper can otherwise expand
a small presence avatar over the page. Clip the photo wrapper, leaving status
dots and focus rings outside it visible. Verify presence after a LiveView patch,
not just on the initial render.


## Listing and editor refinement checks

Work at **1440px first**, then check 390px and expanded content. Review screenshots
at their actual scale; a reduced full-page image can disguise small typography
and misalignment. Use populated rows, long namespaces, photos and initials,
child entries, open menus, and real form values.

- Use 32px workspace headings, 17–18px section headings, and 15px listing titles.
  Keep secondary metadata smaller without making it pale or difficult to read.
- A listing toolbar should share one surface and baseline. Filters and sort
  controls use a 38px box with symmetric padding. Status dots are at least 1em,
  optically centered with their labels. Remove inherited margins before adjusting
  position. The font stored as Main can differ between consumer applications.
  Status labels use `text-box: trim-both cap alphabetic` so alignment follows the
  font's capital height; descenders extend naturally below it. Older browsers use
  the configurable `--status-label-offset` fallback (2px by default). Untrimmed DOM
  bounding-box centers do not prove optical alignment: inspect close-ups with the
  actual consumer font as well as the E2E font. See [Chrome's text-box guide](https://developer.chrome.com/blog/css-text-box-trim)
  for the font-metric behavior.
- Show creator photos when available and centered initials otherwise. Keep creator
  information visible on mobile by giving it a deliberate place in the row.
  Clip image wrappers as well as images to the avatar's dimensions.
- Keep child disclosures rectangular and compact, with an aligned count and one
  chevron. Reserve enough room for the full namespace rather than forcing it into
  a narrow badge. Verify opening the children, including records with no status.
- Text inputs and custom selects in a form must share height, type size, and
  baseline: 44px in content editors, 40px in settings, with 14px text. Keep labels
  on one line where appropriate; inline presence elements can otherwise create an
  extra label line even when the visible text fits.
- Use one spacing owner for settings: 24px between fieldsets, 16px between related
  fields, 8px from label to control, and 24px from the final group to Save. Do not
  stack fieldset, nested fieldset, and input margins for the same relationship.
- Give repeated editor rows a quiet tinted parent surface and white fields/rows.
  On mobile, arrange the status and row actions together, followed by labelled
  fields. Keep editing and deletion controls distinguishable.
- Group dashboard shortcuts in one toolbar. Soft sage, blue, lavender and sand
  distinguish destinations while retaining the same proportions and icon family.
- A settings toolbar with one section and only Save needs less visual emphasis:
  use a white surface, a plain section label, and one sage action accent. Reserve
  selected tab pills and multiple action colors for toolbars with actual choices.
- Use the same chevron asset and rendered dimensions across neighboring dropdowns.
  Preserve visible keyboard focus. Test Enter, Space and Escape against real
  controls; closing an already closed dialog must not toggle it open internally.

A passing overflow check is only the first audit. Follow it with screenshot
inspection, measured alignment checks, and the existing local workflow tests.
Capture fresh screenshots after the last change. Record limitations honestly;
visual approval belongs to the person using the interface.


## Pending subform sweep

Requested on 8 September 2026; recorded for a later implementation pass. Use
Navigation → Edit menu → Menu items as the starting reference, then review the
shared subform components and other nested/repeated editors.

- Increase the status dot **inside the link preview field** to `1em` in both
  dimensions, relative to its accompanying text. This is separate from the row's
  status selector. Align the dot with the visible text and prevent flex shrinking.
- Replace the violet/lilac treatment of subform surfaces, reorder/delete controls,
  and link icon badges with a very light pastel blue. Start by trying a near-white
  blue such as `#f5f9fd`; the exact shade still needs visual review. Retain white
  rows and input surfaces, readable labels/icons, and clear hover/focus states.
- Audit nested levels, row rhythm, label/control alignment, and action placement
  across subform usages. Check 1440px first, then 390px, including long link titles
  and URLs. Capture fresh screenshots and run the relevant local E2E workflows.

## Pending blueprint content-type icons

Requested on 8 September 2026; proposal recorded for later implementation.
Allow an optional top-level blueprint declaration using the existing icon names:

```elixir
icon "hero-folder"
```

Resolve the icon automatically in the link picker's “Content types” navigation
and corresponding entry icons. Use one shared blueprint accessor so other admin
content-type displays can reuse the same metadata. Preserve a sensible fallback
for blueprints without an icon; this remains optional and requires no per-picker
configuration. No blueprint-level icon declaration was found in the current DSL.

When implemented, document the supported declaration in `guides/blueprints.md`
and verify configured icons, unset fallbacks, and their alignment at 1440px and
390px. This proposal is not yet a supported DSL feature.

## Approved modal direction

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
`e2e/e2e/playwright/tests/modal-design.spec.js`, alongside the existing form,
block persistence, upload and accessibility tests.

### Compare implementation against the approved sketch

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
slightly wider navigation column. Show unusual states such as drafts without
repeating published status in every result. Use the existing icon family,
actual counts and creator photos, and truthful completion actions for the
form's state model.
