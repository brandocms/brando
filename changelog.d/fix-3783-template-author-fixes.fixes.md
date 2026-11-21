- A top-level field that only a named form draws as rich text prints in templates as sanitized markup, as subform rows already did, instead of as escaped text. A field one form draws as plain text and another as rich text prints as sanitized markup.

- `size` gives 0 for a record, such as a subform row (`{{ entry.quotes | first | size }}`), and the number of pairs for a map, instead of raising.

- `markdown` on rich text gives its markup, sanitized as when it was read, instead of `<!-- raw HTML omitted -->`.

- A rich-text field read many times in one render is sanitized once.
