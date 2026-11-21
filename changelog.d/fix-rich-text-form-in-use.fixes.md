- A plain column named like a subform row's rich-text input (say `text`) is no longer sanitized as rich text on save, printed as markup in a template or shown as rich text in a proposal review.

- A subform row's rich text prints in a template as a top-level rich-text field does: as sanitized markup, or as its text alone when it holds unsafe markup stored before rows were checked, also through `raw`.
