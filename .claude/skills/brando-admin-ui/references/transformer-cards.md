# Transformer cards

A transformer with `layout :grid` shows its entries as cards with the gallery
grid's hover tools: separate white 28px chips (edit, remove) at the top right,
a sage hover on edit and a red one on remove, shown on hover or focus and
always on touch screens. `Subform.css` owns them.

A card can act on its own entry: the `listing:` component gets `@target` and
`@dom_id`, and `Transformer.set_field/4` changes one field in place, saved like
an edit in the entry's dialog. Use it for one-click choices that belong on the
card (a size switch), not for anything that needs the dialog's room. With
`listing_context true`, cards also get `@index` and `@entries`, for a position
chip or to show which entries share a row; every card then re-renders on each
change, so keep the listing small.
