- A form input declared `readonly: true` or `disabled: true` is now locked for everyone when the form saves, not only in the browser: the save ignores any value sent for it and keeps the value the form has, including inputs (toggles, selects, dates and others) that still render as editable.
  Remove `readonly: true` and `disabled: true` from any Blueprint input that editors are meant to change.
