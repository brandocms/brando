- **`rerender_on_change` and `reassign_on_change` follow every change to their
  field.** An accepted AI suggestion invalidated the field's assigns but sent
  only `<main>`; adding, removing or reordering subform rows, and typing in a
  subform row, matched neither list; and another editor's change did not reach
  the open preview at all. A declared path now also covers the fields below
  it, so `[:items]` names a subform and its rows, and a path below a field
  fires when the whole field changes.
