# Inline subform tables

Approved on 4 October 2026 (`design/drafts/redirects-subform.html`). An inline
subform (`inputs_for … style :inline, cardinality :many`) and a table block's
rows are both a table, built like `.identifier-list`: one `--brando-line` border with a
6px radius around the whole, hairlines between rows, white rows tinted
`--brando-surface-hover` on hover.

- Column headings appear once, in a `--brando-surface-shaded` header row, from each input's own
  label. A cell's label is visually hidden; its error shows under the control.
- Every row is one line. Controls take the block variables' compact look: 32px,
  13px, borderless until the row is hovered or the control focused. Media fields
  use `MediaField`'s `:line` presentation. A row wider than the form scrolls
  sideways inside the table rather than wrapping.
- Small controls (status, toggle, checkbox, radios, number, dates, colour)
  shrink their column to fit; text columns share the rest.
- The grip sits at the left and a ghost × at the right, shown on row hover. An
  insert button sits on the line above each row; "Add entry" and the count sit
  in a `--brando-surface-shaded` footer. A row added either way reveals over 350ms, without a colour flash.
- A field hidden by `show_if` leaves an empty cell, so later columns stay under
  their headings.

Two other lists share the frame. A `:string_list` input (`Input.input/1`) is
a framed list with the row number in a gutter, the same insert and remove
buttons, and its empty "Add another…" line last; the `Brando.StringList` hook
inserts and removes rows (`StringList.css`). A variable list (`Input.Vars`:
global sets, page variables, table templates) has a line per variable with
the grip and insert at the left, × at the right, and opens a variable in
place (`VarsList.css`).

`subform.ex` renders the subform's table; `block/render.ex` `table/1` renders a
table block's. `SubformTable.css` styles both, `TableBlock.css` adapts block
variables to it, and the `Brando.TableRows` hook animates added rows. The E2E
client form's "Inline fields" tab holds one of every input that fits on a line
(`E2eProject.Projects.InlineRow`); check changes there and in
`tests/projects/inline-subform.spec.js`.
