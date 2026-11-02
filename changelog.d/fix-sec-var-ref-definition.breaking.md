- A block save holds a var's type, key and options to its definition: a saved var keeps its own, a new var takes its module's or table template's, and a key with no definition is left out.
  Define a var on its module before a seed or script passes it to `Block.block_changeset/3` or `recursive_block_changeset/4`.

- Only a superuser moves a saved block to another module, which holds its refs and vars to the new definition.

- In legacy mode, setting up global sets at `/admin/config/global_sets` takes a superuser; the Globals screen, which fills in values, stays open.
