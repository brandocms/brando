defmodule Brando.Repo.Migrations.MigrateEntriesToContentIdentifiers do
  use Ecto.Migration
  import Ecto.Query

  def change do
    blueprints = Brando.Blueprint.list_blueprints()

    for blueprint <- blueprints,
        %{type: :entries, name: field_name} <- blueprint.__relations__() do
      # create a join table
      table_name = blueprint.__schema__(:source)
      join_source = "#{table_name}_#{field_name}_identifiers"

      create table(join_source) do
        add :parent_id, references(table_name, on_delete: :delete_all)
        add :identifier_id, references(:content_identifiers, on_delete: :delete_all)
        add :sequence, :integer
        timestamps()
      end

      create unique_index(join_source, [:parent_id, :identifier_id])

      flush()

      entries_field = [{field_name, dynamic([t], field(t, ^field_name))}] |> Enum.into(%{})

      # grab entries for each
      query =
        from(t in table_name,
          select: %{
            id: t.id,
            updated_at: t.updated_at
          },
          select_merge: ^entries_field
        )

      entries = Brando.repo().all(query)

      join_entries =
        Enum.map(entries, fn entry ->
          rel_entries = Map.get(entry, field_name)

          if rel_entries do
            rel_entries
            |> Enum.with_index()
            |> Enum.map(fn {rel, idx} ->
              q =
                from(t in "content_identifiers",
                  select: %{id: t.id},
                  where:
                    t.entry_id == ^rel["id"] and
                      t.schema == ^rel["schema"],
                  limit: 1
                )

              case Brando.repo().all(q) do
                [] ->
                  nil

                [identifier] ->
                  %{}
                  |> Map.put(:parent_id, entry.id)
                  |> Map.put(:identifier_id, identifier.id)
                  |> Map.put(:sequence, idx)
                  |> Map.put(:inserted_at, DateTime.utc_now())
                  |> Map.put(:updated_at, DateTime.utc_now())
              end
            end)
            |> Enum.reject(&(&1 == nil))
          end
        end)
        |> Enum.reject(&(&1 == nil))
        |> List.flatten()

      Brando.repo().insert_all(join_source, join_entries)
    end
  end
end
