- Liquid prints every var, table row var and global holding text escaped, not only `string` and `text`, and an `input` ref's value as text.

- `color`, `date`, `datetime` and `select` values are checked for their type in block saves and on the Globals screen, a `select` against the options its definition gives.

- The Globals screen saves values only, and a block var's owner never comes from the request.
