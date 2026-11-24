- A module rename over the apply's size limit no longer has to come out of the file: the apply moves none of its values, the blocks keep them under the old key, and the plan, the release status and Release changes print the `mix brando.modules resolve --map` command that moves them, never a `--drop` for them.

- `mix brando.modules resolve --map` keeps a value an editor already entered under the new key (and lists the block), and a run whose keys were moved already says so instead of failing.
