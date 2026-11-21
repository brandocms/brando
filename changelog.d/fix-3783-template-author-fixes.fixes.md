- A top-level field that only named forms draw, each as rich text, prints in templates as sanitized markup instead of as escaped text. When forms disagree on a field, the default form decides how it prints.

- `size` gives 0 for a record, such as a subform row (`{{ entry.quotes | first | size }}`), and the number of pairs for a map, instead of raising.

- `markdown` on rich text gives its markup, sanitized as when it was read, instead of `<!-- raw HTML omitted -->`.

- A rich-text field read many times in one render is sanitized once, and so is a rich-text var given to `markdown`.
