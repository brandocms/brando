- A related entries input in a subform's rows no longer crashes the form when its query leaves out the rows' identifiers, and the default preloads now load them.

- Picking an entry or pressing "Clear all" in a related entries input in a subform row, other than a transformer's, changes that row; before, nothing happened.

- A related entries input in a transformer's rows, or in a custom subform component that passes `read_generation` on to its rows, checks again what the editor may read when permissions change.
