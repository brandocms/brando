# Ecto changeset patterns

Rules for changesets with associations and embeds: `put_assoc`, copied
structs, and nested forms that gain rows in LiveView. Each one cost a bug
here. Block changesets have their own pitfalls (NotLoaded guards, reusing
changesets from `get_assoc`, `validate_block` base selection) in the
brando-blocks skill, `.claude/skills/brando-blocks/SKILL.md` §11 "Common Pitfalls".

## Associations

- **Let `put_assoc` set the foreign key.** Use `put_assoc(:gallery, ...)` alone,
  without a `put_change(:gallery_id, nil)` beside it.
- **`on_replace: :nilify` on a `belongs_to` you disassociate.** It sets the FK
  to nil; the default `:raise` refuses any association change.
- **Check for `%Ecto.Association.NotLoaded{}` before `put_assoc`.** It is
  truthy, and passing it on makes the changeset fail.

## New records

Copying a single struct for insertion: mark it `:built`, so Ecto inserts it
rather than treating it as a loaded row with a nil id.

```elixir
struct
|> Map.merge(%{id: nil, parent_id: nil})
|> put_in([Access.key(:__meta__), Access.key(:state)], :built)
```

Several new records in one `put_assoc`: pass them as maps. Changesets built
from nil-id structs all share the nil id, and Ecto matches them against one
another; each map becomes its own insert.

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

## Adding rows in a LiveView form (the append-changeset pattern)

To add a child row (a table row, a subform item) while keeping every pending
edit, append a new changeset to the current ones. Converting the existing
changesets to params or maps drops what the editor has typed.

1. `current = Ecto.Changeset.get_assoc(parent_changeset, :items)`
2. `new_item = change(%Item{}) |> Map.put(:action, :insert)`
3. `put_assoc(parent_changeset, :items, current ++ [new_item])`

If the new item has nested rows of its own (e.g. `vars`), pass those as maps
(see "New records" above).

In the validate handler, keep stripping non-persisted structs from `data`
before casting: the hidden inputs the new changeset renders put it back
through `params`. `lib/brando_admin/components/form/input/subform_helpers.ex`
implements this for subforms.
