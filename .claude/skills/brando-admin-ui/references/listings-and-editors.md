# Listing and editor refinement checks

Work at **1440px first**, then check 390px and expanded content. Review screenshots
at their actual scale; a reduced full-page image can disguise small typography
and misalignment. Use populated rows, long namespaces, photos and initials,
child entries, open menus, and real form values.

- Use 32px workspace headings, 17–18px section headings, and 14px medium listing
  titles. Keep secondary metadata smaller without making it pale or difficult to
  read. A page heading's actions sit on the title's line, also when a subtitle
  follows; on a phone they go under the subtitle.
- A listing row is about 60px on desktop: the title over its URL, the columns,
  the status badge (a dot and its tone, see [Buttons and badges](buttons-badges-menus.md)),
  the author (avatar, name, date) and the ⋯ actions menu. The column headings,
  rows and footer sit in one frame like `.identifier-list` (`.content-list-frame`:
  a `--brando-line` border, 6px radius, hairlines between rows); it isn't
  clipped, so row menus open past it. On a phone a row is two lines: the title
  and the menu, then the status, the author's name and the date.
- A listing toolbar should share one surface and baseline. When a blueprint adds
  filters of its own, it takes two rows: the statuses, then search, those filters
  and the sort and views on the right. Filters and sort
  controls use a 32px box with symmetric padding (40px for coarse pointers).
  Zero-count badges are omitted. Status dots use 1cap,
  optically centered with their labels. Remove inherited margins before adjusting
  position. The admin's sans (`--brando-font-sans`, `theme.typography.families.main`)
  can differ between consumer applications.
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
  chevron, in a column of their own just before the status, so they line up from
  row to row; rows without children keep the empty slot. Reserve enough room for
  the full namespace rather than forcing it into a narrow badge. Verify opening the children, including records with no status.
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
- A settings toolbar is a white bar with one sage action accent. Its sections
  are pill tabs (see [Tab views](tabs.md)); a single section is a plain label.
- Use the same chevron asset and rendered dimensions across neighboring dropdowns.
  Preserve visible keyboard focus. Test Enter, Space and Escape against real
  controls; closing an already closed dialog must not toggle it open internally.

A passing overflow check is only the first audit. Follow it with screenshot
inspection, measured alignment checks, and the existing local workflow tests.
Capture fresh screenshots after the last change. Record limitations honestly;
visual approval belongs to the person using the interface.
