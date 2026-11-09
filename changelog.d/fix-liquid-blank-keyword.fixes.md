- `blank` in Liquid templates matches `nil`, `false`, `""`, `[]` and `{}`: since the Liquex 0.15 upgrade `{% if x != blank %}` was always true, so 0.54 module templates printed the empty links and labels it guarded. `{% when blank %}` matches the same values.

- A Blueprint `identifier` or `absolute_url` Liquid template that uses `blank` compiles again.
