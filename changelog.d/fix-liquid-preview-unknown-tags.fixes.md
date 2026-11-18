- The block editor's module preview no longer prints Liquid comments, `case` and `capture` regions, or tags such as `cycle` as text.
  A `{% ref %}` inside `case`, `capture` or `tablerow` now gets no input in the block editor, as one inside `if` or `for` already did, and the module editor warns about it.
  Declare such a ref at the top level with `{% headless_ref refs.name %}` and read it inside the region.
