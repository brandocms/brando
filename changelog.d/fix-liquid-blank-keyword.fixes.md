- `empty` and `blank` in Liquid templates match a var with no value again: `empty` matches `nil`, `""`, `[]` and `{}`, and `blank` matches those and `false`. Since the Liquex 0.15 upgrade `{% if x != blank %}` was always true and `{% if x != empty %}` was true for `nil`, so 0.54 module templates printed the empty links and labels they guarded. `{% when empty %}` and `{% when blank %}` match the same values.

- A Blueprint `identifier` or `absolute_url` Liquid template that uses `blank` or `empty` compiles again.
