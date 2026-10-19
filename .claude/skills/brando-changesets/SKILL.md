---
name: brando-changesets
description: Ecto changeset traps for associations and embeds in Brando. Use when calling `put_assoc`, copying a struct for insertion, re-casting embeds after `apply_changes`, or adding rows to a nested LiveView form.
user-invocable: true
---

# Changesets with associations and embeds

Each rule below cost a bug here. Block changesets have their own pitfalls
(NotLoaded guards, reusing changesets from `get_assoc`, `validate_block` base
selection): [brando-blocks](../brando-blocks/SKILL.md), "Common Pitfalls".

## Associations

- **Let `put_assoc` set the foreign key.** `put_assoc(:gallery, ...)` alone,
  with no `put_change(:gallery_id, nil)` beside it.
- **`on_replace: :nilify` on a `belongs_to` you disassociate.** It sets the FK
  to nil; the default `:raise` raises when a loaded associated record is
  replaced or removed (`Brando.Content.Ref` media relations are the pattern).
- **Check for `%Ecto.Association.NotLoaded{}` before `put_assoc`.** It is
  truthy, and `put_assoc` raises on it.

## New records

A single struct copied for insertion is marked `:built`, so Ecto inserts it
instead of treating it as a loaded row with a nil id:

```elixir
struct
|> Map.merge(%{id: nil, parent_id: nil})
|> put_in([Access.key(:__meta__), Access.key(:state)], :built)
```

Several new records in one `put_assoc` go in as maps. Ecto matches each new
value to the current rows by primary key, and every nil id is the same key: a
nil-id struct or changeset that matches an unsaved row is sent as an update,
while a map becomes a change on the row it matched, an insert:

```elixir
objects
|> Enum.map(fn obj ->
  if is_nil(obj.id) do
    %{field1: obj.field1, field2: obj.field2}
  else
    Ecto.Changeset.change(obj, %{...})
  end
end)
|> then(&Ecto.Changeset.put_assoc(parent, :objects, &1))
```

After `apply_changes/1`, clear embedded associations with nil ids before the
next changeset call, so Ecto treats the params as fresh inserts instead of
warning about duplicate primary keys
([Ecto #3514](https://github.com/elixir-ecto/ecto/issues/3514)).

## Adding rows to a LiveView form: append a changeset

To add a child row (a table row, a subform item) and keep every pending edit,
append a new changeset to the current ones. Converting the existing
changesets to params or maps drops what the editor has typed.

1. `current = Ecto.Changeset.get_assoc(parent_changeset, :items)`, minus
   changesets whose action is `:replace` or `:delete`, the rows already removed
   (`put_assoc` raises "cannot replace related" on a `:replace` one)
2. `new_item = change(%Item{}) |> Map.put(:action, :insert)`
3. `put_assoc(parent_changeset, :items, current ++ [new_item])`

Nested rows of the new item (e.g. `vars`) go in as maps (New records, above).
The block editor's `"add_table_row"` (`BrandoAdmin.Components.Form.Block.Events`)
is the pattern.

The validate handler casts onto a base without non-persisted rows (the stored
entry, or `data` with nil-id rows filtered out, as `"validate_block"` does for
`table_rows`): the hidden inputs the new changeset renders bring them back
through `params`.

Subforms do all of this through
`lib/brando_admin/components/form/input/subform_helpers.ex`: read with
`current_entries/2`, add with `append_subentries/2` or `insert_subentry/4`, which
send an op the form applies to its own latest changeset (`:update_entries` in
`BrandoAdmin.Components.Form`).
