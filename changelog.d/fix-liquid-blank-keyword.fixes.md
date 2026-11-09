- In Liquid conditions and `{% when %}`, `empty` matches `nil`, `""`, `[]` and `{}`, and `blank` matches those and `false`. Since the Liquex 0.15 upgrade `{% if x != blank %}` was always true and `{% if x != empty %}` was true for `nil`, so 0.54 module templates printed the empty links and labels they guarded. Where 0.54 read both keywords as `nil`, a `""`, `[]` or `{}` now counts as well, and a `false` boolean var counts as `blank`.

- A Blueprint `identifier` or `absolute_url` Liquid template that uses `blank` or `empty` compiles again.
